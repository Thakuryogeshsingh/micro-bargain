import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/motion.dart';
import '../../notifications/notifications_screen.dart';
import '../../../shared/widgets/tab_shell.dart';
import '../merchant_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    if (ref.watch(openOnboardingProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(openOnboardingProvider.notifier).set(false);
        if (context.mounted) context.push('/merchant/onboarding');
      });
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-deal-fab',
        onPressed: () async {
          await context.push('/merchant/deal-form');
          ref.invalidate(dashboardProvider);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('नई डील'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        edgeOffset: 140,
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 168,
            backgroundColor: AppTheme.minimal ? AppTheme.background : AppTheme.primaryDark,
            foregroundColor: AppTheme.minimal ? AppTheme.ink : Colors.white,
            title: Text(tr('डैशबोर्ड'), style: TextStyle(color: AppTheme.minimal ? AppTheme.ink : Colors.white)),
            actions: [
              IconTheme(data: IconThemeData(color: AppTheme.minimal ? AppTheme.ink : Colors.white), child: const NotificationBell()),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: AppTheme.minimal ? BoxDecoration(color: AppTheme.background) : BoxDecoration(gradient: AppTheme.heroGradient),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                alignment: Alignment.bottomLeft,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('नमस्ते, {0}', [user?.displayName ?? '']),
                      style: TextStyle(
                          color: AppTheme.minimal ? AppTheme.ink : Colors.white,
                          fontSize: AppTheme.minimal ? 28 : 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8)),
                  const SizedBox(height: 4),
                  Text(tr('अपनी दुकान की डील डालें और पास के ग्राहकों तक पहुंचें'),
                      style: TextStyle(color: AppTheme.minimal ? AppTheme.muted : Colors.white.withValues(alpha: 0.85))),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AsyncView(
              value: ref.watch(dashboardProvider),
              onRetry: () => ref.invalidate(dashboardProvider),
              data: (s) {
                final goTab = TabSwitcher.maybeOf(context);
                void open(String route) => context.push(route);
                final tiles = [
                  (tr('लाइव डील'), parseNum(s['active_deals']), Icons.local_offer_rounded, null, AppTheme.primary, () => goTab?.call(1)),
                  (tr('कुल बिक्री'), parseNum(s['revenue']), Icons.currency_rupee_rounded, rupees, AppTheme.deal, () => open('/merchant/earnings')),
                  (tr('पूरे हुए पिकअप'), parseNum(s['completed_orders']), Icons.check_circle_rounded, null, const Color(0xFF2563EB), () => goTab?.call(2)),
                  (tr('चल रहे ऑर्डर'), parseNum(s['open_orders']), Icons.delivery_dining_rounded, null, const Color(0xFF7C3AED), () => goTab?.call(2)),
                  (tr('बचा स्टॉक'), parseNum(s['remaining_stock']), Icons.inventory_2_rounded, qty, const Color(0xFF0891B2), () => open('/merchant/inventory')),
                  (tr('रेटिंग'), parseNum(s['rating_avg']), Icons.star_rounded, (double v) => '★ ${v.toStringAsFixed(1)}', AppTheme.featured, () => open('/merchant/reviews')),
                  (tr('खत्म हुई डील'), parseNum(s['expired_deals']), Icons.timer_off_rounded, null, Colors.blueGrey, () => goTab?.call(1)),
                  (tr('पूरी बिकी डील'), parseNum(s['sold_out_deals']), Icons.done_all_rounded, null, const Color(0xFFDB2777), () => goTab?.call(1)),
                  (tr('क्वालिटी स्कोर'), parseNum(s['quality_score'] ?? 100), Icons.verified_rounded, (double v) => '${v.round()}%',
                      const Color(0xFF15803D), () => open('/merchant/complaints')),
                ];
                return Column(children: [
                  const SizedBox(height: 8),
                  FadeSlideIn(child: _ShopStatusBanner(stats: s)),
                  if ((s['open_complaints'] ?? 0) > 0)
                    Card(
                      color: const Color(0xFFFEE2E2),
                      child: ListTile(
                        leading: const Icon(Icons.report_problem_rounded, color: Color(0xFFB91C1C)),
                        title: Text(tr('{0} क्वालिटी शिकायत जवाब का इंतज़ार कर रही है', [s['open_complaints']]),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(tr('24 घंटे में जवाब न देने पर ग्राहक को पूरा रिफंड अपने आप हो जाएगा')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => open('/merchant/complaints'),
                      ),
                    ),
                  if ((s['pending_reservations'] ?? 0) > 0 || (s['pending_orders'] ?? 0) > 0)
                    FadeSlideIn(
                      index: 1,
                      child: _PulseCard(
                        onTap: () => TabSwitcher.maybeOf(context)?.call(2),
                        text: tr('{0} रिज़र्वेशन और {1} ऑर्डर आपके जवाब का इंतज़ार कर रहे हैं',
                            [s['pending_reservations'], s['pending_orders']]),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.55,
                      children: [
                        for (var i = 0; i < tiles.length; i++)
                          FadeSlideIn(
                            index: i + 2,
                            child: StatTile(
                              label: tiles[i].$1,
                              value: tiles[i].$2,
                              icon: tiles[i].$3,
                              format: tiles[i].$4,
                              color: tiles[i].$5,
                              onTap: tiles[i].$6,
                            ),
                          ),
                      ],
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Orange "customers are waiting" card with a gently pulsing bell.
class _PulseCard extends StatefulWidget {
  const _PulseCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<_PulseCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.9, upperBound: 1.1)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: AppTheme.dealGradient, borderRadius: AppTheme.radius, boxShadow: AppTheme.softShadow(0.15)),
        child: Row(children: [
          ScaleTransition(scale: _controller, child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 30)),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ]),
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
      null => (Colors.blue, Icons.add_business_rounded, tr('दुकान सेटअप पूरा करें'), tr('4 आसान स्टेप: जानकारी, दुकान, दस्तावेज़, पेमेंट'), tr('शुरू करें')),
      'pending' when stats['onboarding_submitted'] != true =>
        (Colors.blue, Icons.checklist_rounded, tr('दुकान सेटअप पूरा करें'), tr('दस्तावेज़ और पेमेंट जानकारी डालकर जांच के लिए जमा करें'), tr('जारी रखें')),
      'pending' => (Colors.orange, Icons.hourglass_top_rounded, tr('दुकान वेरिफिकेशन में है'), tr('टीम जल्द जांच करेगी। अप्रूव होते ही नोटिफिकेशन आएगा।'), tr('स्टेटस')),
      'rejected' => (Colors.red, Icons.error_outline_rounded, tr('दुकान अप्रूव नहीं हुई'), '${stats['shop_rejection_reason'] ?? ''}', tr('ठीक करें')),
      _ => (Colors.grey, Icons.block_rounded, tr('दुकान अभी बंद है'), tr('सपोर्ट से संपर्क करें'), tr('मदद')),
    };
    return Card(
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => context.push(status == null || status == 'pending' || status == 'rejected' ? '/merchant/onboarding' : '/support'),
          child: Text(action),
        ),
      ),
    );
  }
}
