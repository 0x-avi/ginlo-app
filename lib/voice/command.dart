/// What a spoken/typed catalog command asks for. The names match `eval/voice_eval_200.json`.
enum Tool {
  setStock('set_stock'),
  addStock('add_stock'),
  removeStock('remove_stock'),
  setPrice('set_price'),
  changePrice('change_price'), // "2 rupaye badha de": price ± amount (the eval expects get_price first)
  getStock('get_stock'),
  getPrice('get_price'),
  createProduct('create_product'),
  renameProduct('rename_product'),
  deleteProduct('delete_product'),
  showCatalog('show_catalog');

  const Tool(this.id);
  final String id;

  /// Read-only tools answer straight away; everything else waits for "yes".
  bool get changesCatalog => !{getStock, getPrice, showCatalog}.contains(this);
}

/// One thing to do, e.g. set_stock(product: Maggi, qty: 3).
class Command {
  final Tool tool;
  final String? product; // as spoken; the screen matches it to a catalog product
  final num? qty;
  final num? price; // for changePrice: the change (+2 / -5)
  final String? newName;
  const Command(this.tool, {this.product, this.qty, this.price, this.newName});

  @override
  String toString() => '${tool.id}($product, qty: $qty, price: $price, newName: $newName)';
}

/// The parser's answer: actions to propose, or a question back ("Kaunsa soap?").
class Parsed {
  final List<Command> actions;
  final String? question;
  const Parsed.ready(this.actions) : question = null;
  const Parsed.ask(this.question) : actions = const [];

  bool get ready => question == null && actions.isNotEmpty;
}

/// Anything that turns text into commands: the rules parser now, an on-device LLM later.
abstract interface class CommandParser {
  String get name;
  Future<Parsed> parse(String text, List<String> catalog);
}
