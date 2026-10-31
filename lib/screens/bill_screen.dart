import 'package:flutter/material.dart';

import '../config.dart';
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

final _detSpec = detectorSpecs[Models.billDetector];
final _embSpec = embedderSpecs[Models.billEmbedder];

/// Camera billing: YOLO finds each item, the embedder fingerprints it, the matcher names it
/// from the shop's own catalog. Live for now; capture -> invoice -> UPI QR comes next.
class BillScreen extends StatelessWidget {
  const BillScreen({super.key, required this.active});

  /// The camera only runs while the Bill tab is on screen.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New bill')),
      body: active ? const _LiveBill() : const SizedBox.shrink(),
    );
  }
}

class _LiveBill extends StatefulWidget {
  const _LiveBill();

  @override
  State<_LiveBill> createState() => _LiveBillState();
}

class _LiveBillState extends State<_LiveBill> {
  Matcher _matcher = Matcher(const []);
  VisionResult? _last;
  List<Match> _matches = const [];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    AppDb.changes.addListener(_loadCatalog); // newly taught products are recognised right away
  }

  @override
  void dispose() {
    AppDb.changes.removeListener(_loadCatalog);
    super.dispose();
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
    final det = await Models.detector(_detSpec), emb = await Models.embedder(_embSpec);
    final wall = Stopwatch()..start();
    final r = await Vision.analyze(det, frame, embedder: emb, conf: 0.25, pick: EmbedPick.all);
    PerfLog.instance.record('Bill: ${_detSpec.title} + ${_embSpec.title}', r, wall.elapsedMilliseconds);
    if (!mounted) return;
    setState(() {
      _last = r;
      _matches = [for (final v in r.vectors) v == null ? const Match(null, null, 0, 0, null) : _matcher.match(v)];
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    final tags = <BoxTag>[];
    if (r != null) {
      for (var i = 0; i < r.detections.length; i++) {
        final d = r.detections[i], m = _matches[i];
        final name = m.known ? m.name! : 'Unknown';
        final text = isDev ? '$name ${m.score.toStringAsFixed(2)} · ${d.label} ${d.score.toStringAsFixed(2)}' : name;
        tags.add(BoxTag(d.box, text, m.known ? Colors.greenAccent : Colors.orangeAccent));
      }
    }

    // What's in view right now: product -> count (the bill this frame would make).
    final counts = <String, int>{};
    final prices = <String, double>{};
    for (final m in _matches.where((m) => m.known)) {
      counts[m.name!] = (counts[m.name!] ?? 0) + 1;
      prices[m.name!] = m.price;
    }
    final unknown = _matches.where((m) => !m.known).length;
    final total = counts.entries.fold(0.0, (s, e) => s + e.value * prices[e.key]!);

    return CameraLayout(
      camera: CameraFeed(
        onFrame: _onFrame,
        overlay: CustomPaint(painter: TagPainter(tags)),
      ),
      panel: [
        if (_matcher.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No products taught yet: add them in Learn, then they show up here by name.'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              for (final e in counts.entries)
                Row(
                  children: [
                    Expanded(child: Text('${e.key} × ${e.value}')),
                    Text('₹${(e.value * prices[e.key]!).toStringAsFixed(2)}'),
                  ],
                ),
              if (unknown > 0)
                Row(
                  children: [
                    Expanded(child: Text('Unknown × $unknown')),
                    const Text('—'),
                  ],
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text('Total', style: Theme.of(context).textTheme.titleMedium)),
                  Text('₹${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ],
          ),
        ),
        if (isDev && r != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              'detect ${r.preMs + r.inferMs + r.postMs} ms · embed ${r.embedCount}× ${r.embedMs} ms · '
              '${_matcher.angles.length} angles in catalog',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (isDev)
          Row(
            children: [
              const SizedBox(width: 16),
              Text('match ≥ ${Matcher.threshold.toStringAsFixed(2)}'),
              Expanded(
                child: Slider(
                  value: Matcher.threshold,
                  min: 0.3,
                  max: 0.95,
                  onChanged: (v) => setState(() => Matcher.threshold = v),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
