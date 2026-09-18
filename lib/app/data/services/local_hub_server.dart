import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'local_hub_network.dart';
import 'local_hub_order_service.dart';

class LocalHubServer {
  static final LocalHubServer instance = LocalHubServer._internal();

  LocalHubServer._internal();

  HttpServer? _server;
  static String? lanIp;
  static const int defaultPort = 8080;

  int get port => _server?.port ?? defaultPort;
  bool get isRunning => _server != null;
  String? get hostAddress => lanIp;
  final Map<String, String> _deviceTokens = {};

  bool _isAuthorized(Request request) {
    final authorization = request.headers['authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) return false;
    final token = authorization.substring(7).trim();
    return token.isNotEmpty && _deviceTokens.containsValue(token);
  }

  String? get serverUrl => lanIp != null ? 'http://$lanIp:$port' : null;

  String _generateAuthToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> start() async {
    if (_server != null) return;
    if (kIsWeb) return;

    try {
      final router = Router();

      router.get('/hub/status', (Request request) {
        return _jsonResponse({
          'success': true,
          'service': 'Fujishka TablePro Local Hub',
          'status': 'online',
          'role': 'host',
          'hostIp': lanIp,
          'port': port,
          'hubUrl': serverUrl,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });

      router.get('/health', (Request request) => _jsonResponse({'success': true, 'status': 'ok'}));

      router.post('/device/register', (Request request) async {
        try {
          final body = await _readJson(request);
          final deviceId = body['deviceId']?.toString().trim() ?? '';
          final role = body['role']?.toString().trim() ?? '';

          if (deviceId.isEmpty || role.isEmpty) return _errorResponse('Device ID and role required', statusCode: 400);
          if (role != 'client') return _errorResponse('Only clients can register', statusCode: 400);

          final authToken = _generateAuthToken();
          _deviceTokens[deviceId] = authToken;

          return _jsonResponse({
            'success': true,
            'message': 'Device registered successfully',
            'data': {
              'deviceId': deviceId,
              'authToken': authToken,
              'hostIp': lanIp,
              'port': port,
            },
          });
        } catch (e) {
          return _errorResponse('Invalid registration request', statusCode: 400);
        }
      });

      // ------------------------------------------------------------
      // ORDERS API
      // ------------------------------------------------------------

      router.post('/orders/create', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final body = await _readJson(request);
          final result = await LocalHubOrderService.instance.createOrder(payload: body);
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to create order: $e', statusCode: 500);
        }
      });

      router.post('/orders/update', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final body = await _readJson(request);
          final result = await LocalHubOrderService.instance.updateOrder(payload: body);
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to update order: $e', statusCode: 500);
        }
      });

      router.get('/orders/list', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final result = await LocalHubOrderService.instance.fetchOrders();
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch orders: $e', statusCode: 500);
        }
      });

      router.get('/orders/sold', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final date = request.url.queryParameters['date'];
          final result = await LocalHubOrderService.instance.fetchOrders(status: 'paid', date: date);
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch sold orders: $e', statusCode: 500);
        }
      });

      router.get('/orders/details', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final id = request.url.queryParameters['id'];
          if (id == null) return _errorResponse('Order ID required', statusCode: 400);
          final result = await LocalHubOrderService.instance.getOrderDetails(id);
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to get order details: $e', statusCode: 500);
        }
      });

      // ------------------------------------------------------------
      // MASTER DATA API
      // ------------------------------------------------------------

      router.get('/master/tables', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final result = await LocalHubOrderService.instance.fetchMasterTables();
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch master tables: $e', statusCode: 500);
        }
      });

      router.get('/master/categories', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final result = await LocalHubOrderService.instance.fetchMasterCategories();
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch master categories: $e', statusCode: 500);
        }
      });

      router.get('/master/captains', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final result = await LocalHubOrderService.instance.fetchMasterCaptains();
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch master captains: $e', statusCode: 500);
        }
      });

      router.get('/master/products', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final categoryId = request.url.queryParameters['category_id'];
          final priceGroupId = int.tryParse(request.url.queryParameters['price_group_id'] ?? '0') ?? 0;
          final result = await LocalHubOrderService.instance.fetchMasterProducts(
            categoryId: categoryId,
            priceGroupId: priceGroupId,
          );
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch master products: $e', statusCode: 500);
        }
      });

      router.get('/master/product-units', (Request request) async {
        if (!_isAuthorized(request)) return _errorResponse('Unauthorized', statusCode: 401);
        try {
          final productIdStr = request.url.queryParameters['product_id'];
          final priceGroupId = int.tryParse(request.url.queryParameters['price_group_id'] ?? '0') ?? 0;
          if (productIdStr == null) return _errorResponse('Product ID required', statusCode: 400);
          final productId = int.tryParse(productIdStr) ?? 0;
          final result = await LocalHubOrderService.instance.fetchMasterProductUnits(productId, priceGroupId);
          return _jsonResponse(result);
        } catch (e) {
          return _errorResponse('Failed to fetch master product units: $e', statusCode: 500);
        }
      });

      router.post('/kot/create', (Request request) async {
        return _jsonResponse({'success': true, 'message': 'KOT received'});
      });

      final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, defaultPort, shared: true);
      lanIp = await LocalHubNetwork.getLocalIp();

      debugPrint('LOCAL HUB SERVER STARTED ON $serverUrl');
    } catch (e) {
      _server = null;
      lanIp = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    try {
      await server.close(force: true);
    } finally {
      _server = null;
      lanIp = null;
    }
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Response _jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(statusCode, body: jsonEncode(data), headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'});
  }

  Response _errorResponse(String message, {int statusCode = 500}) {
    return _jsonResponse({'success': false, 'message': message}, statusCode: statusCode);
  }
}
