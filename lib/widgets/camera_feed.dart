import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../ml/frame.dart';

/// Live back-camera preview (portrait) that hands frames to [onFrame], one at a time.
///
/// Frames arrive ~30 per second; while [onFrame] is still working on one, new ones are skipped,
/// so a slow model just means fewer updates per second, never a growing queue.
/// [overlay] is drawn exactly on top of the preview (same size), e.g. boxes.
class CameraFeed extends StatefulWidget {
  const CameraFeed({super.key, required this.onFrame, this.overlay});
  final Future<void> Function(FrameData frame) onFrame;
  final Widget? overlay;

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
      // The app is portrait-only, so turning by the sensor's fixed mounting angle makes every
      // frame upright, exactly as the preview shows it.
      await cam.startImageStream((img) => _onImage(img, back.sensorOrientation));
      if (!mounted) return await cam.dispose();
      setState(() => _camera = cam);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _starting = false;
    }
  }

  void _onImage(CameraImage img, int rotation) {
    if (_busy || !mounted) return; // still working on the previous frame
    _busy = true;
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
    final cam = _camera;
    if (cam == null) {
      return Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(16), child: Text('Camera: $_error'))
            : const CircularProgressIndicator(),
      );
    }
    // CameraPreview keeps the camera's own aspect ratio (no stretching); the child is drawn exactly on top.
    return Center(child: CameraPreview(cam, child: widget.overlay));
  }
}
