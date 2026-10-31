import 'package:flutter/material.dart';

import '../data/db.dart';
import '../ml/embedder.dart';
import '../ml/models.dart';
import '../ml/vision.dart';
import 'learn_screen.dart';

/// The fingerprint model whose angles the catalog shows and the Learn tab saves.
final _model = embedderSpecs[Models.billEmbedder].id;

/// Products from the database: name, price, stock and how many angles have been taught.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog'), actions: const [_UpgradeAnglesButton()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProductDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Product'),
      ),
      // Reload whenever the database changes (AppDb.changes is bumped after every write).
      body: ValueListenableBuilder(
        valueListenable: AppDb.changes,
        builder: (context, _, _) => FutureBuilder(
          future: _load(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Database: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (products, counts) = snap.data!;
            if (products.isEmpty) {
              return const Center(child: Text('No products yet. Tap + Product, then teach it its angles.'));
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final p in products)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text('₹${p.price.toStringAsFixed(2)} · stock ${p.stock} · ${counts[p.id] ?? 0} angles'),
                    trailing: (counts[p.id] ?? 0) < 4
                        ? const Tooltip(message: 'Teach at least 4 angles', child: Icon(Icons.warning_amber))
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductScreen(product: p))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<(List<Product>, Map<int, int>)> _load() async {
    final db = await AppDb.open();
    return (await db.products(), await db.angleCounts(_model));
  }
}

/// Add-product dialog (name, price, stock). Returns the new product's id, or null if cancelled.
Future<int?> showProductDialog(BuildContext context) {
  final name = TextEditingController(), price = TextEditingController(), stock = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New product'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          TextField(
            controller: price,
            decoration: const InputDecoration(labelText: 'Price (₹)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          TextField(
            controller: stock,
            decoration: const InputDecoration(labelText: 'Stock'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final n = name.text.trim(), pr = double.tryParse(price.text);
            if (n.isEmpty || pr == null) return;
            final id = await (await AppDb.open()).upsertProduct(n, pr, stock: int.tryParse(stock.text) ?? 0);
            if (ctx.mounted) Navigator.pop(ctx, id);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// One product: its taught angles (tap 🗑 to remove a bad one), teach more, or delete it.
class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          IconButton(
            tooltip: 'Delete product',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete ${product.name}?'),
                  content: const Text('Its taught angles are deleted too.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true) return;
              await (await AppDb.open()).deleteProduct(product.id!);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(body: LearnView(productId: product.id)),
          ),
        ),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Teach angles'),
      ),
      body: ValueListenableBuilder(
        valueListenable: AppDb.changes,
        builder: (context, _, _) => FutureBuilder(
          future: AppDb.open().then((db) => db.productAngles(product.id!, _model)),
          builder: (context, snap) {
            final angles = snap.data;
            if (angles == null) return const Center(child: CircularProgressIndicator());
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                Text('₹${product.price.toStringAsFixed(2)} · stock ${product.stock}'),
                const SizedBox(height: 8),
                Text(
                  '${angles.length} taught angles. Remove any that are blurry, cut off or show the wrong thing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [for (final a in angles) _AngleTile(id: a.id, crop: a.crop)],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AngleTile extends StatelessWidget {
  const _AngleTile({required this.id, required this.crop});
  final int id;
  final dynamic crop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: crop == null ? const ColoredBox(color: Colors.black12) : Image.memory(crop, fit: BoxFit.cover),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton.filledTonal(
            tooltip: 'Remove this angle',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () async => (await AppDb.open()).deleteAngle(id),
          ),
        ),
      ],
    );
  }
}

/// Shows "Upgrade N" when some taught angles predate the teach variants (darker, brighter, turned,
/// further, closer); tapping re-fingerprints their stored crop pictures in all variants.
class _UpgradeAnglesButton extends StatefulWidget {
  const _UpgradeAnglesButton();

  @override
  State<_UpgradeAnglesButton> createState() => _UpgradeAnglesButtonState();
}

class _UpgradeAnglesButtonState extends State<_UpgradeAnglesButton> {
  int? _done; // progress while upgrading, null when idle

  Future<int> _pending() async =>
      (await (await AppDb.open()).anglesNeedingVariants(_model, teachVariants.length)).length;

  Future<void> _upgrade() async {
    final db = await AppDb.open();
    final todo = await db.anglesNeedingVariants(_model, teachVariants.length);
    final embedder = await Models.embedder(embedderSpecs[Models.billEmbedder]);
    setState(() => _done = 0);
    // A few pictures per background run, so the progress count moves.
    for (var i = 0; i < todo.length; i += 4) {
      final batch = todo.sublist(i, (i + 4).clamp(0, todo.length));
      final vectors = await Vision.embedStoredVariants(embedder, [for (final a in batch) a.crop]);
      for (var j = 0; j < batch.length; j++) {
        await db.replaceAngleVectors(batch[j].productId, _model, batch[j].crop, vectors[j]);
      }
      if (mounted) setState(() => _done = i + batch.length);
    }
    if (!mounted) return;
    setState(() => _done = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upgraded ${todo.length} angles: each now has ${teachVariants.length} variants')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: Text('Upgrading… $done')),
      );
    }
    return ValueListenableBuilder(
      valueListenable: AppDb.changes,
      builder: (context, _, _) => FutureBuilder(
        future: _pending(),
        builder: (context, snap) {
          final n = snap.data ?? 0;
          if (n == 0) return const SizedBox.shrink();
          return TextButton.icon(
            onPressed: _upgrade,
            icon: const Icon(Icons.auto_awesome),
            label: Text('Upgrade $n old angles'),
          );
        },
      ),
    );
  }
}
