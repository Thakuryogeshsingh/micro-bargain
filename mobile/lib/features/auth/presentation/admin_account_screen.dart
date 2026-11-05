import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../../settings/language_screen.dart';

final _adminDashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('/analytics/dashboard/'));
});

/// The platform admin's view in the app: key numbers for the last 30 days, with links to the web admin
/// for approvals and detailed reports.
class AdminAccountScreen extends ConsumerWidget {
  const AdminAccountScreen({super.key});

  void _open(String path) => launchUrl(Uri.parse('${AppConfig.siteUrl}$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_adminDashboardProvider.future),
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 150,
            backgroundColor: AppTheme.primaryDark,
            foregroundColor: Colors.white,
            title: Text(tr('एडमिन'), style: const TextStyle(color: Colors.white)),
            actions: [
              IconButton(
                tooltip: tr('लॉग आउट'),
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                alignment: Alignment.bottomLeft,
                child: Text('${tr('नमस्ते, {0}', [user?.displayName ?? ''])} 🛡️',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AsyncView(
              value: ref.watch(_adminDashboardProvider),
              onRetry: () => ref.invalidate(_adminDashboardProvider),
              data: (m) {
                final pending = (m['pending_merchant_approvals'] as int) + (m['pending_shop_approvals'] as int);
                final tiles = [
                  (tr('पास की डील'), m['active_deals'], Icons.local_offer_rounded, false),
                  (tr('ग्राहक'), m['total_customers'], Icons.people_alt_rounded, false),
                  (tr('दुकानदार'), m['total_merchants'], Icons.storefront_rounded, false),
                  (tr('कुल बिक्री'), m['total_transaction_value'], Icons.currency_rupee_rounded, true),
                  (tr('आपकी बचत'), m['customer_savings'], Icons.savings_rounded, true),
                  (tr('प्लेटफ़ॉर्म कमीशन'), m['platform_revenue'], Icons.account_balance_wallet_rounded, true),
                ];
                return Column(children: [
                  if (pending > 0)
                    FadeSlideIn(
                      child: Card(
                        color: const Color(0xFFFFF4E5),
                        child: ListTile(
                          leading: const Icon(Icons.pending_actions_rounded, color: Color(0xFFB45309)),
                          title: Text(tr('वेरिफिकेशन बाकी')),
                          subtitle: Text('$pending'),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: () => _open('/admin/shops/shop/?status__exact=pending'),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        for (var i = 0; i < tiles.length; i++)
                          FadeSlideIn(
                            index: i,
                            child: StatTile(
                              label: tiles[i].$1,
                              icon: tiles[i].$3,
                              value: parseNum(tiles[i].$2),
                              format: tiles[i].$4 ? rupees : (v) => '${v.round()}',
                              color: [AppTheme.primary, const Color(0xFF2563EB), const Color(0xFF7C3AED), AppTheme.deal, const Color(0xFF0891B2), const Color(0xFFDB2777)][i],
                            ),
                          ),
                      ],
                    ),
                  ),
                ]);
              },
            ),
          ),
          SliverList.list(children: [
            ListTile(
              leading: const Icon(Icons.dashboard_rounded),
              title: Text(tr('एडमिन पैनल खोलें')),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _open('/admin/dashboard/'),
            ),
            const LanguageTile(),
            const SizedBox(height: 24),
          ]),
        ]),
      ),
    );
  }
}
