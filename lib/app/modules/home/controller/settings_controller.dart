import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:restaurant_pos/app/modules/home/controller/dashboard_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/order_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import 'package:restaurant_pos/helper/snackbar_helper.dart';
import 'package:uuid/uuid.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/services/database_helper.dart';
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
  Timer? _countRefreshTimer; // ← new: Timer for automatic count refresh
  final connectedDevices = <Map<String, dynamic>>[].obs;   // ← new
  final showMyOrdersOnly = DeviceConfig.showMyOrdersOnly.obs;

  final pendingCount = 0.obs;
  final isSyncingOrders = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeHub();
    refreshPendingCount();
    _startCountRefreshPolling(); // ← new

    // Automatically refresh count when background sync status changes
    ever(_syncService.isSyncing, (bool syncing) {
      if (!syncing) {
        refreshPendingCount();
        // Also refresh order lists if they are active
        if (Get.isRegistered<OrdersController>()) {
          Get.find<OrdersController>().fetchOrders();
        }
      }
    });

    // Enforce no-sync for clients in local mode on start
    if (isLocalMode && isClient) {
      toggleBackgroundSync(false);
    }
  }

  /// Starts a timer to refresh the pending count every 5 seconds
  void _startCountRefreshPolling() {
    _countRefreshTimer?.cancel();
    _countRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Don't refresh while a manual sync is already in progress (it handles its own refreshes)
      if (!isSyncingOrders.value) {
        refreshPendingCount();
      }
    });
  }

  @override
  void onClose() {
    _deviceListTimer?.cancel();
    _countRefreshTimer?.cancel(); // ← new
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

    // Switching away from Local while hosting active clients kills their
    // connection immediately — confirm before doing that.
    if (!local && isLocalMode && isHost && connectedDevices.isNotEmpty) {
      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: const Text("Switch to Online Mode?"),
          content: Text(
            "${connectedDevices.length} device(s) are currently connected to this host. "
                "Switching to Online Mode will stop the local server and disconnect them immediately.",
          ),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text("Switch Anyway", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    operationMode.value = newMode;
    await DeviceConfig.setOperationMode(newMode);

    if (newMode == OperationMode.local) {
      if (isHost) {
        await startLocalServer();
      } else {
        // Automatically disable live sync when switching to client local mode
        toggleBackgroundSync(false);
      }
    } else {
      if (LocalHubServer.instance.isRunning) {
        await LocalHubServer.instance.stop();
        isHubServerRunning.value = false;
      }
    }
  }

  Future<Map<String, String>?> _scanSubnetForHost({
    required String myDeviceId,
    required int port,
  }) async {
    final String? myIp = await LocalHubNetwork.getLocalIp();
    if (myIp == null) return null;

    final segments = myIp.split('.');
    if (segments.length != 4) return null;
    final prefix = '${segments[0]}.${segments[1]}.${segments[2]}';

    const int chunkSize = 32; // probe in batches so we don't fire 254 sockets at once
    for (int start = 1; start <= 254; start += chunkSize) {
      final end = math.min(start + chunkSize - 1, 254);
      final candidates = [
        for (int i = start; i <= end; i++)
          if ('$prefix.$i' != myIp) '$prefix.$i'
      ];

      final results = await Future.wait(candidates.map((ip) async {
        try {
          final status = await LocalHubClient.instance
              .testConnection(hostIp: ip, port: port)
              .timeout(const Duration(milliseconds: 350));
          return MapEntry(ip, status);
        } catch (_) {
          return null;
        }
      }));

      for (final entry in results) {
        if (entry == null) continue;
        final respondingId = entry.value['hostDeviceId']?.toString();
        if (respondingId != null && respondingId.isNotEmpty && respondingId != myDeviceId) {
          return {'ip': entry.key, 'deviceId': respondingId};
        }
      }
    }
    return null;
  }

  Future<void> becomeHost() async {
    if (isChangingRole.value) return;
    isChangingRole.value = true;
    try {
      final String myDeviceId = await _getOrCreateDeviceId();
      String? conflictIp;

      // 1. Fast path — check the last-known peer IP, if we have one.
      final String? knownPeerIp = DeviceConfig.hostIp;
      if (knownPeerIp != null && knownPeerIp.trim().isNotEmpty) {
        try {
          final status = await LocalHubClient.instance
              .testConnection(hostIp: knownPeerIp, port: hostPort.value)
              .timeout(const Duration(seconds: 2));
          final respondingId = status['hostDeviceId']?.toString();
          if (respondingId != null && respondingId.isNotEmpty && respondingId != myDeviceId) {
            conflictIp = knownPeerIp;
          }
        } catch (_) {
          // no response from stored peer — fall through to scan
        }
      }

      // 2. Thorough fallback — scan the subnet. Covers a device that has
      //    never connected as a client, so it has no stored peer IP.
      if (conflictIp == null) {
        final scanResult = await _scanSubnetForHost(myDeviceId: myDeviceId, port: hostPort.value);
        if (scanResult != null) conflictIp = scanResult['ip'];
      }

      if (conflictIp != null) {
        Get.snackbar(
          'Host Already Running',
          'Another device is already acting as the Main Cashier at $conflictIp on this network. '
              'Only one host is allowed. Please connect as a client to it instead.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6),
        );
        return;
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

    if (isHost && connectedDevices.isNotEmpty) {
      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: const Text("Switch to Client?"),
          content: Text(
            "${connectedDevices.length} device(s) are currently connected to this host. "
                "Switching roles will disconnect them immediately.",
          ),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text("Switch Anyway", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

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

      if (isLocalMode) {
        toggleBackgroundSync(false);
      }

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
        Get.find<SyncService>().syncPendingHubOrders();
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
    if (Get.isRegistered<DashboardController>()) {
      Get.find<DashboardController>().refreshDashboardData();
    }

    // Refresh Tables and Areas
    if (Get.isRegistered<TablesController>()) {
      Get.find<TablesController>().fetchTables();
    }

    // Refresh Orders and Sold Orders
    if (Get.isRegistered<OrdersController>()) {
      Get.find<OrdersController>().fetchOrders();
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
    // Only host or online mode can manage background sync to live
    if (isLocalMode && isClient) {
      isBackgroundSync.value = false;
      AppState.isBackgroundSyncEnabled = false;
      return;
    }
    isBackgroundSync.value = value;
    AppState.isBackgroundSyncEnabled = value;
  }

  Future<void> performManualMasterSync() async {
    if (isLocalMode && isClient) return;
    try {
      await _syncService.syncMasterData();
      _refreshControllers();
      Get.snackbar('Success', 'Data synced successfully', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to sync data: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> refreshPendingCount() async {
    final orderCount = await DatabaseHelper.instance.getUnsyncedOrdersCount();
    final paymentCount = await DatabaseHelper.instance.getUnsyncedPaymentsCount();
    pendingCount.value = orderCount + paymentCount;
  }

  Future<void> syncOrdersToLive() async {
    if (isLocalMode && isClient) return;
    if (isSyncingOrders.value) return;
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        showSafeSnackbar("No Internet", "Please check your network connection.");
        return;
      }
    } catch (_) {
      showSafeSnackbar("No Internet", "Please check your network connection.");
      return;
    }

    isSyncingOrders.value = true;
    try {
      final unsyncedOrders = await DatabaseHelper.instance.getUnsyncedOrders();
      for (var order in unsyncedOrders) {
        await _syncService.syncOrder(order);
        await refreshPendingCount();
      }

      final unsyncedPayments = await DatabaseHelper.instance.getUnsyncedPayments();
      for (var payment in unsyncedPayments) {
        await _syncService.syncPayment(payment);
        await refreshPendingCount();
      }

      _refreshControllers();

      if (pendingCount.value == 0) {
        showSafeSnackbar("Sync Complete", "All data has been synced to the live server.");
      } else {
        showSafeSnackbar("Sync Partial", "Some items could not be synced. Check logs for details.");
      }
    } catch (e) {
      showSafeSnackbar("Sync Error", "An error occurred: $e");
    } finally {
      isSyncingOrders.value = false;
      await refreshPendingCount();
    }
  }
}