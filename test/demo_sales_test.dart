import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/data/db.dart';
import 'package:ginlo/data/demo_sales.dart';

void main() {
  test('a month of demo bills: every day, cheap items more often, power bank alone', () {
    final products = [
      const Product(id: 1, name: 'mirinda can', price: 40),
      const Product(id: 2, name: 'powerbank', price: 1000),
      const Product(id: 3, name: 'snap cable', price: 2000),
    ];
    final now = DateTime(2026, 10, 31, 21);
    final sales = demoSales(products, now);
    final days = {for (final s in sales) DateTime(s.time.year, s.time.month, s.time.day)};
    expect(days.length, greaterThanOrEqualTo(30));
    expect(sales.every((s) => !s.time.isAfter(now)), isTrue);
    final units = <String, int>{};
    for (final s in sales) {
      for (final l in s.lines) {
        units[l.name] = (units[l.name] ?? 0) + l.qty;
        if (l.price >= 500) expect(l.qty, 1);
      }
      expect(s.total, s.lines.fold(0.0, (t, l) => t + l.amount));
    }
    expect(units['mirinda can']!, greaterThan(units['powerbank']!));
    expect(demoSales(products, now), hasLength(sales.length)); // same seed, same data
  });
}
