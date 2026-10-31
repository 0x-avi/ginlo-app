import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What the label on a pack says, as far as OCR can tell. Either may be null.
typedef LabelGuess = ({String? name, double? price});

/// Reads the text on a product photo (ML Kit, on the phone, offline) and guesses its name and price.
Future<LabelGuess> readLabel(Uint8List jpeg) async {
  final file = File(p.join((await getTemporaryDirectory()).path, 'ginlo_ocr.jpg'));
  await file.writeAsBytes(jpeg);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
    final lines = [
      for (final b in text.blocks)
        for (final l in b.lines) (text: l.text.trim(), height: l.boundingBox.height),
    ];
    return guessLabel(lines);
  } finally {
    recognizer.close();
  }
}

/// Price = the number after MRP / ₹ / Rs; name = the tallest line of words (usually the brand).
LabelGuess guessLabel(List<({String text, double height})> lines) {
  final all = lines.map((l) => l.text).join('\n');
  final m = RegExp(
    r'(?:M\.?\s?R\.?\s?P\.?|₹|Rs\.?|INR)\s*[:.\-]?\s*(\d{1,4}(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(all);
  final price = m == null ? null : double.tryParse(m[1]!);

  const skip = [
    'mrp',
    'net',
    'wt',
    'weight',
    'ingredient',
    'best before',
    'mfd',
    'exp',
    'batch',
    'price',
    'incl',
    'taxes',
    'contents',
    'nutrition',
    'energy',
    'www',
    '.com',
    'fssai',
    'lic',
    'veg',
    'pack',
  ];
  final words = lines.where((l) {
    final t = l.text.toLowerCase();
    final letters = RegExp('[a-z]').allMatches(t).length;
    final digits = RegExp(r'\d').allMatches(t).length;
    return letters >= 3 && digits <= letters / 3 && !skip.any(t.contains) && l.text.length <= 30;
  }).toList()..sort((a, b) => b.height.compareTo(a.height));
  String? name;
  if (words.isNotEmpty) {
    name = words.first.text
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
  return (name: name, price: price);
}
