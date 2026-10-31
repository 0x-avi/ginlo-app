import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/data/invoice_pdf.dart';
import 'package:ginlo/data/sales.dart';

void main() {
  test('invoice PDF renders', () async {
    final sale = Sale(7, DateTime(2026, 10, 31, 14, 5), 108, 'UPI', [
      BillLine(name: 'mirinda can', qty: 2, price: 40),
      BillLine(name: 'Maggi', qty: 2, price: 14),
    ]);
    final bytes = await invoicePdf(sale, "Isha's Store", 'ishastore@paytm');
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
