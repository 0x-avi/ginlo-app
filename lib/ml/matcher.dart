import 'dart:typed_data';

import 'embedder.dart';

/// One saved fingerprint: a taught angle of a product.
class Angle {
  final int id;
  final int productId;
  final String name;
  final double price;
  final Float32List vector;
  const Angle(this.id, this.productId, this.name, this.price, this.vector);
}

/// The closest saved angle to a crop. [productId] is null when nothing is close enough ("Unknown").
class Match {
  final int? productId;
  final String? name;
  final double price;
  final double score; // cosine similarity to the closest angle, -1..1
  final int? angleId;
  const Match(this.productId, this.name, this.price, this.score, this.angleId);

  bool get known => productId != null;
}

/// Nearest-neighbour search over every taught angle of every product (brute force: with a few
/// hundred angles of ~1000 numbers each, this is well under a millisecond).
class Matcher {
  Matcher(this.angles);
  final List<Angle> angles;

  /// Below this similarity a crop is "Unknown". A starting point; tune it in the dev Lab.
  static double threshold = 0.6;

  bool get isEmpty => angles.isEmpty;

  Match match(Float32List v) {
    Angle? best;
    var bestScore = -1.0;
    for (final a in angles) {
      final s = dot(v, a.vector);
      if (s > bestScore) {
        bestScore = s;
        best = a;
      }
    }
    if (best == null || bestScore < threshold) return Match(null, null, 0, bestScore, best?.id);
    return Match(best.productId, best.name, best.price, bestScore, best.id);
  }

  /// Best score per product, highest first (for the dev embedder test).
  List<({String name, double score})> ranking(Float32List v, {int top = 5}) {
    final best = <String, double>{};
    for (final a in angles) {
      final s = dot(v, a.vector);
      if (s > (best[a.name] ?? -2)) best[a.name] = s;
    }
    final out = [for (final e in best.entries) (name: e.key, score: e.value)]
      ..sort((a, b) => b.score.compareTo(a.score));
    return out.take(top).toList();
  }
}
