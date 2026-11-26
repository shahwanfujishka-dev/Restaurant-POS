import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response, ScreenType;
import 'package:intl/intl.dart';
import '../../../data/services/api_endpoints.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../../../../helper/screen_type.dart';

class SyncController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final progress = 0.0.obs;
  final statusMessage = 'initializing_sync'.tr.obs;
  bool _running = false;
  Timer? _retryTimer;
  final _requests = <CancelToken>{};
  Completer<void>? _retryGate;
  Object? _requestFailure;
  final slowRequests = 0.obs;
  final retrySeconds = 0.obs;
  final reconnectingRequests = 0.obs;
  int _retryDelay = 2;
  final syncedCount = 0.obs;
  final totalCount = 0.obs;

  final hasError = false.obs;
  final isComplete = false.obs;

  @override
  void onReady() {
    super.onReady();
    if (isClosed) return;
    _clearCartState();
    unawaited(startSync());
  }

  @override
  void onClose() {
    _stopRequests();
    super.onClose();
  }

  void _clearCartState() {
    try {
      if (Get.isRegistered<CartController>()) {
        final cart = Get.find<CartController>();
        cart.stopEditing();
      }
    } catch (e) {
      log("SyncController: Error clearing cart state: $e");
    }
  }

  void setOrientation({required bool isMobile}) {
    if (isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _fetchAddonsPaginated(DatabaseHelper staging, int userId) async {
    const int pageLimit = 1000;
    int partNo = 0;
    bool isFirstPage = true;
    int totalFetched = 0;

    while (true) {
      statusMessage.value = 'fetching_addons_page'.trParams({'page': (partNo + 1).toString()});

      final response = await _postForSync(
        ApiEndpoints.getProductUnitsAndAddons,
        data: {
          "usr_id": userId,
          "part_no": partNo,
          "limit": pageLimit,
          "sync_time": "",
        },
      );

      final List<dynamic> pageData = response.data['data'] ?? [];
      if (pageData.isEmpty) break;

      if (isFirstPage) {
        isFirstPage = false;
      }

      await staging.insertBulkProductUnits(pageData);
      totalFetched += pageData.length;
      progress.value =
          (0.90 + (totalFetched / (totalFetched + pageLimit)) * 0.09).clamp(
            0.90,
            0.99,
          );
      if (pageData.length < pageLimit) break;

      partNo++;
    }
  }

  Future<void> startSync() async {
    if (_running || isClosed) return;
    _running = true;
    _requestFailure = null;
    _retryDelay = 2;
    hasError.value = false;
    isComplete.value = false;
    progress.value = 0.0;
    syncedCount.value = 0;
    totalCount.value = 0;
    statusMessage.value = 'fetching_data'.tr;

    try {
      await Get.find<SyncService>().runMasterSync(_downloadMasterData);
      if (isClosed) return;
      progress.value = 1.0;
      isComplete.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!isClosed) {
        Get.offAllNamed(ScreenType.isMobile() ? Routes.ORDER_TYPE : Routes.HOME);
      }
    } catch (error, stackTrace) {
      if (isClosed) return;
      log("Master sync failed", error: _requestFailure ?? error, stackTrace: stackTrace);
      hasError.value = true;
    } finally {
      _running = false;
    }
  }

  void retryNow() {
    if (_retryGate == null) return;
    _retryTimer?.cancel();
    final gate = _retryGate!;
    _retryGate = null;
    retrySeconds.value = 0;
    gate.complete();
  }

  void _stopRequests() {
    retryNow();
    for (final token in _requests) {
      token.cancel();
    }
  }

  Future<void> _waitToReconnect() {
    final existing = _retryGate;
    if (existing != null) return existing.future;

    final gate = _retryGate = Completer<void>();
    final delay = _retryDelay;
    retrySeconds.value = delay;
    _retryDelay = (_retryDelay * 2).clamp(2, 30).toInt();
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timer.tick >= delay) {
        retryNow();
      } else {
        retrySeconds.value = delay - timer.tick;
      }
    });
    return gate.future;
  }

  bool _isConnectionFailure(Object error) =>
      error is TimeoutException ||
      (error is DioException &&
          (error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              (error.type == DioExceptionType.unknown &&
                  (error.error is SocketException || error.error is HttpException))));

  Future<Response> _postForSync(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    var reconnecting = false;
    try {
      while (!isClosed && _requestFailure == null) {
        final gate = _retryGate;
        if (gate != null) {
          await gate.future;
          continue;
        }

        final token = CancelToken();
        _requests.add(token);
        var isSlow = false;
        final warning = Timer(const Duration(seconds: 5), () {
          isSlow = true;
          slowRequests.value++;
        });

        try {
          return await _apiService.postForMasterSync(
            path,
            data: data,
            cancelToken: token,
          ).timeout(const Duration(seconds: 45));
        } catch (error) {
          if (token.isCancelled || isClosed) rethrow;
          if (!_isConnectionFailure(error)) {
            _requestFailure = error;
            _stopRequests();
            rethrow;
          }
          token.cancel();
          if (!reconnecting) {
            reconnecting = true;
            reconnectingRequests.value++;
          }
          log("Sync request will retry: $path", error: error);
        } finally {
          _requests.remove(token);
          warning.cancel();
          if (isSlow) slowRequests.value--;
        }
        await _waitToReconnect();
      }
      throw _requestFailure ?? StateError('Sync screen closed');
    } finally {
      if (reconnecting) {
        reconnectingRequests.value--;
        if (reconnectingRequests.value == 0) _retryDelay = 2;
      }
    }
  }

  Future<void> _downloadMasterData() async {
    late final List<dynamic> soldOrders;
    await Get.find<SyncService>().refreshMasterCatalog((staging) async {
      soldOrders = await _downloadCatalog(staging);
    }, fullRefresh: true, isCancelled: () => isClosed);
    if (isClosed) return;
    await _dbHelper.cacheSoldOrders(soldOrders);
    unawaited(_cacheSoldOrderDetails(soldOrders));
  }

  Future<List<dynamic>> _downloadCatalog(DatabaseHelper staging) async {
    final int userId = int.tryParse(AppState.userId) ?? 0;

    final apiResults = await Future.wait([
      _postForSync(
        ApiEndpoints.downloadCategories,
        data: {"part_no": 0, "limit": 1000, "sync_time": ""},
      ),
      _postForSync(
        ApiEndpoints.getTables,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.listFavorites,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.getVatType,
        data: {"part_no": 0, "limit": 500, "sync_time": ""},
      ),
      _postForSync(
        ApiEndpoints.getBranchCashAccounts,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.getBranchBankAccounts,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.listSoldOrders,
        data: {
          "usr_id": userId,
          "date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      ),
      _postForSync(
        ApiEndpoints.downloadCustomers,
        data: {"part_no": 0, "limit": 1000, "sync_time": ""},
      ),
      _postForSync(
        ApiEndpoints.getCaptains,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.getUpiSettings,
        data: {"usr_id": userId},
      ),
      _postForSync(
        ApiEndpoints.downloadUnits,
        data: {"part_no": 0, "limit": "", "sync_time": ""},
      ),
      _postForSync(
        ApiEndpoints.downloadStockUnitRates,
        data: {"part_no": 0, "limit": "", "sync_time": ""},
      ),
    ]);

    progress.value = 0.10;
    statusMessage.value = 'processing_metadata'.tr;

    final categoryResponse = apiResults[0];
    final tablesResponse = apiResults[1];
    final vatResponse = apiResults[3];
    final cashAccResponse = apiResults[4];
    final bankAccResponse = apiResults[5];
    final soldOrdersResponse = apiResults[6];
    final customerResponse = apiResults[7];
    final captainsResponse = apiResults[8];
    final upiResponse = apiResults[9];

    if (upiResponse.statusCode == 200) {
      var upiData = upiResponse.data['data'];
      if (upiData is List && upiData.isNotEmpty) upiData = upiData.first;
      if (upiData != null && upiData is Map) {
        int upiEnable = int.tryParse(upiData['as_upi_enable'].toString()) ?? 0;
        final upiId = upiData['as_upi_id']?.toString() ?? '';
        await staging.saveSetting('as_upi_enable', upiEnable.toString());
        await staging.saveSetting('as_upi_id', upiId);
      }
    }

    if (customerResponse.statusCode == 200) {
      final List<dynamic> customerData = customerResponse.data['data'] ?? [];
      await staging.insertCustomers(customerData.cast<Map<String, dynamic>>());
    }

    if (captainsResponse.statusCode == 200) {
      final List<dynamic> captainsData = captainsResponse.data['data'] ?? [];
      await staging.insertCaptains(captainsData.cast<Map<String, dynamic>>());
    }

    if (vatResponse.statusCode == 200) {
      final data = vatResponse.data['data'];
      if (data != null && data['vat_type'] != null) {
        await staging.saveSetting('vat_type', data['vat_type'].toString());
      }
    }

    if (cashAccResponse.statusCode == 200) {
      final List<dynamic> data = cashAccResponse.data['data'] ?? [];
      await staging.insertLedgers(data.cast<Map<String, dynamic>>(), 'cash');
    }
    if (bankAccResponse.statusCode == 200) {
      final List<dynamic> data = bankAccResponse.data['data'] ?? [];
      await staging.insertLedgers(data.cast<Map<String, dynamic>>(), 'bank');
    }

    final List<Map<String, dynamic>> categories = [];
    if (categoryResponse.statusCode == 200) {
      final List<dynamic> data = categoryResponse.data['data'] ?? [];
      for (int i = 0; i < data.length; i++) {
        final json = data[i];
        categories.add({
          'id': (json['cat_id'] ?? '').toString().trim(),
          'name': (json['cat_name'] ?? '').toString(),
          'cat_pos': (json['cat_pos'] ?? '').toString(),
          'token_printer_id': (json['cat_token_printer'] as num? ?? 0).toInt(),
          'sort_order': i,
        });
      }
    }

    Set<int> priceGroupIds = {0};
    List<dynamic> areasData = [];
    if (tablesResponse.statusCode == 200) {
      areasData = tablesResponse.data['data'] ?? [];
      for (var area in areasData) {
        priceGroupIds.add((area['ra_prcgrp_id'] as num? ?? 0).toInt());
      }
    }

    final List<Map<String, dynamic>> favorites = [];
    if (apiResults[2].statusCode == 200) {
      final List<dynamic> favData = apiResults[2].data['data'] ?? [];
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
      staging.insertCategories(categories),
      staging.insertAreas(areasData.cast<Map<String, dynamic>>()),
      staging.insertFavorites(favorites),
    ]);

    progress.value = 0.15;

    final List<dynamic> unitsData = apiResults[10].data['data'] ?? [];
    await staging.insertUnits(unitsData);

    final posCategories = categories.where((c) => c['cat_pos'] == "1").toList();
    totalCount.value = priceGroupIds.length * (1 + posCategories.length + favorites.length);
    syncedCount.value = 0;

    await _syncProductsParallel(staging, posCategories, priceGroupIds, favorites);

    final List<dynamic> ratesData = apiResults[11].data['data'] ?? [];
    await staging.insertStockUnitRates(ratesData);

    statusMessage.value = 'finalizing_addons'.tr;
    progress.value = 0.90;

    await _fetchAddonsPaginated(staging, userId);

    return soldOrdersResponse.data['data'] as List? ?? [];
  }

  // Receipt previews can be fetched on demand when reprinting.
  Future<void> _cacheSoldOrderDetails(List<dynamic> soldOrders) async {
    for (final orders in _chunked(soldOrders, 5)) {
      await Future.wait(orders.map((order) async {
        final invNo = order['sales_odr_inv_no'];
        if (invNo != null) await _fetchAndCacheSoldOrderDetails(invNo);
      }));
    }
  }

  Future<void> _fetchAndCacheSoldOrderDetails(dynamic invNo) async {
    try {
      final int userId = int.tryParse(AppState.userId) ?? 0;
      final response = await _apiService.post(
        ApiEndpoints.getSoldOrderDetails,
        data: {
          "usr_id": userId,
          "sales_odr_inv_no": invNo,
          "is_reprint": 1,
          "cmp_tax": AppState.cmpTaxType,
        },
      );

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
    } catch (_) {}
  }

  Future<void> _syncProductsParallel(
    DatabaseHelper staging,
    List<Map<String, dynamic>> posCategories,
    Set<int> priceGroupIds,
    List<Map<String, dynamic>> favorites,
  ) async {
    final pgList = priceGroupIds.toList();
    final chunks = _chunked(pgList, 2);
    for (final chunk in chunks) {
      await Future.wait(
        chunk.map((pgId) async {
          await _syncProductsForPriceGroup(staging, pgId, posCategories, favorites);
        }),
      );
    }
  }

  Future<void> _syncProductsForPriceGroup(
    DatabaseHelper staging,
    int pgId,
    List<Map<String, dynamic>> posCategories,
    List<Map<String, dynamic>> favorites,
  ) async {
    statusMessage.value = 'syncing_products_pg'.trParams({'pgId': pgId.toString()});

    await _fetchAndInsertProducts(staging, pgId: pgId);
    _updateProgress();

    final catChunks = _chunked(posCategories, 5);
    for (var chunk in catChunks) {
      await Future.wait(
        chunk.map((cat) async {
          final catId = cat['id'] as String;
          if (catId.isNotEmpty) {
            await _fetchAndInsertProducts(staging, pgId: pgId, catId: catId, forceCatId: catId);
            _updateProgress();
          }
        }),
      );
    }

    for (var fav in favorites) {
      final dynamic fId = fav['id'] ?? fav['fav_id'] ?? fav['favp_id'];
      final int favId = fId is int ? fId : int.tryParse(fId.toString()) ?? 0;
      if (favId > 0) await _fetchAndInsertProducts(staging, pgId: pgId, favId: favId);
      _updateProgress();
    }
  }

  void _updateProgress() {
    syncedCount.value++;
    if (totalCount.value > 0) {
      progress.value = 0.15 + (0.75 * syncedCount.value / totalCount.value);
    }
  }

  Future<void> _fetchAndInsertProducts(DatabaseHelper staging, {
    required int pgId,
    String? catId,
    String? forceCatId,
    int? favId,
  }) async {
    final requestData = <String, dynamic>{
      "usr_id": int.tryParse(AppState.userId) ?? 0,
      "price_group_id": pgId,
      "keyword": "",
    };
    if (catId != null) requestData["category_id"] = int.tryParse(catId) ?? 0;
    if (favId != null) requestData["fav_id"] = favId;

    final res = await _postForSync(ApiEndpoints.getProducts, data: requestData);

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
        'id': prdId,
        'price_group_id': pgId,
        'name': (json['prd_name'] ?? '').toString(),
        'category_id': forceCatId ?? (json['prd_cat_id'] ?? '').toString().trim(),
        'price': (json['sale_rate'] as num? ?? 0.0).toDouble(),
        'prd_tax': (json['prd_tax'] as num? ?? 0.0).toDouble(),
        'image': imgUrl,
        'unit_display': (json['unit_display'] ?? '').toString(),
        'tax_cat_id': (json['prd_tax_cat_id'] as num? ?? 0).toInt(),
        'tax_per': (json['tax_per'] as num? ?? 0.0).toDouble(),
        'is_veg': int.tryParse(json['prd_is_veg']?.toString() ?? "0") ?? 0,
        'sort_order': i,
      });
      if (favId != null) favoriteProductIds.add(prdId);
    }
    await staging.insertProducts(products);
    if (favId != null && favoriteProductIds.isNotEmpty) {
      await staging.insertFavoriteProducts(favId, pgId, favoriteProductIds);
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
