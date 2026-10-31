import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/ml/smoother.dart';

const maggi = Rect.fromLTWH(0.1, 0.1, 0.3, 0.3);
Sighting seen(Rect box, String? name) => Sighting(box, name, 14);

void main() {
  test('a box seen in only one frame never appears', () {
    final s = FrameSmoother();
    expect(s.update([seen(maggi, 'Maggi')]), isEmpty);
    expect(s.update([]), isEmpty);
  });

  test('appears from the second frame and survives two missed frames', () {
    final s = FrameSmoother();
    s.update([seen(maggi, 'Maggi')]);
    expect(s.update([seen(maggi, 'Maggi')]).single.name, 'Maggi');
    expect(s.update([]), hasLength(1)); // missed once
    expect(s.update([]), hasLength(1)); // missed twice
    expect(s.update([]), isEmpty); // gone
  });

  test('one wrong name does not flip the label', () {
    final s = FrameSmoother();
    s.update([seen(maggi, 'Maggi')]);
    s.update([seen(maggi, 'Maggi')]);
    expect(s.update([seen(maggi, 'Lays')]).single.name, 'Maggi');
    expect(s.update([seen(maggi, null)]).single.name, 'Maggi'); // nor one "Unknown" frame
  });

  test('box glides instead of jumping', () {
    final s = FrameSmoother();
    s.update([seen(maggi, 'Maggi')]);
    final moved = maggi.shift(const Offset(0.1, 0));
    expect(s.update([seen(moved, 'Maggi')]).single.box.left, closeTo(0.15, 1e-9)); // halfway
  });

  test('a box mostly inside a bigger one is hidden', () {
    final s = FrameSmoother();
    const logo = Rect.fromLTWH(0.15, 0.15, 0.1, 0.1); // e.g. the logo on the pack
    s.update([seen(maggi, 'Maggi'), seen(logo, null)]);
    expect(s.update([seen(maggi, 'Maggi'), seen(logo, null)]).single.name, 'Maggi');
  });

  test('two separate items are both kept', () {
    final s = FrameSmoother();
    const lays = Rect.fromLTWH(0.6, 0.5, 0.3, 0.3);
    s.update([seen(maggi, 'Maggi'), seen(lays, 'Lays')]);
    final out = s.update([seen(maggi, 'Maggi'), seen(lays, 'Lays')]);
    expect(out.map((i) => i.name), unorderedEquals(['Maggi', 'Lays']));
  });
}
