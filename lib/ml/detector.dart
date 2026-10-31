import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'frame.dart';

/// Everything that differs between the detector models.
class DetectorSpec {
  final String title;
  final String asset;
  final String labelsAsset;

  /// Input layout: [1,3,640,640] (channels first) or [1,640,640,3].
  final bool channelsFirst;

  /// Box coordinates come out as 0..1 (true) or as pixels of the 640 input (false).
  final bool normalizedBoxes;

  /// Classes that are never products (COCO's person, furniture...). Their boxes are dropped.
  final Set<String> ignore;

  const DetectorSpec({
    required this.title,
    required this.asset,
    required this.labelsAsset,
    required this.channelsFirst,
    required this.normalizedBoxes,
    this.ignore = const {},
  });
}

const detectorSpecs = [
  DetectorSpec(
    title: 'YOLOE products (14 classes)',
    asset: 'assets/models/yoloe_products_int8.tflite',
    labelsAsset: 'assets/models/yoloe_products_labels.txt',
    channelsFirst: true,
    normalizedBoxes: true,
  ),
  DetectorSpec(
    title: 'SKU-110K (any product)',
    asset: 'assets/models/sku110k_yolo11n_float16.tflite',
    labelsAsset: '', // one class
    channelsFirst: false,
    normalizedBoxes: false,
  ),
  DetectorSpec(
    title: 'YOLO11n COCO (80 classes)',
    asset: 'assets/models/yolo11n_int8.tflite',
    labelsAsset: 'assets/models/coco_labels.txt',
    channelsFirst: true,
    normalizedBoxes: true,
    ignore: {'person', 'chair', 'couch', 'bed', 'dining table'},
  ),
];

/// One box. [box] is in 0..1 of the upright camera frame, so it can be drawn at any screen size.
class Detection {
  final Rect box;
  final double score;
  final String label;
  const Detection(this.box, this.score, this.label);
}

/// A loaded detector. Loaded once and kept for the app's lifetime (see models.dart).
class Detector {
  Detector._(this.spec, this.interpreter, this.labels);
  final DetectorSpec spec;
  final Interpreter interpreter;
  final List<String> labels;

  static const size = 640; // model input is 640x640

  static Future<Detector> load(DetectorSpec spec) async {
    final interpreter = await Interpreter.fromAsset(spec.asset, options: InterpreterOptions()..threads = 4);
    final labels = spec.labelsAsset.isEmpty
        ? ['object']
        : (await rootBundle.loadString(spec.labelsAsset)).trim().split('\n');
    return Detector._(spec, interpreter, labels);
  }
}

/// Where the upright frame sits inside the 640x640 model input.
class Letterbox {
  final double scale, padX, padY;
  final int uprightW, uprightH;
  Letterbox(this.scale, this.padX, this.padY, this.uprightW, this.uprightH);
}

/// Upright frame -> letterboxed 640x640 (grey padding), scaled to 0..1.
Letterbox prepareDetectorInput(FrameData f, Float32List out, bool channelsFirst) {
  const s = Detector.size, plane = s * s;
  final uw = f.uprightWidth, uh = f.uprightHeight;
  final scale = s / math.max(uw, uh);
  final nw = (uw * scale).round(), nh = (uh * scale).round();
  final padX = (s - nw) ~/ 2, padY = (s - nh) ~/ 2;
  out.fillRange(0, out.length, 114 / 255);

  for (var oy = 0; oy < nh; oy++) {
    final uy = math.min(uh - 1, (oy / scale).floor());
    for (var ox = 0; ox < nw; ox++) {
      final c = f.rgb(math.min(uw - 1, (ox / scale).floor()), uy);
      final px = (oy + padY) * s + ox + padX;
      final r = (c >> 16) / 255, g = ((c >> 8) & 0xFF) / 255, b = (c & 0xFF) / 255;
      if (channelsFirst) {
        out[px] = r;
        out[plane + px] = g;
        out[2 * plane + px] = b;
      } else {
        out[px * 3] = r;
        out[px * 3 + 1] = g;
        out[px * 3 + 2] = b;
      }
    }
  }
  return Letterbox(scale, padX.toDouble(), padY.toDouble(), uw, uh);
}

/// Output layout: row r of `raw` holds value r for all 8400 candidate boxes:
/// rows 0-3 = centre x, centre y, width, height; then one row of scores per class.
List<Detection> decodeDetections(
    Float32List raw, int n, DetectorSpec spec, List<String> labels, double conf, Letterbox lb) {
  final nc = labels.length;
  final unit = spec.normalizedBoxes ? Detector.size.toDouble() : 1.0;
  final cand = <Detection>[];
  for (var a = 0; a < n; a++) {
    var best = 0.0, cls = 0;
    for (var c = 0; c < nc; c++) {
      final sc = raw[(4 + c) * n + a];
      if (sc > best) {
        best = sc;
        cls = c;
      }
    }
    if (best < conf || spec.ignore.contains(labels[cls])) continue;
    final cx = raw[a] * unit, cy = raw[n + a] * unit, w = raw[2 * n + a] * unit, h = raw[3 * n + a] * unit;
    // 640-input pixels -> 0..1 of the upright frame (undo the letterbox)
    double fx(double x) => ((x - lb.padX) / lb.scale / lb.uprightW).clamp(0.0, 1.0);
    double fy(double y) => ((y - lb.padY) / lb.scale / lb.uprightH).clamp(0.0, 1.0);
    cand.add(Detection(
        Rect.fromLTRB(fx(cx - w / 2), fy(cy - h / 2), fx(cx + w / 2), fy(cy + h / 2)), best, labels[cls]));
  }
  return _nms(cand);
}

/// Non-maximum suppression: the model proposes many overlapping boxes per object;
/// keep the highest-scoring one and drop any box overlapping it by > 50% (IoU).
List<Detection> _nms(List<Detection> boxes, {double iou = 0.5, int maxBoxes = 100}) {
  boxes.sort((a, b) => b.score.compareTo(a.score));
  final keep = <Detection>[];
  for (final d in boxes) {
    if (keep.length >= maxBoxes) break;
    if (keep.every((k) => _iou(k.box, d.box) < iou)) keep.add(d);
  }
  return keep;
}

double _iou(Rect a, Rect b) {
  final i = a.intersect(b);
  if (i.width <= 0 || i.height <= 0) return 0;
  final inter = i.width * i.height;
  return inter / (a.width * a.height + b.width * b.height - inter);
}
