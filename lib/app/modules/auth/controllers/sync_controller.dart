import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';

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
    startSync();
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
      log("SyncController: Initiating background fetch for units, addons and rates...");
      
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
      ]);

      progress.value = 0.10;
      statusMessage.value = "Processing metadata...";

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
          favorites.add({
            'id': json['fav_id'],
            'name': json['fav_name'],
            'image': json['fav_img_url'] ?? '',
          });
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
        log("SyncController: Waiting for units response...");
        final unitsResponse = await unitsFuture;
        if (unitsResponse.statusCode == 200) {
          final List<dynamic> unitsData = unitsResponse.data['data'] ?? [];
          if (unitsData.isNotEmpty) {
            await _dbHelper.insertUnits(unitsData);
            log("SyncController: Successfully cached ${unitsData.length} units.");
          }
        }
      } catch (e) {
        log("SyncController: Error fetching units: $e");
      }

      final posCategories = categories.where((c) => c['cat_pos'] == "1").toList();
      totalCount.value = priceGroupIds.length * (1 + posCategories.length);
      syncedCount.value = 0;

      // 3. Sync Products
      await _syncProductsParallel(posCategories, priceGroupIds);

      // Process Stock Unit Rates
      try {
        log("SyncController: Waiting for stock rates response...");
        final stockRatesResponse = await stockRatesFuture;
        if (stockRatesResponse.statusCode == 200) {
          final List<dynamic> ratesData = stockRatesResponse.data['data'] ?? [];
          if (ratesData.isNotEmpty) {
            await _dbHelper.clearStockUnitRates();
            await _dbHelper.insertStockUnitRates(ratesData);
            log("SyncController: Successfully cached ${ratesData.length} stock unit rates.");
          }
        }
      } catch (e) {
        log("SyncController: Error fetching stock rates: $e");
      }

      // 4. Finally, wait for the slow Addon API if it's not done yet
      statusMessage.value = "Finalizing addon data...";
      progress.value = 0.90;
      
      try {
        log("SyncController: Waiting for addon response...");
        final bulkUnitsResponse = await addonFuture;
        if (bulkUnitsResponse.statusCode == 200) {
          final List<dynamic> bulkData = bulkUnitsResponse.data['data'] ?? [];
          if (bulkData.isNotEmpty) {
            await _dbHelper.clearBulkProductUnits();
            await _dbHelper.insertBulkProductUnits(bulkData);
            log("SyncController: Successfully cached ${bulkData.length} bulk records.");
          }
        }
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

  Future<void> _syncProductsParallel(
      List<Map<String, dynamic>> posCategories,
      Set<int> priceGroupIds,
      ) async {
    final pgList = priceGroupIds.toList();
    final chunks = _chunked(pgList, 2);
    for (final chunk in chunks) {
      await Future.wait(chunk.map((pgId) async {
        await _syncProductsForPriceGroup(pgId, posCategories);
      }));
    }
  }

  Future<void> _syncProductsForPriceGroup(
      int pgId,
      List<Map<String, dynamic>> posCategories,
      ) async {
    statusMessage.value = "Syncing products (PG $pgId)...";

    // 1. Global items
    await _fetchAndInsertProducts(pgId: pgId);
    _updateProgress();

    // 2. Category-specific items
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
  }

  void _updateProgress() {
    syncedCount.value++;
    if (totalCount.value > 0) {
      // Products take up 0.15 to 0.90 (75% of the total bar)
      progress.value = 0.15 + (0.75 * syncedCount.value / totalCount.value);
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
