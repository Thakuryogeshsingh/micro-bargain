import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/update/update_checker.dart';
import '../../shared/widgets/floating_nav.dart';
import '../../shared/widgets/tab_shell.dart';
import 'alerts/order_alerts.dart';
import 'bookings/merchant_bookings_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'deals/merchant_deal_screens.dart';
import 'more/more_screens.dart';

class MerchantShell extends StatefulWidget {
  const MerchantShell({super.key});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  OrderAlertWatcher? _watcher;

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabShell(
      pages: const [DashboardScreen(), MerchantDealsScreen(), MerchantBookingsScreen(), MoreScreen()],
      items: [
        FloatingNavItem(Icons.dashboard_outlined, Icons.dashboard_rounded, tr('डैशबोर्ड')),
        FloatingNavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, tr('डील')),
        FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('बुकिंग')),
        FloatingNavItem(Icons.menu_rounded, Icons.menu_open_rounded, tr('और')),
      ],
      onReady: (context) {
        final api = ProviderScope.containerOf(context, listen: false).read(apiProvider);
        UpdateChecker.check(context, api);
        // Ring and show new orders as soon as they arrive.
        _watcher = OrderAlertWatcher(context, api)..start();
      },
    );
  }
}
