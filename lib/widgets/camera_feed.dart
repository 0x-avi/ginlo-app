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

  /// Screen angle that rotation was computed from (dev status lines show it).
  static int lastScreenDegrees = 0;

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
      _sensorDegrees = back.sensorOrientation;
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
      final degrees = await _display.invokeMethod<int>('rotationDegrees') ?? 0;
      if (degrees != _screenDegrees) {
        debugPrint('ginlo: screen turned $_screenDegrees° -> $degrees°');
        _screenDegrees = degrees;
        if (mounted) setState(() {}); // turn the preview to match
      }
    } catch (_) {
      _screenDegrees = 0; // tests / no native side: assume portrait
    }
  }

  /// Screen size changed, e.g. portrait <-> landscape: read the rotation again.
  @override
  void didChangeMetrics() => _readScreenRotation();

  // Flipping straight from one landscape to the other (a 180° turn) doesn't change the screen's
  // size, so Flutter sends no signal: also re-read the rotation a few times a second.
  int _lastRotationRead = 0;

  void _onImage(CameraImage img, int rotation) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRotationRead > 300) {
      _lastRotationRead = now;
      _readScreenRotation();
    }
    if (_busy || !mounted) return; // still working on the previous frame
    _busy = true;
    CameraFeed.lastRotation = rotation;
    CameraFeed.lastScreenDegrees = _screenDegrees;
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

  int _sensorDegrees = 90;

  /// Whether the camera texture arrives already turned upright for portrait (Android's
  /// SurfaceTexture path does this) or raw in the sensor's landscape (ImageReader path).
  /// Checked on the phone: it arrives raw (with `true`, landscape showed upright cans lying down).
  static const _textureUpright = false;

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final size = cam?.value.previewSize;
    if (cam == null || size == null) {
      return Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(16), child: Text('Camera: $_error'))
            : const CircularProgressIndicator(),
      );
    }
    // Draw the raw camera picture ourselves and turn it by the screen angle, the same angle the
    // detection frames use, so picture and boxes always agree. (The plugin's own preview reads
    // the screen angle at the wrong moment while rotating and can stay turned the old way.)
    final long = size.longestSide, short = size.shortestSide;
    final int turns;
    final double textureAspect; // width / height of the picture before turning
    if (_textureUpright) {
      textureAspect = short / long; // portrait picture
      turns = (4 - _screenDegrees ~/ 90) % 4; // screen turned 90° -> picture turned back 270°
    } else {
      textureAspect = long / short; // sensor landscape picture
      turns = ((_sensorDegrees - _screenDegrees + 360) % 360) ~/ 90;
    }
    final aspect = turns.isOdd ? 1 / textureAspect : textureAspect; // as shown on screen

    return LayoutBuilder(
      builder: (context, box) {
        // As large as fits, keeping the picture's own proportions (never stretched).
        var w = box.maxWidth, h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RotatedBox(
                  quarterTurns: turns,
                  child: Texture(textureId: cam.cameraId),
                ),
                if (widget.overlay != null) widget.overlay!,
              ],
            ),
          ),
        );
      },
    );
  }
}
