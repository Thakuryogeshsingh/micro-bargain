import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/utils/format.dart';
import '../models/models.dart';

/// Opens WhatsApp with the deal and its public link (which opens the app when installed).
void shareDeal({required Deal d}) {
  final link = '${AppConfig.siteUrl}/d/${d.id}/';
  final text = '🔥 ${d.productName} ${tr('सिर्फ')} ${rupees(d.offerPrice)}/${unitLabel(d.unit)} '
      '(${d.discountPercent.round()}% OFF) — ${d.shop.name}\n$link';
  launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
}
