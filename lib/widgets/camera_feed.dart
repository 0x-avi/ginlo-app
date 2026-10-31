import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

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
      await cam.startImageStream((img) => _onImage(img, _uprightRotation(back, cam.value.deviceOrientation)));
      if (!mounted) return await cam.dispose();
      setState(() => _camera = cam);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _starting = false;
    }
  }

  /// Clockwise degrees to turn a sensor frame so it matches what's on screen, however the phone
  /// is held. The sensor is mounted at a fixed angle (usually 90°, right for portrait); in
  /// landscape the screen has turned a quarter, so the frame needs a quarter turn more or less.
  ///
  /// Flutter's landscapeLeft/Right are named the opposite way round to Android's ROTATION_90/270,
  /// so the ML Kit table (landscapeLeft = 90) turned frames 180° the wrong way: boxes moved
  /// opposite to the object. Here landscapeLeft = 270.
  int _uprightRotation(CameraDescription camera, DeviceOrientation phone) {
    // The screen only turns when auto-rotate lets it: follow the screen, not the raw sensor.
    final screenLandscape = _screenLandscape;
    final turn = switch (phone) {
      DeviceOrientation.landscapeLeft when screenLandscape => 270,
      DeviceOrientation.landscapeRight when screenLandscape => 90,
      _ when screenLandscape => 270,
      _ => 0, // screen is portrait (rotation locked, or held upright)
    };
    return (camera.sensorOrientation - turn + 360) % 360;
  }

  /// Updated on every build from the screen's actual shape.
  bool _screenLandscape = false;

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
    _screenLandscape = screen.width > screen.height;
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
        final aspect = _screenLandscape ? long / short : short / long;
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
