import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

final dailyDayProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, day) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/daily/shop/', query: {'date': day}));
});

/// Shop owner: who gets what today (milk, bread...), tick off as delivered.
class MerchantDailyScreen extends ConsumerStatefulWidget {
  const MerchantDailyScreen({super.key});

  @override
  ConsumerState<MerchantDailyScreen> createState() => _MerchantDailyScreenState();
}

class _MerchantDailyScreenState extends ConsumerState<MerchantDailyScreen> {
  DateTime _day = DateTime.now();

  String get _key => _day.toIso8601String().substring(0, 10);

  Future<void> _mark(Map item, bool delivered) async {
    final ok = await runAction(context, () => ref.read(apiProvider).post('/daily/shop/${item['id']}/deliver/', {
          'date': _key,
          'delivered': delivered,
        }));
    if (ok) ref.invalidate(dailyDayProvider(_key));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = _day.year == today.year && _day.month == today.month && _day.day == today.day;
    return Scaffold(
      appBar: AppBar(title: Text(tr('रोज़ाना डिलीवरी'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            IconButton(
                onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Text(isToday ? tr('आज') : '${_day.day}/${_day.month}/${_day.year}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            IconButton(onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: ref.watch(dailyDayProvider(_key)),
            onRetry: () => ref.invalidate(dailyDayProvider(_key)),
            data: (data) {
              final items = [for (final r in data['items'] as List) Map<String, dynamic>.from(r)];
              final done = items.where((i) => i['delivery'] == 'delivered').length;
              if (items.isEmpty) {
                return EmptyView(
                  icon: Icons.event_available_rounded,
                  message: data['all_subscribers'] == 0
                      ? tr('अभी कोई ग्राहक रोज़ाना नहीं मंगवाता।\nग्राहक आपकी दुकान के पेज से "रोज़ मंगवाएं" चुन सकते हैं।')
                      : tr('इस दिन कोई डिलीवरी नहीं।'),
                );
              }
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Expanded(
                      child: Text(tr('{0} में से {1} पहुंचा दी', [items.length, done]),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: items.isEmpty ? 0 : done / items.length,
                        strokeWidth: 5,
                        color: AppTheme.minimal ? AppTheme.accent : Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < items.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        title: Text('${items[i]['product_name']} · ${qty(parseNum(items[i]['quantity']))} ${unitLabel(items[i]['unit'])}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text([
                          '${items[i]['customer_name'] ?? ''} · ${items[i]['slot'] == 'morning' ? tr('सुबह') : tr('शाम')}',
                          (items[i]['address_text'] as String).isEmpty ? tr('दुकान से लेंगे') : items[i]['address_text'],
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: tr('कॉल'),
                            onPressed: () => launchUrl(Uri.parse('tel:${items[i]['customer_phone']}')),
                            icon: const Icon(Icons.call_outlined),
                          ),
                          items[i]['delivery'] == 'delivered'
                              ? IconButton.filled(
                                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                                  onPressed: () => _mark(items[i], false),
                                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                                )
                              : IconButton.outlined(onPressed: () => _mark(items[i], true), icon: const Icon(Icons.check_rounded)),
                        ]),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
