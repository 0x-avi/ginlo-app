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
    id: 'mobilenet_v3_small',
    title: 'MobileNet-V3 small (1024-d)',
    asset: 'assets/models/mobilenet_v3_small.tflite',
  ),
  EmbedderSpec(
    id: 'mobilenet_v3_large',
    title: 'MobileNet-V3 large (1280-d)',
    asset: 'assets/models/mobilenet_v3_large.tflite',
  ),
];

class Embedder {
  Embedder._(this.spec, this.interpreter);
  final EmbedderSpec spec;
  final Interpreter interpreter;

  static const size = 224; // input is 224x224 RGB, values 0..1 (from the model's metadata)

  static Future<Embedder> load(EmbedderSpec spec) async =>
      Embedder._(spec, await Interpreter.fromAsset(spec.asset, options: InterpreterOptions()..threads = 4));
}

/// A decoded picture (e.g. a stored crop JPEG) as [Pixels].
class ImagePixels implements Pixels {
  ImagePixels(this.image);
  final img.Image image;
  @override
  int get uprightWidth => image.width;
  @override
  int get uprightHeight => image.height;
  @override
  int rgb(int x, int y) {
    final p = image.getPixel(x, y);
    return (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  }
}

/// Where the product sits inside a stored crop: crops are saved with a 5% margin on each side
/// (see [cropJpeg]), so the product's box is the picture minus that margin.
const storedCropBox = Rect.fromLTRB(0.05 / 1.1, 0.05 / 1.1, 1 - 0.05 / 1.1, 1 - 0.05 / 1.1);

/// Box (0..1 of the upright frame) grown by [pad] on each side, in upright pixels, kept inside the frame.
({int x0, int y0, int w, int h}) _cropRect(Pixels f, Rect box, double pad) {
  final uw = f.uprightWidth, uh = f.uprightHeight;
  final int x0 = ((box.left - box.width * pad) * uw).floor().clamp(0, uw - 1);
  final int y0 = ((box.top - box.height * pad) * uh).floor().clamp(0, uh - 1);
  final int x1 = ((box.right + box.width * pad) * uw).ceil().clamp(x0 + 1, uw);
  final int y1 = ((box.bottom + box.height * pad) * uh).ceil().clamp(y0 + 1, uh);
  return (x0: x0, y0: y0, w: x1 - x0, h: y1 - y0);
}

/// One way of looking at a taught product (see [teachVariants]).
class Variant {
  final String name;
  final int turns; // quarter turns clockwise
  final double gain; // brightness multiplier
  final double pad; // margin around the box, as a fraction of its size (negative = tighter)
  const Variant(this.name, {this.turns = 0, this.gain = 1, this.pad = 0.05});
}

/// Every capture in Learn is fingerprinted all these ways, so the product still matches when it's
/// lying sideways, in a dim or bright shop, far away or close up. All from the one captured frame.
const teachVariants = [
  Variant('as seen'),
  Variant('turned 90°', turns: 1),
  Variant('upside down', turns: 2),
  Variant('turned 270°', turns: 3),
  Variant('darker', gain: 0.55),
  Variant('brighter', gain: 1.4),
  Variant('further away', pad: 0.35), // more surroundings, product smaller in the picture
  Variant('closer', pad: -0.08), // tight crop, product fills the picture
];

/// Crop the box out of the frame, stretch it to 224x224, values 0..1 (NHWC).
/// [turns] rotates the crop clockwise, [gain] scales brightness (teach variants).
/// Parts of the area outside the picture repeat its edge pixels (so "further away" still works
/// for a stored crop, which has no real surroundings).
void prepareEmbedderInput(Pixels f, Rect box, Float32List out, {double pad = 0.05, int turns = 0, double gain = 1}) {
  const s = Embedder.size;
  final uw = f.uprightWidth, uh = f.uprightHeight;
  final x0 = (box.left - box.width * pad) * uw, y0 = (box.top - box.height * pad) * uh;
  final w = box.width * (1 + 2 * pad) * uw, h = box.height * (1 + 2 * pad) * uh;
  for (var oy = 0; oy < s; oy++) {
    for (var ox = 0; ox < s; ox++) {
      // output pixel -> position in the (unturned) crop, both as 0..1
      final nx = (ox + 0.5) / s, ny = (oy + 0.5) / s;
      final (cx, cy) = switch (turns % 4) {
        1 => (ny, 1 - nx),
        2 => (1 - nx, 1 - ny),
        3 => (1 - ny, nx),
        _ => (nx, ny),
      };
      final px = f.rgb((x0 + cx * w).floor().clamp(0, uw - 1), (y0 + cy * h).floor().clamp(0, uh - 1));
      final i = (oy * s + ox) * 3;
      out[i] = math.min(1, (px >> 16) / 255 * gain);
      out[i + 1] = math.min(1, ((px >> 8) & 0xFF) / 255 * gain);
      out[i + 2] = math.min(1, (px & 0xFF) / 255 * gain);
    }
  }
}

/// The same crop as a small JPEG, saved with each taught angle so you can see (and delete) it.
Uint8List cropJpeg(Pixels f, Rect box, {int size = 224, double pad = 0.05}) {
  final c = _cropRect(f, box, pad);
  final scale = size / math.max(c.w, c.h);
  final w = math.max<int>(1, (c.w * scale).round()), h = math.max<int>(1, (c.h * scale).round());
  final im = img.Image(width: w, height: h);
  for (var oy = 0; oy < h; oy++) {
    for (var ox = 0; ox < w; ox++) {
      final px = f.rgb(
        c.x0 + math.min<int>(c.w - 1, (ox / scale).floor()),
        c.y0 + math.min<int>(c.h - 1, (oy / scale).floor()),
      );
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
