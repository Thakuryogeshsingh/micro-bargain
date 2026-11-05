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
import '../../features/customer/deals/collection_screen.dart';
import '../../features/customer/deals/deal_detail_screen.dart';
import '../../features/customer/offers/offers.dart';
import '../../features/customer/plus/plus_screens.dart';
import '../../features/customer/profile/profile_screens.dart';
import '../../features/chat/chat_screens.dart';
import '../../features/customer/daily/daily_screens.dart';
import '../../features/customer/map/shops_map_screen.dart';
import '../../features/customer/search/search_screen.dart';
import '../../features/merchant/daily/merchant_daily_screen.dart';
import '../../features/merchant/khata/khata_screens.dart';
import '../../features/customer/quality/quality_screens.dart';
import '../../features/merchant/onboarding/onboarding_screen.dart';
import '../../features/merchant/quality/complaints_screen.dart';
import '../../features/customer/shops/shop_screens.dart';
import '../../features/customer/wallet/wallet_screen.dart';
import '../../features/merchant/alerts/order_alerts.dart';
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
import '../../features/settings/language_screen.dart';
import '../../features/settings/onboarding_screen.dart';
import '../../features/settings/theme_screen.dart';
import '../../features/customer/bookings/success_screen.dart';
import '../theme/theme_controller.dart';
import '../auth/session.dart';
import '../i18n/i18n.dart';

/// Bridges the Riverpod session to go_router so redirects re-run on login/logout.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
    ref.listen(languageProvider, (_, _) => notifyListeners());
    ref.listen(onboardedProvider, (_, _) => notifyListeners());
  }
}

int _id(GoRouterState state) => int.parse(state.pathParameters['id']!);

/// A shared deal link (microbargain://open/deal/5) that arrived before sign-in; opened once signed in.
String? _pendingLink;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final here = state.matchedLocation;
      if ((here.startsWith('/deal/') || here.startsWith('/shop/')) && ref.read(sessionProvider).status != SessionStatus.signedIn) {
        _pendingLink = here;
      }
      // First launch: pick a language before anything else.
      if (ref.read(languageProvider) == null) return here == '/language' ? null : '/language';
      // Then the welcome slides, once.
      if (!ref.read(onboardedProvider)) return here == '/welcome' ? null : '/welcome';
      final session = ref.read(sessionProvider);
      final onAuth = here == '/login' || here == '/otp';
      switch (session.status) {
        case SessionStatus.unknown:
          return here == '/splash' ? null : '/splash';
        case SessionStatus.signedOut:
          return onAuth ? null : '/login';
        case SessionStatus.signedIn:
          if (session.isAdmin) return here == '/admin-account' ? null : '/admin-account';
          final home = session.isMerchant ? '/merchant' : '/customer';
          if (onAuth && !session.isMerchant && ref.read(loginRoleProvider) == 'merchant') {
            return '/become-merchant'; // chose "shop owner" on the login screen
          }
          if (onAuth || here == '/splash') {
            final link = _pendingLink;
            _pendingLink = null;
            return link ?? home;
          }
          // Becoming a merchant switches apps.
          if (session.isMerchant && (here == '/customer' || here == '/become-merchant')) return home;
          if (!session.isMerchant && here.startsWith('/merchant')) return home;
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/language', builder: (_, _) => const LanguageScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/theme', builder: (_, _) => const ThemeScreen()),
      GoRoute(
        path: '/success',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SuccessScreen(detailRoute: extra['route'] as String, isOrder: extra['order'] == true);
        },
      ),
      GoRoute(path: '/admin-account', builder: (_, _) => const AdminAccountScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OtpScreen(phone: extra['phone'] as String, testOtp: extra['otp'] as String?);
        },
      ),

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
      GoRoute(
        path: '/collection',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CollectionScreen(title: extra['title'] as String, query: extra['query'] as String);
        },
      ),
      GoRoute(path: '/referral', builder: (_, _) => const ReferralScreen()),
      GoRoute(path: '/plus', builder: (_, _) => const PlusScreen()),
      GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
      GoRoute(path: '/refunds', builder: (_, _) => const RefundsScreen()),
      GoRoute(path: '/refund-policy', builder: (_, _) => const RefundPolicyScreen()),
      GoRoute(path: '/search', builder: (_, state) => SearchScreen(initial: state.extra as String? ?? '')),
      GoRoute(path: '/daily', builder: (_, _) => const MyDailyScreen()),
      GoRoute(path: '/chats', builder: (_, _) => const ChatListScreen()),
      GoRoute(path: '/chat/:id', builder: (_, state) => ChatScreen(id: _id(state))),
      GoRoute(path: '/map', builder: (_, _) => const ShopsMapScreen()),
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
      GoRoute(path: '/merchant/incoming', builder: (_, _) => const IncomingOrdersScreen()),
      GoRoute(path: '/merchant/onboarding', builder: (_, _) => const ShopSetupScreen()),
      GoRoute(path: '/merchant/complaints', builder: (_, _) => const MerchantComplaintsScreen()),
      GoRoute(path: '/merchant/khata', builder: (_, _) => const KhataScreen()),
      GoRoute(path: '/merchant/khata/:id', builder: (_, state) => KhataCustomerScreen(id: _id(state))),
      GoRoute(path: '/merchant/daily', builder: (_, _) => const MerchantDailyScreen()),
      GoRoute(path: '/merchant/inventory', builder: (_, _) => const InventoryScreen()),
      GoRoute(path: '/merchant/plans', builder: (_, _) => const PlansScreen()),
      GoRoute(path: '/merchant/promotions', builder: (_, _) => const PromotionsScreen()),
      GoRoute(path: '/merchant/reviews', builder: (_, _) => const MerchantReviewsScreen()),
      GoRoute(path: '/merchant/earnings', builder: (_, _) => const EarningsScreen()),
    ],
  );
});
