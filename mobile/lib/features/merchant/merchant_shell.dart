import 'package:flutter/material.dart';

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
  int _tab = 0;

  static const _pages = [DashboardScreen(), MerchantDealsScreen(), MerchantBookingsScreen(), MoreScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'डैशबोर्ड'),
          NavigationDestination(icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer), label: 'डील'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'बुकिंग'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'और'),
        ],
      ),
    );
  }
}
