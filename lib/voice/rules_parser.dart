import 'command.dart';
import 'numbers.dart';

/// Offline, rule-based command parser for Hinglish, Hindi (Devanagari) and English. No model:
/// keyword lists decide WHAT is asked, the catalog decides WHICH product, the words around each
/// number decide whether it's a price or a quantity. The baseline an on-device LLM has to beat
/// on `eval/voice_eval_200.json`.
class RulesParser implements CommandParser {
  @override
  String get name => 'Rules (offline)';

  @override
  Future<Parsed> parse(String text, List<String> catalog) async => parseNow(text, catalog);

  Parsed parseNow(String text, List<String> catalog) {
    final whole = _parseClause(text, catalog, null);
    if (whole is _Create) return whole.parsed;

    // "Maggi ka rate 14 kar, aur stock bhi bees kar dena" = two commands. Split into clauses and use
    // the split only when at least two clauses are complete commands on their own.
    final clauses = text.split(RegExp(r',|;| aur | and | और | par | but | पर ', caseSensitive: false));
    if (clauses.length > 1) {
      final cmds = <Command>[];
      String? product;
      for (final c in clauses) {
        final r = _parseClause(c, catalog, product);
        if (r is _One && r.cmd.product != null) product = r.cmd.product;
        if (r is _One && r.complete) cmds.add(r.cmd);
      }
      if (cmds.length >= 2) return Parsed.ready(cmds);
    }
    return switch (whole) {
      _One(:final cmd) => _check(cmd),
      _Ask(:final question) => Parsed.ask(question),
      _ => const Parsed.ask('Samjha nahi. Product aur kya badalna hai, bataiye.'),
    };
  }

  /// Turns a command with missing parts into the question to ask back.
  Parsed _check(Command c) {
    if (c.tool == Tool.showCatalog) return Parsed.ready([c]);
    if (c.product == null) {
      return Parsed.ask(switch (c.tool) {
        Tool.setPrice ||
        Tool.changePrice => c.price == null ? 'Kis product ka rate?' : 'Kis product ka price ₹${c.price} karna hai?',
        Tool.renameProduct => 'Kis product ka naam aur naya naam kya hona chahiye?',
        Tool.deleteProduct => 'Kaunsa product remove karna hai?',
        _ => c.qty == null ? 'Kaunsa product?' : 'Kaunse product ke ${c.qty} hain?',
      });
    }
    final needsQty = {Tool.setStock, Tool.addStock, Tool.removeStock}.contains(c.tool);
    if (needsQty && c.qty == null) return Parsed.ask('${c.product} ke kitne?');
    if ((c.tool == Tool.setPrice || c.tool == Tool.changePrice) && c.price == null) {
      return Parsed.ask('${c.product} ka naya rate kya hai?');
    }
    if (c.tool == Tool.renameProduct && c.newName == null) return Parsed.ask('${c.product} ka naya naam kya hai?');
    return Parsed.ready([c]);
  }

  // ------------------------------------------------------------ one clause

  _Result _parseClause(String text, List<String> catalog, String? inherited) {
    final low = text.toLowerCase();
    final tokens = tokenize(text);
    final nums = _quantities(tokens);
    final product = _matchCatalog(text, catalog) ?? inherited;
    bool has(List<String> words) => words.any((w) => _contains(low, w));

    // Rename: "Maggi Masala ka naam Maggi 2-Minute kar de", "rename X as Y", "change X to Y".
    final rename = _rename(text, catalog);
    if (rename != null) return _One(rename, complete: true);

    if (has(_show) && has(_showVerb)) return _One(const Command(Tool.showCatalog), complete: true);

    // A new product (from photos just taken): name + price (+ stock).
    if (has(_createStrong)) return _Create(_create(text, tokens, nums));

    if (has(_deleteVerb) && (has(_productWord) || nums.isEmpty) && !has(_stockChange)) {
      return _One(Command(Tool.deleteProduct, product: product), complete: product != null);
    }

    final question = has(_question) || low.trim().endsWith('?');
    if (question && !has(_stockChange) && !has(_add)) {
      final tool = has(_priceWord) ? Tool.getPrice : Tool.getStock;
      return _One(Command(tool, product: product), complete: product != null);
    }

    final last = nums.isEmpty ? null : nums.last.value; // self-corrections: the last number wins
    final priceTalk = has(_priceWord) || nums.any((n) => _isPrice(tokens, n));
    if (priceTalk && has(_up) && last != null) {
      return _One(
        Command(Tool.changePrice, product: product, price: last),
        complete: product != null,
      );
    }
    if (priceTalk && has(_down) && last != null) {
      return _One(
        Command(Tool.changePrice, product: product, price: -last),
        complete: product != null,
      );
    }
    if (priceTalk && !has(_remove) && !has(_add) && !has(_left)) {
      return _One(
        Command(Tool.setPrice, product: product, price: last),
        complete: product != null && last != null,
      );
    }
    if (has(_remove)) {
      return _One(
        Command(Tool.removeStock, product: product, qty: last),
        complete: last != null,
      );
    }
    if (has(_add)) {
      return _One(
        Command(Tool.addStock, product: product, qty: last),
        complete: last != null,
      );
    }
    if (has(_zero) && last == null) return _One(Command(Tool.setStock, product: product, qty: 0), complete: true);
    if (last != null) {
      return _One(
        Command(Tool.setStock, product: product, qty: last),
        complete: has(_left) || has(_stockWord),
      );
    }
    if (has(_left) || has(_stockWord)) return _One(Command(Tool.setStock, product: product), complete: false);
    return const _Nothing();
  }

  /// Numbers that are quantities or prices: drops pack sizes ("500 ml", "250 gram", "1 litre").
  static List<({int value, int start, int end})> _quantities(List<String> tokens) => [
    for (final n in numberSpans(tokens))
      if (n.end + 1 >= tokens.length || !_sizeUnits.contains(tokens[n.end + 1])) n,
  ];

  static bool _isPrice(List<String> tokens, ({int value, int start, int end}) n) {
    final before = n.start > 0 ? tokens[n.start - 1] : '';
    final after = n.end + 1 < tokens.length ? tokens[n.end + 1] : '';
    return _priceBefore.contains(before) || _priceAfter.contains(after);
  }

  static bool _isStockNumber(List<String> tokens, ({int value, int start, int end}) n) {
    final before = n.start > 0 ? tokens[n.start - 1] : '';
    final after = n.end + 1 < tokens.length ? tokens[n.end + 1] : '';
    return _qtyBefore.contains(before) || _qtyAfter.contains(after);
  }

  // ------------------------------------------------------------ create

  Parsed _create(String text, List<String> tokens, List<({int value, int start, int end})> nums) {
    num? price, qty;
    for (final n in nums) {
      if (_isStockNumber(tokens, n)) {
        qty = n.value;
      } else if (_isPrice(tokens, n) || price == null) {
        price ??= n.value;
      } else {
        qty ??= n.value;
      }
    }
    final name = _newProductName(text);
    if (name == null) return const Parsed.ask('Product ka naam kya hai?');
    if (price == null) return Parsed.ask('$name ka price kya rakhein?');
    return Parsed.ready([Command(Tool.createProduct, product: name, price: price, qty: qty)]);
  }

  /// The new product's name from phrases like "naam hai X", "isko X bolke", "as X", "this one is X".
  static String? _newProductName(String text) {
    const patterns = [
      r'naam\s+(?:hai\s+)?([^,.।]+?)\s+(?:hai|,|bol|rakh|ke naam)',
      r'naam\s+(?:hai\s+)?([^,.।]+?)(?:,|\.|।|$)',
      r'name is\s+([^,.]+)',
      r'isko\s+(.+?)\s+(?:bolke|bol ke|ke naam)',
      r'(?:save (?:this one|the pictures|these shots)?\s*(?:to catalog\s*)?as|add these shots to catalog as)\s+([^,.]+)',
      r'(?:this (?:new )?(?:one|item)(?: we photographed)?|it.s|this new item)\s+is\s+([^,.]+)',
      r'(?:ye|yeh|ye wala|yeh wala|picture wali ye|picture wali|photo wala ye|photo wali)\s+(?:naya\s+|nayi\s+)?(.+?)\s+(?:hai|,)',
      r'(?:नाम|नाम है)\s+([^,।]+?)\s*(?:है|,|।)',
      r'(?:वो|यह|ये)\s+([^,।]+?)\s+है',
    ];
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(text);
      if (m != null) {
        final name = _cleanName(m.group(1)!);
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// Strips filler words and prices from a captured name; keeps sizes ("Colgate 100g").
  static String _cleanName(String s) {
    final words = s
        .replaceAll(RegExp(r'[₹]\s*\d+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_nameFiller.contains(w.toLowerCase()))
        .toList();
    // Join a number with its unit: "100 gram" -> "100g", "500 ml" -> "500ml", "1 litre" -> "1L".
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final unit = i + 1 < words.length ? _unitShort[words[i + 1].toLowerCase()] : null;
      if (unit != null && RegExp(r'^\d+$').hasMatch(words[i])) {
        out.add('${words[i]}$unit');
        i++;
      } else {
        out.add(words[i][0].toUpperCase() + words[i].substring(1));
      }
    }
    return out.join(' ').trim();
  }

  // ------------------------------------------------------------ rename

  static Command? _rename(String text, List<String> catalog) {
    const patterns = [
      r'(.+?)\s+ka naam\s+(.+?)\s+(?:kar|rakh|badal)',
      r'rename\s+(.+?)\s+(?:as|to)\s+(.+?)[.]?$',
      r'change\s+(.+?)\s+to\s+(.+?)(?:\s+in the list)?[.]?$',
      r'नाम\s+(.+?)\s+से\s+(.+?)\s+कर',
    ];
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(text);
      if (m == null) continue;
      final oldName = _matchCatalog(m.group(1)!, catalog) ?? _cleanName(m.group(1)!);
      final newName = _cleanName(m.group(2)!);
      if (oldName.isEmpty || newName.isEmpty) continue;
      return Command(Tool.renameProduct, product: oldName, newName: newName);
    }
    return null;
  }

  // ------------------------------------------------------------ catalog matching

  /// The catalog product mentioned in [text] (longest match wins, so "Coke 500ml" beats "Coke").
  /// Ignores case, spaces and dashes ("parle g" = "Parle-G"), allows small spelling slips by
  /// comparing consonants ("Dabar honey" = "Dabur Honey", "Maza" = "Maaza").
  static String? _matchCatalog(String text, List<String> catalog) {
    final flat = _flat(text);
    final skel = _skeleton(text);
    String? best;
    for (final name in catalog) {
      final key = _flat(name);
      final hit = key.isNotEmpty && (flat.contains(key) || (key.length >= 4 && skel.contains(_skeleton(name))));
      if (hit && (best == null || key.length > _flat(best).length)) best = name;
    }
    return best;
  }

  static String _flat(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]'), '');

  /// Letters without vowels and repeats: "maaza" -> "mz", "dabur honey" -> "dbrhn".
  static String _skeleton(String s) =>
      _flat(s).replaceAll(RegExp(r'[aeiouy]'), '').replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

  /// Whole-word match for Latin words; substring for Devanagari (words there join with matras).
  static bool _contains(String low, String word) {
    if (RegExp(r'[ऀ-ॿ]').hasMatch(word)) return low.contains(word);
    return RegExp('(?<![a-z])${RegExp.escape(word)}(?![a-z])').hasMatch(low);
  }

  // ------------------------------------------------------------ word lists

  static const _show = [
    'list',
    'catalog',
    'catalogue',
    'inventory',
    'लिस्ट',
    'सूची',
    'all the products',
    'saare product',
  ];
  static const _showVerb = ['show', 'dikha', 'dikhao', 'khol', 'open', 'दिखाओ', 'dekhna', 'see', 'products we have'];
  static const _createStrong = [
    'photo',
    'picture',
    'pictures',
    'shots',
    'फोटो',
    'click',
    'clicked',
    'register',
    'रजिस्टर',
    'naam hai',
    'name is',
    'ke naam se',
    'bolke',
    'bol ke',
    'new item',
    'naya item',
    'nayi',
    'this new',
    'save this',
    'save the pictures',
    'नया प्रोडक्ट',
    'नाम है',
    'this one is',
    'iska naam',
    'ye wala naya',
    'naya wala',
    'just clicked',
    'dikhaya',
    'दिखाया',
    'खींची',
    'naya daal',
  ];
  static const _deleteVerb = ['delete', 'remove', 'hata', 'hatao', 'हटा', 'हटाओ'];
  static const _productWord = [
    'product',
    'listing',
    'entry',
    'catalog',
    'प्रोडक्ट',
    'purana',
    'duplicate',
    'old',
    'wala hata',
    'chhota wala',
  ];
  static const _question = [
    'kitna',
    'kitne',
    'kitni',
    'how many',
    'how much',
    'कितने',
    'कितना',
    'कितनी',
    'check kar',
    'bata',
    'batao',
    'बताओ',
    'what is',
    'kya hai',
    'kya chal',
    'are there any',
    'dekh ke',
  ];
  static const _priceWord = [
    'rupaye',
    'rupay',
    'rupees',
    'rupee',
    'rs',
    '₹',
    'price',
    'rate',
    'kimat',
    'keemat',
    'कीमत',
    'भाव',
    'रुपये',
    'रुपए',
    'priced',
    'kitne ka',
    'kitne ki',
    'kitne mein',
    'कितने की',
    'selling price',
  ];
  static const _up = ['badha', 'badhao', 'badha de', 'increase', 'mehenga', 'बढ़ा'];
  static const _down = ['sasta', 'saste', 'cheaper', 'discount', 'सस्ता', 'kam kar'];
  static const _remove = [
    'bik',
    'bike',
    'bika',
    'biki',
    'bech',
    'sold',
    'sell',
    'toot',
    'tut',
    'phat',
    'kharab',
    'expire',
    'wapas',
    'return',
    'minus',
    'ghata',
    'ghatane',
    'kam kar',
    'hata',
    'nikal',
    'leaked',
    'leak',
    'de diya',
    'take away',
    'deduct',
    'remove',
    'बिक',
    'टूट',
    'निकाल',
    'कम कर',
    'वापस',
  ];
  static const _add = [
    'aaye',
    'aaya',
    'aayi',
    'aa gaye',
    'aa gayi',
    'aa gaya',
    'mile',
    'mila',
    'mili',
    'naye',
    'extra',
    'receive',
    'received',
    'delivery',
    'came',
    'got another',
    'just got',
    'add',
    'daal',
    'jod',
    'chadha',
    'rakh diye',
    'rakh di',
    'aur rakh',
    'rakh le',
    'chhod gaya',
    'another',
    'more stock',
    'आए',
    'आई',
    'आ गई',
    'आ गए',
    'मिली',
    'मिला',
    'जोड़',
    'रख दी',
    'और आ',
  ];
  static const _left = [
    'bach',
    'bache',
    'bachi',
    'bacha',
    'reh gaye',
    'reh gaya',
    'reh gayi',
    'left',
    'remaining',
    'count',
    'pade',
    'pada',
    'available',
    'बचे',
    'बची',
    'बचा',
    'निकलीं',
    'gin',
    'on the shelf',
    'exactly',
    'हैं',
    'hain',
    'hai',
  ];
  static const _zero = ['khatam', 'zero', 'ek bhi nahi', 'nahi bacha'];
  static const _stockWord = ['stock', 'स्टॉक', 'count', 'quantity'];
  static const _stockChange = [
    'bik',
    'bech',
    'sold',
    'toot',
    'phat',
    'aaye',
    'aaya',
    'aayi',
    'aa gaye',
    'expire',
    'kharab',
    'टूट',
    'बिक',
  ];
  static const _sizeUnits = {
    'ml',
    'l',
    'litre',
    'liter',
    'ltr',
    'litres',
    'g',
    'gm',
    'gram',
    'grams',
    'ग्राम',
    'लीटर',
    'मिली',
    'mililitre',
  };
  static const _unitShort = {
    'ml': 'ml',
    'gram': 'g',
    'grams': 'g',
    'gm': 'g',
    'g': 'g',
    'litre': 'L',
    'liter': 'L',
    'l': 'L',
    'ltr': 'L',
  };
  static const _priceBefore = {'₹', 'rs', 'price', 'rate', 'priced', 'at', 'kimat', 'कीमत'};
  static const _priceAfter = {
    'ka',
    'ki',
    'ke',
    'rupaye',
    'rupee',
    'rupees',
    'rs',
    'रुपये',
    'का',
    'की',
    'each',
    'mein',
    'में',
  };
  static const _qtyBefore = {'stock', 'quantity', 'qty', 'total', 'मात्रा', 'and'};
  static const _qtyAfter = {
    'packet',
    'packets',
    'pack',
    'packs',
    'piece',
    'pieces',
    'pcs',
    'bottle',
    'bottles',
    'box',
    'boxes',
    'pouch',
    'dabbe',
    'dabba',
    'hain',
    'in',
    'pade',
    'rakhe',
    'पैकेट',
    'पीस',
    'बोतल',
    'jar',
    'tubes',
    'bags',
  };
  static const _nameFiller = {
    'naya',
    'nayi',
    'wala',
    'wali',
    'woh',
    'ye',
    'yeh',
    'abhi',
    'jo',
    'hai',
    'ka',
    'ki',
    'ke',
    'aur',
    'and',
    'the',
    'this',
    'one',
    'new',
    'bhai',
    'arey',
    'haan',
    'item',
    'product',
    'photo',
    'picture',
    'naam',
    'is',
    'as',
    'rupaye',
    'rupees',
    'price',
    'stock',
    'packet',
    'packets',
    'वो',
    'है',
    'नया',
    'प्रोडक्ट',
    'नाम',
    'का',
  };
}

// ------------------------------------------------------------ clause results

sealed class _Result {
  const _Result();
}

class _One extends _Result {
  const _One(this.cmd, {required this.complete});
  final Command cmd;

  /// Has everything it needs on its own (used to decide whether a split into clauses is real).
  final bool complete;
}

class _Create extends _Result {
  const _Create(this.parsed);
  final Parsed parsed;
}

class _Ask extends _Result {
  const _Ask(this.question);
  final String question;
}

class _Nothing extends _Result {
  const _Nothing();
}
