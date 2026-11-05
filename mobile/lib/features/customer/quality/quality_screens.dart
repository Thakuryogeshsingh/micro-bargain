import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../wallet/wallet_screen.dart';

/// Must match the server's QUALITY_COMPLAINT_HOURS.
const complaintWindow = Duration(hours: 48);

bool canComplain(String status, DateTime? completedAt) =>
    status == 'completed' && completedAt != null && DateTime.now().difference(completedAt) < complaintWindow;

// i18n:off
const complaintReasons = {
  'stale': ('🥀', 'बासी / सड़ा हुआ'),
  'damaged': ('💥', 'टूटा / खराब'),
  'expired': ('📅', 'एक्सपायरी निकल चुकी'),
  'wrong_item': ('🔄', 'गलत सामान'),
  'short': ('⚖️', 'कम मात्रा'),
  'other': ('❓', 'कुछ और'),
};

const complaintStatuses = {
  'open': 'दुकान के जवाब का इंतज़ार',
  'refunded': 'रिफंड हो गया',
  'disputed': 'टीम जांच कर रही है',
  'rejected': 'शिकायत बंद',
};
// i18n:on

Color complaintColor(String status) => switch (status) {
      'refunded' => const Color(0xFF15803D),
      'rejected' => const Color(0xFFB91C1C),
      'disputed' => const Color(0xFF7C3AED),
      _ => const Color(0xFFD97706),
    };

final myComplaintsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).list('/quality/complaints/');
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

final refundsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => Map<String, dynamic>.from(await ref.watch(apiProvider).get('/customers/refunds/')),
);

/// "Bad quality?" button for a completed reservation or order.
class ComplaintButton extends ConsumerWidget {
  const ComplaintButton({super.key, this.reservationId, this.orderId, required this.shopName});

  final int? reservationId;
  final int? orderId;
  final String shopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: const Color(0xFFB91C1C),
          side: const BorderSide(color: Color(0xFFFCA5A5)),
        ),
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _ComplaintSheet(api: ref.read(apiProvider), reservationId: reservationId, orderId: orderId, shopName: shopName),
        ).then((sent) {
          if (sent == true) {
            ref.invalidate(myComplaintsProvider);
            if (context.mounted) context.push('/refunds');
          }
        }),
        icon: const Icon(Icons.report_problem_outlined),
        label: Text(tr('सामान खराब निकला? शिकायत करें')),
      ),
    );
  }
}

class _ComplaintSheet extends StatefulWidget {
  const _ComplaintSheet({required this.api, this.reservationId, this.orderId, required this.shopName});

  final ApiClient api;
  final int? reservationId;
  final int? orderId;
  final String shopName;

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  String? _reason;
  XFile? _photo;
  final _note = TextEditingController();

  Future<void> _pick(ImageSource source) async {
    final photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    if (photo != null) setState(() => _photo = photo);
  }

  Future<void> _submit() async {
    if (_reason == null || _photo == null) {
      showMessage(context, tr('दिक्कत चुनें और सामान की फोटो लगाएं'));
      return;
    }
    final ok = await runAction(context, () async => widget.api.post('/quality/complaints/', FormData.fromMap({
          if (widget.reservationId != null) 'reservation': widget.reservationId,
          if (widget.orderId != null) 'order': widget.orderId,
          'reason': _reason,
          'description': _note.text.trim(),
          'photo': await MultipartFile.fromFile(_photo!.path, filename: _photo!.name),
        })), success: tr('शिकायत दर्ज हो गई। दुकान 24 घंटे में जवाब देगी।'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('{0} — क्या दिक्कत हुई?', [widget.shopName]), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(tr('सही शिकायत पर पैसा सीधे आपके वॉलेट में आएगा।'), style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in complaintReasons.entries)
              ChoiceChip(
                label: Text('${e.value.$1} ${tr(e.value.$2)}'),
                selected: _reason == e.key,
                onSelected: (_) => setState(() => _reason = e.key),
              ),
          ]),
          const SizedBox(height: 12),
          if (_photo == null)
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: Text(tr('फोटो खींचें')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(tr('गैलरी')),
                ),
              ),
            ])
          else
            Stack(alignment: Alignment.topRight, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(File(_photo!.path), height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
              IconButton.filledTonal(onPressed: () => setState(() => _photo = null), icon: const Icon(Icons.close_rounded)),
            ]),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 1000,
            decoration: InputDecoration(hintText: tr('थोड़ा बताएं (ज़रूरी नहीं)')),
          ),
          FilledButton(onPressed: _submit, child: Text(tr('शिकायत भेजें'))),
          TextButton(onPressed: () => context.push('/refund-policy'), child: Text(tr('रिफंड पॉलिसी पढ़ें'))),
        ]),
      ),
    );
  }
}

/// Profile -> Refunds & complaints.
class RefundsScreen extends ConsumerWidget {
  const RefundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('रिफंड और शिकायतें')),
          actions: [
            TextButton(onPressed: () => context.push('/refund-policy'), child: Text(tr('पॉलिसी'))),
          ],
          bottom: TabBar(tabs: [Tab(text: tr('रिफंड')), Tab(text: tr('शिकायतें'))]),
        ),
        body: TabBarView(children: [
          AsyncView(
            value: ref.watch(refundsProvider),
            onRetry: () => ref.invalidate(refundsProvider),
            data: (data) {
              final rows = (data['refunds'] as List).cast<Map>();
              return RefreshIndicator(
                onRefresh: () => ref.refresh(refundsProvider.future),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  _TotalCard(total: parseNum(data['total'])),
                  const SizedBox(height: 8),
                  if (rows.isEmpty) EmptyView(icon: Icons.receipt_long_outlined, message: tr('अभी कोई रिफंड नहीं')),
                  for (var i = 0; i < rows.length; i++) FadeSlideIn(index: i, child: _RefundTile(row: rows[i])),
                ]),
              );
            },
          ),
          AsyncView(
            value: ref.watch(myComplaintsProvider),
            onRetry: () => ref.invalidate(myComplaintsProvider),
            data: (rows) => RefreshIndicator(
              onRefresh: () => ref.refresh(myComplaintsProvider.future),
              child: rows.isEmpty
                  ? ListView(children: [
                      EmptyView(
                        icon: Icons.verified_outlined,
                        message: tr('कोई शिकायत नहीं 👍\nसामान खराब निकले तो ऑर्डर/बुकिंग में "शिकायत करें" दबाएं।'),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => FadeSlideIn(index: i, child: ComplaintCard(c: rows[i])),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TotalCard extends ConsumerWidget {
  const _TotalCard({required this.total});

  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('अब तक कुल रिफंड'), style: const TextStyle(color: Colors.white70)),
            Text(rupees(total), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            Text(tr('वॉलेट: {0}', [rupees(walletBalance(ref))]), style: const TextStyle(color: Colors.white)),
          ]),
        ),
        const Icon(Icons.currency_exchange_rounded, color: Colors.white, size: 40),
      ]),
    );
  }
}

class _RefundTile extends StatelessWidget {
  const _RefundTile({required this.row});

  final Map row;

  @override
  Widget build(BuildContext context) {
    final wallet = row['method'] == 'wallet';
    final status = row['status'] as String;
    final (label, color) = switch (status) {
      'processed' => (wallet ? tr('वॉलेट में आ गया') : tr('बैंक में भेजा गया'), const Color(0xFF15803D)),
      'failed' => (tr('रुका हुआ — सपोर्ट से बात करें'), const Color(0xFFB91C1C)),
      _ => (tr('5-7 दिन में बैंक में'), const Color(0xFFD97706)),
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(wallet ? Icons.account_balance_wallet_rounded : Icons.account_balance_rounded, color: color),
        ),
        title: Text('${rupees(parseNum(row['amount']))} · ${row['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${row['reason']}\n${dateTime(parseTime(row['created_at'])!)}'),
        isThreeLine: true,
        trailing: Text(label, textAlign: TextAlign.end, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}

/// One complaint, used by customers and shops.
class ComplaintCard extends StatelessWidget {
  const ComplaintCard({super.key, required this.c, this.forShop = false, this.actions});

  final Map<String, dynamic> c;
  final bool forShop;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final status = c['status'] as String;
    final reason = complaintReasons[c['reason']];
    final color = complaintColor(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((c['photo'] ?? '') != '')
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(clipBehavior: Clip.antiAlias, child: CachedNetworkImage(imageUrl: c['photo'], fit: BoxFit.contain)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(imageUrl: c['photo'], width: 72, height: 72, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${reason?.$1 ?? ''} ${tr(reason?.$2 ?? c['reason'])}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(forShop ? '${c['customer_name'] ?? ''} · ${c['reference']}' : '${c['shop_name']} · ${c['reference']}',
                    style: TextStyle(color: AppTheme.muted)),
                Text(tr('खरीद: {0}', [rupees(parseNum(c['amount_paid']))]), style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    status == 'refunded'
                        ? tr('{0} रिफंड हुआ', [rupees(parseNum(c['refund_amount']))])
                        : tr(complaintStatuses[status] ?? status),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ]),
          if ((c['description'] ?? '') != '') ...[const SizedBox(height: 8), Text('"${c['description']}"')],
          if ((c['shop_note'] ?? '') != '') ...[const SizedBox(height: 6), Text(tr('दुकान: {0}', [c['shop_note']]))],
          if ((c['admin_note'] ?? '') != '') ...[const SizedBox(height: 6), Text(tr('टीम: {0}', [c['admin_note']]))],
          ?actions,
        ]),
      ),
    );
  }
}

/// The refund policy, in the app's language (the web page has the full legal text).
class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final points = [
      ('🥀', tr('खराब, बासी, गलत या कम सामान'), tr('पिकअप/डिलीवरी के 48 घंटे के अंदर फोटो के साथ ऐप में शिकायत करें।')),
      ('⏱️', tr('दुकान 24 घंटे में जवाब देगी'), tr('जवाब नहीं आया तो पूरा पैसा अपने आप आपके वॉलेट में आ जाएगा।')),
      ('⚖️', tr('असहमति हो तो टीम फैसला करेगी'), tr('दुकान शिकायत से असहमत हो तो Micro Bargain टीम फोटो देखकर 48 घंटे में फैसला करेगी।')),
      ('💰', tr('शिकायत का रिफंड तुरंत वॉलेट में'), tr('अगले ऑर्डर में इस्तेमाल करें। कैश और ऑनलाइन, दोनों तरह की खरीद पर लागू।')),
      ('❌', tr('ऑर्डर रद्द हुआ'), tr('दुकान ने मना किया या जवाब नहीं दिया, या आपने स्वीकार होने से पहले रद्द किया — पूरा पैसा वापस।')),
      ('🏦', tr('ऑनलाइन पेमेंट'), tr('बैंक/UPI में 5-7 कामकाजी दिनों में वापस। वॉलेट का पैसा तुरंत वॉलेट में।')),
      ('ℹ️', tr('ध्यान दें'), tr('एक खरीद पर एक ही शिकायत। वॉलेट का पैसा बैंक में नहीं निकाला जा सकता।')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('रिफंड पॉलिसी'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (var i = 0; i < points.length; i++)
          FadeSlideIn(
            index: i,
            child: Card(
              child: ListTile(
                leading: Text(points[i].$1, style: const TextStyle(fontSize: 28)),
                title: Text(points[i].$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(points[i].$3),
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push('/refunds'),
          icon: const Icon(Icons.receipt_long_rounded),
          label: Text(tr('मेरे रिफंड और शिकायतें')),
        ),
      ]),
    );
  }
}
