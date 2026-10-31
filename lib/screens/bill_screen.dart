import 'package:flutter/material.dart';

import '../config.dart';
import '../data/db.dart';
import '../dev/perf_log.dart';
import '../ml/detector.dart';
import '../ml/embedder.dart';
import '../ml/frame.dart';
import '../ml/matcher.dart';
import '../ml/models.dart';
import '../ml/smoother.dart';
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
      // No title bar in landscape: the camera needs the height.
      appBar: _portrait(context) ? AppBar(title: const Text('New bill')) : null,
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

  /// Prod shows steady results: items must persist across frames, names are voted, boxes glide,
  /// duplicates merge, counts are held (see smoother.dart). Dev shows raw per-frame output unless
  /// [_prodView]. The knobs are tunable in dev (Smoothing settings) and saved in the database.
  final _settings = SmoothSettings();
  late final _smoother = FrameSmoother(_settings);
  late final _countSmoother = CountSmoother(_settings);
  List<SteadyItem> _steady = const [];
  Map<String?, int> _steadyCounts = const {}; // product (null = Unknown) -> held count
  final _prices = <String, double>{};
  bool _prodView = false;

  static const _settingsKey = 'smoothing';

  @override
  void initState() {
    super.initState();
    _loadSettings();
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

  Future<void> _loadSettings() async {
    try {
      final saved = SmoothSettings.fromJsonString(await (await AppDb.open()).setting(_settingsKey));
      if (mounted) setState(() => _copySettings(saved));
    } catch (e) {
      debugPrint('smoothing settings: $e');
    }
  }

  void _copySettings(SmoothSettings from) {
    _settings
      ..voteFrames = from.voteFrames
      ..showAfter = from.showAfter
      ..keepMissed = from.keepMissed
      ..glide = from.glide
      ..linkOverlap = from.linkOverlap
      ..mergeOverlap = from.mergeOverlap
      ..countFrames = from.countFrames;
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
      _steady = _smoother.update([
        for (var i = 0; i < r.detections.length; i++)
          Sighting(r.detections[i].box, _matches[i].name, _matches[i].price),
      ]);
      final counts = <String?, int>{};
      for (final it in _steady) {
        counts[it.name] = (counts[it.name] ?? 0) + 1;
        if (it.name != null) _prices[it.name!] = it.price;
      }
      _steadyCounts = _countSmoother.update(counts);
    });
  }

  /// Dev: tune every smoothing knob live; saved to the database when the sheet closes.
  Future<void> _openSmoothingSettings() async {
    setState(() => _prodView = true); // the knobs only affect the smoothed view
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void set(void Function() change) {
            setSheet(change);
            setState(() {});
          }

          Widget knob(
            String label,
            String help,
            double value,
            double min,
            double max,
            int? divisions,
            void Function(double) onChanged,
          ) {
            final shown = divisions == null ? value.toStringAsFixed(2) : value.round().toString();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label: $shown', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(help, style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: (v) => set(() => onChanged(v)),
                  ),
                ],
              ),
            );
          }

          final p = _settings;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Smoothing (prod view)')),
                  knob(
                    'Show after (frames)',
                    'An item appears only once seen in this many frames. Higher = fewer ghost boxes, slower to appear.',
                    p.showAfter.toDouble(),
                    1,
                    6,
                    5,
                    (v) => p.showAfter = v.round(),
                  ),
                  knob(
                    'Keep through misses (frames)',
                    'An item stays this many missed frames. Higher = less blinking, slower to clear.',
                    p.keepMissed.toDouble(),
                    0,
                    6,
                    6,
                    (v) => p.keepMissed = v.round(),
                  ),
                  knob(
                    'Name vote (frames)',
                    'Name = most common over this many frames. Higher = steadier names.',
                    p.voteFrames.toDouble(),
                    1,
                    10,
                    9,
                    (v) => p.voteFrames = v.round(),
                  ),
                  knob(
                    'Count hold (frames)',
                    'Item list counts = most common over this many frames. Higher = steadier counts.',
                    p.countFrames.toDouble(),
                    1,
                    12,
                    11,
                    (v) => p.countFrames = v.round(),
                  ),
                  knob(
                    'Merge duplicates (overlap)',
                    'Hide a box overlapping a bigger one this much. Lower = merges more.',
                    p.mergeOverlap,
                    0.2,
                    1.0,
                    null,
                    (v) => p.mergeOverlap = v,
                  ),
                  knob(
                    'Same item if overlap ≥',
                    'Boxes in consecutive frames overlapping this much are one item.',
                    p.linkOverlap,
                    0.1,
                    0.8,
                    null,
                    (v) => p.linkOverlap = v,
                  ),
                  knob(
                    'Box glide',
                    'How far a box moves to its new position per frame. 1 = jumps.',
                    p.glide,
                    0.1,
                    1.0,
                    null,
                    (v) => p.glide = v,
                  ),
                  TextButton(
                    onPressed: () => set(() => _copySettings(SmoothSettings())),
                    child: const Text('Reset to defaults'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await (await AppDb.open()).setSetting(_settingsKey, _settings.toJsonString());
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    final smooth = !isDev || _prodView;

    // What to draw and bill: steady items (prod) or this frame's raw boxes (dev).
    final items = <({Rect box, String? name, double price, String text})>[];
    if (smooth) {
      for (final it in _steady) {
        items.add((box: it.box, name: it.name, price: it.price, text: it.name ?? 'Unknown'));
      }
    } else if (r != null) {
      for (var i = 0; i < r.detections.length; i++) {
        final d = r.detections[i], m = _matches[i];
        final text = '${m.name ?? 'Unknown'} ${m.score.toStringAsFixed(2)} · ${d.label} ${d.score.toStringAsFixed(2)}';
        items.add((box: d.box, name: m.name, price: m.price, text: text));
      }
    }
    final tags = [
      for (final it in items) BoxTag(it.box, it.text, it.name != null ? Colors.greenAccent : Colors.orangeAccent),
    ];

    // What's in view right now: product -> count (the bill this view would make).
    // Smoothed: each product's count held over the last few frames. Raw: this frame's boxes.
    final counts = <String, int>{};
    final prices = <String, double>{..._prices};
    var unknown = 0;
    if (smooth) {
      _steadyCounts.forEach((name, n) => name == null ? unknown = n : counts[name] = n);
    } else {
      for (final it in items) {
        if (it.name == null) {
          unknown++;
        } else {
          counts[it.name!] = (counts[it.name!] ?? 0) + 1;
          prices[it.name!] = it.price;
        }
      }
    }
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
                  Expanded(
                    child: Text('Total', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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
              '${_matcher.angles.length} angles in catalog · screen ${CameraFeed.lastScreenDegrees}° → frame ${CameraFeed.lastRotation}°',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (isDev)
          SwitchListTile(
            dense: true,
            title: const Text('Prod view (smoothed)'),
            value: _prodView,
            onChanged: (v) => setState(() => _prodView = v),
          ),
        if (isDev)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openSmoothingSettings,
              icon: const Icon(Icons.tune),
              label: const Text('Smoothing settings'),
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

bool _portrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.height >= s.width;
}
