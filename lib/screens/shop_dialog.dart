import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/upi.dart';

/// Edit the store name and the UPI ID that customers pay to. Returns true when saved.
Future<bool> showShopDialog(BuildContext context) async {
  final shop = await (await AppDb.open()).shop();
  if (!context.mounted) return false;
  final name = TextEditingController(text: shop.name), upi = TextEditingController(text: shop.upiId);
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Your store'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Store name'),
            ),
            TextField(
              controller: upi,
              decoration: InputDecoration(
                labelText: 'UPI ID (customers pay to this)',
                hintText: 'e.g. ishastore@paytm',
                errorText: error,
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!looksLikeUpiId(upi.text)) {
                setState(() => error = 'Should look like name@bank');
                return;
              }
              await (await AppDb.open()).setShop(name.text, upi.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
}
