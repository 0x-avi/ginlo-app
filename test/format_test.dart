import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/ui/format.dart';

void main() {
  test('rupees with Indian grouping', () {
    expect(inr(0), '₹0.00');
    expect(inr(24), '₹24.00');
    expect(inr(1240), '₹1,240.00');
    expect(inr(12480), '₹12,480.00');
    expect(inr(1248000.5), '₹12,48,000.50');
    expect(inr(123456789, decimals: 0), '₹12,34,56,789');
  });

  test('percent and clock', () {
    expect(pct(12.43), '+12.4%');
    expect(pct(-6), '−6.0%');
    expect(clock(DateTime(2026, 10, 31, 10, 24)), '10:24 AM');
    expect(clock(DateTime(2026, 10, 31, 0, 5)), '12:05 AM');
    expect(clock(DateTime(2026, 10, 31, 13, 0)), '1:00 PM');
  });
}
