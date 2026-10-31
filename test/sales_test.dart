import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/data/sales.dart';

Sale sale(int id, DateTime t, String payment, Map<String, (int, double)> items) {
  final lines = [for (final e in items.entries) BillLine(name: e.key, qty: e.value.$1, price: e.value.$2)];
  return Sale(id, t, lines.fold(0.0, (s, l) => s + l.amount), payment, lines);
}

void main() {
  final now = DateTime(2026, 10, 31, 15);

  test('today: total, change vs yesterday, top item, payment split, 2-hour bars', () {
    final today = [
      sale(1, DateTime(2026, 10, 31, 9), 'UPI', {'Maggi': (2, 14), 'Lays': (1, 20)}), // 48
      sale(2, DateTime(2026, 10, 31, 14), 'Cash', {'Maggi': (3, 14)}), // 42
    ];
    final yesterday = [
      sale(3, DateTime(2026, 10, 30, 10), 'UPI', {'Maggi': (1, 14), 'Lays': (2, 20)}),
    ]; // 54

    final s = SalesStats.compute(Period.daily, now, today, yesterday);
    expect(s.total, 90);
    expect(s.changePct, closeTo((90 - 54) / 54 * 100, 1e-9));
    expect(s.bills, 2);
    expect(s.avgBill, 45);
    expect(s.topItem!.name, 'Maggi');
    expect(s.topItem!.qty, 5);
    expect(s.topItem!.changePct, 400); // 1 sold yesterday -> 5 today
    expect(s.byPayment, {'UPI': 48.0, 'Cash': 42.0});
    expect(s.buckets, hasLength(12));
    expect(s.buckets[4].amount, 48); // 8-10 AM
    expect(s.buckets[7].amount, 42); // 2-4 PM
    expect(s.recent.first.id, 2); // newest first
  });

  test('no previous sales: no % change instead of dividing by zero', () {
    final s = SalesStats.compute(Period.daily, now, [
      sale(1, now, 'UPI', {'Maggi': (1, 14)}),
    ], []);
    expect(s.changePct, isNull);
  });

  test('periods: today and this month', () {
    final d = periodRange(Period.daily, now);
    expect(d.from, DateTime(2026, 10, 31));
    expect(d.prevFrom, DateTime(2026, 10, 30));
    final m = periodRange(Period.monthly, now);
    expect(m.from, DateTime(2026, 10));
    expect(m.to, DateTime(2026, 11));
    expect(m.prevFrom, DateTime(2026, 9));
  });
}
