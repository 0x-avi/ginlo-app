import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/data/bill_draft.dart';
import 'package:ginlo/data/sales.dart';
import 'package:ginlo/data/upi.dart';

void main() {
  test('UPI link has the amount with 2 decimals and encodes spaces', () {
    final uri = upiUri(upiId: 'ishastore@paytm', shopName: "Isha's Store", amount: 128, note: 'Bill 7');
    expect(uri, startsWith('upi://pay?'));
    expect(uri, contains('pa=ishastore%40paytm'));
    expect(uri, contains('am=128.00'));
    expect(uri, contains('cu=INR'));
    expect(uri, contains('pn=Isha\'s%20Store'));
    expect(uri, contains('tn=Bill%207'));
  });

  test('UPI ID check', () {
    expect(looksLikeUpiId('ishastore@paytm'), isTrue);
    expect(looksLikeUpiId(' 98765.43210@ybl '), isTrue);
    expect(looksLikeUpiId('paytm.me/ishastore'), isFalse);
    expect(looksLikeUpiId(''), isFalse);
  });

  test('bill draft merges photos, edits quantities, totals', () {
    final d = BillDraft.instance..clear();
    d.addAll([BillLine(name: 'Maggi', qty: 2, price: 14)]);
    d.addAll([BillLine(name: 'Maggi', qty: 1, price: 14), BillLine(name: 'Lays', qty: 1, price: 20)]);
    expect(d.lines.map((l) => '${l.name}x${l.qty}'), ['Maggix3', 'Laysx1']);
    expect(d.total, 62);
    d.changeQty(1, -1); // Lays to 0 -> removed
    expect(d.lines, hasLength(1));
    expect(d.itemCount, 3);
  });
}
