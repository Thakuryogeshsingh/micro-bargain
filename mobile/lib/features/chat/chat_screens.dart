import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/motion.dart';

final chatListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(apiProvider).get('/chat/') as List;
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// Opens (or creates) the customer's chat with a shop.
Future<void> startChat(BuildContext context, WidgetRef ref, int shopId) async {
  Map<String, dynamic>? chat;
  final ok = await runAction(context, () async {
    chat = Map<String, dynamic>.from(await ref.read(apiProvider).post('/chat/start/', {'shop': shopId}));
  });
  if (ok && context.mounted) context.push('/chat/${chat!['id']}');
}

/// Both apps: list of conversations.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मैसेज'))),
      body: AsyncView(
        value: ref.watch(chatListProvider),
        onRetry: () => ref.invalidate(chatListProvider),
        data: (rows) => rows.isEmpty
            ? EmptyView(icon: Icons.chat_bubble_outline_rounded, message: tr('अभी कोई बातचीत नहीं।\nदुकान के पेज पर "चैट करें" दबाएं।'))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(chatListProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (_, i) {
                    final c = rows[i];
                    final unread = (c['unread'] ?? 0) as int;
                    return FadeSlideIn(
                      index: i,
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.chip,
                          child: Text((c['title'] as String? ?? '?').characters.first.toUpperCase(),
                              style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.ink)),
                        ),
                        title: Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(c['last_message'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_when(parseTime(c['last_message_at'])), style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                          if (unread > 0) ...[
                            const SizedBox(height: 4),
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: AppTheme.minimal ? AppTheme.accent : AppTheme.primary,
                              child: Text('$unread',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppTheme.minimal ? Colors.black : Colors.white)),
                            ),
                          ],
                        ]),
                        onTap: () async {
                          await context.push('/chat/${c['id']}');
                          ref.invalidate(chatListProvider);
                        },
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

String _when(DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}' : dateTime(local).split(',').first;
}

/// One conversation; checks for new messages every few seconds while open.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  String _title = '';
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final after = _messages.isEmpty ? null : _messages.last['id'];
      final data = Map<String, dynamic>.from(
          await ref.read(apiProvider).get('/chat/${widget.id}/messages/', query: {if (after != null) 'after': after}));
      final fresh = [for (final m in data['messages'] as List) Map<String, dynamic>.from(m)];
      if (!mounted) return;
      setState(() {
        _title = data['conversation']['title'] ?? '';
        _messages.addAll(fresh.where((m) => !_messages.any((old) => old['id'] == m['id'])));
      });
      if (fresh.isNotEmpty) _toBottom();
    } on ApiException {
      // Next poll tries again.
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      final m = Map<String, dynamic>.from(await ref.read(apiProvider).post('/chat/${widget.id}/messages/', {'text': text}));
      _messages.add(m);
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _text.clear();
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? EmptyView(icon: Icons.waving_hand_outlined, message: tr('दुकान से कुछ भी पूछें — दाम, ताज़गी, डिलीवरी…'))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _Bubble(message: _messages[i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: AppTheme.card, boxShadow: AppTheme.softShadow(0.06)),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr('मैसेज लिखें…'),
                    counterText: '',
                    filled: true,
                    fillColor: AppTheme.chip,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.minimal ? AppTheme.accent : AppTheme.primary,
                  foregroundColor: AppTheme.minimal ? Colors.black : Colors.white,
                ),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final mine = message['mine'] == true;
    final time = parseTime(message['created_at'])?.toLocal();
    final bg = mine ? (AppTheme.minimal ? AppTheme.ink : AppTheme.primaryDark) : AppTheme.chip;
    final fg = mine ? Colors.white : AppTheme.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(message['text'] ?? '', style: TextStyle(color: fg, fontSize: 15, height: 1.35)),
          if (time != null)
            Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 10)),
        ]),
      ),
    );
  }
}
