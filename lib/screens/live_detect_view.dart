import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../ml/detector.dart';

/// Dev tool: live camera with every detector box, its class and confidence drawn on top.
///
/// Frames arrive ~30 per second; while one is being detected, new ones are skipped,
/// so a slow model just means fewer updates per second, never a growing queue.
class LiveDetectView extends StatefulWidget {
  const LiveDetectView({super.key});

  @override
  State<LiveDetectView> createState() => _LiveDetectViewState();
}

class _LiveDetectViewState extends State<LiveDetectView> {
  CameraController? _camera;
  Detector? _detector;
  DetectorSpec _spec = detectorSpecs.first;
  double _conf = 0.25;
  bool _busy = false;
  String? _error;

  DetectResult? _last;
  final _frameTimes = <int>[]; // when each recent result arrived, for the FPS counter

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _detector = await Detector.load(_spec);
      final back = (await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      final cam = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await cam.initialize(); // asks for camera permission the first time
      await cam.startImageStream((img) => _onFrame(img, back.sensorOrientation));
      if (!mounted) return await cam.dispose();
      setState(() => _camera = cam);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onFrame(CameraImage img, int rotation) {
    final detector = _detector;
    if (_busy || detector == null) return; // still working on the previous frame
    _busy = true;
    detector.detect(FrameData(img, rotation), conf: _conf).then((r) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      _frameTimes
        ..add(now)
        ..removeWhere((t) => now - t > 2000);
      setState(() {
        _last = r;
        _error = null;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    }).whenComplete(() {
      _busy = false;
      if (!mounted) detector.close(); // screen closed mid-frame: free the model now that it's idle
    });
  }

  Future<void> _switchModel(DetectorSpec spec) async {
    final old = _detector;
    setState(() {
      _spec = spec;
      _detector = null; // _onFrame skips frames until the new model is ready
      _last = null;
      _error = null;
    });
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20)); // let the running frame finish
    }
    old?.close();
    final next = await Detector.load(spec);
    if (mounted) setState(() => _detector = next);
  }

  @override
  void dispose() {
    _camera?.dispose();
    // Closing the model while a background isolate is using it would crash; if a frame is
    // in flight, _onFrame closes it when that frame finishes.
    if (!_busy) _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    if (cam == null) {
      return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    }
    final r = _last;
    final fps = _frameTimes.length / 2;

    return Column(
      children: [
        // CameraPreview sizes itself to the camera's aspect ratio; the child is drawn exactly on top.
        Expanded(
          child: Center(
            child: CameraPreview(cam, child: CustomPaint(painter: _BoxPainter(r?.detections ?? const []))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            _error != null
                ? '${_spec.title}: $_error'
                : r == null
                ? 'Loading ${_spec.title}…'
                : '${r.detections.length} boxes · ${fps.toStringAsFixed(1)} fps · '
                    'prep ${r.preMs} + model ${r.inferMs} + boxes ${r.postMs} ms',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<DetectorSpec>(
                  value: _spec,
                  isExpanded: true,
                  items: [for (final s in detectorSpecs) DropdownMenuItem(value: s, child: Text(s.title))],
                  onChanged: (s) => s == null || s == _spec ? null : _switchModel(s),
                ),
              ),
              const SizedBox(width: 12),
              Text('conf ${_conf.toStringAsFixed(2)}'),
            ],
          ),
        ),
        Slider(value: _conf, min: 0.05, max: 0.9, onChanged: (v) => setState(() => _conf = v)),
      ],
    );
  }
}

/// Draws each box with "label 0.87" on a filled tag. Colour goes red -> green with confidence.
class _BoxPainter extends CustomPainter {
  _BoxPainter(this.dets);
  final List<Detection> dets;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dets) {
      final color = Color.lerp(Colors.red, Colors.greenAccent, d.score.clamp(0.0, 1.0))!;
      final rect = Rect.fromLTRB(d.box.left * size.width, d.box.top * size.height, d.box.right * size.width,
          d.box.bottom * size.height);
      canvas.drawRect(rect, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
      final tag = TextPainter(
        text: TextSpan(
            text: ' ${d.label} ${d.score.toStringAsFixed(2)} ',
            style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = (rect.top - tag.height).clamp(0.0, size.height - tag.height);
      canvas.drawRect(Rect.fromLTWH(rect.left, top, tag.width, tag.height), Paint()..color = color);
      tag.paint(canvas, Offset(rect.left, top));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.dets != dets;
}
