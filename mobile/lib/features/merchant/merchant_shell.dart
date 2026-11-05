import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bookings/merchant_bookings_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'deals/merchant_deal_screens.dart';
import 'more/more_screens.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/update/update_checker.dart';
import '../../shared/widgets/floating_nav.dart';

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
      extendBody: true,
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: FloatingNavBar(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          FloatingNavItem(Icons.dashboard_outlined, Icons.dashboard_rounded, tr('डैशबोर्ड')),
          FloatingNavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, tr('डील')),
          FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('बुकिंग')),
          FloatingNavItem(Icons.menu_rounded, Icons.menu_open_rounded, tr('और')),
        ],
      ),
    );
  }
}
