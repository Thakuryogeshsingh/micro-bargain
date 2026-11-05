import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../core/i18n/i18n.dart';

final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final data = await ref.watch(apiProvider).get('/notifications/unread-count/');
  return data['unread'] as int;
});

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  return [for (final n in await ref.watch(apiProvider).list('/notifications/')) AppNotification.fromJson(n)];
});

/// Bell icon with the unread badge, for app bars.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    return IconButton(
      tooltip: tr('सूचनाएं'),
      onPressed: () async {
        await context.push('/notifications');
        ref.invalidate(unreadCountProvider);
      },
      icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
    );
  }
}

/// Where tapping a notification goes, based on the ids in its data.
String? routeFor(AppNotification n, {required bool merchant}) {
  final d = n.data;
  if (d['order_id'] != null) return merchant ? '/merchant/bookings' : '/order/${d['order_id']}';
  if (d['reservation_id'] != null) return merchant ? '/merchant/bookings' : '/reservation/${d['reservation_id']}';
  if (d['deal_id'] != null) return '/deal/${d['deal_id']}';
  if (d['quality_id'] != null) return merchant ? '/merchant/complaints' : '/refunds';
  if (d['complaint_id'] != null) return '/support/${d['complaint_id']}';
  if (d['shop_id'] != null || n.kind == 'merchant_approved') return merchant ? '/merchant/onboarding' : null;
  if (n.kind == 'cashback') return '/wallet';
  if (d['chat_id'] != null) return '/chat/${d['chat_id']}';
  if (d['daily_id'] != null) return merchant ? '/merchant/daily' : '/daily';
  if (d['review_id'] != null) return '/merchant/reviews';
  return null;
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = ref.watch(sessionProvider).isMerchant;
    return Scaffold(
      appBar: AppBar(title: Text(tr('सूचनाएं')), actions: [
        TextButton(
          onPressed: () async {
            await ref.read(apiProvider).post('/notifications/read-all/');
            ref.invalidate(notificationsProvider);
          },
          child: Text(tr('सब पढ़ा हुआ')),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(notificationsProvider.future),
        child: AsyncView(
          value: ref.watch(notificationsProvider),
          onRetry: () => ref.invalidate(notificationsProvider),
          data: (items) => items.isEmpty
              ? ListView(children: [const SizedBox(height: 120), EmptyView(icon: Icons.notifications_none, message: tr('अभी कोई सूचना नहीं'))])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    return ListTile(
                      tileColor: n.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Text('${n.body}\n${dateTime(n.createdAt)}'),
                      isThreeLine: true,
                      onTap: () async {
                        if (!n.isRead) {
                          await ref.read(apiProvider).post('/notifications/${n.id}/read/');
                          ref.invalidate(notificationsProvider);
                        }
                        final route = routeFor(n, merchant: merchant);
                        if (route != null && context.mounted) context.push(route);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
