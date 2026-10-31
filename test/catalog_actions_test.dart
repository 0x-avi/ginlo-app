import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/data/db.dart';
import 'package:ginlo/voice/catalog_actions.dart';
import 'package:ginlo/voice/rules_parser.dart';

void main() {
  const products = [
    Product(id: 1, name: 'Maggi', price: 14, stock: 12),
    Product(id: 2, name: 'Coke 500ml', price: 40, stock: 6),
  ];
  final names = [for (final p in products) p.name];

  Proposal one(String text) =>
      propose(RulesParser(keepUnknownNames: true).parseNow(text, names).actions.single, products);

  test('changes are proposed with old -> new and need a yes', () {
    final p = one('Maggi ke bas teen packet reh gaye');
    expect(p.text, 'Set Maggi stock: 12 → 3?');
    expect(p.needsConfirm && p.canApply, isTrue);
    expect(one('Make the 500 ml Coke 45 rupees now').text, 'Change Coke 500ml price: ₹40.00 → ₹45.00?');
  });

  test('questions are answered straight away', () {
    final p = one('Maggi kitni bachi hai ab?');
    expect(p.text, 'Maggi: 12 in stock.');
    expect(p.needsConfirm, isFalse);
  });

  test('unknown product is not guessed', () {
    final p = one('Dettol soap ab 35 ka hai');
    expect(p.canApply, isFalse);
    expect(p.text, contains("couldn't find"));
  });

  test('yes / no in Hinglish, Hindi and English', () {
    for (final y in ['haan', 'Yes', 'ok', 'theek hai', 'हाँ']) {
      expect(yesNo(y), isTrue, reason: y);
    }
    for (final n in ['nahi', 'No.', 'nahin', 'cancel', 'नहीं']) {
      expect(yesNo(n), isFalse, reason: n);
    }
    expect(yesNo('Maggi 15 ka kar do'), isNull);
  });
}
