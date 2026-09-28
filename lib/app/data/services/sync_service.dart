import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_disposable.dart';
import 'package:get_storage/get_storage.dart';

import '../../modules/cart/controller/cart_controller.dart';
import '../../modules/home/controller/order_controller.dart';
import '../Device_Roles/device_roles.dart';
import '../utils/AppState.dart';
import 'api_services.dart';
import 'database_helper.dart';
import 'local_hub_client.dart';

class SyncService extends GetxService with WidgetsBindingObserver {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final isSyncing = false.obs;
  final isMasterSyncing = false.obs;
  final masterSyncProgress = 0.0.obs;
  final isHubSyncing = false.obs;
  Timer? _syncTimer;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicSync();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AppState.isBackgroundSyncEnabled) {
        log("SyncService: App resumed, triggering sync...");
        syncPendingOrders();
      }
      syncPendingHubOrders();
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (AppState.isBackgroundSyncEnabled) {
        syncPendingOrders();
      }
      syncPendingHubOrders();
    });
  }

  Future<void> syncOrder(Map<String, dynamic> order) async {
    await _syncOrder(order);
  }

  Future<void> syncPayment(Map<String, dynamic> payment) async {
    await _syncPayment(payment);
  }

  Future<void> syncPendingHubOrders() async {
    if (isHubSyncing.value) return;
    if (!(DeviceConfig.isLocal && DeviceConfig.role == DeviceRole.client)) return;

    final hostIp = DeviceConfig.hostIp;
    if (hostIp == null || hostIp.trim().isEmpty || !DeviceConfig.hasAuthToken) return;

    final pending = await _dbHelper.getOrdersPendingHubSync();
    if (pending.isEmpty) return;

    isHubSyncing.value = true;
    log("SyncService: ${pending.length} order(s) pending hub sync, retrying...");

    try {
      for (var order in pending) {
        final String uuid = order['uuid'];
        final String? payloadStr = order['payload'];
        if (payloadStr == null || payloadStr.isEmpty) continue;

        try {
          final Map<String, dynamic> hubPayload = jsonDecode(payloadStr);
          final result = await LocalHubClient.instance.createOrder(
            order: hubPayload,
            hostIp: hostIp,
            port: DeviceConfig.hostPort,
          );

          if (result['success'] == true || result['duplicate'] == true) {
            await _dbHelper.markOrderHubSynced(uuid);
            log("SyncService: ✅ Hub-synced pending order $uuid");

            if (Get.isRegistered<OrdersController>()) {
              Get.find<OrdersController>().fetchOrdersSafely();
            }
          }
        } catch (e) {
          log("SyncService: Hub still unreachable, stopping retry batch: $e");
          break; // host still down — don't hammer it order-by-order, wait for next tick
        }
      }
    } finally {
      isHubSyncing.value = false;
    }
  }

  Future<void> syncPendingOrders() async {
    if (isSyncing.value) return;

    // Clients in Local Hub Mode are NOT allowed to sync to Live DB
    if (DeviceConfig.isLocal && DeviceConfig.role == DeviceRole.client) {
      log("SyncService: Device is a Client in Local Hub Mode. Live DB sync is disabled for clients.");
      return;
    }

    try {
      final unsyncedOrders = await _dbHelper.getUnsyncedOrders();
      if (unsyncedOrders.isNotEmpty) {
        isSyncing.value = true;
        log("SyncService: Found ${unsyncedOrders.length} unsynced orders.");
        for (var order in unsyncedOrders) {
          await _syncOrder(order);
        }
      }

      final unsyncedPayments = await _dbHelper.getUnsyncedPayments();
      if (unsyncedPayments.isNotEmpty) {
        isSyncing.value = true;
        log("SyncService: Found ${unsyncedPayments.length} unsynced payments.");
        for (var payment in unsyncedPayments) {
          await _syncPayment(payment);
        }
      }

      try {
        await fillMissingProductUnits();
      } catch (e) {
        log("SyncService: fillMissingProductUnits failed during periodic sync: $e");
      }

    } catch (e) {
      log("SyncService Error: $e");
    } finally {
      isSyncing.value = false;
    }
  }

  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }


  Future<void> _fetchAddonsPaginated(int userId) async {
    const int pageLimit = 1000;
    int partNo = 0;
    bool isFirstPage = true;
    int totalFetched = 0;
    log("SyncService: Starting paginated addon fetch (limit: $pageLimit)...");
    while (true) {
      log("SyncService: Fetching addons page — part_no: $partNo");
      final response = await _apiService.post(
        "mobileapp/product_unit/get_prd_unit_and_addon",
        data: {
          "usr_id": userId,
          "part_no": partNo,
          "limit": pageLimit,
          "sync_time": "",
        },
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      if (response.statusCode != 200) {
        log("SyncService: Addon page part_no=$partNo returned ${response.statusCode}, stopping.");
        break;
      }

      final List<dynamic> pageData = response.data['data'] ?? [];

      if (pageData.isEmpty) {
        log("SyncService: Addon page part_no=$partNo returned empty, stopping.");
        break;
      }

      // Clear only on the first page so we don't wipe data mid-fetch
      if (isFirstPage) {
        await _dbHelper.clearBulkProductUnits();
        isFirstPage = false;
      }

      await _dbHelper.insertBulkProductUnits(pageData);
      totalFetched += pageData.length;
      log("SyncService: Fetched ${pageData.length} addon records (part_no=$partNo), total so far: $totalFetched");

      // If the server returned fewer records than the page size, we're done
      if (pageData.length < pageLimit) {
        log("SyncService: Last addon page reached (${pageData.length} < $pageLimit). Done.");
        break;
      }

      partNo++;
    }

    log("SyncService: Addon fetch complete — $totalFetched total records.");
  }

  /// Clears the current cart and table selection to ensure new master data 
  /// doesn't conflict with existing session state.
  void _clearCartState() {
    try {
      if (Get.isRegistered<CartController>()) {
        final cart = Get.find<CartController>();
        cart.stopEditing(); // clears editing state + cart + table selection
        log("SyncService: Cart and table selection cleared for Master Sync.");
      }
    } catch (e) {
      log("SyncService: Error clearing cart state: $e");
    }
  }

  Future<void> syncMasterData() async {
    if (isMasterSyncing.value) return;
    
    // Clear cart and table selection at the start of master sync
    _clearCartState();
    
    isMasterSyncing.value = true;
    masterSyncProgress.value = 0.0;

    try {
      log("SyncService: Starting manual master data sync...");
      final int userId = int.tryParse(AppState.userId) ?? 0;

      // 1. Start slow background calls
      log("SyncService: Initiating background fetch for units, addons and rates...");


      final unitsFuture = _apiService.post("mobileapp/unit/download", data: {
        "part_no": 0,
        "limit": "",
        "sync_time": "",
      }).catchError((e) {
        log("SyncService: Error in mobileapp/unit/download: $e");
        throw e;
      });

      final stockRatesFuture = _apiService.post("mobileapp/stock_unit_rates/download", data: {
        "part_no": 0,
        "limit": "",
        "sync_time": "",
      }).catchError((e) {
        log("SyncService: Error in mobileapp/stock_unit_rates/download: $e");
        throw e;
      });

      // 2. Parallelize metadata calls
      final apiResults = await Future.wait([
        _apiService.post("mobileapp/category/download", data: {
          "part_no": 0,
          "limit": 1000,
          "sync_time": "",
        }).catchError((e) { log("SyncService: Error in mobileapp/category/download: $e"); throw e; }),
        
        _apiService.post('mobileapp/pos/get_pos_table', data: {
          "usr_id": userId,
        }).catchError((e) { log("SyncService: Error in mobileapp/pos/get_pos_table: $e"); throw e; }),
        
        _apiService.post("mobileapp/pos/list_favorite", data: {
          "usr_id": userId,
        }).catchError((e) { log("SyncService: Error in mobileapp/pos/list_favorite: $e"); throw e; }),
        
        _apiService.post("mobileapp/sales_settings/vat_type", data: {
          "part_no": 0,
          "limit": 500,
          "sync_time": "",
        }).catchError((e) { log("SyncService: Error in mobileapp/sales_settings/vat_type: $e"); throw e; }),
        
        _apiService.post('mobileapp/sales/get_branch_all_cash_account', data: {
          "usr_id": userId,
        }).catchError((e) { log("SyncService: Error in mobileapp/sales/get_branch_all_cash_account: $e"); throw e; }),
        
        _apiService.post('mobileapp/sales/get_branch_bank_account', data: {
          "usr_id": userId,
        }).catchError((e) { log("SyncService: Error in mobileapp/sales/get_branch_bank_account: $e"); throw e; }),
        
        _apiService.post('mobileapp/sales/get_all_captains', data: {
          "usr_id": userId,
        }).catchError((e) { log("SyncService: Error in mobileapp/sales/get_all_captains: $e"); throw e; }),

        _apiService.post('mobileapp/general_settings/get_upi_enable_status_and_upi_id', data: {
          "usr_id" : userId,
        }).catchError((e) { log("SyncService: Error in UPI settings: $e"); throw e; }),
      ]);

      masterSyncProgress.value = 0.1;

      final categoryResponse = apiResults[0];
      final tablesResponse   = apiResults[1];
      final favoritesResponse = apiResults[2];
      final vatResponse       = apiResults[3];
      final cashAccResponse   = apiResults[4];
      final bankAccResponse   = apiResults[5];
      final captainsResponse  = apiResults[6];
      final upiResponse       = apiResults[7];

      // Save UPI Settings
      if (upiResponse.statusCode == 200) {
        var upiData = upiResponse.data['data'];
        if (upiData is List && upiData.isNotEmpty) {
          upiData = upiData.first;
        }
        if (upiData != null && upiData is Map) {
          final storage = GetStorage();
          int upiEnable = 0;
          if (upiData['as_upi_enable'] is int) {
            upiEnable = upiData['as_upi_enable'];
          } else if (upiData['as_upi_enable'] != null) {
            upiEnable = int.tryParse(upiData['as_upi_enable'].toString()) ?? 0;
          }
          final upiId = upiData['as_upi_id']?.toString() ?? '';

          storage.write('as_upi_enable', upiEnable);
          storage.write('as_upi_id', upiId);
          
          await _dbHelper.saveSetting('as_upi_enable', upiEnable.toString());
          await _dbHelper.saveSetting('as_upi_id', upiId);
          
          log("SyncService: Saved UPI Settings: Enable=$upiEnable, ID=$upiId");
        }
      }

      // Save VAT type
      if (vatResponse.statusCode == 200) {
        final data = vatResponse.data['data'];
        if (data != null && data['vat_type'] != null) {
          await _dbHelper.saveSetting('vat_type', data['vat_type'].toString());
        }
      }

      // Save Cash & Bank Accounts
      if (cashAccResponse.statusCode == 200) {
        final List<dynamic> data = cashAccResponse.data['data'] ?? [];
        await _dbHelper.insertLedgers(data.cast<Map<String, dynamic>>(), 'cash');
        log("SyncService: Cached ${data.length} cash accounts.");
      }
      if (bankAccResponse.statusCode == 200) {
        final List<dynamic> data = bankAccResponse.data['data'] ?? [];
        await _dbHelper.insertLedgers(data.cast<Map<String, dynamic>>(), 'bank');
        log("SyncService: Cached ${data.length} bank accounts.");
      }

      // Save Captains
      if (captainsResponse.statusCode == 200) {
        final List<dynamic> captainsData = captainsResponse.data['data'] ?? [];
        await _dbHelper.insertCaptains(captainsData.cast<Map<String, dynamic>>());
        log("SyncService: Cached ${captainsData.length} captains.");
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
          final dynamic fId = json['fav_id'] ?? json['favp_id'] ?? json['id'];
          if (fId != null) {
            favoritesData.add({
              'id': fId,
              'name': json['fav_name'] ?? json['favp_name'] ?? json['name'] ?? '',
              'image': json['fav_img_url'] ?? json['favp_img_url'] ?? json['image'] ?? '',
            });
          }
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
        log("SyncService Error processing units: $e");
      }

      final posCategories = categoriesList.where((c) => c['cat_pos'] == "1").toList();

      // 7. Sync Products
      await _syncProductsInParallel(priceGroupIds, posCategories, favoritesData);

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
        log("SyncService Error processing stock rates: $e");
      }

      // 9. Process Addons
      log("SyncService: Finalizing background addon data...");
      masterSyncProgress.value = 0.9;

      try {
        await _fetchAddonsPaginated(userId);
      } catch (e) {
        log("SyncService Error fetching addons: $e");
      }

      log("SyncService: Master data sync complete.");
      
      // Refresh CartController if it's active so it picks up the new captains/ledgers
      if (Get.isRegistered<CartController>()) {
        Get.find<CartController>().loadCaptains();
      }
    } catch (e) {
      log("SyncService Master Sync Error: $e");
      rethrow;
    } finally {
      isMasterSyncing.value = false;
      masterSyncProgress.value = 1.0;
    }
  }

  Future<void> _syncProductsInParallel(Set<int> priceGroupIds, List<Map<String, dynamic>> posCategories, List<Map<String, dynamic>> favorites) async {
    final pgList = priceGroupIds.toList();
    int totalToSync = pgList.length * (1 + posCategories.length + favorites.length);
    int syncedSoFar = 0;

    const pgChunkSize = 2;
    for (int i = 0; i < pgList.length; i += pgChunkSize) {
      final pgChunk = pgList.sublist(i, (i + pgChunkSize > pgList.length) ? pgList.length : i + pgChunkSize);

      await Future.wait(pgChunk.map((pgId) async {
        await _fetchAndInsertProducts(pgId: pgId);
        syncedSoFar++;
        _updateMasterProgress(syncedSoFar, totalToSync);

        // Categories
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

        // Favorites
        for (var fav in favorites) {
          final dynamic fId = fav['id'] ?? fav['fav_id'] ?? fav['favp_id'];
          final int favId = fId is int ? fId : int.tryParse(fId.toString()) ?? 0;
          if (favId > 0) {
            await _fetchAndInsertProducts(pgId: pgId, favId: favId);
          }
          syncedSoFar++;
          _updateMasterProgress(syncedSoFar, totalToSync);
        }
      }));
    }
  }

  void _updateMasterProgress(int current, int total) {
    if (total > 0) {
      masterSyncProgress.value = 0.2 + (0.6 * current / total);
    }
  }

  // Add to SyncService
  Future<void> fillMissingProductUnits() async {
    final missingIds = await _dbHelper.getProductIdsMissingBulkUnits();
    if (missingIds.isEmpty) {
      log("SyncService: No missing product units, nothing to fill.");
      return;
    }
    log("SyncService: ${missingIds.length} products missing unit data, fetching...");

    final int userId = int.tryParse(AppState.userId) ?? 0;
    const chunkSize = 50;

    for (int i = 0; i < missingIds.length; i += chunkSize) {
      final chunk = missingIds.sublist(
        i, (i + chunkSize > missingIds.length) ? missingIds.length : i + chunkSize,
      );
      try {
        final response = await _apiService.post(
          "mobileapp/product_unit/get_prd_unit_and_addon",
          data: {
            "usr_id": userId,
            "prd_ids": chunk, // adjust param name to match your actual endpoint contract
            "limit": chunkSize,
            "sync_time": "",
          },
        );
        if (response.statusCode == 200) {
          final List<dynamic> pageData = response.data['data'] ?? [];
          if (pageData.isNotEmpty) {
            await _dbHelper.insertBulkProductUnits(pageData);
            log("SyncService: Filled ${pageData.length} missing unit records.");
          }
        }
      } catch (e) {
        log("SyncService: fillMissingProductUnits chunk failed: $e");
      }
    }
  }

  Future<void> _fetchAndInsertProducts({
    required int pgId,
    String? catId,
    String? forceCatId,
    int? favId,
  }) async {
    final requestData = <String, dynamic>{
      "usr_id":         int.tryParse(AppState.userId) ?? 0,
      "price_group_id": pgId,
      "keyword":        "",
    };
    if (catId != null) requestData["category_id"] = int.tryParse(catId) ?? 0;
    if (favId != null) requestData["fav_id"] = favId;
    log("_fetchAndInsertProducts called: pgId=$pgId catId=$catId favId=$favId");
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
      final List<String> favoriteProductIds = [];
      final List<Map<String, dynamic>> basicUnits = [];

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
          'is_veg':         int.tryParse(json['prd_is_veg']?.toString() ?? "0") ?? 0,
          'sort_order':     i,
        });

        final double saleRate = (json['sale_rate'] as num? ?? 0.0).toDouble();
        final String unit_display = (json['unit_display'] ?? '').toString();
        basicUnits.add({
          'prd_id':         prdId,
          'price_group_id': pgId,
          'unit_id':        0,
          'unit_name':      unit_display.isNotEmpty ? unit_display : 'Unit',
          'unit_display':   unit_display.isNotEmpty ? unit_display : 'Unit',
          'rate':           saleRate,
          'unit_base_qty':  1.0,
          'exist_addons':   '[]',
        });

        if (favId != null) {
          favoriteProductIds.add(prdId);
        }
      }

      await _dbHelper.insertProducts(products);

      if (basicUnits.isNotEmpty) {
        await _dbHelper.insertBasicProductUnits(basicUnits);
        log("basicUnits built: ${basicUnits.length} rows for pgId=$pgId");
      }

      if (favId != null && favoriteProductIds.isNotEmpty) {
        await _dbHelper.insertFavoriteProducts(favId, pgId, favoriteProductIds);
      }
    } catch (e) {
      log("SyncService: Failed to fetch products (pgId=$pgId, catId=$catId): $e");
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

      // Determine if this is truly an edit of a SERVER-SIDE order
      final String? serverIdInDb = order['server_id'];
      final bool isRealServerOrder = serverIdInDb != null && 
                                     serverIdInDb.isNotEmpty && 
                                     !serverIdInDb.startsWith('ORD-');
                                     
      bool isEdit = payload['is_pos_edit'] == true && isRealServerOrder;

      // Fallback: If payload thinks it's an edit but we don't have a server ID, 
      // treat it as a new order.
      if (payload['is_pos_edit'] == true && !isRealServerOrder) {
        log("SyncService: Order $uuid marked as edit but no server ID found. Falling back to add_sales_order.");
        isEdit = false;
        payload['is_pos_edit'] = false;
        payload.remove('sq_id');
        payload.remove('sq_inv_no');
        payload.remove('sales_odr_id');
        payload.remove('sales_odr_inv_no');
      }

      final String endpoint = isEdit
          ? "mobileapp/pos/update_sales_order"
          : "mobileapp/pos/add_sales_order";

      log("SyncService: Syncing $uuid via $endpoint (isEdit: $isEdit, sq_inv_no: ${payload['sq_inv_no']})");

      // ✅ ADDED DETAILED LOGGING FOR SYNC
      if (payload['sale_items'] != null) {
        final List items = payload['sale_items'];
        log("SyncService: [PAYLOAD CHECK] Order $uuid contains ${items.length} items.");
        for (int i = 0; i < items.length; i++) {
          log("  - Item #$i: ${items[i]['prd_name']} | Qty: ${items[i]['salesub_qty']} | Rate: ${items[i]['salesub_rate']}");
        }
      } else {
        log("SyncService: ⚠️ WARNING! No sale_items found in payload for $uuid");
      }

      if (isEdit) {
        final int sqInvNo = _safeInt(payload['sq_inv_no']);
        final List processingTable =
            (payload['res_table']?['processing_table'] as List?) ?? [];

        if (sqInvNo == 0 || processingTable.isEmpty) {
          log("SyncService: ⚠️ Skipping edit $uuid — invalid payload. NOT marking as synced.");
          return;
        }
      }
      log("SyncService: About to POST ${payload.length} items to $endpoint");
      log("SyncService: Full payload sale_items: ${jsonEncode(payload['sale_items'])}");
      final response = await _apiService.post(endpoint, data: payload);

      if (response.statusCode == 200) {
        dynamic data = response.data;
        if (data is String) data = jsonDecode(data);
        log("SyncService: RAW response → $data");
          if (data is Map && data['message'] is Map) {
            final msg = data['message'] as Map;
            if (msg['status'] == 0) {
              log("SyncService: ❌ Server rejected $uuid: ${msg['msg']}");
              return;
            }
          }

        if (data is Map) {
          // Server might wrap preview under 'message' (Map) or at top level
          final message = data['message'];
          final preview = (message is Map ? message['preview'] : null) ?? data['preview'];

          final String serverId =
              preview?['sq_id']?.toString() ??
                  preview?['sales_odr_id']?.toString() ??
                  data['id']?.toString() ??
                  data['sales_odr_id']?.toString() ?? '';

          final String? invNo =
              preview?['sq_inv_no']?.toString() ??
                  preview?['sales_odr_inv_no']?.toString() ??
                  data['inv_no']?.toString() ??
                  data['sales_odr_inv_no']?.toString();
                  
          final String? branchInv =
              preview?['sales_odr_branch_inv']?.toString() ??
                  data['sales_odr_branch_inv']?.toString(); // ✅ Added

          if (serverId.isNotEmpty && serverId != '0') {
            await _dbHelper.updateOrderStatusByUuid(
              uuid,
              order['status'],
              isSynced: 1,
              serverId: serverId,
              invNo: invNo,
              branchInv: branchInv, // ✅ Added
            );
            log("SyncService: ✅ Synced $uuid → serverId: $serverId, invNo: $invNo, branchInv: $branchInv");
          } else {
            log("SyncService: ⚠️ Server returned 200 but no serverId for $uuid — will retry");
            log("SyncService: Response keys were: ${data.keys.toList()}");
          }
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
      final List<Map<String, dynamic>> orders = await db.query('orders',
          where: 'uuid = ? OR server_id = ?',
          whereArgs: [orderUuid, orderUuid]);

      if (orders.isEmpty) {
        log("SyncService: No order found for payment uuid=$orderUuid, marking done.");
        await _dbHelper.updatePaymentSyncStatus(localPaymentId, 1);
        return;
      }

      final order = orders.first;

      // ✅ KEY FIX: If the order payload already included payment (res_status=3 or
      // sale_pay_type != 0), _syncOrder already settled it in add_sales_order.
      // A separate settle call would double-process and corrupt the order.
      // We check this BEFORE the serverId check so we can clear payments even if the order sync is pending.
      if (order['payload'] != null) {
        try {
          final orderPayload = jsonDecode(order['payload'] as String);
          final int resStatus = _safeInt(orderPayload['res_status']);
          final int payType = _toInt(orderPayload['sale_pay_type']);

          if (resStatus == 3 || payType != 0) {
            log("SyncService: Payment for $orderUuid is already carried in order payload (res_status: $resStatus). Marking payment sync done.");
            await _dbHelper.updatePaymentSyncStatus(localPaymentId, 1);
            return;
          }
        } catch (e) {
          log("SyncService: Error checking payload for $orderUuid: $e");
        }
      }

      final String? serverId = order['server_id'];
      final String? invNo = order['inv_no'];

      if (serverId == null || serverId.isEmpty || serverId.startsWith('ORD-')) {
        log("SyncService: Order $orderUuid not yet synced, skipping payment API call.");
        return;
      }

      // Only reach here for orders that were initially placed as drafts/pending
      // and then paid separately (two-step flow)
      final Map<String, int> payTypeMap = {
        'cash': 2, 'card': 5, 'bank': 3, 'credit': 1, 'multiple': 4, 'compliment': 2,
      };

      final bool isCompliment = payment['method'].toString().toLowerCase() == 'compliment';

      final body = {
        "usr_id": _payloadUserId(order),
        "sales_odr_id": int.tryParse(serverId),
        "sales_odr_inv_no": int.tryParse(invNo ?? "0"),
        "sale_pay_type": payTypeMap[payment['method'].toString().toLowerCase()] ?? 2,
        "amount_paid": isCompliment ? 0 : payment['amount'],
        "received_amount": payment['amount'],
        "change_given": 0,
        "settle_date": payment['created_at'].split('T')[0],
        "sale_acc_ledger_id_cash": payment['cash_ledger_id'],
        "sale_acc_ledger_id_bank": payment['bank_ledger_id'],
        "sq_disc": isCompliment ? payment['amount'] : payment['discount_amount'] ?? 0,
        "is_compliment": isCompliment ? 1 : 0,
      };

      if (order['payload'] != null) {
        try {
          final payload = jsonDecode(order['payload'] as String);
          if (payload['sale_items'] != null && (payload['sale_items'] as List).isNotEmpty) {
            body['sale_items'] = payload['sale_items'];
            log("SyncService: [SETTLEMENT] Attaching ${(payload['sale_items'] as List).length} items.");
          }
        } catch (e) {
          log("SyncService: Error extracting sale_items: $e");
        }
      }

      log("SyncService: Sending settlement for order $serverId...");
      print("🚀 Settlement API URL: ${_apiService.baseUrl}mobileapp/pos/settle_sales_order");

      final response = await _apiService.post("mobileapp/pos/settle_sales_order", data: body);

      if (response.statusCode == 200) {
        await _dbHelper.updatePaymentSyncStatus(localPaymentId, 1);
        log("SyncService: ✅ Synced payment for order $serverId");
      }
    } catch (e) {
      log("SyncService: ❌ Payment sync failed: $e");
    }
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
}
