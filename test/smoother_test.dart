import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/ml/smoother.dart';

const maggi = Rect.fromLTWH(0.1, 0.1, 0.3, 0.3);
Sighting seen(Rect box, String? name) => Sighting(box, name, 14);

/// Small numbers keep the mechanics tests short (the shop defaults are steadier).
SmoothSettings quick() => SmoothSettings()
  ..showAfter = 2
  ..keepMissed = 2
  ..glide = 0.5;

void main() {
  test('a box seen in only one frame never appears', () {
    final s = FrameSmoother(quick());
    expect(s.update([seen(maggi, 'Maggi')]), isEmpty);
    expect(s.update([]), isEmpty);
  });

  test('appears from the second frame and survives two missed frames', () {
    final s = FrameSmoother(quick());
    s.update([seen(maggi, 'Maggi')]);
    expect(s.update([seen(maggi, 'Maggi')]).single.name, 'Maggi');
    expect(s.update([]), hasLength(1)); // missed once
    expect(s.update([]), hasLength(1)); // missed twice
    expect(s.update([]), isEmpty); // gone
  });

  test('one wrong name does not flip the label', () {
    final s = FrameSmoother(quick());
    s.update([seen(maggi, 'Maggi')]);
    s.update([seen(maggi, 'Maggi')]);
    expect(s.update([seen(maggi, 'Lays')]).single.name, 'Maggi');
    expect(s.update([seen(maggi, null)]).single.name, 'Maggi'); // nor one "Unknown" frame
  });

  test('box glides instead of jumping', () {
    final s = FrameSmoother(quick());
    s.update([seen(maggi, 'Maggi')]);
    final moved = maggi.shift(const Offset(0.1, 0));
    expect(s.update([seen(moved, 'Maggi')]).single.box.left, closeTo(0.15, 1e-9)); // halfway
  });

  test('a box mostly inside a bigger one is hidden', () {
    final s = FrameSmoother(quick());
    const logo = Rect.fromLTWH(0.15, 0.15, 0.1, 0.1); // e.g. the logo on the pack
    s.update([seen(maggi, 'Maggi'), seen(logo, null)]);
    expect(s.update([seen(maggi, 'Maggi'), seen(logo, null)]).single.name, 'Maggi');
  });

  test('two separate items are both kept', () {
    final s = FrameSmoother(quick());
    const lays = Rect.fromLTWH(0.6, 0.5, 0.3, 0.3);
    s.update([seen(maggi, 'Maggi'), seen(lays, 'Lays')]);
    final out = s.update([seen(maggi, 'Maggi'), seen(lays, 'Lays')]);
    expect(out.map((i) => i.name), unorderedEquals(['Maggi', 'Lays']));
  });

  test('a duplicate box half-overlapping a bigger one is merged away', () {
    final s = FrameSmoother(quick());
    const dup = Rect.fromLTWH(0.2, 0.2, 0.25, 0.25); // 2nd box over most of the same can
    s.update([seen(maggi, 'Maggi'), seen(dup, 'Maggi')]);
    expect(s.update([seen(maggi, 'Maggi'), seen(dup, 'Maggi')]), hasLength(1));
  });

  test('settings are live: showAfter 3 needs three frames', () {
    final settings = SmoothSettings()..showAfter = 3;
    final s = FrameSmoother(settings);
    s.update([seen(maggi, 'Maggi')]);
    expect(s.update([seen(maggi, 'Maggi')]), isEmpty);
    expect(s.update([seen(maggi, 'Maggi')]), hasLength(1));
  });

  test('shop defaults hold an item through 6 missed frames', () {
    final s = FrameSmoother();
    for (var i = 0; i < 3; i++) {
      s.update([seen(maggi, 'Maggi')]);
    }
    for (var i = 0; i < 6; i++) {
      expect(s.update([]), hasLength(1));
    }
    expect(s.update([]), isEmpty);
  });

  test('a box that moved fast (no overlap) stays the same item', () {
    final s = FrameSmoother(quick());
    s.update([seen(maggi, 'Maggi')]);
    s.update([seen(maggi, 'Maggi')]);
    final jumped = maggi.shift(const Offset(0.2, 0.1)); // IoU 0.13 (< 0.2) but centre close
    expect(s.update([seen(jumped, 'Maggi')]), hasLength(1));
  });

  test('settings survive a save and load', () {
    final a = SmoothSettings()
      ..voteFrames = 6
      ..glide = 0.3;
    final b = SmoothSettings.fromJsonString(a.toJsonString());
    expect(b.voteFrames, 6);
    expect(b.glide, 0.3);
    expect(b.showAfter, SmoothSettings().showAfter); // untouched values keep defaults
  });

  test('item counts hold steady through a one-frame dip', () {
    final c = CountSmoother(SmoothSettings()..countFrames = 5);
    for (var i = 0; i < 3; i++) {
      c.update({'Maggi': 3});
    }
    expect(c.update({'Maggi': 2}), {'Maggi': 3}); // one frame saw only 2
    expect(c.update({'Maggi': 3}), {'Maggi': 3});
  });

  test('an item missing from most recent frames drops out of the list', () {
    final c = CountSmoother(SmoothSettings()..countFrames = 3);
    c.update({'Lays': 1});
    c.update({});
    expect(c.update({}), isEmpty);
  });
}
