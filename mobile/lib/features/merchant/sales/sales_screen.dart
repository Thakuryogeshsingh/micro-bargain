import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

final salesProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/merchants/sales/', query: {'days': days}));
});

/// Shop owner: sales per day as a bar chart, totals and best sellers.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('बिक्री'))),
      body: AsyncView(
        value: ref.watch(salesProvider(_days)),
        onRetry: () => ref.invalidate(salesProvider(_days)),
        data: (d) {
          final series = (d['series'] as List).cast<Map>();
          final top = (d['top_products'] as List).cast<Map>();
          final max = series.fold<double>(0, (m, e) => parseNum(e['sales']) > m ? parseNum(e['sales']) : m);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(salesProvider(_days).future),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<int>(
                segments: [ButtonSegment(value: 7, label: Text(tr('7 दिन'))), ButtonSegment(value: 30, label: Text(tr('30 दिन')))],
                selected: {_days},
                onSelectionChanged: (v) => setState(() => _days = v.first),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _Stat(label: tr('कुल बिक्री'), value: rupees(parseNum(d['total'])), dark: true)),
                const SizedBox(width: 10),
                Expanded(child: _Stat(label: tr('ऑर्डर + पिकअप'), value: '${d['count']}')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(label: tr('औसत बिल'), value: rupees(parseNum(d['average'])))),
              ]),
              const SizedBox(height: 16),
              Container(
                height: 210,
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow(0.05)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < series.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${series[i]['date']}: ${rupees(parseNum(series[i]['sales']))}',
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: max == 0 ? 0 : parseNum(series[i]['sales']) / max),
                            duration: Duration(milliseconds: 500 + i * 20),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) => Container(
                              height: 4 + 150 * v,
                              margin: EdgeInsets.symmetric(horizontal: series.length > 10 ? 1 : 4),
                              decoration: BoxDecoration(
                                color: i == series.length - 1 ? AppTheme.ink : (AppTheme.minimal ? AppTheme.accent : AppTheme.primary),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (series.length <= 10 || i % 5 == 0)
                            Text((series[i]['date'] as String).substring(8),
                                style: TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
              ),
              SectionTitle(tr('सबसे ज़्यादा बिकने वाले')),
              if (top.isEmpty) Text(tr('इस दौरान कोई बिक्री नहीं।'), style: TextStyle(color: AppTheme.muted)),
              for (var i = 0; i < top.length; i++)
                FadeSlideIn(
                  index: i,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: i == 0 ? AppTheme.accent : AppTheme.chip,
                      child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: i == 0 ? Colors.black : AppTheme.ink)),
                    ),
                    title: Text(top[i]['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('{0} बिका', [qty(parseNum(top[i]['quantity']))])),
                    trailing: Text(rupees(parseNum(top[i]['sales'])), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.dark = false});

  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: dark ? AppTheme.heroGradient : null,
          color: dark ? null : AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: dark ? null : AppTheme.softShadow(0.05),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: dark ? Colors.white : AppTheme.ink)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : AppTheme.muted)),
        ]),
      );
}
