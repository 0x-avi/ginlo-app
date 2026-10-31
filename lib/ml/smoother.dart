import 'dart:ui' show Rect;

/// One item as seen in a single frame: its box and what the matcher called it (null = Unknown).
class Sighting {
  final Rect box;
  final String? name;
  final double price;
  const Sighting(this.box, this.name, this.price);
}

/// One item as shown in prod: steady box and a name voted over the last few frames.
class SteadyItem {
  final Rect box;
  final String? name; // null = Unknown
  final double price;
  const SteadyItem(this.box, this.name, this.price);
}

class _Track {
  _Track(Sighting s) : box = s.box {
    names.add(s.name);
    prices[s.name] = s.price;
  }
  Rect box;
  final names = <String?>[]; // last few frames' names, newest last
  final prices = <String?, double>{};
  int misses = 0; // frames missed in a row
}

/// Smooths per-frame results for the shop app, so boxes don't flicker and names don't flip.
///
/// Each item gets a short memory (a "track"), linked frame to frame by box overlap:
///  - shown only after it's been seen in [showAfter] frames (one-frame ghosts never appear)
///  - box glides toward the new position instead of jumping
///  - name = most common name over the last [window] frames
///  - kept through [keepMissed] missed frames, then dropped
///  - boxes lying mostly inside a bigger shown box are hidden (a part of the same item)
class FrameSmoother {
  FrameSmoother({this.window = 4, this.showAfter = 2, this.keepMissed = 2, this.glide = 0.5});
  final int window, showAfter, keepMissed;
  final double glide; // 0 = never move, 1 = jump to the new box

  final _tracks = <_Track>[];

  void reset() => _tracks.clear();

  List<SteadyItem> update(List<Sighting> frame) {
    // Link each new sighting to the existing track it overlaps most (greedy, best overlap first).
    final pairs = <(double, int, int)>[];
    for (var t = 0; t < _tracks.length; t++) {
      for (var s = 0; s < frame.length; s++) {
        final o = _iou(_tracks[t].box, frame[s].box);
        if (o > 0.3) pairs.add((o, t, s));
      }
    }
    pairs.sort((a, b) => b.$1.compareTo(a.$1));
    final usedT = <int>{}, usedS = <int>{};
    for (final (_, t, s) in pairs) {
      if (usedT.contains(t) || usedS.contains(s)) continue;
      usedT.add(t);
      usedS.add(s);
      final tr = _tracks[t], sg = frame[s];
      tr.box = Rect.lerp(tr.box, sg.box, glide)!;
      tr.names.add(sg.name);
      if (tr.names.length > window) tr.names.removeAt(0);
      tr.prices[sg.name] = sg.price;
      tr.misses = 0;
    }
    for (var t = 0; t < _tracks.length; t++) {
      if (!usedT.contains(t)) {
        _tracks[t].misses++;
      }
    }
    _tracks.removeWhere((t) => t.misses > keepMissed);
    for (var s = 0; s < frame.length; s++) {
      if (!usedS.contains(s)) _tracks.add(_Track(frame[s]));
    }

    // Shown once seen in enough frames; biggest first so parts of an item can be hidden.
    final shown = _tracks.where((t) => t.names.length >= showAfter).toList()
      ..sort((a, b) => _area(b.box).compareTo(_area(a.box)));
    final out = <SteadyItem>[];
    final kept = <Rect>[];
    for (final t in shown) {
      if (kept.any((k) => _insideFraction(t.box, k) > 0.8)) continue; // part of a bigger item
      kept.add(t.box);
      final name = _vote(t.names);
      out.add(SteadyItem(t.box, name, t.prices[name] ?? 0));
    }
    return out;
  }

  /// Most common name; ties go to the most recent.
  static String? _vote(List<String?> names) {
    final counts = <String?, int>{};
    for (final n in names) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    String? best;
    var bestCount = 0;
    for (final n in names.reversed) {
      if (counts[n]! > bestCount) {
        best = n;
        bestCount = counts[n]!;
      }
    }
    return best;
  }

  static double _area(Rect r) => r.width * r.height;

  static double _iou(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final inter = _area(i);
    return inter / (_area(a) + _area(b) - inter);
  }

  /// How much of [small] lies inside [big] (0..1).
  static double _insideFraction(Rect small, Rect big) {
    final i = small.intersect(big);
    if (i.width <= 0 || i.height <= 0) return 0;
    return _area(i) / _area(small);
  }
}
