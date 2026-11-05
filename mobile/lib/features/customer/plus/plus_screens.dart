import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

final plusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/plus/'));
});

final impactProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/impact/'));
});

const _gold = LinearGradient(colors: [Color(0xFF1F1A0E), Color(0xFF4A3A12)], begin: Alignment.topLeft, end: Alignment.bottomRight);
const _goldText = Color(0xFFF5C451);

/// "You saved ₹X and rescued Y kg of food" card for the profile.
class ImpactCard extends ConsumerWidget {
  const ImpactCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(impactProvider).value;
    if (data == null) return const SizedBox.shrink();
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF0D9488)]),
          borderRadius: AppTheme.radius,
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('आपकी कुल बचत'), style: const TextStyle(color: Colors.white70)),
              CountUp(
                value: parseNum(data['money_saved']),
                format: rupees,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                tr('🌱 {0} किलो खाना बर्बाद होने से बचाया', [qty(parseNum(data['food_rescued_kg']))]),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
          const Text('🌍', style: TextStyle(fontSize: 48)),
        ]),
      ),
    );
  }
}

/// Gold Bargain Plus banner for the profile: shows status or invites to join.
class PlusBanner extends ConsumerWidget {
  const PlusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(plusProvider).value;
    if (data == null) return const SizedBox.shrink();
    final active = data['active'] == true;
    return Pressable(
      onTap: () => context.push('/plus'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: _gold, borderRadius: AppTheme.radius),
        child: Row(children: [
          const Text('💎', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Bargain Plus', style: TextStyle(color: _goldText, fontSize: 18, fontWeight: FontWeight.w900)),
              Text(
                active
                    ? tr('चालू है · {0} तक', [dateTime(parseTime(data['ends_at'])!)])
                    : tr('फ्री डिलीवरी + हर ऑर्डर पर {0}% और छूट', [data['extra_percent']]),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ]),
          ),
          Icon(active ? Icons.verified_rounded : Icons.chevron_right_rounded, color: _goldText),
        ]),
      ),
    );
  }
}

class PlusScreen extends ConsumerWidget {
  const PlusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bargain Plus')),
      body: AsyncView(
        value: ref.watch(plusProvider),
        onRetry: () => ref.invalidate(plusProvider),
        data: (p) {
          final active = p['active'] == true;
          final benefits = [
            ('🚚', tr('हर ऑर्डर पर फ्री डिलीवरी')),
            ('💸', tr('हर ऑर्डर पर {0}% और छूट (₹{1} तक)', [p['extra_percent'], p['extra_cap']])),
            ('⭐', tr('नई डील की सूचना सबसे पहले')),
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(gradient: _gold, borderRadius: BorderRadius.circular(28), boxShadow: AppTheme.softShadow(0.2)),
                child: Column(children: [
                  const Text('💎', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 8),
                  const Text('Bargain Plus', style: TextStyle(color: _goldText, fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    active
                        ? tr('चालू है · {0} तक', [dateTime(parseTime(p['ends_at'])!)])
                        : tr('सिर्फ ₹{0} में {1} दिन', [p['price'], p['days']]),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < benefits.length; i++)
              FadeSlideIn(
                index: i + 1,
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: Text(benefits[i].$1, style: const TextStyle(fontSize: 26)),
                    title: Text(benefits[i].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A3A12), foregroundColor: _goldText),
              onPressed: () async {
                final api = ref.read(apiProvider);
                final ok = await runAction(context, () async {
                  final membership = await api.post('/customers/plus/');
                  if (!context.mounted || !await payOnline(context, api, purpose: 'membership', id: membership['id'])) {
                    throw ApiException(tr('पेमेंट पूरा नहीं हुआ'));
                  }
                }, success: tr('Bargain Plus चालू हो गया 💎'));
                if (ok) ref.invalidate(plusProvider);
              },
              child: Text(active ? tr('एक महीना और बढ़ाएं') : tr('₹{0} में Plus लें', [p['price']])),
            ),
          ]);
        },
      ),
    );
  }
}
