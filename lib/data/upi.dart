/// The link inside the payment QR. Any UPI app (Paytm, GPay, PhonePe...) that scans it opens a
/// payment to [upiId] with the amount already filled in, so the customer only confirms.
///   pa = payee address (UPI ID), pn = payee name, am = amount, cu = currency, tn = note
String upiUri({required String upiId, required String shopName, required double amount, required String note}) {
  final q = {
    'pa': upiId.trim(),
    'pn': shopName.trim(),
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    'tn': note,
  }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return 'upi://pay?$q';
}

/// A UPI ID looks like name@bank (e.g. ishastore@paytm).
bool looksLikeUpiId(String s) => RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(s.trim());
