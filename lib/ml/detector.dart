import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

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

/// Boxes plus how long each stage took (shown in the dev overlay).
class DetectResult {
  final List<Detection> detections;
  final int preMs, inferMs, postMs;
  const DetectResult(this.detections, this.preMs, this.inferMs, this.postMs);
}

/// A copy of one camera frame that can be sent to a background isolate.
/// Android gives YUV420: a full-size brightness plane (Y) and quarter-size colour planes (U, V).
class FrameData {
  final Uint8List y, u, v;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;

  /// Clockwise degrees to turn the sensor image upright (the camera's sensorOrientation).
  final int rotation;

  FrameData(CameraImage img, this.rotation)
      : y = img.planes[0].bytes,
        u = img.planes[1].bytes,
        v = img.planes[2].bytes,
        width = img.width,
        height = img.height,
        yRowStride = img.planes[0].bytesPerRow,
        uvRowStride = img.planes[1].bytesPerRow,
        uvPixelStride = img.planes[1].bytesPerPixel ?? 1;
}

class Detector {
  Detector._(this.spec, this._interpreter, this._labels);
  final DetectorSpec spec;
  final Interpreter _interpreter;
  final List<String> _labels;

  static const size = 640; // model input is 640x640

  static Future<Detector> load(DetectorSpec spec) async {
    final interpreter = await Interpreter.fromAsset(spec.asset, options: InterpreterOptions()..threads = 4);
    final labels = spec.labelsAsset.isEmpty
        ? ['object']
        : (await rootBundle.loadString(spec.labelsAsset)).trim().split('\n');
    return Detector._(spec, interpreter, labels);
  }

  /// Runs the whole pipeline in a background isolate (the UI keeps drawing meanwhile).
  Future<DetectResult> detect(FrameData frame, {double conf = 0.25}) =>
      _spawn(_Job(_interpreter.address, spec, _labels, frame, conf));

  void close() => _interpreter.close();

  // Static, so the isolate closure can't accidentally capture `this` (an Interpreter can't be sent).
  static Future<DetectResult> _spawn(_Job job) => Isolate.run(() => _run(job));
}

class _Job {
  final int address;
  final DetectorSpec spec;
  final List<String> labels;
  final FrameData frame;
  final double conf;
  _Job(this.address, this.spec, this.labels, this.frame, this.conf);
}

/// Where the upright frame sits inside the 640x640 model input.
class _Letterbox {
  final double scale, padX, padY;
  final int uprightW, uprightH;
  _Letterbox(this.scale, this.padX, this.padY, this.uprightW, this.uprightH);
}

DetectResult _run(_Job job) {
  final sw = Stopwatch()..start();
  // Same native interpreter, re-wrapped in this isolate by its memory address.
  final interpreter = Interpreter.fromAddress(job.address, allocated: true);

  final input = Float32List(3 * Detector.size * Detector.size);
  final lb = _preprocess(job.frame, input, job.spec.channelsFirst);
  interpreter.getInputTensor(0).data = input.buffer.asUint8List();
  final preMs = sw.elapsedMilliseconds;

  interpreter.invoke();
  final inferMs = sw.elapsedMilliseconds - preMs;

  // YOLOE also outputs mask prototypes; the boxes are the 3-D output [1, 4 + classes (+32 mask), 8400].
  final out = interpreter.getOutputTensors().firstWhere((t) => t.shape.length == 3);
  final raw = out.data.buffer.asFloat32List(out.data.offsetInBytes, out.data.lengthInBytes ~/ 4);
  final dets = _decode(raw, out.shape[1], out.shape[2], job, lb);
  return DetectResult(dets, preMs, inferMs, sw.elapsedMilliseconds - preMs - inferMs);
}

/// YUV -> RGB, rotate upright, letterbox into 640x640 (grey padding), scale to 0..1.
_Letterbox _preprocess(FrameData f, Float32List out, bool channelsFirst) {
  const s = Detector.size, plane = s * s;
  final turned = f.rotation == 90 || f.rotation == 270;
  final uw = turned ? f.height : f.width, uh = turned ? f.width : f.height;
  final scale = s / math.max(uw, uh);
  final nw = (uw * scale).round(), nh = (uh * scale).round();
  final padX = (s - nw) ~/ 2, padY = (s - nh) ~/ 2;
  out.fillRange(0, out.length, 114 / 255);

  for (var oy = 0; oy < nh; oy++) {
    final uy = math.min(uh - 1, (oy / scale).floor());
    for (var ox = 0; ox < nw; ox++) {
      final ux = math.min(uw - 1, (ox / scale).floor());
      // upright pixel (ux, uy) -> sensor pixel (sx, sy)
      int sx, sy;
      switch (f.rotation) {
        case 90:
          sx = uy;
          sy = f.height - 1 - ux;
        case 180:
          sx = f.width - 1 - ux;
          sy = f.height - 1 - uy;
        case 270:
          sx = f.width - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }
      final yv = f.y[sy * f.yRowStride + sx];
      final uvi = (sy >> 1) * f.uvRowStride + (sx >> 1) * f.uvPixelStride;
      final uu = f.u[uvi] - 128, vv = f.v[uvi] - 128;
      final r = (yv + 1.402 * vv).clamp(0, 255) / 255;
      final g = (yv - 0.344 * uu - 0.714 * vv).clamp(0, 255) / 255;
      final b = (yv + 1.772 * uu).clamp(0, 255) / 255;

      final px = (oy + padY) * s + ox + padX;
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
  return _Letterbox(scale, padX.toDouble(), padY.toDouble(), uw, uh);
}

/// Output layout: row r of `raw` holds value r for all 8400 candidate boxes:
/// rows 0-3 = centre x, centre y, width, height; then one row of scores per class.
List<Detection> _decode(Float32List raw, int rows, int n, _Job job, _Letterbox lb) {
  final nc = job.labels.length;
  final unit = job.spec.normalizedBoxes ? Detector.size.toDouble() : 1.0;
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
    if (best < job.conf || job.spec.ignore.contains(job.labels[cls])) continue;
    final cx = raw[a] * unit, cy = raw[n + a] * unit, w = raw[2 * n + a] * unit, h = raw[3 * n + a] * unit;
    // 640-input pixels -> 0..1 of the upright frame (undo the letterbox)
    double fx(double x) => ((x - lb.padX) / lb.scale / lb.uprightW).clamp(0.0, 1.0);
    double fy(double y) => ((y - lb.padY) / lb.scale / lb.uprightH).clamp(0.0, 1.0);
    cand.add(Detection(
        Rect.fromLTRB(fx(cx - w / 2), fy(cy - h / 2), fx(cx + w / 2), fy(cy + h / 2)), best, job.labels[cls]));
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
