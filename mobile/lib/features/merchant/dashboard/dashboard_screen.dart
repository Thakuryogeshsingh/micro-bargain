import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../notifications/notifications_screen.dart';
import '../merchant_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(title: Text('नमस्ते, ${user?.displayName ?? ''}'), actions: const [NotificationBell()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/merchant/deal-form');
          ref.invalidate(dashboardProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('नई डील'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: AsyncView(
          value: ref.watch(dashboardProvider),
          onRetry: () => ref.invalidate(dashboardProvider),
          data: (s) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            _ShopStatusBanner(stats: s),
            if ((s['pending_reservations'] ?? 0) > 0 || (s['pending_orders'] ?? 0) > 0)
              Card(
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.notification_important, color: Colors.orange),
                  title: Text('${s['pending_reservations']} रिज़र्वेशन और ${s['pending_orders']} ऑर्डर आपके जवाब का इंतज़ार कर रहे हैं'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/merchant/bookings'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  StatTile(label: 'लाइव डील', value: '${s['active_deals']}', icon: Icons.local_offer),
                  StatTile(label: 'कुल बिक्री', value: rupees(parseNum(s['revenue'])), icon: Icons.currency_rupee),
                  StatTile(label: 'पूरे हुए पिकअप', value: '${s['completed_orders']}', icon: Icons.check_circle),
                  StatTile(label: 'चल रहे ऑर्डर', value: '${s['open_orders']}', icon: Icons.delivery_dining),
                  StatTile(label: 'बचा स्टॉक', value: qty(parseNum(s['remaining_stock'])), icon: Icons.inventory_2),
                  StatTile(label: 'रेटिंग', value: '★ ${parseNum(s['rating_avg']).toStringAsFixed(1)}', icon: Icons.star),
                  StatTile(label: 'खत्म हुई डील', value: '${s['expired_deals']}', icon: Icons.timer_off),
                  StatTile(label: 'पूरी बिकी डील', value: '${s['sold_out_deals']}', icon: Icons.done_all),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ShopStatusBanner extends StatelessWidget {
  const _ShopStatusBanner({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final status = stats['shop_status'];
    if (status == 'approved') return const SizedBox.shrink();
    final (color, icon, title, subtitle, action) = switch (status) {
      null => (Colors.blue, Icons.add_business, 'अपनी दुकान की जानकारी जोड़ें', 'दुकान का पता और लोकेशन डालें, फिर डील बनाएं', 'दुकान जोड़ें'),
      'pending' => (Colors.orange, Icons.hourglass_top, 'दुकान वेरिफिकेशन में है', 'टीम जल्द जांच करेगी। दुकान की फोटो और ID अपलोड करने से जल्दी होगा।', 'दस्तावेज़'),
      'rejected' => (Colors.red, Icons.error_outline, 'दुकान अप्रूव नहीं हुई', '${stats['shop_rejection_reason'] ?? ''}', 'ठीक करें'),
      _ => (Colors.grey, Icons.block, 'दुकान अभी बंद है', 'सपोर्ट से संपर्क करें', 'मदद'),
    };
    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: TextButton(
          onPressed: () => context.push(status == null || status == 'pending' || status == 'rejected' ? '/merchant/shop-form' : '/support'),
          child: Text(action),
        ),
      ),
    );
  }
}
