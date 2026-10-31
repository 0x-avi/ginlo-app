import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/bill_draft.dart';
import '../data/db.dart';
import '../data/upi.dart';
import '../ui/theme.dart';
import 'shop_dialog.dart';

/// Turn the phone to the customer: a big UPI QR with the bill amount already in it.
/// They scan it with any UPI app; then tap "Paid via UPI" (or "Paid in cash") to save the sale.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  ({String name, String upiId})? _shop;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    final shop = await (await AppDb.open()).shop();
    if (mounted) setState(() => _shop = shop);
  }

  Future<void> _paid(String payment) async {
    final draft = BillDraft.instance;
    setState(() => _saving = true);
    final total = draft.total;
    await (await AppDb.open()).recordSale(List.of(draft.lines), total, payment);
    draft.clear();
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst); // back to the camera for the next customer
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('₹${total.toStringAsFixed(2)} saved ($payment)')));
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    final total = BillDraft.instance.total;
    if (shop == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final hasUpi = looksLikeUpiId(shop.upiId);
    final uri = upiUri(upiId: shop.upiId, shopName: shop.name, amount: total, note: 'Ginlo bill');

    return Scaffold(
      appBar: AppBar(title: const Text('Scan to pay')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          GinloCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(shop.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: GinloColors.ink),
                ),
                const SizedBox(height: 16),
                if (hasUpi)
                  QrImageView(
                    data: uri,
                    size: 260,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: GinloColors.blue),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: GinloColors.ink,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Text('Add your UPI ID to show the payment QR.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            if (await showShopDialog(context)) _loadShop();
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Set UPI ID'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (hasUpi)
                  Text(
                    'Scan with any UPI app · ${shop.upiId}',
                    style: const TextStyle(color: GinloColors.muted),
                    textAlign: TextAlign.center,
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
                  onPressed: _saving ? null : () => _paid('Cash'),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Paid in cash'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || !hasUpi ? null : () => _paid('UPI'),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Paid via UPI'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
