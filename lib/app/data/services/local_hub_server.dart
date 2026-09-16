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

  /// Actual LAN IP of this device.
  static String? lanIp;

  /// Server port.
  static const int defaultPort = 8080;

  int get port => _server?.port ?? defaultPort;

  bool get isRunning => _server != null;

  /// Returns the actual LAN IP.
  String? get hostAddress => lanIp;
  final Map<String, String> _deviceTokens = {};

  bool _isAuthorized(Request request) {
    final authorization =
    request.headers['authorization'];

    if (authorization == null ||
        !authorization.startsWith('Bearer ')) {
      return false;
    }

    final token =
    authorization.substring(7).trim();

    if (token.isEmpty) {
      return false;
    }

    return _deviceTokens.containsValue(token);
  }

  /// Returns:
  /// http://192.168.x.x:8080
  String? get serverUrl {
    final ip = lanIp;

    if (ip == null || ip.isEmpty) {
      return null;
    }

    return 'http://$ip:$port';
  }

  String _generateAuthToken() {
    final random = Random.secure();

    final bytes = List<int>.generate(
      32,
          (_) => random.nextInt(256),
    );

    return base64UrlEncode(bytes);
  }

  Future<void> start() async {
    if (_server != null) {
      debugPrint('LOCAL HUB: Server already running');
      return;
    }

    if (kIsWeb) {
      debugPrint('LOCAL HUB: Web platform is not supported');
      return;
    }

    try {
      // ------------------------------------------------------------
      // ROUTER
      // ------------------------------------------------------------

      final router = Router();

      // ------------------------------------------------------------
      // HUB STATUS
      // ------------------------------------------------------------

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

      // ------------------------------------------------------------
      // HEALTH CHECK
      // ------------------------------------------------------------

      router.get('/health', (Request request) {
        return _jsonResponse({
          'success': true,
          'status': 'ok',
        });
      });

      // ------------------------------------------------------------
      // DEVICE REGISTRATION
      // ------------------------------------------------------------



      router.post('/device/register', (Request request) async {
        try {
          final body = await _readJson(request);

          debugPrint('======================================');
          debugPrint('LOCAL HUB: DEVICE REGISTRATION REQUEST');
          debugPrint(
            const JsonEncoder.withIndent('  ').convert(body),
          );
          debugPrint('======================================');

          final deviceId =
              body['deviceId']?.toString().trim() ?? '';

          final deviceName =
              body['deviceName']?.toString().trim() ?? '';

          final role =
              body['role']?.toString().trim() ?? '';

          final userId =
          body['userId']?.toString();

          final userName =
          body['userName']?.toString();

          // ------------------------------------------------------------
          // VALIDATION
          // ------------------------------------------------------------

          if (deviceId.isEmpty) {
            return _errorResponse(
              'Device ID is required',
              statusCode: 400,
            );
          }

          if (role.isEmpty) {
            return _errorResponse(
              'Device role is required',
              statusCode: 400,
            );
          }

          // Only CLIENT devices should register with the Local Hub.
          if (role != 'client') {
            return _errorResponse(
              'Only client devices can register with the Local Hub.',
              statusCode: 400,
            );
          }

          // ------------------------------------------------------------
          // GENERATE AUTH TOKEN
          // ------------------------------------------------------------

          final authToken = _generateAuthToken();

          // ------------------------------------------------------------
          // SAVE TOKEN
          // ------------------------------------------------------------

          _deviceTokens[deviceId] = authToken;

          debugPrint('======================================');
          debugPrint('LOCAL HUB: DEVICE REGISTERED');
          debugPrint('Device ID   : $deviceId');
          debugPrint('Device Name : $deviceName');
          debugPrint('Role        : $role');
          debugPrint('User ID     : $userId');
          debugPrint('User Name   : $userName');
          debugPrint('Token       : SAVED');
          debugPrint(
            'Registered Devices : ${_deviceTokens.length}',
          );
          debugPrint('======================================');

          // ------------------------------------------------------------
          // RESPONSE
          // ------------------------------------------------------------

          return _jsonResponse({
            'success': true,
            'message': 'Device registered successfully',
            'data': {
              'deviceId': deviceId,
              'deviceName': deviceName,
              'role': role,
              'userId': userId,
              'userName': userName,
              'authToken': authToken,
              'hostIp': lanIp,
              'port': port,
              'hubUrl': serverUrl,
            },
          });
        } catch (e, stackTrace) {
          debugPrint(
            'LOCAL HUB: Device registration error: $e',
          );

          debugPrint(
            stackTrace.toString(),
          );

          return _errorResponse(
            'Invalid device registration request',
            statusCode: 400,
          );
        }
      });

      // ------------------------------------------------------------
      // CREATE ORDER
      // ------------------------------------------------------------

      router.post('/orders/create', (Request request) async {
        // ------------------------------------------------------------
        // AUTHENTICATION
        // ------------------------------------------------------------

        if (!_isAuthorized(request)) {
          debugPrint(
            'LOCAL HUB: Unauthorized order request',
          );

          return _errorResponse(
            'Unauthorized device',
            statusCode: 401,
          );
        }

        try {
          final body = await _readJson(request);

          debugPrint('======================================');
          debugPrint('LOCAL HUB: CREATE ORDER');
          debugPrint(
            const JsonEncoder.withIndent('  ').convert(body),
          );
          debugPrint('======================================');

          final result =
          await LocalHubOrderService.instance.createOrder(
            payload: body,
          );

          return _jsonResponse(result);
        } catch (e, stackTrace) {
          debugPrint(
            'LOCAL HUB: Create order error: $e',
          );

          debugPrint(
            stackTrace.toString(),
          );

          return _errorResponse(
            'Failed to create order: $e',
            statusCode: 500,
          );
        }
      });
      // ------------------------------------------------------------
      // UPDATE ORDER
      // ------------------------------------------------------------

      router.post('/orders/update', (Request request) async {
        try {
          final body = await _readJson(request);

          debugPrint(
            'LOCAL HUB: Update order request',
          );

          debugPrint(
            const JsonEncoder.withIndent('  ').convert(body),
          );

          return _jsonResponse({
            'success': true,
            'message': 'Order update received by local hub',
          });
        } catch (e) {
          debugPrint(
            'LOCAL HUB: Update order error: $e',
          );

          return _errorResponse(
            'Invalid order update request',
            statusCode: 400,
          );
        }
      });

      // ------------------------------------------------------------
      // KOT
      // ------------------------------------------------------------

      router.post('/kot/create', (Request request) async {
        try {
          final body = await _readJson(request);

          debugPrint(
            'LOCAL HUB: KOT request',
          );

          debugPrint(
            const JsonEncoder.withIndent('  ').convert(body),
          );

          return _jsonResponse({
            'success': true,
            'message': 'KOT received by local hub',
          });
        } catch (e) {
          debugPrint(
            'LOCAL HUB: KOT error: $e',
          );

          return _errorResponse(
            'Invalid KOT request',
            statusCode: 400,
          );
        }
      });

      // ------------------------------------------------------------
      // MIDDLEWARE
      // ------------------------------------------------------------

      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addHandler(router.call);

      // ------------------------------------------------------------
      // START SERVER
      // ------------------------------------------------------------

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        defaultPort,
        shared: true,
      );

      // ------------------------------------------------------------
      // GET ACTUAL LAN IP
      // ------------------------------------------------------------

      lanIp = await LocalHubNetwork.getLocalIp();

      // ------------------------------------------------------------
      // LOG
      // ------------------------------------------------------------

      debugPrint('======================================');
      debugPrint('LOCAL HUB SERVER STARTED');
      debugPrint('Listen Address : ${_server!.address.address}');
      debugPrint('Port           : ${_server!.port}');
      debugPrint('LAN IP         : $lanIp');
      debugPrint('Hub URL        : $serverUrl');
      debugPrint('======================================');
    } catch (e) {
      debugPrint(
        'LOCAL HUB: Failed to start server: $e',
      );
      _server = null;
      lanIp = null;

      rethrow;
    }
  }

  // ------------------------------------------------------------
  // STOP SERVER
  // ------------------------------------------------------------

  Future<void> stop() async {
    final server = _server;

    if (server == null) {
      return;
    }

    try {
      await server.close(force: true);
    } finally {
      _server = null;
      lanIp = null;
    }

    debugPrint('======================================');
    debugPrint('LOCAL HUB SERVER STOPPED');
    debugPrint('======================================');
  }

  // ------------------------------------------------------------
  // READ JSON
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> _readJson(
      Request request,
      ) async {
    final body = await request.readAsString();

    if (body.trim().isEmpty) {
      return {};
    }

    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw const FormatException(
      'Request body must be a JSON object',
    );
  }

  // ------------------------------------------------------------
  // JSON RESPONSE
  // ------------------------------------------------------------

  Response _jsonResponse(
      Map<String, dynamic> data, {
        int statusCode = 200,
      }) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
      },
    );
  }

  // ------------------------------------------------------------
  // ERROR RESPONSE
  // ------------------------------------------------------------

  Response _errorResponse(
      String message, {
        int statusCode = 500,
      }) {
    return _jsonResponse(
      {
        'success': false,
        'message': message,
      },
      statusCode: statusCode,
    );
  }
}