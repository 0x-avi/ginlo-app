import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/db.dart';
import '../dev/perf_log.dart';
import '../ml/detector.dart';
import '../ml/embedder.dart';
import '../ml/frame.dart';
import '../ml/models.dart';
import '../ml/vision.dart';
import '../widgets/camera_feed.dart';
import '../widgets/camera_layout.dart';
import '../widgets/tag_painter.dart';
import 'catalog_screen.dart';

final _detSpec = detectorSpecs[Models.billDetector];
final _embSpec = embedderSpecs[Models.billEmbedder];

/// Learn tab: teach a product its angles. Hold it up, the biggest box is the product,
/// tap Capture for each side, drop any bad captures, then Save.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, required this.active});

  /// The camera only runs while this tab is on screen.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _portrait(context) ? AppBar(title: const Text('Learn products')) : null,
      body: active ? const LearnView() : const SizedBox.shrink(),
    );
  }
}

class LearnView extends StatefulWidget {
  const LearnView({super.key, this.productId});

  /// Pre-selected product (when opened from the catalog).
  final int? productId;

  @override
  State<LearnView> createState() => _LearnViewState();
}

class _LearnViewState extends State<LearnView> {
  List<Product> _products = [];
  int? _productId;
  VisionResult? _last;
  FrameData? _lastFrame; // the frame _last came from: Capture fingerprints it

  /// Each capture: its fingerprints in every teach variant (turned, darker, brighter, further,
  /// closer; see teachVariants) and the crop picture shown in the gallery.
  final _captures = <({List<Float32List> vectors, Uint8List crop})>[];
  bool _saving = false, _capturing = false;

  /// Enough sides to recognise a product reliably, without wasting the shopkeeper's time.
  static const minCaptures = 6, maxCaptures = 8;

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await (await AppDb.open()).products();
    if (mounted) setState(() => _products = products);
  }

  Future<void> _onFrame(FrameData frame) async {
    final det = await Models.detector(_detSpec);
    final wall = Stopwatch()..start();
    // Live view only needs the boxes; fingerprints are made when you tap Capture.
    final r = await Vision.analyze(det, frame, conf: 0.2);
    PerfLog.instance.record('Learn: ${_detSpec.title}', r, wall.elapsedMilliseconds);
    if (mounted) {
      setState(() {
        _last = r;
        _lastFrame = frame;
      });
    }
  }

  Future<void> _capture() async {
    final r = _last, frame = _lastFrame;
    final i = r?.largest ?? -1;
    if (r == null || frame == null || i < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No product in view yet')));
      return;
    }
    setState(() => _capturing = true);
    final c = await Vision.embedVariants(await Models.embedder(_embSpec), frame, r.detections[i].box);
    if (!mounted) return;
    setState(() {
      _captures.add(c);
      _capturing = false;
    });
  }

  Future<void> _save() async {
    final id = _productId;
    if (id == null || _captures.isEmpty) return;
    setState(() => _saving = true);
    final db = await AppDb.open();
    for (final c in _captures) {
      await db.addCapture(id, _embSpec.id, c.vectors, [for (final v in teachVariants) v.name], c.crop);
    }
    if (!mounted) return;
    final name = _products.firstWhere((p) => p.id == id).name;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${_captures.length} angles of $name')));
    setState(() {
      _captures.clear();
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    final big = r?.largest ?? -1;
    final tags = [
      if (r != null)
        for (var i = 0; i < r.detections.length; i++)
          i == big
              ? BoxTag(
                  r.detections[i].box,
                  isDev ? 'this one ${r.detections[i].score.toStringAsFixed(2)}' : 'this one',
                  Colors.greenAccent,
                  strokeWidth: 4,
                )
              : BoxTag(r.detections[i].box, '', Colors.white54, strokeWidth: 1.5),
    ];

    return SafeArea(
      child: CameraLayout(
        camera: CameraFeed(
          onFrame: _onFrame,
          overlay: CustomPaint(painter: TagPainter(tags)),
        ),
        panel: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    value: _products.any((p) => p.id == _productId) ? _productId : null,
                    hint: const Text('Which product?'),
                    isExpanded: true,
                    items: [for (final p in _products) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (id) => setState(() => _productId = id),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () async {
                    final id = await showProductDialog(context);
                    if (id == null) return;
                    await _loadProducts();
                    setState(() => _productId = id);
                  },
                ),
              ],
            ),
          ),
          // Captured angles: tap ✕ to drop a bad one before saving.
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              children: [
                if (_captures.isEmpty)
                  const Center(child: Text('  Turn the product and tap Capture for each side: 6 to 8 sides')),
                for (var i = 0; i < _captures.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(_captures[i].crop, width: 72, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _captures.removeAt(i)),
                            child: const CircleAvatar(radius: 11, child: Icon(Icons.close, size: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _capturing || _captures.length >= maxCaptures ? null : _capture,
                    icon: const Icon(Icons.camera),
                    label: Text(_capturing ? 'Capturing…' : 'Capture ${_captures.length}/$maxCaptures'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _productId == null || _captures.length < minCaptures || _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_captures.length < minCaptures ? 'Save (need $minCaptures)' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _portrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.height >= s.width;
}
