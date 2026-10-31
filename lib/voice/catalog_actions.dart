import '../data/db.dart';
import '../ui/format.dart';
import 'command.dart';

/// What a command would do to the catalog, in words, before anything changes.
class Proposal {
  final Command cmd;
  final Product? product; // the catalog product it matched (null for a new product / not found)
  final String text; // shown to the shopkeeper: "Set Maggi stock: 12 → 3"
  final bool needsConfirm; // changes the catalog -> ask "yes / no" first
  final bool canApply; // false when the product wasn't found
  const Proposal(this.cmd, this.product, this.text, {required this.needsConfirm, required this.canApply});
}

/// Matches a command to the catalog and describes it. Read-only questions are answered right away.
Proposal propose(Command c, List<Product> products) {
  Product? find(String? name) {
    if (name == null) return null;
    final key = name.toLowerCase().trim();
    for (final p in products) {
      if (p.name.toLowerCase().trim() == key) return p;
    }
    return null;
  }

  final p = find(c.product);
  Proposal change(String text) => Proposal(c, p, text, needsConfirm: true, canApply: true);
  Proposal answer(String text) => Proposal(c, p, text, needsConfirm: false, canApply: false);

  if (c.tool == Tool.showCatalog) {
    if (products.isEmpty) return answer('No products yet.');
    return answer([for (final x in products) '• ${x.name}: ${inr(x.price)} · stock ${x.stock}'].join('\n'));
  }
  if (c.tool == Tool.createProduct) {
    if (p != null) {
      return change(
        '"${p.name}" already exists. Update it: price ${inr(p.price)} → ${inr(c.price!.toDouble())}'
        '${c.qty != null ? ', stock ${p.stock} → ${c.qty}' : ''}?',
      );
    }
    return change(
      'Add new product "${c.product}" at ${inr(c.price!.toDouble())}${c.qty != null ? ', stock ${c.qty}' : ''}? '
      '(Then teach it its angles in Learn.)',
    );
  }
  if (p == null) {
    final close = _closest(c.product ?? '', products);
    return Proposal(
      c,
      null,
      'I couldn\'t find "${c.product}" in your products.${close.isEmpty ? '' : ' Did you mean ${close.join(' or ')}?'}',
      needsConfirm: false,
      canApply: false,
    );
  }
  return switch (c.tool) {
    Tool.getStock => answer('${p.name}: ${p.stock} in stock.'),
    Tool.getPrice => answer('${p.name}: ${inr(p.price)}.'),
    Tool.setStock => change('Set ${p.name} stock: ${p.stock} → ${c.qty}?'),
    Tool.addStock => change('Add ${c.qty} to ${p.name}: stock ${p.stock} → ${p.stock + c.qty!}?'),
    Tool.removeStock => change(
      'Remove ${c.qty} from ${p.name}: stock ${p.stock} → ${(p.stock - c.qty!).clamp(0, 1 << 31)}?',
    ),
    Tool.setPrice => change('Change ${p.name} price: ${inr(p.price)} → ${inr(c.price!.toDouble())}?'),
    Tool.changePrice => change(
      '${c.price! >= 0 ? 'Raise' : 'Lower'} ${p.name} price by ${inr(c.price!.abs().toDouble())}: '
      '${inr(p.price)} → ${inr(p.price + c.price!)}?',
    ),
    Tool.renameProduct => change('Rename ${p.name} → ${c.newName}?'),
    Tool.deleteProduct => change('Delete ${p.name} and all its taught angles? This can\'t be undone.'),
    Tool.showCatalog || Tool.createProduct => answer(''), // handled above
  };
}

/// Does what a confirmed proposal says. Returns the message to show.
Future<String> apply(Proposal pr, AppDb db) async {
  final c = pr.cmd, p = pr.product;
  switch (c.tool) {
    case Tool.createProduct:
      if (p != null) {
        await db.updateProduct(p.id!, price: c.price!.toDouble(), stock: c.qty?.toInt());
        return 'Updated ${p.name}.';
      }
      await db.upsertProduct(c.product!, c.price!.toDouble(), stock: c.qty?.toInt());
      return 'Added ${c.product}. Teach it in Learn so the camera can recognise it.';
    case Tool.setStock:
      await db.updateProduct(p!.id!, stock: c.qty!.toInt());
    case Tool.addStock:
      await db.updateProduct(p!.id!, stock: p.stock + c.qty!.toInt());
    case Tool.removeStock:
      await db.updateProduct(p!.id!, stock: p.stock - c.qty!.toInt());
    case Tool.setPrice:
      await db.updateProduct(p!.id!, price: c.price!.toDouble());
    case Tool.changePrice:
      await db.updateProduct(p!.id!, price: p.price + c.price!);
    case Tool.renameProduct:
      await db.updateProduct(p!.id!, name: c.newName);
    case Tool.deleteProduct:
      await db.deleteProduct(p!.id!);
    case Tool.getStock || Tool.getPrice || Tool.showCatalog:
      return '';
  }
  return 'Done ✓';
}

/// Up to 2 catalog names sharing a word with [spoken] (for "Did you mean ...?").
List<String> _closest(String spoken, List<Product> products) {
  final words = spoken.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 3).toSet();
  return [
    for (final p in products)
      if (p.name.toLowerCase().split(RegExp(r'\s+')).any(words.contains)) p.name,
  ].take(2).toList();
}

/// "haan" / "yes" / "ok" -> true, "nahi" / "no" / "cancel" -> false, anything else -> null.
bool? yesNo(String reply) {
  final t = reply.toLowerCase().trim().replaceAll(RegExp(r'[.!?।]'), '');
  const yes = {
    'haan',
    'han',
    'ha',
    'haa',
    'yes',
    'y',
    'ok',
    'okay',
    'theek',
    'theek hai',
    'thik hai',
    'thik',
    'kar do',
    'karo',
    'confirm',
    'sahi',
    'sahi hai',
    'ji',
    'haan ji',
    'हाँ',
    'हां',
    'ठीक है',
    'ठीक',
    'जी',
  };
  const no = {
    'no',
    'n',
    'nahi',
    'nahin',
    'nai',
    'na',
    'mat',
    'mat karo',
    'cancel',
    'galat',
    'nope',
    'rehne do',
    'नहीं',
    'ना',
    'मत',
  };
  if (yes.contains(t)) return true;
  if (no.contains(t)) return false;
  return null;
}
