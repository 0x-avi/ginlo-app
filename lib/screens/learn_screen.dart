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
import '../ui/theme.dart';
import '../voice/ocr.dart';
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
  Map<int, int> _angleCounts = {}; // product id -> angles already saved
  int? _productId;
  VisionResult? _last;
  FrameData? _lastFrame; // the frame _last came from: Capture fingerprints it

  /// Each capture: its fingerprints in every teach variant (turned, darker, brighter, further,
  /// closer; see teachVariants) and the crop picture shown in the gallery.
  final _captures = <({List<Float32List> vectors, Uint8List crop})>[];
  bool _saving = false, _capturing = false;

  /// A product needs [minAngles] saved angles in total to be recognised reliably; one session takes
  /// up to [maxCaptures]. A product that already has enough can get any number of extra angles.
  static const minAngles = 6, maxCaptures = 8;

  /// Captures still needed before Save (counting the angles this product already has).
  int get _stillNeeded {
    final have = _angleCounts[_productId] ?? 0;
    return (minAngles - have - _captures.length).clamp(0, minAngles);
  }

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await AppDb.open();
    final products = await db.products(), counts = await db.angleCounts(_embSpec.id);
    if (mounted) {
      setState(() {
        _products = products;
        _angleCounts = counts;
      });
    }
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
      _captures.add((vectors: c.vectors, crop: c.crop));
      _capturing = false;
    });
    // Read the label (name, MRP) from this capture; keep the best guess so far.
    try {
      final g = await readLabel(c.ocr);
      if (mounted && (g.name != null || g.price != null)) {
        setState(() => _ocr = (name: g.name ?? _ocr?.name, price: g.price ?? _ocr?.price));
      }
    } catch (e) {
      debugPrint('ocr: $e');
    }
  }

  void _hint(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _tryCapture() => _captures.length >= maxCaptures ? _hint('$maxCaptures sides captured: tap Save') : _capture();

  void _trySave() {
    if (_productId == null) return _hint('Pick a product above (or New product) first');
    if (_captures.isEmpty || _stillNeeded > 0) return _hint('Capture $_stillNeeded more side(s) first');
    _save();
  }

  /// Name / price read from the pack by OCR, offered to prefill "New product".
  LabelGuess? _ocr;

  Future<void> _newProduct({String? name, double? price}) async {
    final id = await showProductDialog(context, name: name, price: price);
    if (id == null) return;
    await _loadProducts();
    setState(() {
      _productId = id;
      _ocr = null;
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
    _loadProducts(); // refresh the angle counts on the chips
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
          // Which product: one chip each (with how many angles it already has); the selected one is filled.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                for (final p in _products)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${p.name} · ${_angleCounts[p.id] ?? 0}'),
                      selected: p.id == _productId,
                      onSelected: (_) => setState(() => _productId = p.id),
                      showCheckmark: true,
                      checkmarkColor: Colors.white,
                      selectedColor: GinloColors.blue,
                      labelStyle: TextStyle(
                        color: p.id == _productId ? Colors.white : GinloColors.ink,
                        fontWeight: p.id == _productId ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New product'),
                  onPressed: () => _newProduct(name: _ocr?.name, price: _ocr?.price),
                ),
              ],
            ),
          ),
          // Text read from the pack: one tap creates the product with it filled in.
          if (_ocr != null && _productId == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: ActionChip(
                avatar: const Icon(Icons.document_scanner, size: 18),
                label: Text(
                  'Read: ${_ocr!.name ?? '?'}${_ocr!.price != null ? ' · ₹${_ocr!.price!.toStringAsFixed(0)}' : ''} — Use',
                ),
                onPressed: () => _newProduct(name: _ocr!.name, price: _ocr!.price),
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
                  const Center(child: Text('  Pick a product, turn it and tap Capture for each side')),
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
                    onPressed: _capturing ? null : _tryCapture,
                    icon: const Icon(Icons.camera),
                    label: Text(_capturing ? 'Capturing…' : 'Capture ${_captures.length}/$maxCaptures'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _trySave, // stays full colour; says what's missing if not ready
                    icon: const Icon(Icons.save),
                    label: Text(
                      _productId == null
                          ? 'Pick a product'
                          : _stillNeeded > 0
                          ? 'Save ($_stillNeeded more)'
                          : 'Save',
                    ),
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
