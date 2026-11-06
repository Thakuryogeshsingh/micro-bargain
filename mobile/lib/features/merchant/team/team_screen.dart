import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../merchant_providers.dart';

final teamProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).get('/team/') as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// Shop owner: helpers and delivery people (they log in with their own number).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var kind = 'helper';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: tr('टीम में जोड़ें'),
          icon: Icons.person_add_alt_1_rounded,
          message: tr('वो इसी नंबर से OTP डालकर ऐप में लॉगिन करेंगे।'),
          body: Column(children: [
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: tr('नाम'), filled: true, fillColor: AppTheme.chip)),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(hintText: tr('मोबाइल नंबर'), prefixText: '+91 ', filled: true, fillColor: AppTheme.chip, counterText: ''),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'helper', label: Text(tr('हेल्पर')), icon: const Icon(Icons.storefront_outlined)),
                ButtonSegment(value: 'delivery', label: Text(tr('डिलीवरी')), icon: const Icon(Icons.delivery_dining_outlined)),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setState(() => kind = v.first),
            ),
          ]),
          okLabel: tr('जोड़ें'),
          cancelLabel: tr('रद्द'),
          onOk: () => Navigator.pop(dialog, true),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final added = await runAction(context, () => ref.read(apiProvider).post('/team/', {
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'kind': kind,
        }), success: tr('टीम में जोड़ दिया'));
    if (added) ref.invalidate(teamProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मेरी टीम'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'team-add',
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('जोड़ें')),
      ),
      body: AsyncView(
        value: ref.watch(teamProvider),
        onRetry: () => ref.invalidate(teamProvider),
        data: (rows) => rows.isEmpty
            ? EmptyView(icon: Icons.groups_2_outlined, message: tr('अभी टीम में कोई नहीं।\nहेल्पर ऑर्डर संभाल सकते हैं, डिलीवरी वाले अपने ऑर्डर पहुंचाते हैं।'))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                for (final s in rows)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.chip,
                        child: Icon(s['kind'] == 'delivery' ? Icons.delivery_dining_rounded : Icons.storefront_rounded, color: AppTheme.ink),
                      ),
                      title: Text(s['name'].toString().isEmpty ? s['phone'] : s['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${s['kind'] == 'delivery' ? tr('डिलीवरी') : tr('हेल्पर')} · +91 ${s['phone']}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: () => launchUrl(Uri.parse('tel:${s['phone']}')), icon: const Icon(Icons.call_outlined)),
                        IconButton(
                          icon: const Icon(Icons.person_remove_outlined, color: Color(0xFFE5484D)),
                          onPressed: () async {
                            if (!await confirm(context, tr('टीम से हटाएं?'), icon: Icons.person_remove_outlined, danger: true)) return;
                            if (context.mounted && await runAction(context, () => ref.read(apiProvider).delete('/team/${s['id']}/'))) {
                              ref.invalidate(teamProvider);
                            }
                          },
                        ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}

/// Give a delivery order to one of the shop's delivery people.
Future<void> assignDelivery(BuildContext context, WidgetRef ref, Order order) async {
  final team = await ref.read(teamProvider.future).catchError((_) => <Map<String, dynamic>>[]);
  final riders = team.where((s) => s['kind'] == 'delivery').toList();
  if (!context.mounted) return;
  if (riders.isEmpty) {
    showMessage(context, tr('पहले "मेरी टीम" में डिलीवरी वाले को जोड़ें'), error: true);
    return;
  }
  final picked = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('किसे भेजें?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        for (final r in riders)
          ListTile(
            leading: const Icon(Icons.delivery_dining_rounded),
            title: Text(r['name'].toString().isEmpty ? r['phone'] : r['name']),
            onTap: () => Navigator.pop(sheet, r),
          ),
      ]),
    ),
  );
  if (picked == null || !context.mounted) return;
  final ok = await runAction(context, () => ref.read(apiProvider).post('/orders/${order.id}/assign/', {'staff': picked['id']}),
      success: tr('{0} को भेज दिया', [picked['name']]));
  if (ok) ref.invalidate(merchantOrdersProvider);
}
