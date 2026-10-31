import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'sales.dart';

/// "Rs. 1,240.00" — the PDF's built-in fonts have no ₹ sign.
String _rs(double v) {
  final s = v.toStringAsFixed(2);
  return 'Rs. $s';
}

/// A one-page A6 invoice for a paid bill.
Future<Uint8List> invoicePdf(Sale sale, String shopName, String upiId) async {
  final doc = pw.Document();
  final t = sale.time;
  final when =
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(shopName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (upiId.isNotEmpty) pw.Text('UPI: $upiId', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.Text('Invoice #${sale.id}   $when', style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Price', 'Amount'],
            data: [
              for (final l in sale.lines) [l.name, '${l.qty}', _rs(l.price), _rs(l.amount)],
            ],
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
            border: null,
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(_rs(sale.total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Text('Paid via ${sale.payment}', style: const pw.TextStyle(fontSize: 9)),
          pw.Spacer(),
          pw.Center(child: pw.Text('Thank you! Billed with Ginlo', style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Writes the invoice to a temporary file and opens Android's share sheet (WhatsApp, email...).
Future<void> shareInvoice(Sale sale, String shopName, String upiId) async {
  final bytes = await invoicePdf(sale, shopName, upiId);
  final file = File(p.join((await getTemporaryDirectory()).path, 'ginlo_invoice_${sale.id}.pdf'));
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      text: 'Invoice #${sale.id} from $shopName',
    ),
  );
}
