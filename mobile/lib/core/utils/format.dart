import 'package:intl/intl.dart';

import '../i18n/i18n.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _rupeePaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// ₹1,250 for whole rupees, ₹62.50 otherwise.
String rupees(num value) => value == value.roundToDouble() ? _rupee.format(value) : _rupeePaise.format(value);

/// 2 instead of 2.00, 1.5 instead of 1.50.
String qty(num value) {
  final text = value.toStringAsFixed(2);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

// i18n:off (translated where used)
const unitLabels = {
  'kg': 'किलो',
  'g': 'ग्राम',
  'piece': 'पीस',
  'packet': 'पैकेट',
  'litre': 'लीटर',
  'dozen': 'दर्जन',
  'box': 'डिब्बा',
};
// i18n:on

String unitLabel(String unit) => tr(unitLabels[unit] ?? unit);

String distance(int? meters) {
  if (meters == null) return '';
  return meters < 1000 ? tr('{0} मी.', [meters]) : tr('{0} कि.मी.', [(meters / 1000).toStringAsFixed(1)]);
}

/// "1 घंटा 20 मिनट बाकी" style countdown text.
String timeLeft(DateTime until) {
  final left = until.difference(DateTime.now());
  if (left.isNegative) return tr('समय खत्म');
  if (left.inHours >= 1) return tr('{0} घं {1} मि बाकी', [left.inHours, left.inMinutes % 60]);
  if (left.inMinutes >= 1) return tr('{0} मि {1} से बाकी', [left.inMinutes, left.inSeconds % 60]);
  return tr('{0} सेकंड बाकी', [left.inSeconds]);
}

String dateTime(DateTime value) => DateFormat('d MMM, h:mm a').format(value);
String timeOnly(DateTime value) => DateFormat('h:mm a').format(value);

// i18n:off (translated where used)
const statusLabels = {
  // reservations
  'pending': 'दुकान के जवाब का इंतज़ार',
  'confirmed': 'कन्फर्म हुआ',
  'completed': 'पूरा हुआ',
  'rejected': 'अस्वीकार हुआ',
  'cancelled': 'रद्द हुआ',
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
// i18n:on

String statusLabel(String status) => tr(statusLabels[status] ?? status);
