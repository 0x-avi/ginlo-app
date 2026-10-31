import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'frame.dart';

/// An image embedder: crop in, "fingerprint" vector out. Similar-looking products give
/// vectors pointing the same way, so cosine similarity (dot product of unit vectors) = how alike.
class EmbedderSpec {
  /// Stored with every saved fingerprint: vectors from different embedders can't be compared.
  final String id;
  final String title;
  final String asset;
  const EmbedderSpec({required this.id, required this.title, required this.asset});
}

const embedderSpecs = [
  EmbedderSpec(
      id: 'mobilenet_v3_small', title: 'MobileNet-V3 small (1024-d)', asset: 'assets/models/mobilenet_v3_small.tflite'),
  EmbedderSpec(
      id: 'mobilenet_v3_large', title: 'MobileNet-V3 large (1280-d)', asset: 'assets/models/mobilenet_v3_large.tflite'),
];

class Embedder {
  Embedder._(this.spec, this.interpreter);
  final EmbedderSpec spec;
  final Interpreter interpreter;

  static const size = 224; // input is 224x224 RGB, values 0..1 (from the model's metadata)

  static Future<Embedder> load(EmbedderSpec spec) async =>
      Embedder._(spec, await Interpreter.fromAsset(spec.asset, options: InterpreterOptions()..threads = 4));
}

/// Box (0..1 of the upright frame) grown by [pad] on each side, in upright pixels.
({int x0, int y0, int w, int h}) _cropRect(FrameData f, Rect box, double pad) {
  final uw = f.uprightWidth, uh = f.uprightHeight;
  final int x0 = ((box.left - box.width * pad) * uw).floor().clamp(0, uw - 1);
  final int y0 = ((box.top - box.height * pad) * uh).floor().clamp(0, uh - 1);
  final int x1 = ((box.right + box.width * pad) * uw).ceil().clamp(x0 + 1, uw);
  final int y1 = ((box.bottom + box.height * pad) * uh).ceil().clamp(y0 + 1, uh);
  return (x0: x0, y0: y0, w: x1 - x0, h: y1 - y0);
}

/// Crop the box out of the frame, stretch it to 224x224, values 0..1 (NHWC).
void prepareEmbedderInput(FrameData f, Rect box, Float32List out, {double pad = 0.05}) {
  const s = Embedder.size;
  final c = _cropRect(f, box, pad);
  for (var oy = 0; oy < s; oy++) {
    final uy = c.y0 + math.min<int>(c.h - 1, (oy * c.h / s).floor());
    for (var ox = 0; ox < s; ox++) {
      final px = f.rgb(c.x0 + math.min<int>(c.w - 1, (ox * c.w / s).floor()), uy);
      final i = (oy * s + ox) * 3;
      out[i] = (px >> 16) / 255;
      out[i + 1] = ((px >> 8) & 0xFF) / 255;
      out[i + 2] = (px & 0xFF) / 255;
    }
  }
}

/// The same crop as a small JPEG, saved with each taught angle so you can see (and delete) it.
Uint8List cropJpeg(FrameData f, Rect box, {int size = 224, double pad = 0.05}) {
  final c = _cropRect(f, box, pad);
  final scale = size / math.max(c.w, c.h);
  final w = math.max<int>(1, (c.w * scale).round()), h = math.max<int>(1, (c.h * scale).round());
  final im = img.Image(width: w, height: h);
  for (var oy = 0; oy < h; oy++) {
    for (var ox = 0; ox < w; ox++) {
      final px = f.rgb(c.x0 + math.min<int>(c.w - 1, (ox / scale).floor()), c.y0 + math.min<int>(c.h - 1, (oy / scale).floor()));
      im.setPixelRgb(ox, oy, px >> 16, (px >> 8) & 0xFF, px & 0xFF);
    }
  }
  return img.encodeJpg(im, quality: 85);
}

/// Scale a vector to length 1, so a dot product between two of them is their cosine similarity.
Float32List l2normalize(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final n = math.sqrt(sum) + 1e-9;
  return Float32List.fromList([for (final x in v) x / n]);
}

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}
