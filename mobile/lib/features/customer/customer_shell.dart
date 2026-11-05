import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/update/update_checker.dart';
import '../../shared/widgets/floating_nav.dart';
import '../../shared/widgets/tab_shell.dart';
import 'bookings/bookings_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screens.dart';
import 'shops/shop_screens.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key});

  @override
  Widget build(BuildContext context) {
    return TabShell(
      pages: const [HomeScreen(), BookingsScreen(), FavoritesScreen(), ProfileScreen()],
      items: [
        FloatingNavItem(Icons.home_outlined, Icons.home_rounded, tr('डील')),
        FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('बुकिंग')),
        FloatingNavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, tr('पसंदीदा')),
        FloatingNavItem(Icons.person_outline_rounded, Icons.person_rounded, tr('प्रोफाइल')),
      ],
      onReady: (context) => UpdateChecker.check(context, ProviderScope.containerOf(context, listen: false).read(apiProvider)),
    );
  }
}
