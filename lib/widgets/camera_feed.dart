import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../ml/frame.dart';

/// Live back-camera preview that hands frames to [onFrame], one at a time.
///
/// Frames arrive ~30 per second; while [onFrame] is still working on one, new ones are skipped,
/// so a slow model just means fewer updates per second, never a growing queue.
/// [overlay] is drawn exactly on top of the preview (same size), e.g. boxes.
class CameraFeed extends StatefulWidget {
  const CameraFeed({super.key, required this.onFrame, this.overlay});
  final Future<void> Function(FrameData frame) onFrame;
  final Widget? overlay;

  /// Rotation applied to the latest frame (dev status lines show it).
  static int lastRotation = 0;

  @override
  State<CameraFeed> createState() => _CameraFeedState();
}

// WidgetsBindingObserver: tells us when the app goes to the background / comes back.
class _CameraFeedState extends State<CameraFeed> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _starting = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readScreenRotation();
    _start();
  }

  Future<void> _start() async {
    if (_camera != null || _starting) return;
    _starting = true;
    try {
      final back = (await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      final cam = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await cam.initialize(); // asks for camera permission the first time
      // Frame turn = sensor angle - screen angle (Android's own formula for the back camera).
      await cam.startImageStream((img) => _onImage(img, (back.sensorOrientation - _screenDegrees + 360) % 360));
      if (!mounted) return await cam.dispose();
      setState(() => _camera = cam);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _starting = false;
    }
  }

  /// How far the screen has turned from the phone's natural (portrait) position: 0/90/180/270.
  /// Asked from Android (MainActivity.kt): neither Flutter nor the camera plugin reports it
  /// reliably, and guessing from the camera plugin turned landscape frames the wrong way.
  int _screenDegrees = 0;
  static const _display = MethodChannel('ginlo/display');

  Future<void> _readScreenRotation() async {
    try {
      _screenDegrees = await _display.invokeMethod<int>('rotationDegrees') ?? 0;
    } catch (_) {
      _screenDegrees = 0; // tests / no native side: assume portrait
    }
  }

  /// Screen size changed, e.g. the phone was turned: read the rotation again.
  @override
  void didChangeMetrics() => _readScreenRotation();

  void _onImage(CameraImage img, int rotation) {
    if (_busy || !mounted) return; // still working on the previous frame
    _busy = true;
    CameraFeed.lastRotation = rotation;
    widget
        .onFrame(FrameData(img, rotation))
        .catchError((Object e) {
          debugPrint('frame failed: $e');
        })
        .whenComplete(() => _busy = false);
  }

  /// The camera plugin doesn't handle this itself: Android takes the camera away when the
  /// phone locks or the app is backgrounded, so release it then and start it again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final cam = _camera;
      if (cam != null) {
        setState(() => _camera = null);
        cam.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final landscape = screen.width > screen.height;
    final cam = _camera;
    if (cam == null) {
      return Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(16), child: Text('Camera: $_error'))
            : const CircularProgressIndicator(),
      );
    }
    // Size the preview ourselves from the screen's shape (wide in landscape, tall in portrait),
    // as large as fits. The overlay (boxes) is drawn exactly on top, at the same size.
    return LayoutBuilder(
      builder: (context, box) {
        final s = cam.value.previewSize;
        final long = s == null ? 16.0 : (s.width > s.height ? s.width : s.height);
        final short = s == null ? 9.0 : (s.width > s.height ? s.height : s.width);
        final aspect = landscape ? long / short : short / long;
        var w = box.maxWidth, h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: CameraPreview(cam, child: widget.overlay),
          ),
        );
      },
    );
  }
}
