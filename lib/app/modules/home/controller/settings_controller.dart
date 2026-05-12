import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';

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
      await _syncService.syncMasterData();
      Get.snackbar(
        "Sync Complete",
        "Your restaurant data has been updated successfully.",
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
