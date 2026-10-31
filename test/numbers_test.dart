import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/voice/numbers.dart';

void main() {
  test('digits, English, Hindi roman and Devanagari', () {
    expect(numbersIn('Sirf 5 hi Coke bachi hai'), [5]);
    expect(numbersIn('Maggi ke bas teen packet reh gaye'), [3]);
    expect(numbersIn('Coke ka rate chaalis kar de'), [40]);
    expect(numbersIn('Twenty-six eggs left'), [26]);
    expect(numbersIn('सर्फ एक्सेल का पैकेट एक सौ पचहत्तर का है'), [175]);
    expect(numbersIn('अभी सिर्फ चार साबुन बचे हैं'), [4]);
    expect(numbersIn('This one is Amul Taaza, 500 ml, ₹28. I have got 12'), [500, 28, 12]);
  });

  test('self-corrections keep every number (the parser takes the last)', () {
    expect(numbersIn('Coke ki bas, uh, paanch... nahi chaar bottle hain'), [5, 4]);
  });

  test('"do" after a verb means "do it", not 2', () {
    expect(numbersIn('teen dabbe kam kar do'), [3]);
    expect(numbersIn('Do packet Maggi phat gaye the, hata do'), [2]);
    expect(numbersIn('do Oreo ke packet expire ho gaye'), [2]);
  });
}
