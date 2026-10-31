import 'dart:convert';
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

/// Every knob of the smoothing, tunable live in the dev app (Bill → Smoothing settings).
class SmoothSettings {
  /// Name = most common name over this many recent frames of an item.
  int voteFrames = 8;

  /// An item is shown only after it's been seen in this many frames (kills one-frame ghosts).
  int showAfter = 3;

  /// An item survives this many frames in a row without being seen before it disappears.
  int keepMissed = 6;

  /// How far a box moves toward its new position each frame (0 = frozen, 1 = jumps).
  double glide = 0.35;

  /// Two boxes in consecutive frames are the same item if they overlap at least this much (IoU).
  double linkOverlap = 0.2;

  /// A shown box overlapping a bigger shown box at least this much is a duplicate and hidden
  /// (overlap = intersection / the smaller box's area, so a box fully inside another counts as 1).
  double mergeOverlap = 0.6;

  /// The item list shows each product's most common count over this many frames.
  int countFrames = 10;

  Map<String, num> toJson() => {
    'voteFrames': voteFrames,
    'showAfter': showAfter,
    'keepMissed': keepMissed,
    'glide': glide,
    'linkOverlap': linkOverlap,
    'mergeOverlap': mergeOverlap,
    'countFrames': countFrames,
  };

  /// Loads saved values; anything missing keeps its default.
  static SmoothSettings fromJsonString(String? s) {
    final out = SmoothSettings();
    if (s == null) return out;
    final m = jsonDecode(s) as Map<String, dynamic>;
    out
      ..voteFrames = (m['voteFrames'] as num? ?? out.voteFrames).toInt()
      ..showAfter = (m['showAfter'] as num? ?? out.showAfter).toInt()
      ..keepMissed = (m['keepMissed'] as num? ?? out.keepMissed).toInt()
      ..glide = (m['glide'] as num? ?? out.glide).toDouble()
      ..linkOverlap = (m['linkOverlap'] as num? ?? out.linkOverlap).toDouble()
      ..mergeOverlap = (m['mergeOverlap'] as num? ?? out.mergeOverlap).toDouble()
      ..countFrames = (m['countFrames'] as num? ?? out.countFrames).toInt();
    return out;
  }

  String toJsonString() => jsonEncode(toJson());
}

class _Track {
  _Track(Sighting s) : box = s.box {
    names.add(s.name);
    prices[s.name] = s.price;
  }
  Rect box;
  final names = <String?>[]; // recent frames' names, newest last
  final prices = <String?, double>{};
  int seen = 1; // frames this item has been seen in
  int misses = 0; // frames missed in a row
}

/// Smooths per-frame results for the shop app, so boxes don't flicker and names don't flip.
///
/// Each item gets a short memory (a "track"), linked frame to frame by box overlap:
///  - shown only after it's been seen in [SmoothSettings.showAfter] frames (one-frame ghosts never appear)
///  - box glides toward the new position instead of jumping
///  - name = most common name over the last [SmoothSettings.voteFrames] frames
///  - kept through [SmoothSettings.keepMissed] missed frames, then dropped
///  - a box overlapping a bigger shown box by [SmoothSettings.mergeOverlap] is a duplicate, hidden
class FrameSmoother {
  FrameSmoother([SmoothSettings? settings]) : settings = settings ?? SmoothSettings();
  final SmoothSettings settings;

  final _tracks = <_Track>[];

  void reset() => _tracks.clear();

  List<SteadyItem> update(List<Sighting> frame) {
    final p = settings;
    // Link each new sighting to the existing track it overlaps most (greedy, best overlap first).
    final pairs = <(double, int, int)>[];
    for (var t = 0; t < _tracks.length; t++) {
      for (var s = 0; s < frame.length; s++) {
        var o = _iou(_tracks[t].box, frame[s].box);
        // Moved fast (little overlap) but its centre is still close and it's a similar size: same item.
        if (o < p.linkOverlap && _near(_tracks[t].box, frame[s].box)) o = p.linkOverlap;
        if (o >= p.linkOverlap) pairs.add((o, t, s));
      }
    }
    pairs.sort((a, b) => b.$1.compareTo(a.$1));
    final usedT = <int>{}, usedS = <int>{};
    for (final (_, t, s) in pairs) {
      if (usedT.contains(t) || usedS.contains(s)) continue;
      usedT.add(t);
      usedS.add(s);
      final tr = _tracks[t], sg = frame[s];
      tr.box = Rect.lerp(tr.box, sg.box, p.glide)!;
      tr.names.add(sg.name);
      while (tr.names.length > p.voteFrames) {
        tr.names.removeAt(0);
      }
      tr.prices[sg.name] = sg.price;
      tr.seen++;
      tr.misses = 0;
    }
    for (var t = 0; t < _tracks.length; t++) {
      if (!usedT.contains(t)) _tracks[t].misses++;
    }
    _tracks.removeWhere((t) => t.misses > p.keepMissed);
    for (var s = 0; s < frame.length; s++) {
      if (!usedS.contains(s)) _tracks.add(_Track(frame[s]));
    }

    // Shown once seen in enough frames; biggest first so duplicates/parts of an item can be hidden.
    final shown = _tracks.where((t) => t.seen >= p.showAfter).toList()
      ..sort((a, b) => _area(b.box).compareTo(_area(a.box)));
    final out = <SteadyItem>[];
    final kept = <Rect>[];
    for (final t in shown) {
      if (kept.any((k) => _overlapOfSmaller(t.box, k) >= p.mergeOverlap)) continue;
      kept.add(t.box);
      final name = _vote(t.names);
      out.add(SteadyItem(t.box, name, t.prices[name] ?? 0));
    }
    return out;
  }

  /// Most common name; ties go to the most recent. An Unknown frame counts half, so one blurry
  /// frame doesn't turn "Maggi" into Unknown.
  static String? _vote(List<String?> names) {
    final counts = <String?, double>{};
    for (final n in names) {
      counts[n] = (counts[n] ?? 0) + (n == null ? 0.5 : 1);
    }
    String? best;
    var bestCount = 0.0;
    for (final n in names.reversed) {
      if (counts[n]! > bestCount) {
        best = n;
        bestCount = counts[n]!;
      }
    }
    return best;
  }

  static double _area(Rect r) => r.width * r.height;

  /// Centres within one box-length of each other and areas within 2× of each other.
  static bool _near(Rect a, Rect b) {
    final reach = [a.width, a.height, b.width, b.height].reduce((x, y) => x > y ? x : y);
    final ratio = _area(a) / _area(b);
    return (a.center - b.center).distance <= reach && ratio > 0.5 && ratio < 2;
  }

  static double _iou(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final inter = _area(i);
    return inter / (_area(a) + _area(b) - inter);
  }

  /// Intersection as a share of the smaller box (1 = one box fully inside the other).
  static double _overlapOfSmaller(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final smaller = _area(a) < _area(b) ? _area(a) : _area(b);
    return _area(i) / smaller;
  }
}

/// Steadies the item list: each product's count is its most common count over the last
/// [SmoothSettings.countFrames] frames, so "Maggi × 3" doesn't flick to × 2 and back.
class CountSmoother {
  CountSmoother(this.settings);
  final SmoothSettings settings;
  final _history = <Map<String?, int>>[]; // newest last; key null = Unknown

  void reset() => _history.clear();

  Map<String?, int> update(Map<String?, int> counts) {
    _history.add(counts);
    while (_history.length > settings.countFrames) {
      _history.removeAt(0);
    }
    final names = {for (final h in _history) ...h.keys};
    final out = <String?, int>{};
    for (final n in names) {
      final seen = <int, int>{}; // count value -> how many frames had it
      for (final h in _history) {
        final c = h[n] ?? 0;
        seen[c] = (seen[c] ?? 0) + 1;
      }
      // Most common value; on a tie prefer the newest frame's value.
      final newest = _history.last[n] ?? 0;
      var best = newest, bestFrames = seen[newest]!;
      seen.forEach((c, f) {
        if (f > bestFrames) {
          best = c;
          bestFrames = f;
        }
      });
      if (best > 0) out[n] = best;
    }
    return out;
  }
}
