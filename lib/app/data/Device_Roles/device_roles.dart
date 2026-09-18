import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

enum DeviceRole {
  server,
  client,
}

enum OperationMode {
  online,
  local,
}

class DeviceConfig {
  static final GetStorage _storage = GetStorage();

  static const String _hostIpKey = 'host_ip';
  static const String _hostPortKey = 'host_port';
  static const String _deviceIdKey = 'device_id';
  static const String _operationModeKey = 'operation_mode';
  static const String _authTokenKey = 'hub_auth_token';

  // ============================================================
  // PLATFORM HELPERS
  // ============================================================

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // ============================================================
  // ROLE (Automatically determined by Platform)
  // ============================================================

  static DeviceRole get role {
    if (isDesktop) {
      return DeviceRole.server;
    }
    return DeviceRole.client;
  }

  static bool get isServer => role == DeviceRole.server;
  static bool get isClient => role == DeviceRole.client;

  // ============================================================
  // OPERATION MODE
  // ============================================================

  static OperationMode get operationMode {
    final value = _storage.read<String>(_operationModeKey);

    return OperationMode.values.firstWhere(
          (mode) => mode.name == value,
      orElse: () => OperationMode.online,
    );
  }

  static Future<void> setOperationMode(OperationMode value) async {
    await _storage.write(
      _operationModeKey,
      value.name,
    );
  }

  static bool get isOnline =>
      operationMode == OperationMode.online;

  static bool get isLocal =>
      operationMode == OperationMode.local;

  // ============================================================
  // HOST IP
  // ============================================================

  static String? get hostIp {
    return _storage.read<String>(_hostIpKey);
  }

  static Future<void> setHostIp(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.remove(_hostIpKey);
      return;
    }

    await _storage.write(
      _hostIpKey,
      value.trim(),
    );
  }

  // ============================================================
  // HOST PORT
  // ============================================================

  static int get hostPort {
    return _storage.read<int>(_hostPortKey) ?? 8080;
  }

  static Future<void> setHostPort(int value) async {
    await _storage.write(
      _hostPortKey,
      value,
    );
  }

  // ============================================================
  // DEVICE ID
  // ============================================================

  static String get deviceId {
    return _storage.read<String>(_deviceIdKey) ?? '';
  }

  static Future<void> setDeviceId(String value) async {
    await _storage.write(
      _deviceIdKey,
      value.trim(),
    );
  }

  // ============================================================
  // AUTH TOKEN
  // ============================================================

  static String get authToken {
    return _storage.read<String>(_authTokenKey) ?? '';
  }

  static bool get hasAuthToken =>
      authToken.trim().isNotEmpty;

  static Future<void> setAuthToken(String value) async {
    await _storage.write(
      _authTokenKey,
      value,
    );
  }

  static Future<void> clearAuthToken() async {
    await _storage.remove(_authTokenKey);
  }

  // ============================================================
  // HUB URL
  // ============================================================

  static String? get hostUrl {
    final ip = hostIp;

    if (ip == null || ip.trim().isEmpty) {
      return null;
    }

    return 'http://$ip:$hostPort';
  }

  // ============================================================
  // DISPLAY
  // ============================================================

  static String get roleName {
    switch (role) {
      case DeviceRole.server:
        return 'Main Cashier / Host';

      case DeviceRole.client:
        return 'Client Device';
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

  // ============================================================
  // CLEAR
  // ============================================================

  static Future<void> clearDeviceConfig() async {
    await _storage.remove(_hostIpKey);
    await _storage.remove(_hostPortKey);
    await _storage.remove(_deviceIdKey);
    await _storage.remove(_operationModeKey);
    await _storage.remove(_authTokenKey);
  }
}
