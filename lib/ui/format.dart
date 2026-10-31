/// ₹ with Indian digit grouping: 1240 -> ₹1,240.00, 1248000 -> ₹12,48,000.00 (lakhs, crores).
String inr(double amount, {int decimals = 2}) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  var whole = parts[0];
  // Last 3 digits, then groups of 2 (the Indian system).
  var out = whole.length > 3 ? whole.substring(whole.length - 3) : whole;
  whole = whole.length > 3 ? whole.substring(0, whole.length - 3) : '';
  while (whole.isNotEmpty) {
    final cut = whole.length > 2 ? whole.length - 2 : 0;
    out = '${whole.substring(cut)},$out';
    whole = whole.substring(0, cut);
  }
  return '${negative ? '-' : ''}₹$out${decimals > 0 ? '.${parts[1]}' : ''}';
}

/// "+12.4%" / "−6.0%".
String pct(double p) => '${p >= 0 ? '+' : '−'}${p.abs().toStringAsFixed(1)}%';

/// "10:24 AM".
String clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}
