import 'package:flutter/material.dart';

import '../dev/perf_log.dart';
import '../ml/detector.dart';
import '../ml/frame.dart';
import '../ml/models.dart';
import '../ml/vision.dart';
import '../widgets/tag_painter.dart';
import '../widgets/camera_feed.dart';

/// Dev Lab: live camera with every detector box, its class and confidence drawn on top.
class LiveDetectView extends StatefulWidget {
  const LiveDetectView({super.key});

  @override
  State<LiveDetectView> createState() => _LiveDetectViewState();
}

class _LiveDetectViewState extends State<LiveDetectView> {
  DetectorSpec _spec = detectorSpecs.first;
  double _conf = 0.25;
  VisionResult? _last;
  String? _error;
  final _frameTimes = <int>[]; // when each recent result arrived, for the FPS counter

  Future<void> _onFrame(FrameData frame) async {
    final spec = _spec;
    try {
      final detector = await Models.detector(spec);
      final wall = Stopwatch()..start();
      final r = await Vision.analyze(detector, frame, conf: _conf);
      PerfLog.instance.record(spec.title, r, wall.elapsedMilliseconds);
      if (!mounted || spec != _spec) return; // model was switched meanwhile: drop this result
      final now = DateTime.now().millisecondsSinceEpoch;
      _frameTimes
        ..add(now)
        ..removeWhere((t) => now - t > 2000);
      setState(() {
        _last = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    final tags = [
      for (final d in r?.detections ?? const <Detection>[])
        BoxTag(d.box, '${d.label} ${d.score.toStringAsFixed(2)}', TagPainter.scoreColor(d.score)),
    ];
    return Column(
      children: [
        Expanded(child: CameraFeed(onFrame: _onFrame, overlay: CustomPaint(painter: TagPainter(tags)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            _error != null
                ? '${_spec.title}: $_error'
                : r == null
                    ? 'Loading ${_spec.title}…'
                    : '${r.detections.length} boxes · ${(_frameTimes.length / 2).toStringAsFixed(1)} fps · '
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
                  onChanged: (s) => setState(() {
                    _spec = s ?? _spec;
                    _last = null;
                  }),
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
