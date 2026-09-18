import 'dart:convert';
import 'package:get/get.dart';
import 'database_helper.dart';
import '../../modules/home/controller/order_controller.dart';

class LocalHubOrderService {
  static final LocalHubOrderService instance = LocalHubOrderService._internal();
  LocalHubOrderService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Map<String, dynamic> _buildPreviewMap(String uuid, Map<String, dynamic> payload) {
    final List<dynamic> saleItems = payload['sale_items'] ?? payload['sales_order_sub'] ?? [];
    List<Map<String, dynamic>> salesOrderSub = [];
    
    for (var item in saleItems) {
      if (item is Map) {
        final itemMap = Map<String, dynamic>.from(item);
        salesOrderSub.add({
          'sales_ord_sub_id': itemMap['sales_ord_sub_id'] ?? itemMap['salesub_id'] ?? 0,
          'sales_ord_sub_prod_id': itemMap['sales_ord_sub_prod_id'] ?? itemMap['salesub_prd_id'] ?? 0,
          'sales_ord_sub_unit_id': itemMap['sales_ord_sub_unit_id'] ?? itemMap['salesub_unit_id'] ?? 0,
          'sales_ord_sub_qty': itemMap['sales_ord_sub_qty'] ?? itemMap['salesub_qty'] ?? 1,
          'sales_ord_sub_rate': itemMap['sales_ord_sub_rate'] ?? itemMap['salesub_rate'] ?? itemMap['rate'] ?? 0.0,
          'unit_base_qty': itemMap['unit_base_qty'] ?? itemMap['base_qty'] ?? 1.0,
          'sales_ord_sub_cgst_rate': itemMap['sales_ord_sub_cgst_rate'] ?? 0.0,
          'sales_ord_sub_sgst_rate': itemMap['sales_ord_sub_sgst_rate'] ?? 0.0,
          'cat_token_printer': itemMap['cat_token_printer'] ?? itemMap['token_printer_id'] ?? 0,
          'prd_name': itemMap['prd_name'] ?? '',
          'salesub_unit_display': itemMap['salesub_unit_display'] ?? itemMap['unit_display'] ?? '',
          'unit_display': itemMap['unit_display'] ?? itemMap['salesub_unit_display'] ?? '',
          'sales_ord_sub_flags': itemMap['sales_ord_sub_flags'] ?? ((itemMap['is_deleted'] == 1) ? 0 : 1),
          'item_desc': itemMap['item_desc'] ?? itemMap['sales_ord_sub_notes'] ?? '',
          'sales_odr_sub_is_addon': itemMap['sales_odr_sub_is_addon'] ?? itemMap['is_addon'] ?? 0,
          'sales_odr_sub_addon_parent_prd_id': itemMap['sales_odr_sub_addon_parent_prd_id'] ?? itemMap['addon_parent_prd_id'] ?? 0,
          'sales_odr_sub_addon_parent_unit_id': itemMap['sales_odr_sub_addon_parent_unit_id'] ?? itemMap['addon_parent_unit_id'] ?? 0,
          'sales_ord_sub_tax_per': itemMap['sales_ord_sub_tax_per'] ?? itemMap['salesub_tax_per'] ?? 0.0,
          'sales_ord_sub_taxcat_id': itemMap['sales_ord_sub_taxcat_id'] ?? itemMap['prd_tax_cat_id'] ?? 0,
        });
      }
    }

    int orderTypeId = payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0;
    String statusStr = payload['status'] ?? (payload['res_status'] == 0 ? 'draft' : (payload['res_status'] == 2 ? 'billed' : (payload['res_status'] == 3 ? 'paid' : 'pending')));
    int posStatus = 1;
    if (statusStr == 'draft' || payload['res_status'] == 0) posStatus = 0;
    if (statusStr == 'billed' || payload['res_status'] == 2) posStatus = 2;
    if (statusStr == 'paid' || payload['res_status'] == 3) posStatus = 3;

    final now = DateTime.now();
    String dateStr = payload['date'] ?? payload['saleqt_date'] ?? "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    String timeStr = payload['time'] ?? payload['saleqt_time'] ?? "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    return {
      'sales_odr_id': uuid,
      'sales_odr_inv_no': payload['inv_no'] ?? payload['sq_inv_no']?.toString() ?? '',
      'sales_odr_branch_inv': payload['branch_inv'] ?? '',
      'sales_odr_order_type': orderTypeId,
      'sales_odr_pos_status': posStatus,
      'sales_odr_table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? '',
      'sales_odr_table_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'] ?? '',
      'sales_odr_no_seats': payload['chair_number'] ?? payload['no_seats'] ?? (payload['res_table']?['rt_seat_count']) ?? 0,
      'sales_odr_total': _toDouble(payload['total_amount'] ?? payload['sq_total']),
      'sales_odr_tax': _toDouble(payload['total_tax'] ?? payload['sq_tax']),
      'sales_odr_date': dateStr,
      'sales_odr_time': timeStr,
      'agent_name': payload['agent_name'] ?? payload['sale_agent_name'] ?? payload['captain_name'] ?? '',
      'sales_order_sub': salesOrderSub,
      'offline': true,
      'local_uuid': uuid,
    };
  }

  Future<Map<String, dynamic>> createOrder({required Map<String, dynamic> payload}) async {
    final String uuid = (payload['uuid'] ?? '').toString().trim();
    if (uuid.isEmpty) throw Exception('Order UUID is required');

    final existingOrders = await _findOrder(uuid);
    if (existingOrders.isNotEmpty) {
      return {'success': true, 'duplicate': true, 'message': 'Order already exists', 'order': existingOrders.first};
    }

    final List<dynamic> rawItems = payload['items'] is List ? payload['items'] as List : [];
    final List<Map<String, dynamic>> items = rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).map((item) => {...item, 'order_uuid': uuid}).toList();

    final now = DateTime.now().toIso8601String();
    final Map<String, dynamic> order = {
      'uuid': uuid,
      'server_id': payload['server_id'],
      'inv_no': payload['inv_no'],
      'branch_inv': payload['branch_inv'],
      'order_type_id': payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0,
      'table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? 0,
      'customer_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'],
      'customer_phone': payload['customer_phone'] ?? payload['phone_no'],
      'total_amount': _toDouble(payload['total_amount'] ?? payload['sq_total']),
      'total_tax': _toDouble(payload['total_tax'] ?? payload['sq_tax']),
      'status': payload['status'] ?? (payload['res_status'] == 0 ? 'draft' : (payload['res_status'] == 2 ? 'billed' : (payload['res_status'] == 3 ? 'paid' : 'pending'))),
      'is_synced': 0,
      'payload': jsonEncode(payload),
      'created_at': payload['created_at'] ?? now,
    };

    await _db.saveOrderOffline(order, items);
    final int offlineSeq = await _db.assignOfflineSeqForOrder(uuid);
    
    if (Get.isRegistered<OrdersController>()) {
      final oc = Get.find<OrdersController>();
      final previewMap = _buildPreviewMap(uuid, payload);
      oc.updateExistingOrder(oc.parseOrderResponse({'preview': previewMap, 'offline': true}));
    }

    return {
      'success': true,
      'duplicate': false,
      'message': 'Order created successfully',
      'order': {...order, 'offline_seq': offlineSeq},
    };
  }

  Future<Map<String, dynamic>> updateOrder({required Map<String, dynamic> payload}) async {
    final String uuid = (payload['uuid'] ?? payload['local_uuid'] ?? '').toString().trim();
    if (uuid.isEmpty) throw Exception('Order UUID is required for update');

    final existing = await _findOrder(uuid);
    String? createdAt;
    if (existing.isNotEmpty) {
      createdAt = existing.first['created_at'];
    }

    final List<dynamic> rawItems = payload['items'] is List ? payload['items'] as List : [];
    final List<Map<String, dynamic>> items = rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).map((item) => {...item, 'order_uuid': uuid}).toList();

    final Map<String, dynamic> orderRow = {
      'uuid': uuid,
      'server_id': payload['server_id'] ?? payload['sq_inv_no']?.toString(),
      'inv_no': payload['inv_no'] ?? payload['sq_inv_no']?.toString(),
      'branch_inv': payload['branch_inv'],
      'order_type_id': payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0,
      'table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? 0,
      'customer_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'],
      'customer_phone': payload['customer_phone'] ?? payload['phone_no'],
      'total_amount': _toDouble(payload['total_amount'] ?? payload['sq_total']),
      'total_tax': _toDouble(payload['total_tax'] ?? payload['sq_tax']),
      'status': payload['status'] ?? (payload['res_status'] == 0 ? 'draft' : (payload['res_status'] == 2 ? 'billed' : (payload['res_status'] == 3 ? 'paid' : 'pending'))),
      'is_synced': 0,
      'payload': jsonEncode(payload),
      if (createdAt != null) 'created_at': createdAt,
    };

    await _db.saveOrderOffline(orderRow, items);
    
    if (Get.isRegistered<OrdersController>()) {
      final oc = Get.find<OrdersController>();
      final previewMap = _buildPreviewMap(uuid, payload);
      oc.updateExistingOrder(oc.parseOrderResponse({'preview': previewMap, 'offline': true}));
    }

    return {
      'success': true,
      'message': 'Order updated successfully on local hub',
    };
  }

  Future<Map<String, dynamic>> fetchOrders({String? status, String? date}) async {
    try {
      final db = await _db.database;
      String where = '1=1';
      List<dynamic> whereArgs = [];
      
      if (status != null) {
        where += ' AND status = ?';
        whereArgs.add(status);
      } else {
        where += ' AND status NOT IN (?, ?)';
        whereArgs.addAll(['paid', 'cancelled']);
      }
      
      if (date != null) {
        where += ' AND created_at LIKE ?';
        whereArgs.add('$date%');
      }

      final List<Map<String, dynamic>> orders = await db.query('orders', where: where, whereArgs: whereArgs, orderBy: 'created_at DESC');
      return {'success': true, 'data': orders};
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch orders: $e'};
    }
  }

  Future<Map<String, dynamic>> getOrderDetails(String id) async {
    try {
      final db = await _db.database;
      final List<Map<String, dynamic>> orders = await db.query(
        'orders',
        where: 'uuid = ? OR server_id = ?',
        whereArgs: [id, id],
        limit: 1,
      );

      if (orders.isEmpty) return {'success': false, 'message': 'Order not found'};

      final order = Map<String, dynamic>.from(orders.first);
      final List<Map<String, dynamic>> items = await _db.getOrderItemsByUuid(order['uuid']);
      order['order_items'] = items;

      return {'success': true, 'data': order};
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // --- Master Data Methods ---

  Future<Map<String, dynamic>> fetchMasterTables() async {
    try {
      final areas = await _db.getAreas();
      List<Map<String, dynamic>> dataList = [];
      for (var area in areas) {
        final tables = await _db.getTablesForArea(area['id']);
        dataList.add({
          'ra_id': area['id'],
          'ra_name': area['name'],
          'ra_is_default': area['is_default'],
          'ra_prcgrp_id': area['price_group_id'],
          'pos_tables': tables.map((t) => {
            'rt_id': t['id'],
            'rt_name': t['name'],
            'rt_seat_count': t['chair_count'],
            'processing_table': t['processing_table'] is String 
                ? jsonDecode(t['processing_table']) 
                : t['processing_table'],
          }).toList(),
        });
      }
      return {'success': true, 'data': dataList};
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch tables: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchMasterCategories() async {
    try {
      final categories = await _db.getCategories();
      return {'success': true, 'data': categories};
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch categories: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchMasterCaptains() async {
    try {
      final captains = await _db.getCaptains();
      return {'success': true, 'data': captains};
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch captains: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchMasterProducts({String? categoryId, int priceGroupId = 0}) async {
    try {
      final products = await _db.getProducts(categoryId: categoryId, priceGroupId: priceGroupId);
      return {'success': true, 'data': products};
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch products: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchMasterProductUnits(int productId, int priceGroupId) async {
    try {
      final List<Map<String, dynamic>> localBulkUnits = await _db.getBulkProductUnits(productId);
      
      if (localBulkUnits.isNotEmpty) {
        return {
          'success': true, 
          'data': localBulkUnits,
          'source': 'bulk'
        };
      }

      final units = await _db.getProductUnits(productId.toString(), priceGroupId);
      final commonAddons = await _db.getCommonAddons();

      return {
        'success': true,
        'data': units,
        'commonAddon': commonAddons,
        'source': 'standard'
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch product units: $e'};
    }
  }

  Future<List<Map<String, dynamic>>> _findOrder(String uuid) async {
    final db = await _db.database;
    return await db.query('orders', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
