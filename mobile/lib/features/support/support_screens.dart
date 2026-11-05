import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../core/i18n/i18n.dart';

// i18n:off (translated where used)
const _categories = {
  'order': 'ऑर्डर',
  'reservation': 'रिज़र्वेशन / पिकअप',
  'payment': 'पेमेंट / रिफंड',
  'shop': 'दुकान या सामान की क्वालिटी',
  'account': 'अकाउंट / लॉगिन',
  'app': 'ऐप में दिक्कत',
  'other': 'अन्य',
};
// i18n:on

final ticketsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return (await ref.watch(apiProvider).get('/support/') as List).cast<Map<String, dynamic>>();
});

final ticketProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/support/$id/'));
});

class SupportListScreen extends ConsumerWidget {
  const SupportListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मदद और शिकायत'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/support/new');
          ref.invalidate(ticketsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(tr('नई शिकायत')),
      ),
      body: AsyncView(
        value: ref.watch(ticketsProvider),
        onRetry: () => ref.invalidate(ticketsProvider),
        data: (tickets) => tickets.isEmpty
            ? EmptyView(icon: Icons.support_agent, message: tr('कोई समस्या? नीचे बटन से हमें बताएं।'))
            : ListView(children: [
                for (final t in tickets)
                  ListTile(
                    title: Text(t['subject']),
                    subtitle: Text('${t['ticket_number']} · ${tr(_categories[t['category']] ?? t['category'])}'),
                    trailing: Chip(label: Text(t['status'] == 'resolved' ? tr('हल हुई') : t['status'] == 'closed' ? tr('बंद') : tr('खुली'))),
                    onTap: () => context.push('/support/${t['id']}'),
                  ),
              ]),
      ),
    );
  }
}

class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key, this.link = const {}});

  /// Optional {"order": id} / {"reservation": id} and a default "category".
  final Map<String, dynamic> link;

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  late String _category = widget.link['category'] ?? 'other';
  final _subject = TextEditingController();
  final _message = TextEditingController();

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      showMessage(context, tr('विषय और पूरी बात लिखें'));
      return;
    }
    final ok = await runAction(context, () => ref.read(apiProvider).post('/support/', {
          'category': _category,
          'subject': _subject.text.trim(),
          'message': _message.text.trim(),
          if (widget.link['order'] != null) 'order': widget.link['order'],
          if (widget.link['reservation'] != null) 'reservation': widget.link['reservation'],
        }), success: tr('शिकायत दर्ज हो गई। जल्द जवाब मिलेगा।'));
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('नई शिकायत'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: InputDecoration(labelText: tr('किस बारे में?')),
          items: [for (final e in _categories.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: _subject, maxLength: 150, decoration: InputDecoration(labelText: tr('विषय'))),
        TextField(controller: _message, maxLines: 5, maxLength: 2000, decoration: InputDecoration(labelText: tr('पूरी बात लिखें'))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: Text(tr('भेजें'))),
      ]),
    );
  }
}

class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final _reply = TextEditingController();

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    if (await runAction(context, () => ref.read(apiProvider).post('/support/${widget.id}/message/', {'message': text}))) {
      _reply.clear();
      ref.invalidate(ticketProvider(widget.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('शिकायत'))),
      body: AsyncView(
        value: ref.watch(ticketProvider(widget.id)),
        onRetry: () => ref.invalidate(ticketProvider(widget.id)),
        data: (t) => Column(children: [
          ListTile(title: Text(t['subject']), subtitle: Text('${t['ticket_number']} · ${tr(_categories[t['category']] ?? t['category'])}')),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final m in (t['messages'] as List))
                Align(
                  alignment: m['is_staff_reply'] == true ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: m['is_staff_reply'] == true ? scheme.surfaceContainerHighest : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (m['is_staff_reply'] == true) Text(tr('सपोर्ट टीम'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(m['message']),
                      Text(dateTime(parseTime(m['created_at'])!), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
            ]),
          ),
          if (t['status'] != 'closed')
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: TextField(controller: _reply, decoration: InputDecoration(hintText: tr('जवाब लिखें…'), isDense: true))),
                  IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
