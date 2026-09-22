import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:restaurant_pos/app/modules/home/controller/dashboard_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import 'package:uuid/uuid.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/services/local_hub_network.dart';
import '../../../data/services/local_hub_server.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';

class SettingsController extends GetxController {
  final SyncService _syncService = Get.find<SyncService>();
  final isBackgroundSync = AppState.isBackgroundSyncEnabled.obs;
  RxBool get isMasterSyncing => _syncService.isMasterSyncing;
  RxDouble get masterSyncProgress => _syncService.masterSyncProgress;
  final operationMode = DeviceConfig.operationMode.obs;
  // DeviceRole get deviceRole => DeviceConfig.role;
  final deviceRoleRx = DeviceConfig.role.obs; // ← new: replaces the old plain getter
  final isChangingRole = false.obs;
  final hostIp = RxnString(DeviceConfig.hostIp);
  final hostPort = DeviceConfig.hostPort.obs;
  final deviceId = DeviceConfig.deviceId.obs;
  final isHubConnected = false.obs;
  final isHubServerRunning = false.obs;
  final isTestingHubConnection = false.obs;
  final hubStatus = 'Not connected'.obs;
  Timer? _deviceListTimer;
  final connectedDevices = <Map<String, dynamic>>[].obs;   // ← new
  final showMyOrdersOnly = DeviceConfig.showMyOrdersOnly.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeHub();
  }

  @override
  void onClose() {
    _deviceListTimer?.cancel();   // ← new
    super.onClose();
  }

  void _initializeHub() async {
    isHubServerRunning.value = LocalHubServer.instance.isRunning;

    if (isLocalMode && isHost && !isHubServerRunning.value) {
      await startLocalServer();
    }

    if (isLocalMode && isHost) {                       // ← new
      _startConnectedDevicesPolling();
    }
  }

  void _startConnectedDevicesPolling() {                // ← new
    _refreshConnectedDevices();
    _deviceListTimer?.cancel();
    _deviceListTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshConnectedDevices();
    });
  }

  void _refreshConnectedDevices() {                      // ← new
    connectedDevices.assignAll(LocalHubServer.instance.connectedDevices);
  }

  void toggleOrderVisibility(bool value) {
    showMyOrdersOnly.value = value;
    DeviceConfig.setShowMyOrdersOnly(value);
  }

  bool get isLocalMode => operationMode.value == OperationMode.local;
  bool get isOnlineMode => operationMode.value == OperationMode.online;
  bool get isHost => deviceRoleRx.value == DeviceRole.server; // ← now reads the Rx
  bool get isClient => deviceRoleRx.value == DeviceRole.client;
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

  Future<void> becomeHost() async {
    if (isChangingRole.value) return;
    isChangingRole.value = true;
    try {
      final String myDeviceId = await _getOrCreateDeviceId();
      final String? probeIp = await LocalHubNetwork.getLocalIp();

      if (probeIp != null) {
        try {
          final status = await LocalHubClient.instance.testConnection(hostIp: probeIp, port: hostPort.value);
          final String? respondingDeviceId = status['hostDeviceId']?.toString();

          if (respondingDeviceId != null && respondingDeviceId.isNotEmpty && respondingDeviceId != myDeviceId) {
            Get.snackbar(
              'Host Already Running',
              'Another device is already acting as the Main Cashier on this network ($probeIp). Only one host is allowed. Please connect as a client to it instead.',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 6),
            );
            return;
          }
          // Same device id, or no id returned — safe to proceed.
        } catch (_) {
          // No response — nothing hosting at this address, safe to proceed.
        }
      }

      await DeviceConfig.setRole(DeviceRole.server);
      deviceRoleRx.value = DeviceRole.server;

      if (isLocalMode) {
        await startLocalServer();
        _startConnectedDevicesPolling();
      }

      Get.snackbar('Host Mode Enabled', 'This device is now the Main Cashier.', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isChangingRole.value = false;
    }
  }

  Future<void> becomeClient() async {
    if (isChangingRole.value) return;
    isChangingRole.value = true;
    try {
      if (LocalHubServer.instance.isRunning) {
        await LocalHubServer.instance.stop();
        isHubServerRunning.value = false;
      }
      _deviceListTimer?.cancel();
      connectedDevices.clear();

      await DeviceConfig.setRole(DeviceRole.client);
      deviceRoleRx.value = DeviceRole.client;

      Get.snackbar('Client Mode Enabled', 'Enter the Main Cashier IP below to connect.', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isChangingRole.value = false;
    }
  }

  Future<void> startLocalServer() async {
    try {
      // Same conflict probe as becomeHost() — protects against the server
      // auto-starting (e.g. app relaunch already in host role + local mode)
      // onto a network where another host has since appeared.
      final String myDeviceId = await _getOrCreateDeviceId();
      final String? probeIp = await LocalHubNetwork.getLocalIp();
      if (probeIp != null) {
        try {
          final status = await LocalHubClient.instance.testConnection(hostIp: probeIp, port: hostPort.value);
          final String? respondingDeviceId = status['hostDeviceId']?.toString();

          if (respondingDeviceId != null && respondingDeviceId.isNotEmpty && respondingDeviceId != myDeviceId) {
            Get.snackbar(
              'Host Already Running',
              'Another device is already acting as the Main Cashier on this network ($probeIp). Only one host is allowed. Please switch this device to Client mode instead.',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 6),
            );
            return;
          }
        } catch (_) {
          // No response — safe to proceed.
        }
      }

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
      Get.snackbar(
        'Host IP Required',
        'Please enter the IP of the Main Cashier.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isTestingHubConnection.value = true;

      // 1. Test connection
      await LocalHubClient.instance.testConnection(
        hostIp: ip,
        port: hostPort.value,
      );

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

        // Refresh Master Data (Categories, Products, Tables, etc.)
        _refreshControllers();

        Get.snackbar(
          'Success',
          'Connected to Main Cashier',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      isHubConnected.value = false;
      Get.snackbar(
        'Connection Failed',
        'Could not reach Main Cashier.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isTestingHubConnection.value = false;
    }
  }

  void _refreshControllers() {
    // Refresh Dashboard Data (Categories, Products, Favorites, VAT)
    if (Get.isRegistered<DashboardController>()) {
      Get.find<DashboardController>().refreshDashboardData();
    }

    // Refresh Tables and Areas
    if (Get.isRegistered<TablesController>()) {
      Get.find<TablesController>().fetchTables();
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
