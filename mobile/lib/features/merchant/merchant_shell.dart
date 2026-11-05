import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bookings/merchant_bookings_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'deals/merchant_deal_screens.dart';
import 'more/more_screens.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/update/update_checker.dart';

class MerchantShell extends StatefulWidget {
  const MerchantShell({super.key});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // After the first frame, offer a newer app version if one is published.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context, ProviderScope.containerOf(context, listen: false).read(apiProvider));
    });
  }

  static const _pages = [DashboardScreen(), MerchantDealsScreen(), MerchantBookingsScreen(), MoreScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: tr('डैशबोर्ड')),
          NavigationDestination(icon: const Icon(Icons.local_offer_outlined), selectedIcon: const Icon(Icons.local_offer), label: tr('डील')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: tr('बुकिंग')),
          NavigationDestination(icon: const Icon(Icons.menu), label: tr('और')),
        ],
      ),
    );
  }
}
