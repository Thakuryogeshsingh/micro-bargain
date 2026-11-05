import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/admin_account_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/customer/bookings/booking_detail_screens.dart';
import '../../features/customer/cart/cart_screen.dart';
import '../../features/customer/customer_shell.dart';
import '../../features/customer/deals/deal_detail_screen.dart';
import '../../features/customer/profile/profile_screens.dart';
import '../../features/customer/shops/shop_screens.dart';
import '../../features/merchant/bookings/merchant_bookings_screen.dart';
import '../../features/merchant/deals/merchant_deal_screens.dart';
import '../../features/merchant/merchant_shell.dart';
import '../../features/merchant/more/more_screens.dart';
import '../../features/merchant/products/product_screens.dart';
import '../../features/merchant/register/merchant_register_screen.dart';
import '../../features/merchant/shop/shop_form_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/support/support_screens.dart';
import '../../shared/models/models.dart';
import '../auth/session.dart';

/// Bridges the Riverpod session to go_router so redirects re-run on login/logout.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

int _id(GoRouterState state) => int.parse(state.pathParameters['id']!);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final here = state.matchedLocation;
      final onAuth = here == '/login' || here == '/otp';
      switch (session.status) {
        case SessionStatus.unknown:
          return here == '/splash' ? null : '/splash';
        case SessionStatus.signedOut:
          return onAuth ? null : '/login';
        case SessionStatus.signedIn:
          if (session.isAdmin) return here == '/admin-account' ? null : '/admin-account';
          final home = session.isMerchant ? '/merchant' : '/customer';
          if (onAuth || here == '/splash') return home;
          // Becoming a merchant switches apps.
          if (session.isMerchant && (here == '/customer' || here == '/become-merchant')) return home;
          if (!session.isMerchant && here.startsWith('/merchant')) return home;
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/admin-account', builder: (_, _) => const AdminAccountScreen()),
      GoRoute(path: '/otp', builder: (_, state) => OtpScreen(phone: state.extra as String)),

      // Shared
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/support', builder: (_, _) => const SupportListScreen()),
      GoRoute(
        path: '/support/new',
        builder: (_, state) => NewTicketScreen(link: (state.extra as Map<String, dynamic>?) ?? const {}),
      ),
      GoRoute(path: '/support/:id', builder: (_, state) => TicketScreen(id: _id(state))),
      GoRoute(path: '/deal/:id', builder: (_, state) => DealDetailScreen(id: _id(state))),
      GoRoute(path: '/shop/:id', builder: (_, state) => ShopScreen(id: _id(state))),

      // Customer
      GoRoute(path: '/customer', builder: (_, _) => const CustomerShell()),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/reservation/:id', builder: (_, state) => ReservationDetailScreen(id: _id(state))),
      GoRoute(path: '/order/:id', builder: (_, state) => OrderDetailScreen(id: _id(state))),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
      GoRoute(path: '/addresses', builder: (_, _) => const AddressesScreen()),
      GoRoute(path: '/addresses/new', builder: (_, _) => const AddressFormScreen()),
      GoRoute(path: '/become-merchant', builder: (_, _) => const MerchantRegisterScreen()),

      // Merchant
      GoRoute(path: '/merchant', builder: (_, _) => const MerchantShell()),
      GoRoute(path: '/merchant/shop-form', builder: (_, _) => const ShopFormScreen()),
      GoRoute(path: '/merchant/products', builder: (_, _) => const ProductsScreen()),
      GoRoute(path: '/merchant/product-form', builder: (_, state) => ProductFormScreen(product: state.extra as Product?)),
      GoRoute(path: '/merchant/deal-form', builder: (_, _) => const DealFormScreen()),
      GoRoute(path: '/merchant/bookings', builder: (_, _) => const MerchantBookingsScreen()),
      GoRoute(path: '/merchant/inventory', builder: (_, _) => const InventoryScreen()),
      GoRoute(path: '/merchant/plans', builder: (_, _) => const PlansScreen()),
      GoRoute(path: '/merchant/promotions', builder: (_, _) => const PromotionsScreen()),
      GoRoute(path: '/merchant/reviews', builder: (_, _) => const MerchantReviewsScreen()),
      GoRoute(path: '/merchant/earnings', builder: (_, _) => const EarningsScreen()),
    ],
  );
});
