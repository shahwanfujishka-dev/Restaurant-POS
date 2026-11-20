import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get_storage/get_storage.dart';
import '../../modules/cart/controller/cart_controller.dart';
import '../../modules/home/controller/dashboard_controller.dart';
import '../../modules/home/controller/order_controller.dart';
import '../../modules/home/controller/printer_controller.dart';
import '../../modules/home/controller/table_controller.dart';
import '../../modules/home/controller/cashier_controller.dart';
import '../../modules/home/controller/settings_controller.dart';
import '../../modules/order_type/controller/order_type_controller.dart';
import '../../modules/home/controller/home_controller.dart';
import '../../modules/auth/controllers/auth_controller.dart';
import '../models/order_type.dart';
import '../Device_Roles/device_roles.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class AppState {
  static final GetStorage _storage = GetStorage();
  static bool get isLoggedIn => _storage.read('user_profile') != null;
  static String get token => _storage.read('branch_token') ?? '';
  static String get companyCode => _storage.read('company_code') ?? '';
  static String get branchToken => _storage.read('mobileapptoken') ?? '';
  static String get branchName => _storage.read('branch_name') ?? '';
  static String get branchDisName => _storage.read('branch_display_name') ?? '';
  static String get branchAddress => _storage.read('branch_address') ?? '';
  static String get branchMob => _storage.read('branch_mob') ?? '';
  static String get branchPhNo => _storage.read('branch_phone') ?? '';
  static String get branchVat => _storage.read('branch_tin') ?? '';
  static String get cmptoken => _storage.read('cmptoken') ?? '';
  static String get username => _storage.read('usr_name') ?? '';
  static String get userId => _storage.read('usr_id')?.toString() ?? '';
  static String get lastSyncedUserId =>
      _storage.read('last_synced_user_id')?.toString() ?? '';
  static set lastSyncedUserId(String val) =>
      _storage.write('last_synced_user_id', val);
  static String get serverUrl => _storage.read('base_url') ?? '';
  static String get ledgerId => _storage.read('ledger_id')?.toString() ?? '0';
  static String get cashLedgerId =>
      _storage.read('usr_cash_ledger_id')?.toString() ?? '0';
  static String get bankLedgerId =>
      _storage.read('usr_bank_ledger_id')?.toString() ?? '0';
  static int get cmpTaxType => _storage.read('cmp_tax_type') ?? 1;
  static String get upiId => _storage.read('as_upi_id') ?? '';
  static bool get isUpiEnabled => (_storage.read('as_upi_enable') ?? 0) == 1;

  static String get appLanguage => _storage.read('app_language') ?? 'en';
  static Future<void> setAppLanguage(String lang) async {
    await _storage.write('app_language', lang);
  }

  static OrderType get orderType {
    final int? id = _storage.read('selected_order_type_id');
    if (id == null) return OrderType.dineIn;
    return OrderType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => OrderType.dineIn,
    );
  }

  static set orderType(OrderType type) {
    _storage.write('selected_order_type_id', type.id);
  }

  static bool get isBackgroundSyncEnabled =>
      _storage.read('bg_sync_enabled') ?? true;
  static set isBackgroundSyncEnabled(bool value) =>
      _storage.write('bg_sync_enabled', value);
  static bool get isSyncInProgress =>
      _storage.read('is_sync_in_progress') ?? false;
  static set isSyncInProgress(bool value) =>
      _storage.write('is_sync_in_progress', value);

  static void updateSession({required dynamic profile}) {
    _storage.write('usr_id', profile['usr_id']);
    _storage.write('usr_name', profile['usr_name']);
    _storage.write('ledger_id', profile['ledger_id']);
    _storage.write('user_profile', profile);
    _storage.write('usr_cash_ledger_id', profile['usr_cash_ledger_id']);
    _storage.write('usr_bank_ledger_id', profile['usr_bank_ledger_id']);
  }

  static Future<void> clearAllData() async {
    // Preserve only the theme mode setting across app data clearing / logout
    final isDarkMode = _storage.read('is_dark_mode');

    // Erase all GetStorage data
    await _storage.erase();

    // Restore theme mode if it was set
    if (isDarkMode != null) {
      _storage.write('is_dark_mode', isDarkMode);
    }

    // Explicitly reset operation mode back to online on logout
    await DeviceConfig.setOperationMode(OperationMode.online);

    orderType = OrderType.dineIn;

    // Clear cached network images and in-memory image cache
    try {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      debugPrint("Error clearing image cache: $e");
    }

    // Clear SQLite database tables (cached products, orders, customers, etc.)
    try {
      final db = await DatabaseHelper.instance.database;
      var tableNames = (await db.query(
        'sqlite_master',
        where: 'type = ?',
        whereArgs: ['table'],
      )).map((row) => row['name'] as String).toList();

      for (var tableName in tableNames) {
        if (tableName != 'android_metadata' && tableName != 'sqlite_sequence') {
          await db.delete(tableName);
        }
      }
    } catch (e) {
      debugPrint("Error clearing database: $e");
    }

    // Clear GetX controllers
    try {
      if (Get.isRegistered<CartController>()) {
        Get.delete<CartController>(force: true);
      }
      if (Get.isRegistered<OrdersController>()) {
        Get.delete<OrdersController>(force: true);
      }
      if (Get.isRegistered<DashboardController>()) {
        Get.delete<DashboardController>(force: true);
      }
      if (Get.isRegistered<TablesController>()) {
        Get.delete<TablesController>(force: true);
      }
      if (Get.isRegistered<PrinterController>()) {
        Get.delete<PrinterController>(force: true);
      }
      if (Get.isRegistered<OrderTypeController>()) {
        Get.delete<OrderTypeController>(force: true);
      }
      if (Get.isRegistered<HomeController>()) {
        Get.delete<HomeController>(force: true);
      }
      if (Get.isRegistered<SettingsController>()) {
        Get.delete<SettingsController>(force: true);
      }
      if (Get.isRegistered<CashierController>()) {
        Get.delete<CashierController>(force: true);
      }
      if (Get.isRegistered<AuthController>()) {
        Get.delete<AuthController>(force: true);
      }
    } catch (e) {
      debugPrint("Error deleting controllers: $e");
    }
  }

  static Future<void> logout() async {
    if (DeviceConfig.isServer) {
      final pending = await DatabaseHelper.instance.getPendingSyncTotal();
      if (pending > 0) {
        await Get.dialog(
          AlertDialog(
            title: const Text('Cannot log out'),
            content: Text(
              '$pending order/payment(s) are not synced yet. '
              'Logging out now would lose them. Sync first, then log out.',
            ),
            actions: [
              TextButton(onPressed: () => Get.back(), child: const Text('OK')),
              TextButton(
                onPressed: () async {
                  Get.back();
                  try {
                    await Get.find<SyncService>().syncPendingOrders();
                  } catch (_) {}
                  final left = await DatabaseHelper.instance
                      .getPendingSyncTotal();
                  if (left == 0) {
                    await logout();
                  } else {
                    Get.snackbar(
                      'Sync incomplete',
                      '$left item(s) still pending. Check the connection and try again.',
                    );
                  }
                },
                child: const Text('Sync now'),
              ),
            ],
          ),
        );
        return;
      }
    }

    await clearAllData();
    Get.offAllNamed('/auth');
  }
}