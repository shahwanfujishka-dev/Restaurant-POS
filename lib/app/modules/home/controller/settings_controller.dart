import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/services/local_hub_server.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';

class SettingsController extends GetxController {
  final SyncService _syncService = Get.find<SyncService>();

  // ---------------------------------------------------------------------------
  // SYNC
  // ---------------------------------------------------------------------------
  final isBackgroundSync = AppState.isBackgroundSyncEnabled.obs;
  RxBool get isMasterSyncing => _syncService.isMasterSyncing;
  RxDouble get masterSyncProgress => _syncService.masterSyncProgress;

  // ---------------------------------------------------------------------------
  // DEVICE CONFIGURATION
  // ---------------------------------------------------------------------------
  final operationMode = DeviceConfig.operationMode.obs;
  
  // Role is now automatically determined by platform and cannot be changed manually.
  DeviceRole get deviceRole => DeviceConfig.role;
  
  final hostIp = RxnString(DeviceConfig.hostIp);
  final hostPort = DeviceConfig.hostPort.obs;
  final deviceId = DeviceConfig.deviceId.obs;

  // ---------------------------------------------------------------------------
  // HUB STATUS
  // ---------------------------------------------------------------------------
  final isHubConnected = false.obs;
  final isHubServerRunning = false.obs;
  final isTestingHubConnection = false.obs;
  final hubStatus = 'Not connected'.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeHub();
  }

  void _initializeHub() async {
    // Sync current server status
    isHubServerRunning.value = LocalHubServer.instance.isRunning;

    // Automatically start server if this is a Host (Desktop) in Local Mode
    if (isLocalMode && isHost && !isHubServerRunning.value) {
      await startLocalServer();
    }
  }

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------
  bool get isLocalMode => operationMode.value == OperationMode.local;
  bool get isOnlineMode => operationMode.value == OperationMode.online;
  bool get isHost => deviceRole == DeviceRole.server;
  bool get isClient => deviceRole == DeviceRole.client;

  String get deviceRoleLabel => DeviceConfig.roleName;
  String get operationModeLabel => DeviceConfig.operationModeName;

  String get hostAddress {
    final ip = hostIp.value;
    if (ip == null || ip.isEmpty) return 'Not configured';
    return '$ip:${hostPort.value}';
  }

  String get hubUrl {
    final ip = hostIp.value;
    if (ip == null || ip.isEmpty) return 'Not configured';
    return 'http://$ip:${hostPort.value}';
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> changeOperationMode(bool local) async {
    final newMode = local ? OperationMode.local : OperationMode.online;
    operationMode.value = newMode;
    await DeviceConfig.setOperationMode(newMode);

    if (newMode == OperationMode.local) {
      if (isHost) {
        await startLocalServer();
      }
    } else {
      if (LocalHubServer.instance.isRunning) {
        await LocalHubServer.instance.stop();
        isHubServerRunning.value = false;
      }
    }
  }

  Future<void> startLocalServer() async {
    try {
      if (!LocalHubServer.instance.isRunning) {
        await LocalHubServer.instance.start();
      }
      isHubServerRunning.value = true;
      final ip = LocalHubServer.instance.hostAddress;
      if (ip != null) {
        hostIp.value = ip;
        await DeviceConfig.setHostIp(ip);
      }
    } catch (e) {
      debugPrint('LOCAL HUB: Failed to start server: $e');
      isHubServerRunning.value = false;
    }
  }

  Future<void> setHostIp(String ip) async {
    hostIp.value = ip.trim();
    await DeviceConfig.setHostIp(ip.trim());
    isHubConnected.value = false;
  }

  Future<void> setHostPort(int port) async {
    hostPort.value = port;
    await DeviceConfig.setHostPort(port);
    isHubConnected.value = false;
  }

  Future<void> testHubConnection() async {
    final ip = hostIp.value?.trim();
    if (ip == null || ip.isEmpty) {
      Get.snackbar('Host IP Required', 'Please enter the IP of the Main Cashier.', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      isTestingHubConnection.value = true;

      // 1. Test connection
      await LocalHubClient.instance.testConnection(hostIp: ip, port: hostPort.value);

      // 2. Register Device
      final currentDeviceId = await _getOrCreateDeviceId();
      final registration = await LocalHubClient.instance.registerDevice(
        hostIp: ip,
        port: hostPort.value,
        deviceName: '${DeviceConfig.isDesktop ? "Desktop" : "Mobile"} Client',
        role: 'client',
        deviceId: currentDeviceId,
        userId: AppState.userId?.toString(),
        userName: AppState.username,
      );

      final token = registration['data']?['authToken']?.toString() ?? '';
      if (token.isNotEmpty) {
        await DeviceConfig.setAuthToken(token);
        isHubConnected.value = true;
        Get.snackbar('Success', 'Connected to Main Cashier', snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      isHubConnected.value = false;
      Get.snackbar('Connection Failed', 'Could not reach Main Cashier.', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isTestingHubConnection.value = false;
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    String id = DeviceConfig.deviceId;
    if (id.isEmpty) {
      id = const Uuid().v4();
      await DeviceConfig.setDeviceId(id);
      deviceId.value = id;
    }
    return id;
  }

  void toggleBackgroundSync(bool value) {
    isBackgroundSync.value = value;
    AppState.isBackgroundSyncEnabled = value;
  }

  Future<void> performManualMasterSync() async {
    await _syncService.syncMasterData();
  }
}
