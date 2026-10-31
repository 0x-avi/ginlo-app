import 'package:flutter/material.dart';

import '../data/bill_draft.dart';
import '../ui/theme.dart';
import 'payment_screen.dart';

/// The bill so far. Fix quantities with − / +, then either go back for more photos
/// ("Add more photos") or finish ("Done") and show the customer the payment QR.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = BillDraft.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Bill')),
      body: ListenableBuilder(
        listenable: draft,
        builder: (context, _) {
          if (draft.isEmpty) {
            return const Center(child: Text('Nothing on the bill yet. Add a photo of the items.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              GinloCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < draft.lines.length; i++)
                      _LineTile(
                        index: i,
                        name: draft.lines[i].name,
                        qty: draft.lines[i].qty,
                        price: draft.lines[i].price,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GinloCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${draft.itemCount} items',
                        style: const TextStyle(color: GinloColors.muted, fontSize: 15),
                      ),
                    ),
                    Text(
                      '₹${draft.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ListenableBuilder(
            listenable: draft,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                    onPressed: () => Navigator.pop(context), // back to the camera; the bill is kept
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add more photos'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: draft.isEmpty
                        ? null
                        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen())),
                    child: Text('Done · ₹${draft.total.toStringAsFixed(0)}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.index, required this.name, required this.qty, required this.price});
  final int index, qty;
  final String name;
  final double price;

  @override
  Widget build(BuildContext context) {
    final draft = BillDraft.instance;
    return ListTile(
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('₹${price.toStringAsFixed(2)} each'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(onPressed: () => draft.changeQty(index, -1), icon: const Icon(Icons.remove, size: 18)),
          SizedBox(
            width: 32,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton.filledTonal(onPressed: () => draft.changeQty(index, 1), icon: const Icon(Icons.add, size: 18)),
          SizedBox(width: 76, child: Text('₹${(qty * price).toStringAsFixed(2)}', textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
