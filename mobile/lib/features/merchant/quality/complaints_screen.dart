import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../../customer/quality/quality_screens.dart';
import '../merchant_providers.dart';

final shopComplaintsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).list('/quality/shop-complaints/');
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// Quality complaints about the shop: refund (to the customer's wallet) or explain and dispute.
class MerchantComplaintsScreen extends ConsumerWidget {
  const MerchantComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = parseNum(ref.watch(dashboardProvider).value?['quality_score'] ?? 100).round();
    return Scaffold(
      appBar: AppBar(title: Text(tr('क्वालिटी शिकायतें'))),
      body: AsyncView(
        value: ref.watch(shopComplaintsProvider),
        onRetry: () => ref.invalidate(shopComplaintsProvider),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(shopComplaintsProvider.future),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FadeSlideIn(child: _ScoreCard(score: score)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              EmptyView(icon: Icons.verified_rounded, message: tr('कोई शिकायत नहीं 🎉\nताज़ा सामान रखें, क्वालिटी स्कोर ऊंचा रहेगा।')),
            for (var i = 0; i < rows.length; i++)
              FadeSlideIn(
                index: i + 1,
                child: ComplaintCard(
                  c: rows[i],
                  forShop: true,
                  actions: rows[i]['status'] == 'open' ? _Actions(c: rows[i]) : null,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 95 ? const Color(0xFF15803D) : score >= 80 ? const Color(0xFFD97706) : const Color(0xFFB91C1C);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: score / 100, strokeWidth: 7, color: color, backgroundColor: color.withValues(alpha: 0.15)),
              Text('$score', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('आपका क्वालिटी स्कोर'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(tr('95+ पर ग्राहकों को "क्वालिटी पक्की" बैज दिखता है। 24 घंटे में जवाब न देने पर ग्राहक को पूरा रिफंड अपने आप हो जाता है।'),
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.c});

  final Map<String, dynamic> c;

  Future<void> _respond(BuildContext context, WidgetRef ref, Map<String, dynamic> body, String success) async {
    final ok = await runAction(context, () => ref.read(apiProvider).post('/quality/complaints/${c['id']}/respond/', body), success: success);
    if (ok) {
      ref.invalidate(shopComplaintsProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = parseNum(c['amount_paid']);
    final created = parseTime(c['created_at']);
    final left = created?.add(const Duration(hours: 24)).difference(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (left != null && !left.isNegative)
          Text(tr('⏱️ जवाब के लिए {0} घंटे बाकी', [left.inHours]),
              style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () async {
                if (await confirm(context, tr('{0} पूरा रिफंड दें?', [rupees(paid)]), icon: Icons.currency_rupee_rounded)) {
                  if (context.mounted) await _respond(context, ref, {'accept': true}, tr('रिफंड ग्राहक के वॉलेट में भेज दिया'));
                }
              },
              child: Text(tr('पूरा रिफंड')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final amount = await _ask(context, tr('कितना रिफंड दें? (₹{0} तक)', [qty(paid)]), number: true);
                if (amount == null || !context.mounted) return;
                await _respond(context, ref, {'accept': true, 'amount': amount}, tr('रिफंड ग्राहक के वॉलेट में भेज दिया'));
              },
              child: Text(tr('थोड़ा रिफंड')),
            ),
          ),
        ]),
        TextButton(
          onPressed: () async {
            final note = await _ask(context, tr('आप असहमत क्यों हैं? (टीम फोटो देखकर फैसला करेगी)'));
            if (note == null || !context.mounted) return;
            await _respond(context, ref, {'accept': false, 'note': note}, tr('टीम को भेज दिया'));
          },
          child: Text(tr('मैं असहमत हूँ')),
        ),
      ]),
    );
  }

  Future<String?> _ask(BuildContext context, String title, {bool number = false}) async {
    final text = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLines: number ? 1 : 3,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))] : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('रद्द'))),
          FilledButton(style: dialogButtonStyle, onPressed: () => Navigator.pop(dialog, text.text.trim()), child: Text(tr('भेजें'))),
        ],
      ),
    );
    return (value ?? '').isEmpty ? null : value;
  }
}
