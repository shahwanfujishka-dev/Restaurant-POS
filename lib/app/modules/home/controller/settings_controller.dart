import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/services/local_hub_server.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import 'order_controller.dart';

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
  final deviceRole = DeviceConfig.role.obs;
  final hostIp = RxnString(DeviceConfig.hostIp);
  final hostPort = DeviceConfig.hostPort.obs;
  final deviceId = DeviceConfig.deviceId.obs;
  final RxInt hubPort = 8080.obs;

  final RxString hubStatus = 'Not connected'.obs;


  // ---------------------------------------------------------------------------
  // HUB STATUS
  // ---------------------------------------------------------------------------

  final isHubConnected = false.obs;
  final isHubServerRunning = false.obs;
  final isTestingHubConnection = false.obs;

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  bool get isLocalMode => operationMode.value == OperationMode.local;
  bool get isOnlineMode => operationMode.value == OperationMode.online;
  bool get isHost => deviceRole.value == DeviceRole.host;
  bool get isClient => deviceRole.value == DeviceRole.client;
  bool get isSolo => deviceRole.value == DeviceRole.solo;

  String get deviceRoleLabel {
    switch (deviceRole.value) {
      case DeviceRole.host:
        return 'Main Cashier / Host';
      case DeviceRole.client:
        return 'Client Device';
      case DeviceRole.solo:
        return 'Standalone';
    }
  }

  String get operationModeLabel {
    switch (operationMode.value) {
      case OperationMode.online:
        return 'Online';

      case OperationMode.local:
        return 'Local Hub';
    }
  }

  String get hostAddress {
    final ip = hostIp.value;

    if (ip == null || ip.isEmpty) {
      return 'Not configured';
    }

    return '$ip:${hostPort.value}';
  }

  String get hubUrl {
    final ip = hostIp.value;

    if (ip == null || ip.isEmpty) {
      return 'Not configured';
    }

    return 'http://$ip:${hostPort.value}';
  }

  String get hubStatusLabel {
    if (isHost) {
      return isHubServerRunning.value ? 'Server Running' : 'Server Stopped';
    }

    return isHubConnected.value ? 'Connected' : 'Not connected';
  }

  // ---------------------------------------------------------------------------
  // OPERATION MODE
  // ---------------------------------------------------------------------------

  Future<void> selectDeviceRole() async {
    final selectedRole = await Get.dialog<DeviceRole>(
      AlertDialog(
        title: const Text('Select Device Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _deviceRoleOption(
              role: DeviceRole.host,
              title: 'Main Cashier / Host',
              subtitle: 'Runs the local server for other devices.',
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 10),
            _deviceRoleOption(
              role: DeviceRole.client,
              title: 'Client',
              subtitle: 'Connects to the Main Cashier over LAN.',
              icon: Icons.tablet_android_outlined,
            ),
          ],
        ),
      ),
    );

    if (selectedRole == null) {
      return;
    }

    await changeDeviceRole(selectedRole);
  }

  Widget _deviceRoleOption({
    required DeviceRole role,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Get.back(result: role);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> changeOperationMode(bool local) async {
    final newMode = local
        ? OperationMode.local
        : OperationMode.online;

    if (newMode == OperationMode.local &&
        deviceRole.value == DeviceRole.solo) {
      await selectDeviceRole();

      // User may have closed the dialog without selecting.
      if (deviceRole.value == DeviceRole.solo) {
        return;
      }
    }

    operationMode.value = newMode;

    await DeviceConfig.setOperationMode(newMode);

    debugPrint(
      'Operation mode changed: ${newMode.name}',
    );
  }
  // ---------------------------------------------------------------------------
  // DEVICE ROLE
  // ---------------------------------------------------------------------------

  Future<void> changeDeviceRole(DeviceRole role) async {
    deviceRole.value = role;

    await DeviceConfig.setRole(role);

    // ------------------------------------------------------------
    // HOST
    // ------------------------------------------------------------

    if (role == DeviceRole.host) {
      try {
        await LocalHubServer.instance.start();

        isHubServerRunning.value =
            LocalHubServer.instance.isRunning;

        final ip = LocalHubServer.instance.hostAddress;

        if (ip != null && ip.isNotEmpty) {
          hostIp.value = ip;

          await DeviceConfig.setHostIp(ip);
        }

        debugPrint('======================================');
        debugPrint('DEVICE CONFIGURED AS HOST');
        debugPrint('Host IP : $ip');
        debugPrint(
          'Hub URL : ${LocalHubServer.instance.serverUrl}',
        );
        debugPrint('======================================');
      } catch (e) {
        isHubServerRunning.value = false;

        Get.snackbar(
          'Local Hub Error',
          'Could not start the local server: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );

        return;
      }
    }

    // ------------------------------------------------------------
    // CLIENT
    // ------------------------------------------------------------

    if (role == DeviceRole.client) {
      // A client must not run the server.
      isHubServerRunning.value = false;

      debugPrint(
        'DEVICE CONFIGURED AS CLIENT',
      );
    }

    // ------------------------------------------------------------
    // SOLO
    // ------------------------------------------------------------

    if (role == DeviceRole.solo) {
      if (LocalHubServer.instance.isRunning) {
        await LocalHubServer.instance.stop();
      }

      isHubServerRunning.value = false;

      hostIp.value = null;

      await DeviceConfig.setHostIp(null);

      debugPrint(
        'DEVICE CONFIGURED AS SOLO',
      );
    }

    // ------------------------------------------------------------
    // LOCAL MODE
    // ------------------------------------------------------------

    if (role == DeviceRole.solo &&
        operationMode.value == OperationMode.local) {
      operationMode.value = OperationMode.online;

      await DeviceConfig.setOperationMode(
        OperationMode.online,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // HOST IP
  // ---------------------------------------------------------------------------

  Future<void> setHostIp(String ip) async {
    final cleanedIp = ip.trim();

    if (cleanedIp.isEmpty) {
      Get.snackbar(
        'Invalid Host',
        'Please enter a valid host IP address.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );

      return;
    }

    hostIp.value = cleanedIp;

    await DeviceConfig.setHostIp(cleanedIp);

    isHubConnected.value = false;
  }

  // ---------------------------------------------------------------------------
  // HOST PORT
  // ---------------------------------------------------------------------------

  Future<void> setHostPort(int port) async {
    if (port < 1 || port > 65535) {
      Get.snackbar(
        'Invalid Port',
        'Please enter a valid port number.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );

      return;
    }

    hostPort.value = port;

    await DeviceConfig.setHostPort(port);

    isHubConnected.value = false;
  }

  // ---------------------------------------------------------------------------
  // DEVICE ID
  // ---------------------------------------------------------------------------

  Future<void> setDeviceId(String value) async {
    final id = value.trim();

    if (id.isEmpty) {
      return;
    }

    deviceId.value = id;

    await DeviceConfig.setDeviceId(id);
  }

  // ---------------------------------------------------------------------------
  // HUB CONNECTION TEST
  // ---------------------------------------------------------------------------


  Future<void> testHubConnection() async {
    final ip = hostIp.value!.trim();

    if (ip.isEmpty) {
      Get.snackbar(
        'Host Address Required',
        'Enter the Main Cashier IP address first.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isTestingHubConnection.value = true;
      hubStatus.value = 'Connecting...';

      final result =
      await LocalHubClient.instance.testConnection(
        hostIp: ip,
        port: hubPort.value,
      );

      debugPrint('======================================');
      debugPrint('LOCAL HUB CONNECTION SUCCESS');
      debugPrint('Host IP: ${result['hostIp']}');
      debugPrint('Port: ${result['port']}');
      debugPrint('Hub URL: ${result['hubUrl']}');
      debugPrint('======================================');

      hubStatus.value = 'Connected';

      Get.snackbar(
        'Connected',
        'Successfully connected to Main Cashier.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('LOCAL HUB CONNECTION FAILED: $e');

      hubStatus.value = 'Connection Failed';

      Get.snackbar(
        'Connection Failed',
        'Could not connect to Main Cashier.\n'
            'Check the IP address and Wi-Fi connection.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isTestingHubConnection.value = false;
    }
  }

  Future<Map<String, dynamic>> testConnection({
    required String hostIp,
    int port = 8080,
  }) async {
    final url = Uri.parse(
      'http://$hostIp:$port/hub/status',
    );

    try {
      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT');
      debugPrint('Testing Hub: $url');
      debugPrint('======================================');

      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 5));

      debugPrint('Hub Status Code: ${response.statusCode}');
      debugPrint('Hub Response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid hub response');
      }

      if (data['success'] != true) {
        throw Exception(
          data['message'] ?? 'Hub connection failed',
        );
      }

      if (data['role'] != 'host') {
        throw Exception(
          'The device at $hostIp is not configured as a Host.',
        );
      }

      return data;
    } catch (e) {
      debugPrint('LOCAL HUB CLIENT ERROR: $e');
      rethrow;
    }
  }
  // ---------------------------------------------------------------------------
  // SERVER STATE
  // ---------------------------------------------------------------------------

  void updateHubServerState(bool running) {
    isHubServerRunning.value = running;
  }

  // ---------------------------------------------------------------------------
  // SYNC
  // ---------------------------------------------------------------------------

  void toggleBackgroundSync(bool value) {
    isBackgroundSync.value = value;
    AppState.isBackgroundSyncEnabled = value;
  }

  Future<void> performManualMasterSync() async {
    try {
      await _syncService.syncPendingOrders();
      await _syncService.syncMasterData();

      if (Get.isRegistered<OrdersController>()) {
        await Get.find<OrdersController>().fetchOrders();
      }

      Get.snackbar(
        'Sync Complete',
        'Orders and restaurant data have been updated successfully.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Sync Failed',
        'Could not sync data: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
