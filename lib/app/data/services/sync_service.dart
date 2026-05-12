import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_disposable.dart';

import '../utils/AppState.dart';
import 'api_services.dart';
import 'database_helper.dart';

class SyncService extends GetxService {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final isSyncing = false.obs;
  final isMasterSyncing = false.obs;
  final masterSyncProgress = 0.0.obs;

  Timer? _syncTimer;

  @override
  void onInit() {
    super.onInit();
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    // Check every 5 minutes if background sync is enabled
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (AppState.isBackgroundSyncEnabled) {
        syncPendingOrders();
      }
    });
  }

  /// Entry point to trigger a sync of all pending orders and payments
  Future<void> syncPendingOrders() async {
    if (isSyncing.value) return;
    isSyncing.value = true;

    try {
      // 1. Sync Orders first
      final unsyncedOrders = await _dbHelper.getUnsyncedOrders();
      if (unsyncedOrders.isNotEmpty) {
        log("SyncService: Found ${unsyncedOrders.length} unsynced orders.");
        for (var order in unsyncedOrders) {
          await _syncOrder(order);
        }
      }

      // 2. Sync Payments
      final unsyncedPayments = await _dbHelper.getUnsyncedPayments();
      if (unsyncedPayments.isNotEmpty) {
        log("SyncService: Found ${unsyncedPayments.length} unsynced payments.");
        for (var payment in unsyncedPayments) {
          await _syncPayment(payment);
        }
      }

    } catch (e) {
      log("SyncService Error: $e");
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> syncMasterData() async {
    if (isMasterSyncing.value) return;
    isMasterSyncing.value = true;
    masterSyncProgress.value = 0.0;

    try {
      log("SyncService: Starting manual master data sync...");
      final int userId = int.tryParse(AppState.userId) ?? 0;

      // 1. Start slow background calls
      log("SyncService: Initiating background fetch for units, addons and rates...");
      final addonFuture = _apiService.post("mobileapp/product_unit/get_prd_unit_and_addon", data: {
        "usr_id": userId,
        "part_no": 0,
        "limit": 20000,
        "sync_time": "",
      });

      final unitsFuture = _apiService.post("mobileapp/unit/download", data: {
        "part_no": 0,
        "limit": "",
        "sync_time": "",
      });

      final stockRatesFuture = _apiService.post("mobileapp/stock_unit_rates/download", data: {
        "part_no": 0,
        "limit": "",
        "sync_time": "",
      });

      // 2. Parallelize metadata calls
      final apiResults = await Future.wait([
        _apiService.post("mobileapp/category/download", data: {
          "part_no": 0,
          "limit": 1000,
          "sync_time": "",
        }),
        _apiService.post('mobileapp/pos/get_pos_table', data: {
          "usr_id": userId,
        }),
        _apiService.post("mobileapp/pos/list_favorite", data: {
          "usr_id": userId,
        }),
        _apiService.post("mobileapp/sales_settings/vat_type", data: {
          "part_no": 0,
          "limit": 500,
          "sync_time": "",
        }),
      ]);

      masterSyncProgress.value = 0.1;

      final categoryResponse = apiResults[0];
      final tablesResponse   = apiResults[1];
      final favoritesResponse = apiResults[2];
      final vatResponse       = apiResults[3];

      // Save VAT type
      if (vatResponse.statusCode == 200) {
        final data = vatResponse.data['data'];
        if (data != null && data['vat_type'] != null) {
          await _dbHelper.saveSetting('vat_type', data['vat_type'].toString());
        }
      }

      // 3. Process Categories
      final List<Map<String, dynamic>> categoriesList = [];
      if (categoryResponse.statusCode == 200) {
        final List<dynamic> data = categoryResponse.data['data'] ?? [];
        for (int i = 0; i < data.length; i++) {
          final json = data[i];
          categoriesList.add({
            'id':               (json['cat_id']            ?? '').toString().trim(),
            'name':             (json['cat_name']          ?? '').toString(),
            'cat_pos':          (json['cat_pos']           ?? '').toString(),
            'token_printer_id': (json['cat_token_printer'] as num? ?? 0).toInt(),
            'sort_order':       i,
          });
        }
      }

      // 4. Process Tables & Areas
      Set<int> priceGroupIds = {0};
      List<dynamic> areasData = [];
      if (tablesResponse.statusCode == 200) {
        areasData = tablesResponse.data['data'] ?? [];
        for (var area in areasData) {
          final int pgId = (area['ra_prcgrp_id'] as num? ?? 0).toInt();
          priceGroupIds.add(pgId);
        }
      }

      // 5. Process Favorites
      final List<Map<String, dynamic>> favoritesData = [];
      if (favoritesResponse.statusCode == 200) {
        final List<dynamic> favData = favoritesResponse.data['data'] ?? [];
        for (var json in favData) {
          favoritesData.add({
            'id': json['fav_id'],
            'name': json['fav_name'],
            'image': json['fav_img_url'] ?? '',
          });
        }
      }

      // Store basic master data
      await Future.wait([
        _dbHelper.insertCategories(categoriesList),
        _dbHelper.insertAreas(areasData.cast<Map<String, dynamic>>()),
        _dbHelper.insertFavorites(favoritesData),
      ]);

      masterSyncProgress.value = 0.2;

      // 6. Process Units (New)
      try {
        final unitsResponse = await unitsFuture;
        if (unitsResponse.statusCode == 200) {
          final List<dynamic> unitsData = unitsResponse.data['data'] ?? [];
          if (unitsData.isNotEmpty) {
            await _dbHelper.insertUnits(unitsData);
            log("SyncService: Successfully cached units.");
          }
        }
      } catch (e) {
        log("SyncService Error fetching units: $e");
      }

      final posCategories = categoriesList.where((c) => c['cat_pos'] == "1").toList();

      // 7. Sync Products
      await _syncProductsInParallel(priceGroupIds, posCategories);

      // 8. Process Stock Unit Rates (New)
      try {
        final stockRatesResponse = await stockRatesFuture;
        if (stockRatesResponse.statusCode == 200) {
          final List<dynamic> ratesData = stockRatesResponse.data['data'] ?? [];
          if (ratesData.isNotEmpty) {
            await _dbHelper.clearStockUnitRates();
            await _dbHelper.insertStockUnitRates(ratesData);
            log("SyncService: Successfully cached stock unit rates.");
          }
        }
      } catch (e) {
        log("SyncService Error fetching stock rates: $e");
      }

      // 9. Process Addons
      log("SyncService: Finalizing background addon data...");
      masterSyncProgress.value = 0.9;

      try {
        final bulkUnitsResponse = await addonFuture;
        if (bulkUnitsResponse.statusCode == 200) {
          final List<dynamic> bulkData = bulkUnitsResponse.data['data'] ?? [];
          log("SyncService: Processing ${bulkData.length} bulk units/addons...");

          if (bulkData.isNotEmpty) {
            await _dbHelper.clearBulkProductUnits();
            await _dbHelper.insertBulkProductUnits(bulkData);
            log("SyncService: Successfully cached bulk records.");
          }
        }
      } catch (e) {
        log("SyncService Error fetching addons: $e");
      }

      log("SyncService: Master data sync complete.");
    } catch (e) {
      log("SyncService Master Sync Error: $e");
      rethrow;
    } finally {
      isMasterSyncing.value = false;
      masterSyncProgress.value = 1.0;
    }
  }

  Future<void> _syncProductsInParallel(Set<int> priceGroupIds, List<Map<String, dynamic>> posCategories) async {
    final pgList = priceGroupIds.toList();
    int totalToSync = pgList.length * (1 + posCategories.length);
    int syncedSoFar = 0;

    const pgChunkSize = 2;
    for (int i = 0; i < pgList.length; i += pgChunkSize) {
      final pgChunk = pgList.sublist(i, (i + pgChunkSize > pgList.length) ? pgList.length : i + pgChunkSize);

      await Future.wait(pgChunk.map((pgId) async {
        await _fetchAndInsertProducts(pgId: pgId);
        syncedSoFar++;
        _updateMasterProgress(syncedSoFar, totalToSync);

        const catChunkSize = 5;
        for (int j = 0; j < posCategories.length; j += catChunkSize) {
          final catChunk = posCategories.sublist(j, (j + catChunkSize > posCategories.length) ? posCategories.length : j + catChunkSize);
          await Future.wait(catChunk.map((cat) async {
            final catId = cat['id'] as String;
            await _fetchAndInsertProducts(pgId: pgId, catId: catId, forceCatId: catId);
            syncedSoFar++;
            _updateMasterProgress(syncedSoFar, totalToSync);
          }));
        }
      }));
    }
  }

  void _updateMasterProgress(int current, int total) {
    if (total > 0) {
      masterSyncProgress.value = 0.2 + (0.6 * current / total);
    }
  }

  Future<void> _fetchAndInsertProducts({
    required int pgId,
    String? catId,
    String? forceCatId,
  }) async {
    final requestData = <String, dynamic>{
      "usr_id":         int.tryParse(AppState.userId) ?? 0,
      "price_group_id": pgId,
      "keyword":        "",
    };
    if (catId != null) requestData["category_id"] = int.tryParse(catId) ?? 0;

    try {
      final res = await _apiService.post(
        "mobileapp/pos/get_product_list",
        data: requestData,
      );
      if (res.statusCode != 200) return;

      final List<dynamic> rawData = res.data['data'] ?? [];
      if (rawData.isEmpty) return;

      final String baseUrl = res.data['url']?.toString() ?? "";

      final List<Map<String, dynamic>> products = [];
      for (int i = 0; i < rawData.length; i++) {
        final json = rawData[i];
        final String prdId = (json['prd_id'] ?? '').toString();

        String imgUrl = json['prd_img_url']?.toString() ?? '';
        if (imgUrl.isNotEmpty && baseUrl.isNotEmpty && !imgUrl.startsWith('http')) {
          imgUrl = baseUrl + imgUrl;
        }

        products.add({
          'id':             prdId,
          'price_group_id': pgId,
          'name':           (json['prd_name']        ?? '').toString(),
          'category_id':    forceCatId ?? (json['prd_cat_id'] ?? '').toString().trim(),
          'price':          (json['sale_rate']        as num? ?? 0.0).toDouble(),
          'prd_tax':        (json['prd_tax']          as num? ?? 0.0).toDouble(),
          'image':          imgUrl,
          'unit_display':   (json['unit_display']     ?? '').toString(),
          'tax_cat_id':     (json['prd_tax_cat_id']   as num? ?? 0).toInt(),
          'tax_per':        (json['tax_per']           as num? ?? 0.0).toDouble(),
          'sort_order':     i,
        });
      }

      await _dbHelper.insertProducts(products);
    } catch (e) {
      log("SyncService: Failed to fetch products: $e");
    }
  }

  Future<void> _syncOrder(Map<String, dynamic> order) async {
    final String uuid = order['uuid'];
    final String? payloadStr = order['payload'];

    if (payloadStr == null || payloadStr.isEmpty) {
      log("SyncService: Skipping $uuid — no payload");
      return;
    }

    try {
      final Map<String, dynamic> payload = jsonDecode(payloadStr);
      final bool isEdit = payload['is_pos_edit'] == true;

      // ── Validate edit payloads before sending ──────────────────────────
      if (isEdit) {
        final int sqInvNo = (payload['sq_inv_no'] as num? ?? 0).toInt();
        final List processingTable =
            (payload['res_table']?['processing_table'] as List?) ?? [];

        if (sqInvNo == 0 || processingTable.isEmpty) {
          log("SyncService: ⚠️ Skipping edit $uuid — "
              "sq_inv_no=$sqInvNo, processingTable=${processingTable.length}. "
              "Cannot update without server identity.");
          // Mark as synced so it stops retrying a permanently broken payload
          await _dbHelper.updateOrderStatusByUuid(uuid, order['status'], isSynced: 1);
          return;
        }
      }

      final String endpoint = isEdit
          ? "mobileapp/pos/update_sales_order"
          : "mobileapp/pos/add_sales_order";

      log("SyncService: Syncing $uuid via $endpoint "
          "(isEdit: $isEdit, sq_inv_no: ${payload['sq_inv_no']})");
      log("SyncService: Payload preview → "
          "items: ${(payload['sale_items'] as List?)?.length}, "
          "total: ${payload['sq_total']}, "
          "table: ${payload['res_table']?['rt_id']}");

      final response = await _apiService.post(endpoint, data: payload);

      if (response.statusCode == 200) {
        dynamic data = response.data;
        if (data is String) data = jsonDecode(data);

        // Check for application-level errors (status:0 in message)
        if (data is Map && data['message'] is Map) {
          final msg = data['message'] as Map;
          if (msg['status'] == 0) {
            log("SyncService: ❌ Server rejected $uuid: ${msg['msg']}");
            return; // Leave is_synced=0 to retry later
          }
        }

        if (data is Map && (data['status'] == 200 || data['id'] != null)) {
          final String serverId = data['id']?.toString() ?? "";
          final String? invNo = data['preview']?['sales_odr_inv_no']?.toString();

          await _dbHelper.updateOrderStatusByUuid(
            uuid,
            order['status'],
            isSynced: 1,
            serverId: serverId.isNotEmpty ? serverId : null,
            invNo: invNo,
          );
          log("SyncService: ✅ Synced $uuid → serverId: $serverId, invNo: $invNo");
        }
      }
    } catch (e) {
      log("SyncService: Failed to sync order $uuid: $e");
    }
  }

  Future<void> _syncPayment(Map<String, dynamic> payment) async {
    final String orderUuid = payment['order_uuid'];
    final int localPaymentId = payment['id'];

    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> orders = await db.query('orders', where: 'uuid = ? OR server_id = ?', whereArgs: [orderUuid, orderUuid]);

      if (orders.isEmpty) return;

      final order = orders.first;
      final String? serverId = order['server_id'];
      final String? invNo = order['inv_no'] ?? order['uuid'];

      if (serverId == null || serverId.isEmpty) return;

      final body = {
        "usr_id": _payloadUserId(order),
        "sales_odr_id": int.tryParse(serverId),
        "sales_odr_inv_no": int.tryParse(invNo ?? "0"),
        "payment_method": payment['method'],
        "amount_paid": payment['amount'],
        "received_amount": payment['amount'],
        "change_given": 0,
        "settle_date": payment['created_at'].split('T')[0],
      };

      final response = await _apiService.post("mobileapp/pos/settle_sales_order", data: body);

      if (response.statusCode == 200) {
        await _dbHelper.updatePaymentSyncStatus(localPaymentId, 1);
        log("SyncService: Successfully synced payment for order $serverId");
      }
    } catch (e) {
      log("SyncService: Failed to sync payment for $orderUuid: $e");
    }
  }

  int _payloadUserId(Map<String, dynamic> order) {
    try {
      if (order['payload'] != null) {
        final p = jsonDecode(order['payload']);
        return p['usr_id'] ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  @override
  void onClose() {
    _syncTimer?.cancel();
    super.onClose();
  }
}
