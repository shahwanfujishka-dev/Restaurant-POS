import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get_storage/get_storage.dart';

import '../../modules/cart/controller/cart_controller.dart';
import '../../modules/home/controller/dashboard_controller.dart';
import '../../modules/home/controller/order_controller.dart';
import '../../modules/home/controller/printer_controller.dart';
import '../../modules/home/controller/table_controller.dart';
import '../../modules/order_type/controller/order_type_controller.dart';
import '../../modules/home/controller/home_controller.dart';
import '../models/order_type.dart';
import '../services/database_helper.dart';

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
  static String get serverUrl => _storage.read('base_url') ?? '';
  static String get ledgerId => _storage.read('ledger_id')?.toString() ?? '0';
  static String get cashLedgerId =>
      _storage.read('usr_cash_ledger_id')?.toString() ?? '0';
  static String get bankLedgerId =>
      _storage.read('usr_bank_ledger_id')?.toString() ?? '0';
  static int get cmpTaxType => _storage.read('cmp_tax_type') ?? 1;
  static String get upiId => _storage.read('as_upi_id') ?? '';
  static bool get isUpiEnabled => (_storage.read('as_upi_enable') ?? 0) == 1;
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
    // Keep essential branch config before erasing
    final baseUrl = _storage.read('base_url');
    final companyCode = _storage.read('company_code');
    final branchId = _storage.read('branch_id');
    final branchToken = _storage.read('branch_token');
    final mobileAppToken = _storage.read('mobileapptoken');
    final branchName = _storage.read('branch_name');
    final branchDisName = _storage.read('branch_display_name');
    final branchAddress = _storage.read('branch_address');
    final branchPhone = _storage.read('branch_phone');
    final branchMob = _storage.read('branch_mob');
    final branchTin = _storage.read('branch_tin');
    final taxType = _storage.read('cmp_tax_type');

    await _storage.erase();

    // Restore branch config
    if (baseUrl != null) _storage.write('base_url', baseUrl);
    if (companyCode != null) _storage.write('company_code', companyCode);
    if (branchId != null) _storage.write('branch_id', branchId);
    if (branchToken != null) _storage.write('branch_token', branchToken);
    if (mobileAppToken != null)
      _storage.write('mobileapptoken', mobileAppToken);
    if (branchName != null) _storage.write('branch_name', branchName);
    if (branchDisName != null)
      _storage.write('branch_display_name', branchDisName);
    if (branchAddress != null) _storage.write('branch_address', branchAddress);
    if (branchPhone != null) _storage.write('branch_phone', branchPhone);
    if (branchMob != null) _storage.write('branch_mob', branchMob);
    if (branchTin != null) _storage.write('branch_tin', branchTin);
    if (taxType != null) _storage.write('cmp_tax_type', taxType);

    // Explicitly reset order type to Dine In
    orderType = OrderType.dineIn;

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
      print("Error clearing database: $e");
    }

    try {
      if (Get.isRegistered<CartController>())
        Get.delete<CartController>(force: true);
      if (Get.isRegistered<OrdersController>())
        Get.delete<OrdersController>(force: true);
      if (Get.isRegistered<DashboardController>())
        Get.delete<DashboardController>(force: true);
      if (Get.isRegistered<TablesController>())
        Get.delete<TablesController>(force: true);
      if (Get.isRegistered<PrinterController>())
        Get.delete<PrinterController>(force: true);
      if (Get.isRegistered<OrderTypeController>())
        Get.delete<OrderTypeController>(force: true);
      if (Get.isRegistered<HomeController>())
        Get.delete<HomeController>(force: true);
    } catch (e) {
      print("Error deleting controllers: $e");
    }
  }

  static Future<void> logout() async {
    await clearAllData();
    Get.offAllNamed('/auth');
  }
}
