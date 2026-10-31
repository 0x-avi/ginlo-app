import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../dev/perf_log.dart';
import '../ml/detector.dart';
import '../ml/embedder.dart';
import '../ml/frame.dart';
import '../ml/matcher.dart';
import '../ml/models.dart';
import '../ml/vision.dart';
import '../widgets/camera_feed.dart';
import '../widgets/camera_layout.dart';
import '../widgets/tag_painter.dart';
import 'live_detect_view.dart';
import 'logs_screen.dart';

/// Dev-only tab: try detectors and embedders live, and see timings.
class LabScreen extends StatelessWidget {
  const LabScreen({super.key, required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lab'),
          toolbarHeight: _portrait(context) ? null : 0, // landscape: just the sub-tabs
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Detect'),
              Tab(text: 'Embed'),
              Tab(text: 'Logs'),
            ],
          ),
        ),
        // TabBarView only builds the visible page, so only one camera runs at a time.
        body: active
            ? const TabBarView(
                physics: NeverScrollableScrollPhysics(), // swiping would fight with the camera
                children: [LiveDetectView(), EmbedLabView(), LogsView()],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Embedder test: fingerprint the biggest box live, see which catalog products it's closest to,
/// and pin one object to compare against another ("same product, other side" vs "different product").
class EmbedLabView extends StatefulWidget {
  const EmbedLabView({super.key});

  @override
  State<EmbedLabView> createState() => _EmbedLabViewState();
}

class _EmbedLabViewState extends State<EmbedLabView> {
  final _detSpec = detectorSpecs[Models.billDetector];
  EmbedderSpec _embSpec = embedderSpecs.first;
  Matcher _matcher = Matcher(const []);
  VisionResult? _last;
  ({Float32List vector, Uint8List crop})? _pinned;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final angles = await (await AppDb.open()).angles(_embSpec.id);
      if (mounted) setState(() => _matcher = Matcher(angles));
    } catch (e) {
      debugPrint('catalog: $e');
    }
  }

  Future<void> _onFrame(FrameData frame) async {
    final spec = _embSpec;
    final det = await Models.detector(_detSpec), emb = await Models.embedder(spec);
    final wall = Stopwatch()..start();
    final r = await Vision.analyze(det, frame, embedder: emb, conf: 0.2, pick: EmbedPick.largest, wantCrops: true);
    PerfLog.instance.record('Lab: ${_detSpec.title} + ${spec.title}', r, wall.elapsedMilliseconds);
    if (mounted && spec == _embSpec) setState(() => _last = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    final i = r?.largest ?? -1;
    final v = i >= 0 ? r!.vectors[i] : null;
    final ranking = v == null ? const <({String name, double score})>[] : _matcher.ranking(v);
    final pinned = _pinned;

    return CameraLayout(
      camera: CameraFeed(
        onFrame: _onFrame,
        overlay: CustomPaint(
          painter: TagPainter([
            if (i >= 0) BoxTag(r!.detections[i].box, 'embedding this', Colors.cyanAccent, strokeWidth: 4),
          ]),
        ),
      ),
      panel: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<EmbedderSpec>(
            value: _embSpec,
            isExpanded: true,
            items: [for (final s in embedderSpecs) DropdownMenuItem(value: s, child: Text(s.title))],
            onChanged: (s) {
              setState(() {
                _embSpec = s ?? _embSpec;
                _last = null;
                _pinned = null; // vectors from different embedders can't be compared
              });
              _loadCatalog();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v == null
                    ? 'Point at one object…'
                    : '${v.length}-d fingerprint · ${r!.embedMs} ms · catalog has ${_matcher.angles.length} angles '
                          'for this embedder',
                style: const TextStyle(fontSize: 12),
              ),
              if (pinned != null)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(pinned.crop, width: 40, height: 40, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        v == null ? 'vs pinned: —' : 'vs pinned: ${dot(v, pinned.vector).toStringAsFixed(3)}',
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    TextButton(onPressed: () => setState(() => _pinned = null), child: const Text('Unpin')),
                  ],
                ),
              for (final m in ranking)
                Row(
                  children: [
                    SizedBox(width: 110, child: Text(m.name, overflow: TextOverflow.ellipsis)),
                    Expanded(child: LinearProgressIndicator(value: m.score.clamp(0.0, 1.0))),
                    SizedBox(width: 48, child: Text(' ${m.score.toStringAsFixed(2)}')),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.tonalIcon(
            onPressed: v == null ? null : () => setState(() => _pinned = (vector: v, crop: r!.crops[i]!)),
            icon: const Icon(Icons.push_pin),
            label: const Text('Pin this as A'),
          ),
        ),
      ],
    );
  }
}

bool _portrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.height >= s.width;
}
