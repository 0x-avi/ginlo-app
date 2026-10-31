import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/invoice_pdf.dart';
import '../data/sales.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Shown after a bill is paid: the final invoice, with Share (PDF) and New bill.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Invoice #${sale.id}'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          GinloCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: GinloColors.up, size: 56),
                const SizedBox(height: 8),
                Text(inr(sale.total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                Text(
                  'Paid via ${sale.payment} · ${clock(sale.time)}',
                  style: const TextStyle(color: GinloColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GinloCard(
            child: Column(
              children: [
                for (final l in sale.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text('${l.qty} × ${inr(l.price)}', style: const TextStyle(color: GinloColors.muted)),
                        const SizedBox(width: 12),
                        SizedBox(width: 90, child: Text(inr(l.amount), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Text(inr(sale.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: () async {
                    final shop = await (await AppDb.open()).shop();
                    await shareInvoice(sale, shop.name, shop.upiId);
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share invoice'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), // back to the camera
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('New bill'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
