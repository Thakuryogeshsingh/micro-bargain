import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';

const _red = Color(0xFFE5484D);
const _green = Color(0xFF15803D);

final khataProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, q) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/khata/customers/', query: {'q': q}));
});

final khataCustomerProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/khata/customers/$id/'));
});

/// Udhaar khata: everyone who owes the shop, the total, and quick add.
class KhataScreen extends ConsumerStatefulWidget {
  const KhataScreen({super.key});

  @override
  ConsumerState<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends ConsumerState<KhataScreen> {
  String _q = '';

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: tr('नया ग्राहक'),
        icon: Icons.person_add_alt_1_rounded,
        body: Column(children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: tr('नाम'), filled: true, fillColor: AppTheme.chip)),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: tr('मोबाइल (ज़रूरी नहीं)'), filled: true, fillColor: AppTheme.chip, counterText: ''),
          ),
        ]),
        okLabel: tr('जोड़ें'),
        cancelLabel: tr('रद्द'),
        onOk: () => Navigator.pop(dialog, true),
      ),
    );
    if (saved != true || name.text.trim().isEmpty || !mounted) return;
    Map<String, dynamic>? created;
    final ok = await runAction(context, () async {
      created = Map<String, dynamic>.from(
          await ref.read(apiProvider).post('/khata/customers/', {'name': name.text.trim(), 'phone': phone.text.trim()}));
    });
    if (ok && mounted) {
      ref.invalidate(khataProvider(_q));
      context.push('/merchant/khata/${created!['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('उधार खाता'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'khata-add',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('ग्राहक जोड़ें')),
      ),
      body: AsyncView(
        value: ref.watch(khataProvider(_q)),
        onRetry: () => ref.invalidate(khataProvider(_q)),
        data: (data) {
          final customers = [for (final c in data['customers'] as List) Map<String, dynamic>.from(c)];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(khataProvider(_q).future),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: AppTheme.heroGradient, borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('कुल बकाया'), style: const TextStyle(color: Colors.white70)),
                  Text(rupees(parseNum(data['total_due'])),
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  Text(tr('{0} ग्राहक', [customers.length]), style: const TextStyle(color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: tr('नाम या नंबर से खोजें'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppTheme.chip,
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                onSubmitted: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 8),
              if (customers.isEmpty)
                EmptyView(icon: Icons.menu_book_rounded, message: tr('उधार खाता खाली है।\nजिसे उधार दिया, उसे "ग्राहक जोड़ें" से जोड़ें।')),
              for (var i = 0; i < customers.length; i++)
                FadeSlideIn(
                  index: i,
                  child: _CustomerRow(
                    c: customers[i],
                    onTap: () async {
                      await context.push('/merchant/khata/${customers[i]['id']}');
                      ref.invalidate(khataProvider(_q));
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.c, required this.onTap});

  final Map<String, dynamic> c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = parseNum(c['balance']);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppTheme.chip,
        child: Text((c['name'] as String).characters.first.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.ink)),
      ),
      title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text((c['phone'] as String? ?? '').isEmpty ? '—' : c['phone']),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(rupees(balance.abs()),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: balance > 0 ? _red : balance < 0 ? _green : AppTheme.muted)),
        Text(balance > 0 ? tr('लेना है') : balance < 0 ? tr('देना है') : tr('हिसाब बराबर'), style: TextStyle(fontSize: 11, color: AppTheme.muted)),
      ]),
    );
  }
}

/// One customer's ledger: entries, and "gave credit" / "got paid" buttons.
class KhataCustomerScreen extends ConsumerWidget {
  const KhataCustomerScreen({super.key, required this.id});

  final int id;

  Future<void> _entry(BuildContext context, WidgetRef ref, String kind) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final credit = kind == 'credit';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: credit ? tr('उधार दिया') : tr('पैसा मिला'),
        icon: credit ? Icons.north_east_rounded : Icons.south_west_rounded,
        danger: credit,
        body: Column(children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            decoration: InputDecoration(prefixText: '₹ ', hintText: '0', filled: true, fillColor: AppTheme.chip),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: InputDecoration(hintText: tr('क्या सामान / नोट (ज़रूरी नहीं)'), filled: true, fillColor: AppTheme.chip)),
        ]),
        okLabel: tr('सेव करें'),
        cancelLabel: tr('रद्द'),
        onOk: () => Navigator.pop(dialog, true),
      ),
    );
    if (saved != true || amount.text.trim().isEmpty || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).post('/khata/customers/$id/entries/', {
          'kind': kind,
          'amount': amount.text.trim(),
          'note': note.text.trim(),
        }), success: tr('सेव हो गया'));
    if (ok) ref.invalidate(khataCustomerProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(khataCustomerProvider(id)),
      onRetry: () => ref.invalidate(khataCustomerProvider(id)),
      data: (c) {
        final balance = parseNum(c['balance']);
        final entries = [for (final e in c['entries'] as List) Map<String, dynamic>.from(e)];
        final phone = c['phone'] as String? ?? '';
        return Scaffold(
          appBar: AppBar(title: Text(c['name']), actions: [
            if (phone.isNotEmpty) IconButton(onPressed: () => launchUrl(Uri.parse('tel:$phone')), icon: const Icon(Icons.call_outlined)),
          ]),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _red),
                    onPressed: () => _entry(context, ref, 'credit'),
                    child: Text(tr('उधार दिया')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    onPressed: () => _entry(context, ref, 'payment'),
                    child: Text(tr('पैसा मिला')),
                  ),
                ),
              ]),
            ),
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: (balance > 0 ? _red : _green).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(balance > 0 ? tr('लेना है') : balance < 0 ? tr('देना है') : tr('हिसाब बराबर'), style: TextStyle(color: AppTheme.muted)),
                    Text(rupees(balance.abs()),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1, color: balance > 0 ? _red : _green)),
                  ]),
                ),
                if (balance > 0 && phone.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: const Color(0xFF25D366)),
                    onPressed: () => launchUrl(
                      Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent(tr('नमस्ते {0} जी, आपका {1} बकाया है। सुविधा अनुसार चुका दें। धन्यवाद!', [c['name'], rupees(balance)]))}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: Text(tr('याद दिलाएं')),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('अभी कोई लेन-देन नहीं।'), textAlign: TextAlign.center)),
            for (final e in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: CircleAvatar(
                  backgroundColor: (e['kind'] == 'credit' ? _red : _green).withValues(alpha: 0.12),
                  child: Icon(e['kind'] == 'credit' ? Icons.north_east_rounded : Icons.south_west_rounded,
                      color: e['kind'] == 'credit' ? _red : _green, size: 20),
                ),
                title: Text(e['kind'] == 'credit' ? tr('उधार दिया') : tr('पैसा मिला'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([if ((e['note'] ?? '').isNotEmpty) e['note'], dateTime(parseTime(e['created_at'])!)].join(' · ')),
                trailing: Text(rupees(parseNum(e['amount'])),
                    style: TextStyle(fontWeight: FontWeight.w900, color: e['kind'] == 'credit' ? _red : _green)),
              ),
          ]),
        );
      },
    );
  }
}
