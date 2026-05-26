import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import 'order_controller.dart';

class SettingsController extends GetxController {
  final SyncService _syncService = Get.find<SyncService>();
  
  final isBackgroundSync = AppState.isBackgroundSyncEnabled.obs;
  
  // Observables for UI feedback during manual sync
  RxBool get isMasterSyncing => _syncService.isMasterSyncing;
  RxDouble get masterSyncProgress => _syncService.masterSyncProgress;

  void toggleBackgroundSync(bool value) {
    isBackgroundSync.value = value;
    AppState.isBackgroundSyncEnabled = value;
  }

  Future<void> performManualMasterSync() async {
    try {
      // 1. Sync any pending offline orders/payments first
      await _syncService.syncPendingOrders();

      // 2. Then sync master data (products, tables, etc.)
      await _syncService.syncMasterData();

      // 3. Refresh the orders list in UI if controller is registered
      if (Get.isRegistered<OrdersController>()) {
        await Get.find<OrdersController>().fetchOrders();
      }

      Get.snackbar(
        "Sync Complete",
        "Orders and restaurant data have been updated successfully.",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        "Sync Failed",
        "Could not sync data: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
