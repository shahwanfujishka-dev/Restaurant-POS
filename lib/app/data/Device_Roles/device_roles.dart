import 'package:get_storage/get_storage.dart';

enum DeviceRole { host, client, solo }

enum OperationMode { online, local }

class DeviceConfig {
  static final GetStorage _storage = GetStorage();

  // Storage keys
  static const String _roleKey = 'device_role';
  static const String _hostIpKey = 'host_ip';
  static const String _hostPortKey = 'host_port';
  static const String _deviceIdKey = 'device_id';
  static const String _operationModeKey = 'operation_mode';

  // ---------------------------------------------------------------------------
  // DEVICE ROLE
  // ---------------------------------------------------------------------------

  static DeviceRole get role {
    final value = _storage.read<String>(_roleKey);

    return DeviceRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => DeviceRole.solo,
    );
  }

  static Future<void> setRole(DeviceRole value) async {
    await _storage.write(_roleKey, value.name);
  }

  // ---------------------------------------------------------------------------
  // OPERATION MODE
  // ---------------------------------------------------------------------------

  static OperationMode get operationMode {
    final value = _storage.read<String>(_operationModeKey);

    return OperationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => OperationMode.online,
    );
  }

  static Future<void> setOperationMode(OperationMode value) async {
    await _storage.write(_operationModeKey, value.name);
  }

  // ---------------------------------------------------------------------------
  // HOST IP
  // ---------------------------------------------------------------------------

  static String? get hostIp {
    return _storage.read<String>(_hostIpKey);
  }

  static Future<void> setHostIp(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.remove(_hostIpKey);
      return;
    }

    await _storage.write(_hostIpKey, value.trim());
  }

  // ---------------------------------------------------------------------------
  // HOST PORT
  // ---------------------------------------------------------------------------

  static int get hostPort {
    return _storage.read<int>(_hostPortKey) ?? 8080;
  }

  static Future<void> setHostPort(int value) async {
    await _storage.write(_hostPortKey, value);
  }

  // ---------------------------------------------------------------------------
  // DEVICE ID
  // ---------------------------------------------------------------------------

  static String get deviceId {
    return _storage.read<String>(_deviceIdKey) ?? '';
  }

  static Future<void> setDeviceId(String value) async {
    await _storage.write(_deviceIdKey, value);
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  static bool get isHost => role == DeviceRole.host;

  static bool get isClient => role == DeviceRole.client;

  static bool get isSolo => role == DeviceRole.solo;

  static bool get isOnline => operationMode == OperationMode.online;

  static bool get isLocal => operationMode == OperationMode.local;

  static String? get hostUrl {
    final ip = hostIp;

    if (ip == null || ip.isEmpty) {
      return null;
    }

    return 'http://$ip:$hostPort';
  }

  static String get roleName {
    switch (role) {
      case DeviceRole.host:
        return 'Main Cashier / Host';

      case DeviceRole.client:
        return 'Client Device';

      case DeviceRole.solo:
        return 'Standalone';
    }
  }

  static String get operationModeName {
    switch (operationMode) {
      case OperationMode.online:
        return 'Online';

      case OperationMode.local:
        return 'Local Hub';
    }
  }

  /// Clears only local-hub configuration.
  ///
  /// This is intentionally separate from AppState.clearAllData().
  static Future<void> clearDeviceConfig() async {
    await _storage.remove(_roleKey);
    await _storage.remove(_hostIpKey);
    await _storage.remove(_hostPortKey);
    await _storage.remove(_deviceIdKey);
    await _storage.remove(_operationModeKey);
  }
}
