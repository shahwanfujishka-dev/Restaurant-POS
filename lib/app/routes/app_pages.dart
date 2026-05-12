import 'package:get/get_navigation/src/routes/get_route.dart';

import '../modules/auth/bindings/auth_binding.dart';
import '../modules/auth/bindings/sync_binding.dart';
import '../modules/auth/views/auth_view.dart';
import '../modules/auth/views/sync_view.dart';
import '../modules/auth/views/widgets/qr_scanner_view.dart';
import '../modules/cart/bindings/cart_binding.dart';
import '../modules/cart/views/cart_view.dart';
import '../modules/home/bindings/cashier_binding.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/bindings/settings_binding.dart';
import '../modules/home/home_view.dart';
import '../modules/home/views/cashier/cashier_view.dart';
import '../modules/home/views/settings/settings_view.dart';
import '../modules/order_type/bindings/order_type_binding.dart';
import '../modules/order_type/views/order_type_view.dart';
part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.AUTH;

  static final routes = [
    GetPage(
      name: _Paths.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: _Paths.AUTH,
      page: () => const AuthView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: _Paths.SYNC,
      page: () => const SyncView(),
      binding: SyncBinding(),
    ),
    GetPage(
      name: _Paths.CART,
      page: () => const CartView(),
      binding: CartBinding(),
    ),
    GetPage(
      name: _Paths.QrScann,
      page: () => const QrScannerView(),
    ),
    GetPage(
      name: _Paths.ORDER_TYPE,
      page: () => const OrderTypeView(),
      binding: OrderTypeBinding(),
    ),
    GetPage(
      name: _Paths.CASHIER,
      page: () => const CashierView(),
      binding: CashierBinding(),
    ),
    GetPage(
      name: _Paths.SETTINGS,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
    ),
  ];
}
