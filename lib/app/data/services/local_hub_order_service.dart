import 'dart:convert';

import 'database_helper.dart';

class LocalHubOrderService {
  static final LocalHubOrderService instance =
  LocalHubOrderService._internal();

  LocalHubOrderService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<Map<String, dynamic>> createOrder({
    required Map<String, dynamic> payload,
  }) async {
    final String uuid =
    (payload['uuid'] ?? '').toString().trim();

    if (uuid.isEmpty) {
      throw Exception('Order UUID is required');
    }

    // ------------------------------------------------------------
    // IDEMPOTENCY
    // ------------------------------------------------------------
    // If the client retries the same request because of a timeout,
    // don't create the order twice.
    final existingOrders = await _findOrder(uuid);

    if (existingOrders.isNotEmpty) {
      final existing = existingOrders.first;

      return {
        'success': true,
        'duplicate': true,
        'message': 'Order already exists',
        'order': existing,
      };
    }

    // ------------------------------------------------------------
    // EXTRACT ITEMS
    // ------------------------------------------------------------

    final List<dynamic> rawItems =
    payload['items'] is List
        ? payload['items'] as List
        : [];

    final List<Map<String, dynamic>> items =
    rawItems
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
    )
        .map(
          (item) => {
        ...item,
        'order_uuid': uuid,
      },
    )
        .toList();

    // ------------------------------------------------------------
    // CREATE LOCAL ORDER RECORD
    // ------------------------------------------------------------

    final now = DateTime.now().toIso8601String();

    final Map<String, dynamic> order = {
      'uuid': uuid,

      // This is intentionally NULL/empty for now.
      // The actual server_id/inv_no can be assigned during sync.
      'server_id': payload['server_id'],

      'inv_no': payload['inv_no'],
      'branch_inv': payload['branch_inv'],

      'order_type_id':
      payload['order_type_id'] ?? 0,

      'table_id':
      payload['table_id'] ?? 0,

      'customer_name':
      payload['customer_name'],

      'customer_phone':
      payload['customer_phone'],

      'total_amount':
      _toDouble(payload['total_amount']),

      'total_tax':
      _toDouble(payload['total_tax']),

      'status':
      payload['status'] ?? 'pending',

      // Important:
      // Host order still needs to be synchronized with backend.
      'is_synced': 0,

      'payload':
      jsonEncode(payload),

      'created_at':
      payload['created_at'] ?? now,
    };

    // ------------------------------------------------------------
    // SAVE ATOMICALLY
    // ------------------------------------------------------------

    await _db.saveOrderOffline(
      order,
      items,
    );

    // ------------------------------------------------------------
    // ASSIGN HOST-SIDE LOCAL SEQUENCE
    // ------------------------------------------------------------

    final int offlineSeq =
    await _db.assignOfflineSeqForOrder(uuid);

    final savedOrders =
    await _findOrder(uuid);

    final savedOrder =
    savedOrders.isNotEmpty
        ? savedOrders.first
        : order;

    return {
      'success': true,
      'duplicate': false,
      'message': 'Order created successfully',
      'order': {
        ...savedOrder,
        'offline_seq': offlineSeq,
      },
    };
  }

  Future<List<Map<String, dynamic>>> _findOrder(
      String uuid,
      ) async {
    final db = await _db.database;

    return await db.query(
      'orders',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        0;
  }
}