import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class LocalHubClient {
  static final LocalHubClient instance = LocalHubClient._internal();

  LocalHubClient._internal();

  Future<Map<String, dynamic>> testConnection({
    required String hostIp,
    int port = 8080,
  }) async {
    final url = Uri.parse(
      'http://$hostIp:$port/hub/status',
    );

    try {
      print('LOCAL HUB CLIENT');
      print('Testing: $url');

      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 5));

      print('Status code: ${response.statusCode}');
      print('Response: ${response.body}');

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

      return data;
    } catch (e) {
      print('LOCAL HUB CLIENT ERROR: $e');
      rethrow;
    }
  }
  Future<Map<String, dynamic>> createOrder({
    required Map<String, dynamic> order,
    required String hostIp,
    int port = 8080,
  }) async {
    final url = Uri.parse(
      'http://$hostIp:$port/orders/create',
    );

    try {
      debugPrint('======================================');
      debugPrint('LOCAL HUB CLIENT: CREATE ORDER');
      debugPrint('URL: $url');
      debugPrint('UUID: ${order['uuid']}');
      debugPrint('======================================');

      final response = await http
          .post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(order),
      )
          .timeout(const Duration(seconds: 10));

      debugPrint(
        'LOCAL HUB CREATE STATUS: ${response.statusCode}',
      );

      debugPrint(
        'LOCAL HUB CREATE RESPONSE: ${response.body}',
      );

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
          data['message'] ?? 'Hub failed to create order',
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

}