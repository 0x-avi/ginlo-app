/// Numbers as shopkeepers say them: digits, English words, Hindi in Roman letters ("pandrah") and in
/// Devanagari ("पंद्रह"), including compounds like "एक सौ पचहत्तर" (175).
library;

const _english = {
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

/// Hindi number words in Roman letters (the common spellings people type or speech-to-text writes).
const _hindiRoman = {
  'shunya': 0,
  'ek': 1,
  'do': 2,
  'teen': 3,
  'tin': 3,
  'char': 4,
  'chaar': 4,
  'paanch': 5,
  'panch': 5,
  'chhe': 6,
  'chhah': 6,
  'che': 6,
  'chah': 6,
  'saat': 7,
  'sat': 7,
  'aath': 8,
  'ath': 8,
  'nau': 9,
  'das': 10,
  'dus': 10,
  'gyarah': 11,
  'gyara': 11,
  'barah': 12,
  'bara': 12,
  'baarah': 12,
  'terah': 13,
  'tera': 13,
  'chaudah': 14,
  'chauda': 14,
  'pandrah': 15,
  'pandra': 15,
  'solah': 16,
  'sola': 16,
  'satrah': 17,
  'satra': 17,
  'atharah': 18,
  'athara': 18,
  'unnis': 19,
  'unees': 19,
  'bees': 20,
  'bis': 20,
  'ikkis': 21,
  'bais': 22,
  'teis': 23,
  'chaubis': 24,
  'pachis': 25,
  'pachees': 25,
  'chhabbis': 26,
  'sattais': 27,
  'atthais': 28,
  'untis': 29,
  'tees': 30,
  'chalis': 40,
  'chaalis': 40,
  'pachas': 50,
  'pachaas': 50,
  'saath': 60,
  'sattar': 70,
  'assi': 80,
  'nabbe': 90,
  'sau': 100,
};

/// Hindi number words in Devanagari.
const _hindiDevanagari = {
  'शून्य': 0,
  'एक': 1,
  'दो': 2,
  'तीन': 3,
  'चार': 4,
  'पाँच': 5,
  'पांच': 5,
  'छह': 6,
  'छः': 6,
  'छे': 6,
  'सात': 7,
  'आठ': 8,
  'नौ': 9,
  'दस': 10,
  'ग्यारह': 11,
  'बारह': 12,
  'तेरह': 13,
  'चौदह': 14,
  'पंद्रह': 15,
  'पन्द्रह': 15,
  'सोलह': 16,
  'सत्रह': 17,
  'अठारह': 18,
  'उन्नीस': 19,
  'बीस': 20,
  'इक्कीस': 21,
  'बाईस': 22,
  'तेईस': 23,
  'चौबीस': 24,
  'पच्चीस': 25,
  'छब्बीस': 26,
  'सत्ताईस': 27,
  'अट्ठाईस': 28,
  'उनतीस': 29,
  'तीस': 30,
  'पैंतीस': 35,
  'चालीस': 40,
  'पैंतालीस': 45,
  'पचास': 50,
  'पचपन': 55,
  'साठ': 60,
  'पैंसठ': 65,
  'सत्तर': 70,
  'पचहत्तर': 75,
  'अस्सी': 80,
  'नब्बे': 90,
  'सौ': 100,
};

/// Verbs after which "do" means "do it", not 2.
const _verbsBeforeDo = {
  'kar',
  'hata',
  'daal',
  'dal',
  'rakh',
  'jod',
  'likh',
  'bata',
  'dikha',
  'bhej',
  'nikal',
  'ghata',
  'badha',
  'chadha',
  'de',
  'le',
  'mila',
  'bana',
  'badal',
  'hatao',
  'kardo',
  'karo',
};

/// Words like "twenty"/"forty" that can be followed by a units word ("twenty six").
const _tens = {20, 30, 40, 50, 60, 70, 80, 90};

/// Every number in [text], in the order spoken. "One hundred seventy five" / "एक सौ पचहत्तर" -> 175;
/// "twenty-six" -> 26; digits as digits.
List<int> numbersIn(String text) => [for (final n in numberSpans(tokenize(text))) n.value];

/// Numbers with where they are in [tokens] (start..end inclusive), so a parser can look at the
/// words around each one ("das **ka**" = a price, "bees **packet**" = a quantity).
List<({int value, int start, int end})> numberSpans(List<String> tokens) {
  final out = <({int value, int start, int end})>[];
  int? pending, start; // number being built from words, and where it began
  var end = 0;
  void flush() {
    if (pending != null) out.add((value: pending!, start: start!, end: end));
    pending = null;
    start = null;
  }

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    // Hinglish "do" is also "please do it": "kam kar do", "hata do" - not the number 2 there.
    if ((t == 'do' || t == 'दो') && (i == tokens.length - 1 || (i > 0 && _verbsBeforeDo.contains(tokens[i - 1])))) {
      flush();
      continue;
    }
    // English "this one" / "the new one" is a pronoun, not 1.
    if (t == 'one' &&
        i > 0 &&
        const {'this', 'that', 'which', 'the', 'new', 'old', 'any', 'same'}.contains(tokens[i - 1])) {
      flush();
      continue;
    }
    final digits = int.tryParse(t.replaceAll(RegExp(r'[₹,]'), ''));
    if (digits != null) {
      flush();
      out.add((value: digits, start: i, end: i));
      continue;
    }
    final w = _english[t] ?? _hindiRoman[t] ?? _hindiDevanagari[t] ?? (t == 'hundred' ? 100 : null);
    if (w == null) {
      flush();
      continue;
    }
    if (w == 100) {
      start ??= i;
      pending = (pending ?? 1) * 100; // "ek sau" / "one hundred"
    } else if (pending != null && pending! % 100 == 0 && pending! > 0) {
      pending = pending! + w; // "ek sau pachhattar"
    } else if (pending != null && _tens.contains(pending) && w < 10) {
      pending = pending! + w; // "twenty six"
    } else {
      flush();
      pending = w;
      start = i;
    }
    end = i;
  }
  flush();
  return out;
}

/// Lower-case words and numbers; keeps Devanagari letters, splits "twenty-six" and "₹40".
List<String> tokenize(String text) => text
    .toLowerCase()
    .replaceAll('₹', ' ₹ ')
    .split(RegExp(r'[^a-z0-9ऀ-ॿ₹.]+'))
    .map((t) => t.replaceAll(RegExp(r'^\.+|\.+$'), ''))
    .where((t) => t.isNotEmpty)
    .toList();
