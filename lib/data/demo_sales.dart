import 'dart:math' as math;

import 'db.dart';
import 'sales.dart';

/// A month of believable bills for the dashboard demo, from the products in the catalog.
/// Cheap items sell often and in twos/threes, expensive ones (a ₹1000 power bank) rarely and alone;
/// more bills in the evening and on weekends; ~70% paid by UPI. Same seed = same data.
List<Sale> demoSales(List<Product> products, DateTime now, {int days = 30, int seed = 42}) {
  if (products.isEmpty) return [];
  final rnd = math.Random(seed);
  // How likely each product is to be in a bill: cheaper = more popular.
  final weights = [for (final p in products) 1 / math.sqrt(math.max(p.price, 1))];
  final totalWeight = weights.fold(0.0, (a, b) => a + b);
  Product pick() {
    var r = rnd.nextDouble() * totalWeight;
    for (var i = 0; i < products.length; i++) {
      r -= weights[i];
      if (r <= 0) return products[i];
    }
    return products.last;
  }

  final out = <Sale>[];
  var id = 0;
  for (var d = days; d >= 0; d--) {
    final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
    final weekend = day.weekday >= DateTime.saturday;
    final bills = 6 + rnd.nextInt(10) + (weekend ? 5 : 0);
    for (var b = 0; b < bills; b++) {
      // Busier around 10-12 and 18-21.
      final hour = [8, 9, 10, 10, 11, 11, 12, 13, 15, 16, 17, 18, 18, 19, 19, 20, 20, 21][rnd.nextInt(18)];
      final time = day.add(Duration(hours: hour, minutes: rnd.nextInt(60)));
      if (time.isAfter(now)) continue;
      final lines = <String, BillLine>{};
      for (var n = 1 + rnd.nextInt(3); n > 0; n--) {
        final p = pick();
        final expensive = p.price >= 500;
        if (expensive && lines.containsKey(p.name)) continue; // one of a costly item per bill
        final qty = expensive ? 1 : 1 + rnd.nextInt(3);
        lines.update(
          p.name,
          (l) => l..qty += qty,
          ifAbsent: () => BillLine(productId: p.id, name: p.name, qty: qty, price: p.price),
        );
      }
      final total = lines.values.fold(0.0, (t, l) => t + l.amount);
      out.add(Sale(id++, time, total, rnd.nextDouble() < 0.7 ? 'UPI' : 'Cash', lines.values.toList()));
    }
  }
  return out;
}
