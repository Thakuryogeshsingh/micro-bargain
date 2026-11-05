import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/wallet/')),
);

double walletBalance(WidgetRef ref) => parseNum(ref.watch(walletProvider).value?['balance']);

// i18n:off
const _kinds = {'cashback': 'कैशबैक', 'used': 'ऑर्डर में इस्तेमाल', 'returned': 'वापस आया (ऑर्डर रद्द)'};
// i18n:on

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मेरा वॉलेट'))),
      body: AsyncView(
        value: ref.watch(walletProvider),
        data: (data) {
          final entries = (data['entries'] as List).cast<Map>();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(walletProvider.future),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('वॉलेट बैलेंस'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(rupees(parseNum(data['balance'])),
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(tr('हर खरीद पर {0}% कैशबैक। अगले ऑर्डर में कार्ट से इस्तेमाल करें।', [data['cashback_percent']]),
                        style: const TextStyle(color: Colors.white)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                EmptyView(icon: Icons.account_balance_wallet_outlined, message: tr('अभी कोई लेन-देन नहीं।\nपहली खरीद पर कैशबैक पाएं!')),
              for (var i = 0; i < entries.length; i++)
                FadeSlideIn(
                  index: i,
                  child: _EntryTile(entry: entries[i]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final Map entry;

  @override
  Widget build(BuildContext context) {
    final amount = parseNum(entry['amount']);
    final credit = amount >= 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: credit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        child: Icon(credit ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: credit ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
      ),
      title: Text(tr(_kinds[entry['kind']] ?? entry['kind'])),
      subtitle: Text('${entry['reference']} · ${dateTime(parseTime(entry['created_at'])!)}'),
      trailing: Text(
        '${credit ? '+' : '-'} ${rupees(amount.abs())}',
        style: TextStyle(fontWeight: FontWeight.w800, color: credit ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
      ),
    );
  }
}
