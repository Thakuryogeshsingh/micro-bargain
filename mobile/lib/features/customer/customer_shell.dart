import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bookings/bookings_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screens.dart';
import 'shops/shop_screens.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/update/update_checker.dart';
import '../../shared/widgets/floating_nav.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // After the first frame, offer a newer app version if one is published.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context, ProviderScope.containerOf(context, listen: false).read(apiProvider));
    });
  }

  static const _pages = [HomeScreen(), BookingsScreen(), FavoritesScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // content scrolls under the floating bar
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: FloatingNavBar(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          FloatingNavItem(Icons.home_outlined, Icons.home_rounded, tr('डील')),
          FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('बुकिंग')),
          FloatingNavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, tr('पसंदीदा')),
          FloatingNavItem(Icons.person_outline_rounded, Icons.person_rounded, tr('प्रोफाइल')),
        ],
      ),
    );
  }
}
