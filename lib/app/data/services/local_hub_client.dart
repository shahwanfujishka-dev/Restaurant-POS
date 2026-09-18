import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../Device_Roles/device_roles.dart';

class LocalHubClient {
  static final LocalHubClient instance = LocalHubClient._internal();
  LocalHubClient._internal();

  Uri _url({required String hostIp, required int port, required String path, Map<String, String>? queryParameters}) {
    return Uri.http('$hostIp:$port', path, queryParameters);
  }

  Future<Map<String, dynamic>> testConnection({required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/hub/status');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw Exception('Hub returned HTTP ${response.statusCode}');
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['success'] != true) throw Exception(data['message'] ?? 'Hub connection failed');
      return data;
    } catch (e) {
      debugPrint('LOCAL HUB CLIENT ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> registerDevice({
    required String hostIp,
    int port = 8080,
    required String deviceName,
    required String role,
    String? deviceId,
    String? userId,
    String? userName,
  }) async {
    final url = Uri.parse('http://$hostIp:$port/device/register');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': deviceId,
          'device_name': deviceName,
          'role': role,
          'user_id': userId,
          'user_name': userName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) throw Exception('Hub returned HTTP ${response.statusCode}');
      final data = jsonDecode(response.body);
      final registrationData = data['data'] as Map<String, dynamic>?;
      if (registrationData == null) throw Exception('Registration data missing');
      final token = registrationData['authToken']?.toString() ?? '';
      if (token.isEmpty) throw Exception('No auth token returned');

      await DeviceConfig.setAuthToken(token);
      return data;
    } catch (e) {
      debugPrint('LOCAL HUB REGISTER ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createOrder({required Map<String, dynamic> order, required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/orders/create');
    try {
      final response = await http.post(
        url,
        headers: _authenticatedHeaders(),
        body: jsonEncode(order),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) throw Exception('Hub authentication failed.');
      if (response.statusCode != 200) throw Exception('Hub returned HTTP ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB CREATE ORDER ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateOrder({required Map<String, dynamic> order, required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/orders/update');
    try {
      final response = await http.post(
        url,
        headers: _authenticatedHeaders(),
        body: jsonEncode(order),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) throw Exception('Hub authentication failed.');
      if (response.statusCode != 200) throw Exception('Hub returned HTTP ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB UPDATE ORDER ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchActiveOrders({required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/orders/list');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH ACTIVE ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchSoldOrders({required String hostIp, int port = 8080, required String date}) async {
    final url = Uri.parse('http://$hostIp:$port/orders/sold?date=$date');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH SOLD ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchOrderDetails({required String hostIp, int port = 8080, required String orderId}) async {
    final url = Uri.parse('http://$hostIp:$port/orders/details?id=$orderId');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH DETAILS ERROR: $e');
      rethrow;
    }
  }

  // Master Data Methods

  Future<Map<String, dynamic>> fetchMasterTables({required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/master/tables');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH MASTER TABLES ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchMasterCategories({required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/master/categories');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH MASTER CATEGORIES ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchMasterCaptains({required String hostIp, int port = 8080}) async {
    final url = Uri.parse('http://$hostIp:$port/master/captains');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH MASTER CAPTAINS ERROR: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchMasterProducts({
    required String hostIp,
    int port = 8080,
    String? categoryId,
    int priceGroupId = 0,
  }) async {
    final query = categoryId != null ? 'category_id=$categoryId&price_group_id=$priceGroupId' : 'price_group_id=$priceGroupId';
    final url = Uri.parse('http://$hostIp:$port/master/products?$query');
    try {
      final response = await http.get(url, headers: _authenticatedHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Hub returned ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('LOCAL HUB FETCH MASTER PRODUCTS ERROR: $e');
      rethrow;
    }
  }

  Map<String, String> _authenticatedHeaders() {
    final token = DeviceConfig.authToken;
    if (token.isEmpty) throw Exception('Device not registered');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}
