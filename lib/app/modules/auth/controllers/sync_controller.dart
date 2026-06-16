import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:intl/intl.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';

class SyncController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final progress = 0.0.obs;
  final statusMessage = "Initializing sync...".obs;

  final syncedCount = 0.obs;
  final totalCount = 0.obs;

  final hasError = false.obs;
  final errorMessage = "".obs;

  @override
  void onInit() {
    super.onInit();
    _clearCartState();
    startSync();
  }

  void _clearCartState() {
    try {
      if (Get.isRegistered<CartController>()) {
        final cart = Get.find<CartController>();
        cart.stopEditing();
        log("SyncController: Cart and table selection cleared for Master Sync.");
      }
    } catch (e) {
      log("SyncController: Error clearing cart state: $e");
    }
  }

  Future<void> _fetchAddonsPaginated(int userId) async {
    const int pageLimit = 1000;
    int partNo = 0;
    bool isFirstPage = true;
    int totalFetched = 0;

    log("SyncController: Starting paginated addon fetch (limit: $pageLimit)...");

    while (true) {
      statusMessage.value = "Fetching addon data (page ${partNo + 1})...";
      log("SyncController: Fetching addons page — part_no: $partNo");

      final response = await _apiService.post(
        "mobileapp/product_unit/get_prd_unit_and_addon",
        data: {
          "usr_id": userId,
          "part_no": partNo,
          "limit": pageLimit,
          "sync_time": "",
        },
      );

      if (response.statusCode != 200) {
        log("SyncController: Addon page part_no=$partNo returned ${response.statusCode}, stopping.");
        break;
      }

      final List<dynamic> pageData = response.data['data'] ?? [];

      if (pageData.isEmpty) {
        log("SyncController: Addon page part_no=$partNo returned empty, stopping.");
        break;
      }

      if (isFirstPage) {
        await _dbHelper.clearBulkProductUnits();
        isFirstPage = false;
      }

      await _dbHelper.insertBulkProductUnits(pageData);
      totalFetched += pageData.length;
      log("SyncController: Fetched ${pageData.length} addon records (part_no=$partNo), total so far: $totalFetched");
      progress.value = (0.90 + (totalFetched / (totalFetched + pageLimit)) * 0.09)
          .clamp(0.90, 0.99);
      if (pageData.length < pageLimit) {
        log("SyncController: Last addon page reached (${pageData.length} < $pageLimit). Done.");
        break;
      }

      partNo++;
    }

    log("SyncController: Addon fetch complete — $totalFetched total records.");
  }

  Future<void> startSync() async {
    try {
      log("SyncController: startSync() triggered.");
      hasError.value = false;
      errorMessage.value = "";
      statusMessage.value = "Fetching data...";
      await _dbHelper.clearAllCache();

      final int userId = int.tryParse(AppState.userId) ?? 0;

      // 1. Start slow background calls
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

      // 2. Parallelize independent FAST metadata calls
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
        _apiService.post('mobileapp/sales/get_branch_all_cash_account', data: {
          "usr_id": userId,
        }),
        _apiService.post('mobileapp/sales/get_branch_bank_account', data: {
          "usr_id": userId,
        }),
        _apiService.post("mobileapp/pos/get_sold_pos_order_list", data: {
          "usr_id": userId,
          "date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        }),
        _apiService.post('mobileapp/customer/download', data: {
          "part_no": 0,
          "limit": 1000,
          "sync_time": "",
        }),
      ]);

      progress.value = 0.10;
      statusMessage.value = "Processing metadata...";

      final categoryResponse = apiResults[0];
      final tablesResponse   = apiResults[1];
      final favoritesResponse = apiResults[2];
      final vatResponse       = apiResults[3];
      final cashAccResponse   = apiResults[4];
      final bankAccResponse   = apiResults[5];
      final soldOrdersResponse = apiResults[6];
      final customerResponse = apiResults[7];

      // Save Customers
      if (customerResponse.statusCode == 200) {
        final List<dynamic> customerData = customerResponse.data['data'] ?? [];
        await _dbHelper.insertCustomers(customerData.cast<Map<String, dynamic>>());
        log("SyncController: Cached ${customerData.length} customers.");
      }

      // Save Sold Orders and their details
      if (soldOrdersResponse.statusCode == 200) {
        final List<dynamic> soldData = soldOrdersResponse.data['data'] ?? [];
        await _dbHelper.cacheSoldOrders(soldData);
        log("SyncController: Cached ${soldData.length} sold orders summary. Fetching details...");
        
        for (var order in soldData) {
           _fetchAndCacheSoldOrderDetails(order['sales_odr_inv_no']);
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
      }
      if (bankAccResponse.statusCode == 200) {
        final List<dynamic> data = bankAccResponse.data['data'] ?? [];
        await _dbHelper.insertLedgers(data.cast<Map<String, dynamic>>(), 'bank');
      }

      // Process Categories
      final List<Map<String, dynamic>> categories = [];
      if (categoryResponse.statusCode == 200) {
        final List<dynamic> data = categoryResponse.data['data'] ?? [];
        for (int i = 0; i < data.length; i++) {
          final json = data[i];
          categories.add({
            'id':               (json['cat_id']            ?? '').toString().trim(),
            'name':             (json['cat_name']          ?? '').toString(),
            'cat_pos':          (json['cat_pos']           ?? '').toString(),
            'token_printer_id': (json['cat_token_printer'] as num? ?? 0).toInt(),
            'sort_order':       i,
          });
        }
      }

      // Process Tables & Areas
      Set<int> priceGroupIds = {0};
      List<dynamic> areasData = [];
      if (tablesResponse.statusCode == 200) {
        areasData = tablesResponse.data['data'] ?? [];
        for (var area in areasData) {
          final int pgId = (area['ra_prcgrp_id'] as num? ?? 0).toInt();
          priceGroupIds.add(pgId);
        }
      }

      // Process Favorites
      final List<Map<String, dynamic>> favorites = [];
      if (favoritesResponse.statusCode == 200) {
        final List<dynamic> favData = favoritesResponse.data['data'] ?? [];
        for (var json in favData) {
          final dynamic fId = json['fav_id'] ?? json['favp_id'] ?? json['id'];
          if (fId != null) {
            favorites.add({
              'id': fId,
              'name': json['fav_name'] ?? json['favp_name'] ?? json['name'] ?? '',
              'image': json['fav_img_url'] ?? json['favp_img_url'] ?? json['image'] ?? '',
            });
          }
        }
      }

      await Future.wait([
        _dbHelper.insertCategories(categories),
        _dbHelper.insertAreas(areasData.cast<Map<String, dynamic>>()),
        _dbHelper.insertFavorites(favorites),
      ]);

      progress.value = 0.15;

      // Process Units
      try {
        final unitsResponse = await unitsFuture;
        if (unitsResponse.statusCode == 200) {
          final List<dynamic> unitsData = unitsResponse.data['data'] ?? [];
          if (unitsData.isNotEmpty) {
            await _dbHelper.insertUnits(unitsData);
          }
        }
      } catch (e) {
        log("SyncController: Error fetching units: $e");
      }

      final posCategories = categories.where((c) => c['cat_pos'] == "1").toList();
      totalCount.value = priceGroupIds.length * (1 + posCategories.length + favorites.length);
      syncedCount.value = 0;

      // Sync Products
      await _syncProductsParallel(posCategories, priceGroupIds, favorites);

      // Process Stock Unit Rates
      try {
        final stockRatesResponse = await stockRatesFuture;
        if (stockRatesResponse.statusCode == 200) {
          final List<dynamic> ratesData = stockRatesResponse.data['data'] ?? [];
          if (ratesData.isNotEmpty) {
            await _dbHelper.clearStockUnitRates();
            await _dbHelper.insertStockUnitRates(ratesData);
          }
        }
      } catch (e) {
        log("SyncController: Error fetching stock rates: $e");
      }

      statusMessage.value = "Finalizing addon data...";
      progress.value = 0.90;

      try {
        await _fetchAddonsPaginated(userId);
      } catch (e) {
        log("SyncController: Error fetching background addons: $e");
      }

      progress.value = 1.0;
      statusMessage.value = "Sync complete!";
      await Future.delayed(const Duration(milliseconds: 500));
      Get.offAllNamed(Routes.ORDER_TYPE);

    } catch (e) {
      log("Sync Error: $e");
      hasError.value = true;
      errorMessage.value = e.toString();

      Get.snackbar(
        "Sync Failed",
        "Error: $e. Please retry.",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 10),
      );
    }
  }

  Future<void> _fetchAndCacheSoldOrderDetails(dynamic invNo) async {
    try {
      final int userId = int.tryParse(AppState.userId) ?? 0;
      final response = await _apiService.post("mobileapp/pos/get_sold_pos_data", data: {
        "usr_id": userId,
        "sales_odr_inv_no": invNo,
        "is_reprint": 1,
      });

      if (response.statusCode == 200) {
        final data = response.data['data'];
        if (data != null && data['preview'] != null) {
          final preview = data['preview'];
          final String serverId = (preview['sales_odr_id'] ?? '').toString();
          if (serverId.isNotEmpty) {
            await _dbHelper.updateOrderStatusByUuid(
              serverId,
              'paid',
              payload: jsonEncode(preview),
              isSynced: 1,
              invNo: invNo.toString(),
              serverId: serverId,
            );
          }
        }
      }
    } catch (e) {
      log("SyncController: Error fetching sold order details for $invNo: $e");
    }
  }

  Future<void> _syncProductsParallel(
      List<Map<String, dynamic>> posCategories,
      Set<int> priceGroupIds,
      List<Map<String, dynamic>> favorites,
      ) async {
    final pgList = priceGroupIds.toList();
    final chunks = _chunked(pgList, 2);
    for (final chunk in chunks) {
      await Future.wait(chunk.map((pgId) async {
        await _syncProductsForPriceGroup(pgId, posCategories, favorites);
      }));
    }
  }

  Future<void> _syncProductsForPriceGroup(
      int pgId,
      List<Map<String, dynamic>> posCategories,
      List<Map<String, dynamic>> favorites,
      ) async {
    statusMessage.value = "Syncing products (PG $pgId)...";

    // Global items
    await _fetchAndInsertProducts(pgId: pgId);
    _updateProgress();

    // Category-specific items
    final catChunks = _chunked(posCategories, 5);
    for (var chunk in catChunks) {
      await Future.wait(chunk.map((cat) async {
        final catId = cat['id'] as String;
        if (catId.isNotEmpty) {
          await _fetchAndInsertProducts(pgId: pgId, catId: catId, forceCatId: catId);
          _updateProgress();
        }
      }));
    }

    // Favorite-specific items
    for (var fav in favorites) {
      final dynamic fId = fav['id'] ?? fav['fav_id'] ?? fav['favp_id'];
      final int favId = fId is int ? fId : int.tryParse(fId.toString()) ?? 0;
      if (favId > 0) {
        await _fetchAndInsertProducts(pgId: pgId, favId: favId);
      }
      _updateProgress();
    }
  }

  void _updateProgress() {
    syncedCount.value++;
    if (totalCount.value > 0) {
      progress.value = 0.15 + (0.75 * syncedCount.value / totalCount.value);
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

        if (favId != null) {
          favoriteProductIds.add(prdId);
        }
      }

      await _dbHelper.insertProducts(products);

      if (favId != null && favoriteProductIds.isNotEmpty) {
        await _dbHelper.insertFavoriteProducts(favId, pgId, favoriteProductIds);
      }
    } catch (e) {
      log("SyncController: Error in _fetchAndInsertProducts: $e");
    }
  }

  List<List<T>> _chunked<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      final end = (i + size < list.length) ? i + size : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
