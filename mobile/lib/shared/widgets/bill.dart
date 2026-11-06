import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';

/// Printable bill page for an order / pickup (the token comes signed from the server).
String billUrl(String token) => '${AppConfig.siteUrl}/bill/$token/';

void openBill(String token) => launchUrl(Uri.parse(billUrl(token)), mode: LaunchMode.externalApplication);

/// Send the bill link on WhatsApp (to a customer's number, or let the person pick a chat).
void shareBill(String token, String number, {String phone = ''}) {
  final text = tr('आपका बिल {0}: {1}', [number, billUrl(token)]);
  final to = phone.length == 10 && !phone.contains('x') ? '91$phone' : '';
  launchUrl(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
}
