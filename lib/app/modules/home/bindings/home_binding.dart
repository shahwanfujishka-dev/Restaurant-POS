import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/bindings_interface.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:restaurant_pos/app/modules/home/controller/settings_controller.dart';
import '../../cart/controller/cart_controller.dart';
import '../../order_type/controller/order_type_controller.dart';
import '../controller/dashboard_controller.dart';
import '../controller/home_controller.dart';
import '../controller/order_controller.dart';
import '../controller/printer_controller.dart';
import '../controller/table_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(() => HomeController());
    Get.lazyPut<DashboardController>(() => DashboardController());
    Get.lazyPut<TablesController>(() => TablesController());
    Get.lazyPut<SettingsController>(() => SettingsController());
    Get.put(OrderTypeController(), permanent: true); // ✅ Make OrderType reactive globally
    Get.put(PrinterController());
    Get.put(OrdersController(), permanent: true);
    Get.put(CartController(), permanent: true);
  }
}
