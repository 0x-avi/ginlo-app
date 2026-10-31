import 'package:flutter/foundation.dart';

import 'sales.dart';

/// The bill being built: each "Add to bill" photo adds its items here, the invoice edits it,
/// and it's cleared once paid. One for the whole app, so it survives going back for more photos.
class BillDraft extends ChangeNotifier {
  BillDraft._();
  static final instance = BillDraft._();

  final List<BillLine> lines = [];

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (n, l) => n + l.qty);
  double get total => lines.fold(0.0, (t, l) => t + l.amount);

  /// Adds one photo's items: products already on the bill get their quantity increased.
  void addAll(Iterable<BillLine> items) {
    for (final it in items) {
      final i = lines.indexWhere((l) => l.name == it.name);
      if (i >= 0) {
        lines[i].qty += it.qty;
      } else {
        lines.add(BillLine(productId: it.productId, name: it.name, qty: it.qty, price: it.price));
      }
    }
    notifyListeners();
  }

  /// +1 / -1 from the invoice; a line at 0 is removed.
  void changeQty(int index, int delta) {
    lines[index].qty += delta;
    if (lines[index].qty <= 0) lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}
