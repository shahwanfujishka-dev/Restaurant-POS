import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../utils/AppState.dart';
import 'database_helper.dart';
import '../../modules/home/controller/order_controller.dart';
import '../../modules/home/controller/table_controller.dart';

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
        final bool isDeletedItem = (itemMap['is_deleted'] == 1) || (itemMap['is_deleted'] == '1');
        final num qtyNum = (itemMap['sales_ord_sub_qty'] ?? itemMap['salesub_qty'] ?? 0) as num;
        if (isDeletedItem || qtyNum <= 0) continue;
        salesOrderSub.add({
          'sales_ord_sub_id': _toInt(itemMap['sales_ord_sub_id'] ?? itemMap['salesub_id'] ?? 0),
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

    int orderTypeId = _toInt(payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0);
    int rawResStatus = _toInt(payload['res_status']);
    String statusStr = payload['status'] ?? (rawResStatus == 0 ? 'draft' : (rawResStatus == 2 ? 'billed' : (rawResStatus == 3 ? 'paid' : 'pending')));
    int posStatus = 1;
    if (statusStr == 'draft' || rawResStatus == 0) posStatus = 0;
    if (statusStr == 'billed' || rawResStatus == 2) posStatus = 2;
    if (statusStr == 'paid' || rawResStatus == 3) posStatus = 3;

    final now = DateTime.now();
    String dateStr = payload['date'] ?? payload['saleqt_date'] ?? "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    String timeStr = payload['time'] ?? payload['saleqt_time'] ?? "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    return {
      'sales_odr_id': uuid,
      'sales_odr_inv_no': payload['inv_no'] ??
          ((payload['sq_inv_no'] != null && payload['sq_inv_no'] != 0)
              ? payload['sq_inv_no'].toString()
              : ''),
      'sales_odr_branch_inv': payload['branch_inv'] ?? '',
      'created_by_device_id': payload['created_by_device_id'] ?? '',
      'sales_odr_order_type': orderTypeId,
      'sales_odr_pos_status': posStatus,
      'sales_odr_table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? '',
      'sales_odr_table_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'] ?? '',
      'sales_odr_no_seats': _toInt(payload['no_seats'] ?? payload['sales_odr_no_seats'] ?? (payload['res_table']?['rt_seat_count']) ?? 0),
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
    debugPrint('[LocalHubOrderService] createOrder called for uuid: ${payload['uuid']}');
    final String uuid = (payload['uuid'] ?? '').toString().trim();
    if (uuid.isEmpty) throw Exception('Order UUID is required');

    final existingOrders = await _findOrder(uuid);
    if (existingOrders.isNotEmpty) {
      debugPrint('[LocalHubOrderService] createOrder: order already exists for uuid: $uuid');
      return {'success': true, 'duplicate': true, 'message': 'Order already exists', 'order': _injectStatus(existingOrders.first)};
    }

    final String branchInv = await _db.generateLocalInvoiceNumber(AppState.branchDisName);
    payload = {...payload, 'branch_inv': branchInv};
    final List<dynamic> rawItems = payload['items'] is List ? payload['items'] as List : [];
    final List<Map<String, dynamic>> items = rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).map((item) => {...item, 'order_uuid': uuid}).toList();

    final now = DateTime.now().toIso8601String();
    final Map<String, dynamic> order = {
      'uuid': uuid,
      'server_id': payload['server_id'],
      'inv_no': payload['inv_no'],
      'branch_inv': payload['branch_inv'],
      'created_by_device_id': payload['created_by_device_id'],
      'order_type_id': _toInt(payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0),
      'table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? 0,
      'customer_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'],
      'customer_phone': payload['customer_phone'] ?? payload['phone_no'],
      'total_amount': _toDouble(payload['total_amount'] ?? payload['sq_total']),
      'total_tax': _toDouble(payload['total_tax'] ?? payload['sq_tax']),
      'status': payload['status'] ?? (_toInt(payload['res_status']) == 0 ? 'draft' : (_toInt(payload['res_status']) == 2 ? 'billed' : (_toInt(payload['res_status']) == 3 ? 'paid' : 'pending'))),
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

    if (Get.isRegistered<TablesController>()) {
       Get.find<TablesController>().fetchTables(silent: true);
    }

    debugPrint('[LocalHubOrderService] createOrder success for uuid: $uuid');
    return {
      'success': true,
      'duplicate': false,
      'message': 'Order created successfully',
      'order': {..._injectStatus(order), 'offline_seq': offlineSeq},
    };
  }

  Future<Map<String, dynamic>> updateOrder({required Map<String, dynamic> payload}) async {
    debugPrint('[LocalHubOrderService] updateOrder called for uuid: ${payload['uuid']}');
    final String uuid = (payload['uuid'] ?? payload['local_uuid'] ?? '').toString().trim();
    if (uuid.isEmpty) throw Exception('Order UUID is required for update');

    final existing = await _findOrder(uuid);
    String? createdAt;
    String? existingBranchInv;
    if (existing.isNotEmpty) {
      createdAt = existing.first['created_at'];
      existingBranchInv = existing.first['branch_inv']?.toString();
    }
    final String? resolvedBranchInv =
    (existingBranchInv != null && existingBranchInv.isNotEmpty)
        ? existingBranchInv
        : payload['branch_inv'];
    payload = {...payload, 'branch_inv': resolvedBranchInv};
    final List<dynamic> rawItems = payload['items'] is List ? payload['items'] as List : [];
    final List<Map<String, dynamic>> items = rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).map((item) => {...item, 'order_uuid': uuid}).toList();

    final Map<String, dynamic> orderRow = {
      'uuid': uuid,
      'server_id': payload['server_id'],
      'inv_no': payload['inv_no'] ?? payload['sq_inv_no']?.toString(),
      'branch_inv': payload['branch_inv'],
      'order_type_id': _toInt(payload['order_type_id'] ?? payload['pos_odr_type'] ?? 0),
      'table_id': payload['table_id'] ?? (payload['res_table']?['rt_id']) ?? 0,
      'customer_name': payload['customer_name'] ?? payload['cust_name'] ?? payload['table_name'],
      'customer_phone': payload['customer_phone'] ?? payload['phone_no'],
      'total_amount': _toDouble(payload['total_amount'] ?? payload['sq_total']),
      'total_tax': _toDouble(payload['total_tax'] ?? payload['sq_tax']),
      'status': payload['status'] ?? (_toInt(payload['res_status']) == 0 ? 'draft' : (_toInt(payload['res_status']) == 2 ? 'billed' : (_toInt(payload['res_status']) == 3 ? 'paid' : 'pending'))),
      'is_synced': 0,
      'payload': jsonEncode(payload),
    };
    
    if (createdAt != null) {
      orderRow['created_at'] = createdAt;
    }

    await _db.saveOrderOffline(orderRow, items);
    
    if (Get.isRegistered<OrdersController>()) {
      final oc = Get.find<OrdersController>();
      final previewMap = _buildPreviewMap(uuid, payload);
      oc.updateExistingOrder(oc.parseOrderResponse({'preview': previewMap, 'offline': true}));
    }

    if (Get.isRegistered<TablesController>()) {
       Get.find<TablesController>().fetchTables(silent: true);
    }

    debugPrint('[LocalHubOrderService] updateOrder success for uuid: $uuid');
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
      final mappedOrders = orders.map((o) => _injectStatus(o)).toList();
      return {'success': true, 'data': mappedOrders};
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

      if (orders.isEmpty) {
        return {'success': false, 'message': 'Order not found'};
      }

      final order = Map<String, dynamic>.from(orders.first);
      final List<Map<String, dynamic>> items = await _db.getOrderItemsByUuid(order['uuid']);
      order['order_items'] = items;

      return {'success': true, 'data': _injectStatus(order)};
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // --- Master Data Methods ---

  int _statusToPosStatus(String? status) {
    if (status == null) return 1;
    status = status.toLowerCase();
    if (status == 'draft') return 0;
    if (status == 'billed') return 2;
    if (status == 'paid') return 3;
    if (status == 'cancelled') return 4;
    return 1; // pending
  }

  Map<String, dynamic> _injectStatus(Map<String, dynamic> row) {
    final Map<String, dynamic> newRow = Map<String, dynamic>.from(row);
    newRow['sales_odr_pos_status'] = _statusToPosStatus(row['status']?.toString());
    return newRow;
  }

  Future<Map<String, dynamic>> fetchMasterTables() async {
    debugPrint('[LocalHubOrderService] fetchMasterTables starting...');
    try {
      // 1. Fetch all hub orders that are active to calculate dynamic occupancy
      final db = await _db.database;
      final activeOrders = await db.query(
        'orders',
        where: 'status NOT IN (?, ?, ?)',
        whereArgs: ['paid', 'cancelled', 'deleted'],
      );

      // 2. Group by table_id
      final Map<int, List<Map<String, dynamic>>> hubOccupancy = {};
      for (var order in activeOrders) {
        final tableId = _toInt(order['table_id']);
        if (tableId == 0) continue;

        int seats = 0;
        final payloadStr = order['payload'] as String?;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final payload = jsonDecode(payloadStr);
            seats = _toInt(payload['no_seats'] ?? payload['sales_odr_no_seats']);
          } catch (e) {}
        }
        
        // Fallback for seats if payload missing it
        if (seats == 0) {
            seats = _toInt(order['total_seats'] ?? 0);
        }

        if (!hubOccupancy.containsKey(tableId)) {
          hubOccupancy[tableId] = [];
        }
        
        hubOccupancy[tableId]!.add({
          'sales_odr_id': order['uuid'],
          'sq_id': order['server_id'],
          'sales_odr_inv_no': order['inv_no'],
          'sq_inv_no': _toInt(order['inv_no']),
          'sales_odr_no_seats': seats,
          'status': order['status'],
          'sales_odr_pos_status': _statusToPosStatus(order['status']?.toString()),
          'branch_inv': order['branch_inv'],
        });
      }

      final areas = await _db.getAreas();
      List<Map<String, dynamic>> dataList = [];
      for (var area in areas) {
        final tables = await _db.getTablesForArea(area['id']);
        dataList.add({
          'ra_id': area['id'],
          'ra_name': area['name'],
          'ra_is_default': area['is_default'],
          'ra_prcgrp_id': area['price_group_id'],
          'pos_tables': tables.map((t) {
            final tId = _toInt(t['id']);
            
            // Start with static processing table from server
            List<dynamic> combined = [];
            final cloudProcessing = t['processing_table'] is String 
                ? jsonDecode(t['processing_table']) 
                : (t['processing_table'] is List ? t['processing_table'] : []);
            combined.addAll(cloudProcessing);
            
            // Merge with local hub orders
            if (hubOccupancy.containsKey(tId)) {
              for (var hubOrder in hubOccupancy[tId]!) {
                final hUuid = hubOrder['sales_odr_id']?.toString();
                final hServerId = hubOrder['sq_id']?.toString();
                
                // Use findIndex or similar to update existing if found
                int existingIdx = combined.indexWhere((c) {
                  final cUuid = (c['sales_odr_id'] ?? c['local_uuid'] ?? c['uuid'])?.toString();
                  final cServerId = (c['sq_id'] ?? c['sales_odr_id'])?.toString();
                  
                  bool matchUuid = (hUuid != null && hUuid.isNotEmpty && hUuid == cUuid);
                  bool matchServerId = (hServerId != null && hServerId.isNotEmpty && hServerId == cServerId);
                  return matchUuid || matchServerId;
                });

                if (existingIdx != -1) {
                  // Update existing entry with fresh status info from Hub
                  final existing = Map<String, dynamic>.from(combined[existingIdx]);
                  existing['status'] = hubOrder['status'];
                  existing['sales_odr_pos_status'] = hubOrder['sales_odr_pos_status'];
                  combined[existingIdx] = existing;
                } else {
                  combined.add(hubOrder);
                }
              }
            }

            return {
              'rt_id': t['id'],
              'rt_name': t['name'],
              'rt_seat_count': t['chair_count'],
              'processing_table': combined,
            };
          }).toList(),
        });
      }
      debugPrint('[LocalHubOrderService] fetchMasterTables returning ${dataList.length} areas');
      return {'success': true, 'data': dataList};
    } catch (e) {
      debugPrint('[LocalHubOrderService] fetchMasterTables error: $e');
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

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}
