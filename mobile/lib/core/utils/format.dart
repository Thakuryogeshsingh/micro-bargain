import 'package:intl/intl.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _rupeePaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// ₹1,250 for whole rupees, ₹62.50 otherwise.
String rupees(num value) => value == value.roundToDouble() ? _rupee.format(value) : _rupeePaise.format(value);

/// 2 instead of 2.00, 1.5 instead of 1.50.
String qty(num value) {
  final text = value.toStringAsFixed(2);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

const unitLabels = {
  'kg': 'किलो',
  'g': 'ग्राम',
  'piece': 'पीस',
  'packet': 'पैकेट',
  'litre': 'लीटर',
  'dozen': 'दर्जन',
  'box': 'डिब्बा',
};

String unitLabel(String unit) => unitLabels[unit] ?? unit;

String distance(int? meters) {
  if (meters == null) return '';
  return meters < 1000 ? '$meters मी.' : '${(meters / 1000).toStringAsFixed(1)} कि.मी.';
}

/// "1 घंटा 20 मिनट बाकी" style countdown text.
String timeLeft(DateTime until) {
  final left = until.difference(DateTime.now());
  if (left.isNegative) return 'समय खत्म';
  if (left.inHours >= 1) return '${left.inHours} घं ${left.inMinutes % 60} मि बाकी';
  if (left.inMinutes >= 1) return '${left.inMinutes} मि ${left.inSeconds % 60} से बाकी';
  return '${left.inSeconds} सेकंड बाकी';
}

String dateTime(DateTime value) => DateFormat('d MMM, h:mm a').format(value);
String timeOnly(DateTime value) => DateFormat('h:mm a').format(value);

const statusLabels = {
  // reservations
  'pending': 'दुकान के जवाब का इंतज़ार',
  'confirmed': 'कन्फर्म',
  'completed': 'पूरा हुआ',
  'rejected': 'अस्वीकार',
  'cancelled': 'रद्द',
  'expired': 'समय खत्म',
  // orders
  'pending_payment': 'पेमेंट बाकी',
  'ready': 'पिकअप के लिए तैयार',
  'out_for_delivery': 'डिलीवरी के रास्ते में',
  'refunded': 'रिफंड हुआ',
  // deals
  'draft': 'ड्राफ्ट',
  'active': 'लाइव',
  'paused': 'रुकी हुई',
  'sold_out': 'खत्म (बिक गई)',
  'ended': 'बंद',
};

String statusLabel(String status) => statusLabels[status] ?? status;
