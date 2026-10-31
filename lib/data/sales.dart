import 'dart:convert';

/// One line of a bill: a product, how many, at what price.
class BillLine {
  final int? productId;
  final String name;
  int qty;
  final double price;
  BillLine({this.productId, required this.name, required this.qty, required this.price});

  double get amount => qty * price;

  Map<String, Object?> toJson() => {'productId': productId, 'name': name, 'qty': qty, 'price': price};
  factory BillLine.fromJson(Map<String, dynamic> m) => BillLine(
    productId: m['productId'] as int?,
    name: m['name'] as String,
    qty: (m['qty'] as num).toInt(),
    price: (m['price'] as num).toDouble(),
  );
}

/// A paid bill.
class Sale {
  final int id;
  final DateTime time;
  final double total;
  final String payment; // 'UPI' or 'Cash'
  final List<BillLine> lines;
  const Sale(this.id, this.time, this.total, this.payment, this.lines);

  static List<BillLine> linesFromJson(String s) => [
    for (final m in jsonDecode(s) as List) BillLine.fromJson(m as Map<String, dynamic>),
  ];
  static String linesToJson(List<BillLine> lines) => jsonEncode([for (final l in lines) l.toJson()]);
}

/// The dashboard's time window.
enum Period {
  daily('Today', 'from yesterday'),
  monthly('This month', 'from last month'),
  lifetime('Lifetime', '');

  const Period(this.label, this.comparedTo);
  final String label;
  final String comparedTo;
}

/// Start (inclusive) and end (exclusive) of the period containing [now], and of the one before.
({DateTime from, DateTime to, DateTime prevFrom}) periodRange(Period p, DateTime now) {
  switch (p) {
    case Period.daily:
      final from = DateTime(now.year, now.month, now.day);
      return (from: from, to: from.add(const Duration(days: 1)), prevFrom: from.subtract(const Duration(days: 1)));
    case Period.monthly:
      final from = DateTime(now.year, now.month);
      return (from: from, to: DateTime(now.year, now.month + 1), prevFrom: DateTime(now.year, now.month - 1));
    case Period.lifetime:
      final from = DateTime(2000);
      return (from: from, to: now.add(const Duration(days: 1)), prevFrom: from);
  }
}

/// Everything the Home dashboard shows for one period. Pure Dart: [SalesStats.compute] only needs the sales.
class SalesStats {
  final double total;
  final double? changePct; // vs the previous period; null when there's nothing to compare
  final int bills;
  final int itemsSold;
  final double avgBill;

  /// Chart: (label, amount) per hour (today), per day (this month) or per month (lifetime).
  final List<({String label, double amount})> buckets;
  final ({String name, int qty, double? changePct})? topItem;
  final Map<String, int> itemsByName; // units sold
  final Map<String, double> byPayment; // amount per payment method
  final List<Sale> recent;

  const SalesStats({
    required this.total,
    required this.changePct,
    required this.bills,
    required this.itemsSold,
    required this.avgBill,
    required this.buckets,
    required this.topItem,
    required this.itemsByName,
    required this.byPayment,
    required this.recent,
  });

  /// [sales] in the period, [previous] in the period before (for the % change).
  static SalesStats compute(Period period, DateTime now, List<Sale> sales, List<Sale> previous) {
    double sum(List<Sale> s) => s.fold(0.0, (t, x) => t + x.total);
    double? pct(num cur, num prev) => prev == 0 ? null : (cur - prev) / prev * 100;

    Map<String, int> units(List<Sale> s) {
      final m = <String, int>{};
      for (final sale in s) {
        for (final l in sale.lines) {
          m[l.name] = (m[l.name] ?? 0) + l.qty;
        }
      }
      return m;
    }

    final items = units(sales), prevItems = units(previous);
    final byPayment = <String, double>{};
    for (final s in sales) {
      byPayment[s.payment] = (byPayment[s.payment] ?? 0) + s.total;
    }

    ({String name, int qty, double? changePct})? top;
    if (items.isNotEmpty) {
      final best = items.entries.reduce((a, b) => b.value > a.value ? b : a);
      top = (
        name: best.key,
        qty: best.value,
        changePct: period == Period.lifetime ? null : pct(best.value, prevItems[best.key] ?? 0),
      );
    }

    final total = sum(sales);
    return SalesStats(
      total: total,
      changePct: period == Period.lifetime ? null : pct(total, sum(previous)),
      bills: sales.length,
      itemsSold: items.values.fold(0, (a, b) => a + b),
      avgBill: sales.isEmpty ? 0 : total / sales.length,
      buckets: _buckets(period, now, sales),
      topItem: top,
      itemsByName: items,
      byPayment: byPayment,
      recent: (List.of(sales)..sort((a, b) => b.time.compareTo(a.time))).take(5).toList(),
    );
  }

  static List<({String label, double amount})> _buckets(Period period, DateTime now, List<Sale> sales) {
    switch (period) {
      case Period.daily: // 12 two-hour bars, like the "Daily" mock-up
        final out = List.generate(12, (i) => 0.0);
        for (final s in sales) {
          out[s.time.hour ~/ 2] += s.total;
        }
        String hour(int h) => h == 0
            ? '12 AM'
            : h < 12
            ? '$h AM'
            : h == 12
            ? '12 PM'
            : '${h - 12} PM';
        return [for (var i = 0; i < 12; i++) (label: hour(i * 2), amount: out[i])];
      case Period.monthly:
        final days = DateTime(now.year, now.month + 1, 0).day;
        final out = List.generate(days, (i) => 0.0);
        for (final s in sales) {
          out[s.time.day - 1] += s.total;
        }
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return [for (var d = 0; d < days; d++) (label: '${d + 1} ${months[now.month - 1]}', amount: out[d])];
      case Period.lifetime: // last 12 months
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final out = <({String label, double amount})>[];
        for (var i = 11; i >= 0; i--) {
          final m = DateTime(now.year, now.month - i);
          final amount = sales
              .where((s) => s.time.year == m.year && s.time.month == m.month)
              .fold(0.0, (t, s) => t + s.total);
          out.add((label: months[m.month - 1], amount: amount));
        }
        return out;
    }
  }
}
