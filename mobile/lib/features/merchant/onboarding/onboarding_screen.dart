import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../merchant_providers.dart';

final onboardingProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => Map<String, dynamic>.from(await ref.watch(apiProvider).get('/merchants/onboarding/')),
);

final merchantProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => Map<String, dynamic>.from(await ref.watch(apiProvider).get('/merchants/profile/')),
);

// i18n:off
const _steps = {
  'owner': ('मालिक की जानकारी', 'आपका नाम और दुकान का प्रकार', Icons.person_rounded),
  'shop': ('दुकान की जानकारी और लोकेशन', 'नाम, पता, समय और मैप पर दुकान', Icons.storefront_rounded),
  'documents': ('दस्तावेज़', 'दुकान की फोटो और मालिक का ID ज़रूरी', Icons.badge_rounded),
  'payout': ('पेमेंट कहाँ लें', 'UPI ID या बैंक खाता', Icons.account_balance_rounded),
};

const _documents = {
  'shop_photo': 'दुकान की फोटो',
  'id_proof': 'मालिक का ID (आधार/PAN)',
  'fssai': 'FSSAI लाइसेंस',
  'gst': 'GST सर्टिफिकेट',
};

const _docStatus = {'pending': 'जांच बाकी', 'approved': 'सही है ✅', 'rejected': 'दोबारा भेजें'};
// i18n:on

void _refresh(WidgetRef ref) {
  ref.invalidate(onboardingProvider);
  ref.invalidate(merchantProfileProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(myShopProvider);
}

/// Step-by-step setup for a new shop owner, then the review status.
class ShopSetupScreen extends ConsumerWidget {
  const ShopSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('दुकान सेटअप'))),
      body: AsyncView(
        value: ref.watch(onboardingProvider),
        onRetry: () => ref.invalidate(onboardingProvider),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(onboardingProvider.future),
          child: _Body(data: data),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = (data['steps'] as List).cast<Map>();
    final done = steps.where((s) => s['done'] == true).length;
    final approved = data['shop_status'] == 'approved' && data['merchant_status'] == 'approved';
    final rejected = data['shop_status'] == 'rejected' || data['merchant_status'] == 'rejected';
    final submitted = data['submitted_at'] != null && !rejected;

    return ListView(padding: const EdgeInsets.all(16), children: [
      FadeSlideIn(child: _Header(done: done, total: steps.length, approved: approved, submitted: submitted)),
      const SizedBox(height: 12),
      if (approved)
        FadeSlideIn(
          index: 1,
          child: Card(
            color: const Color(0xFFDCFCE7),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('🎉 बधाई! आपकी दुकान लाइव है'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF15803D))),
                const SizedBox(height: 4),
                Text(tr('अब पास के ग्राहक आपकी दुकान देख सकते हैं। पहली डील डालें!')),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/merchant/deal-form'),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('पहली डील बनाएं')),
                ),
              ]),
            ),
          ),
        )
      else if (rejected)
        Card(
          color: const Color(0xFFFEE2E2),
          child: ListTile(
            leading: const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
            title: Text(tr('अप्रूव नहीं हुई'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(tr('{0}\nठीक करके नीचे से दोबारा जमा करें।', [data['rejection_reason'] ?? ''])),
          ),
        )
      else if (submitted)
        _ReviewTimeline(),
      const SizedBox(height: 8),
      for (var i = 0; i < steps.length; i++)
        FadeSlideIn(
          index: i + 2,
          child: _StepCard(number: i + 1, step: steps[i], data: data, locked: submitted || approved),
        ),
      const SizedBox(height: 16),
      if (!approved && !submitted)
        FilledButton.icon(
          onPressed: data['complete'] == true
              ? () async {
                  final ok = await runAction(context, () => ref.read(apiProvider).post('/merchants/onboarding/'),
                      success: tr('जमा हो गया! टीम जल्द जांच करेगी, अप्रूव होते ही नोटिफिकेशन आएगा।'));
                  if (ok) _refresh(ref);
                }
              : null,
          icon: const Icon(Icons.send_rounded),
          label: Text(data['complete'] == true ? tr('जांच के लिए जमा करें') : tr('पहले सभी स्टेप पूरे करें')),
        ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.done, required this.total, required this.approved, required this.submitted});

  final int done;
  final int total;
  final bool approved;
  final bool submitted;

  @override
  Widget build(BuildContext context) {
    final title = approved ? tr('सेटअप पूरा ✅') : submitted ? tr('जांच चल रही है ⏳') : tr('{0}/{1} स्टेप पूरे', [done, total]);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(tr('ये स्टेप पूरे करें, टीम जांच करके दुकान अप्रूव करेगी।'), style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: approved ? 1 : done / total),
            duration: const Duration(milliseconds: 700),
            builder: (_, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReviewTimeline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, bool done) => Row(children: [
          Icon(icon, color: done ? const Color(0xFF15803D) : AppTheme.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontWeight: done ? FontWeight.w800 : FontWeight.w500))),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row(Icons.check_circle_rounded, tr('जानकारी जमा हो गई'), true),
          const SizedBox(height: 10),
          row(Icons.manage_search_rounded, tr('टीम दस्तावेज़ और लोकेशन जांच रही है (आम तौर पर 24 घंटे)'), true),
          const SizedBox(height: 10),
          row(Icons.verified_rounded, tr('अप्रूव होते ही आपको नोटिफिकेशन आएगा'), false),
        ]),
      ),
    );
  }
}

class _StepCard extends ConsumerWidget {
  const _StepCard({required this.number, required this.step, required this.data, required this.locked});

  final int number;
  final Map step;
  final Map<String, dynamic> data;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = step['key'] as String;
    final done = step['done'] == true;
    final info = _steps[key]!;
    final color = done ? const Color(0xFF15803D) : AppTheme.accent;
    return Card(
      child: Column(children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: done ? Icon(Icons.check_rounded, color: color) : Text('$number', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ),
          title: Text(tr(info.$1), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(tr(info.$2)),
          trailing: Icon(info.$3, color: AppTheme.muted),
          onTap: () => _open(context, ref, key),
        ),
        if (key == 'documents' && data['shop_id'] != null) _Documents(data: data, locked: locked),
      ]),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String key) async {
    switch (key) {
      case 'owner':
        await _editOwner(context, ref);
      case 'shop':
        await context.push('/merchant/shop-form');
        _refresh(ref);
      case 'documents':
        if (data['shop_id'] == null) showMessage(context, tr('पहले दुकान की जानकारी भरें'));
      case 'payout':
        await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const PayoutSheet());
        _refresh(ref);
    }
  }

  Future<void> _editOwner(BuildContext context, WidgetRef ref) async {
    final profile = await ref.read(merchantProfileProvider.future);
    if (!context.mounted) return;
    final name = TextEditingController(text: profile['owner_name'] ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(tr('मालिक का नाम')),
        content: TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('पूरा नाम'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(tr('रद्द'))),
          FilledButton(style: dialogButtonStyle, onPressed: () => Navigator.pop(dialog, true), child: Text(tr('सेव करें'))),
        ],
      ),
    );
    if (saved != true || !context.mounted || name.text.trim().isEmpty) return;
    if (await runAction(context, () => ref.read(apiProvider).patch('/merchants/profile/update/', {'owner_name': name.text.trim()}))) {
      _refresh(ref);
    }
  }
}

class _Documents extends ConsumerWidget {
  const _Documents({required this.data, required this.locked});

  final Map<String, dynamic> data;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = (data['required_documents'] as List).cast<String>();
    final uploaded = <String, Map>{for (final d in (data['documents'] as List).cast<Map>()) d['doc_type'] as String: d};
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(children: [
        for (final e in _documents.entries)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.chip, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(uploaded.containsKey(e.key) ? Icons.task_alt_rounded : Icons.upload_file_rounded,
                  size: 20, color: uploaded.containsKey(e.key) ? const Color(0xFF15803D) : AppTheme.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr(e.value)}${required.contains(e.key) ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    uploaded.containsKey(e.key)
                        ? tr(_docStatus[uploaded[e.key]!['status']] ?? '')
                        : (required.contains(e.key) ? tr('ज़रूरी') : tr('हो तो लगाएं (ज़रूरी नहीं)')),
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ]),
              ),
              if (!locked || uploaded[e.key]?['status'] == 'rejected')
                TextButton(
                  onPressed: () => _upload(context, ref, e.key),
                  child: Text(uploaded.containsKey(e.key) ? tr('बदलें') : tr('अपलोड')),
                ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: Text(tr('फोटो खींचें')), onTap: () => Navigator.pop(sheet, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: Text(tr('गैलरी')), onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    if (photo == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      await ref.read(apiProvider).post('/merchants/shop/${data['shop_id']}/documents/', FormData.fromMap({
        'doc_type': type,
        'file': await MultipartFile.fromFile(photo.path, filename: photo.name),
      }));
    }, success: tr('{0} अपलोड हो गया', [tr(_documents[type]!)]));
    if (ok) _refresh(ref);
  }
}

/// UPI ID or bank account for payouts (also reachable from More).
class PayoutSheet extends ConsumerStatefulWidget {
  const PayoutSheet({super.key});

  @override
  ConsumerState<PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends ConsumerState<PayoutSheet> {
  final _form = GlobalKey<FormState>();
  final _upi = TextEditingController();
  final _name = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  bool _bank = false;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(merchantProfileProvider).value;
    if (profile != null && !_loaded) {
      _loaded = true;
      _upi.text = profile['upi_id'] ?? '';
      _name.text = profile['bank_account_name'] ?? '';
      _account.text = profile['bank_account_number'] ?? '';
      _ifsc.text = profile['bank_ifsc'] ?? '';
      _bank = _upi.text.isEmpty && _account.text.isNotEmpty;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('पेमेंट कहाँ लें?'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tr('ऑनलाइन ऑर्डर का पैसा (कमीशन काटकर) यहाँ भेजा जाएगा।'), style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('UPI ID')), icon: const Icon(Icons.qr_code_rounded)),
                ButtonSegment(value: true, label: Text(tr('बैंक खाता')), icon: const Icon(Icons.account_balance_rounded)),
              ],
              selected: {_bank},
              onSelectionChanged: (v) => setState(() => _bank = v.first),
            ),
            const SizedBox(height: 12),
            if (!_bank)
              TextFormField(
                controller: _upi,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: tr('UPI ID'), hintText: 'name@okaxis'),
                validator: (v) => RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(v?.trim() ?? '') ? null : tr('सही UPI ID डालें'),
              )
            else ...[
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: tr('खाताधारक का नाम')),
                validator: (v) => (v ?? '').trim().isEmpty ? tr('ज़रूरी है') : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _account,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('खाता नंबर')),
                validator: (v) => RegExp(r'^\d{9,18}$').hasMatch(v?.trim() ?? '') ? null : tr('9 से 18 अंक'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ifsc,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('IFSC कोड'), hintText: 'SBIN0001234'),
                validator: (v) => RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v?.trim().toUpperCase() ?? '') ? null : tr('सही IFSC डालें'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final body = _bank
                    ? {
                        'bank_account_name': _name.text.trim(),
                        'bank_account_number': _account.text.trim(),
                        'bank_ifsc': _ifsc.text.trim().toUpperCase(),
                      }
                    : {'upi_id': _upi.text.trim()};
                final ok = await runAction(context, () => ref.read(apiProvider).patch('/merchants/profile/update/', body),
                    success: tr('सेव हो गया'));
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: Text(tr('सेव करें')),
            ),
          ]),
        ),
      ),
    );
  }
}
