import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../Device_Roles/device_roles.dart';

class LocalHubClient {
  static final LocalHubClient instance =
  LocalHubClient._internal();

  LocalHubClient._internal();

  // ---------------------------------------------------------------------------
  // BUILD URL
  // ---------------------------------------------------------------------------

  Uri _url({
    required String hostIp,
    required int port,
    required String path,
  }) {
    return Uri.parse(
      'http://$hostIp:$port$path',
    );
  }

  // ---------------------------------------------------------------------------
  // TEST CONNECTION
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> testConnection({
    required String hostIp,
    int port = 8080,
  }) async {
    final url = _url(
      hostIp: hostIp,
      port: port,
      path: '/hub/status',
    );

    try {
      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT');
      debugPrint('Testing: $url');
      debugPrint('======================================');

      final response = await http
          .get(url)
          .timeout(
        const Duration(seconds: 5),
      );

      debugPrint(
        'Status code: ${response.statusCode}',
      );

      debugPrint(
        'Response: ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(
        response.body,
      );

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid hub response',
        );
      }

      if (data['success'] != true) {
        throw Exception(
          data['message'] ??
              'Hub connection failed',
        );
      }

      return data;
    } catch (e) {
      debugPrint(
        'LOCAL HUB CLIENT ERROR: $e',
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // REGISTER DEVICE
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> registerDevice({
    required String hostIp,
    int port = 8080,
    required String deviceName,
    required String role,
    String? deviceId,
    String? userId,
    String? userName,
  }) async {
    final url = _url(
      hostIp: hostIp,
      port: port,
      path: '/device/register',
    );

    try {
      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT: REGISTER DEVICE');
      debugPrint('URL: $url');
      debugPrint('Device Name: $deviceName');
      debugPrint('Role: $role');
      debugPrint('Device ID: $deviceId');
      debugPrint('User ID: $userId');
      debugPrint('User Name: $userName');
      debugPrint('======================================');

      final response = await http
          .post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_id': deviceId,
          'device_name': deviceName,
          'role': role,
          'user_id': userId,
          'user_name': userName,
        }),
      )
          .timeout(
        const Duration(seconds: 10),
      );

      debugPrint(
        'LOCAL HUB REGISTER STATUS: '
            '${response.statusCode}',
      );

      debugPrint(
        'LOCAL HUB REGISTER RESPONSE: '
            '${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid registration response',
        );
      }

      if (data['success'] != true) {
        throw Exception(
          data['message'] ??
              'Device registration failed',
        );
      }

      final registrationData =
      data['data'] as Map<String, dynamic>?;

      if (registrationData == null) {
        throw Exception(
          'Registration data missing from Local Hub response.',
        );
      }

      final token =
          registrationData['authToken']?.toString() ?? '';

      if (token.isEmpty) {
        throw Exception(
          'Local Hub did not return authentication token.',
        );
      }

      await DeviceConfig.setAuthToken(token);

      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT REGISTERED');
      debugPrint('Device ID : $deviceId');
      debugPrint('Auth Token: SAVED');
      debugPrint('======================================');

      return data;
    } catch (e) {
      debugPrint(
        'LOCAL HUB REGISTER ERROR: $e',
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // CREATE ORDER
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createOrder({
    required Map<String, dynamic> order,
    required String hostIp,
    int port = 8080,
  }) async {
    final url = _url(
      hostIp: hostIp,
      port: port,
      path: '/orders/create',
    );

    try {
      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT: CREATE ORDER');
      debugPrint('URL: $url');
      debugPrint('UUID: ${order['uuid']}');
      debugPrint('======================================');

      final headers = _authenticatedHeaders();

      final response = await http
          .post(
        url,
        headers: headers,
        body: jsonEncode(order),
      )
          .timeout(
        const Duration(seconds: 10),
      );

      debugPrint(
        'LOCAL HUB CREATE STATUS: '
            '${response.statusCode}',
      );

      debugPrint(
        'LOCAL HUB CREATE RESPONSE: '
            '${response.body}',
      );

      if (response.statusCode == 401) {
        throw Exception(
          'Hub authentication failed. '
              'Please register this device again.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(
        response.body,
      );

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid hub response',
        );
      }

      if (data['success'] != true) {
        throw Exception(
          data['message'] ??
              'Hub failed to create order',
        );
      }

      return data;
    } catch (e) {
      debugPrint(
        'LOCAL HUB CLIENT CREATE ERROR: $e',
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // HEARTBEAT
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> heartbeat({
    required String hostIp,
    int port = 8080,
  }) async {
    final url = _url(
      hostIp: hostIp,
      port: port,
      path: '/device/heartbeat',
    );

    try {
      final response = await http
          .post(
        url,
        headers: _authenticatedHeaders(),
      )
          .timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 401) {
        throw Exception(
          'Hub authentication failed.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(
        response.body,
      );

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid heartbeat response',
        );
      }

      return data;
    } catch (e) {
      debugPrint(
        'LOCAL HUB HEARTBEAT ERROR: $e',
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // GET DEVICES
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getDevices({
    required String hostIp,
    int port = 8080,
  }) async {
    final url = _url(
      hostIp: hostIp,
      port: port,
      path: '/devices',
    );

    try {
      final response = await http
          .get(
        url,
        headers: _authenticatedHeaders(),
      )
          .timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 401) {
        throw Exception(
          'Hub authentication failed.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Hub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(
        response.body,
      );

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid devices response',
        );
      }

      return data;
    } catch (e) {
      debugPrint(
        'LOCAL HUB GET DEVICES ERROR: $e',
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // AUTH HEADERS
  // ---------------------------------------------------------------------------

  Map<String, String> _authenticatedHeaders() {
    final token = DeviceConfig.authToken;

    if (token.isEmpty) {
      throw Exception(
        'This device is not registered with the Local Hub.',
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}