import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import 'package:restaurant_pos/app/modules/home/views/settings/settings_view.dart';

import '../../../data/utils/AppState.dart';
import '../../../theme/app_theme.dart';
import '../views/dashoard/dashboard_page.dart';
import '../views/orders/orders_page.dart';
import '../views/printers/printers_page.dart';
import '../views/tables/tables_page.dart';
import 'order_controller.dart';

class HomeController extends GetxController {
  // ✅ Changed initial index to 0 (Dashboard)
  final selectedIndex = 0.obs;

  final List<String> pageTitles = [
    'dashboard',
    'tables',
    'orders',
    'printers',
    'settings'
  ];

  final List<Widget> pages = [
    const DashboardPage(),
    const TablesPage(),
    const OrdersPage(),
    PrintersPage(),
    SettingsView()
  ];

  void changeIndex(int index) {
    selectedIndex.value = index;

    // Refresh tables and floors whenever the Tables page (index 1) is selected
    if (index == 1) {
      if (Get.isRegistered<TablesController>()) {
        Get.find<TablesController>().fetchTables();
      }
    }

    // Refresh orders whenever the Orders page (index 2) is selected
    if (index == 2) {
      if (Get.isRegistered<OrdersController>()) {
        Get.find<OrdersController>().fetchOrders();
      }
    }
  }

  String get pageTitle => pageTitles[selectedIndex.value];

  void setOrientation({required bool isMobile}) {
    if (isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void logout() {
    Get.defaultDialog(
      title: "confirm_logout".tr,
      middleText: "logout_msg".tr,
      textConfirm: "yes".tr,
      textCancel: "no".tr,
      confirmTextColor: Colors.white,
      buttonColor: AppTheme.primaryGreen,
      onCancel: () {
        Get.back();
      },
      onConfirm: () async {
        await AppState.logout();
      },
    );
  }
}
