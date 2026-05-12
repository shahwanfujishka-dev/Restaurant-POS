import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get_storage/get_storage.dart';

import '../../modules/cart/controller/cart_controller.dart';
import '../../modules/home/controller/dashboard_controller.dart';
import '../../modules/home/controller/order_controller.dart';
import '../../modules/home/controller/printer_controller.dart';
import '../../modules/home/controller/table_controller.dart';
import '../models/order_type.dart';
import '../services/database_helper.dart';

class AppState {
  static final GetStorage _storage = GetStorage();

  static bool get isLoggedIn => _storage.read('user_profile') != null;
  static String get token => _storage.read('branch_token') ?? '';
  static String get companyCode => _storage.read('company_code') ?? '';
  static String get branchToken => _storage.read('mobileapptoken') ?? '';
  static String get cmptoken => _storage.read('cmptoken') ?? '';
  static String get username => _storage.read('usr_name') ?? '';
  static String get userId => _storage.read('usr_id')?.toString() ?? '';
  static String get serverUrl => _storage.read('base_url') ?? '';

  // Order Type Persistence
  static OrderType get orderType {
    final int? id = _storage.read('selected_order_type_id');
    if (id == null) return OrderType.dineIn;
    return OrderType.values.firstWhere((e) => e.id == id, orElse: () => OrderType.dineIn);
  }

  static set orderType(OrderType type) {
    _storage.write('selected_order_type_id', type.id);
  }

  // Sync Preferences
  static bool get isBackgroundSyncEnabled => _storage.read('bg_sync_enabled') ?? true;
  static set isBackgroundSyncEnabled(bool value) => _storage.write('bg_sync_enabled', value);

  static void updateSession({
    required dynamic profile,
  }) {
    _storage.write('usr_id', profile['usr_id']);
    _storage.write('usr_name', profile['usr_name']);
    _storage.write('ledger_id', profile['ledger_id']);
    _storage.write('user_profile', profile);
  }

  static Future<void> clearAllData() async {
    await _storage.erase();
    try {
      final db = await DatabaseHelper.instance.database;
      var tableNames = (await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']))
          .map((row) => row['name'] as String)
          .toList();

      for (var tableName in tableNames) {
        if (tableName != 'android_metadata' && tableName != 'sqlite_sequence') {
          await db.delete(tableName);
        }
      }
    } catch (e) {
      print("Error clearing database: $e");
    }

    try {
      if (Get.isRegistered<CartController>()) Get.delete<CartController>(force: true);
      if (Get.isRegistered<OrdersController>()) Get.delete<OrdersController>(force: true);
      if (Get.isRegistered<DashboardController>()) Get.delete<DashboardController>(force: true);
      if (Get.isRegistered<TablesController>()) Get.delete<TablesController>(force: true);
      if (Get.isRegistered<PrinterController>()) Get.delete<PrinterController>(force: true);
    } catch (e) {
      print("Error deleting controllers: $e");
    }
  }

  static Future<void> logout() async {
    await clearAllData();
    Get.offAllNamed('/auth');
  }
}
