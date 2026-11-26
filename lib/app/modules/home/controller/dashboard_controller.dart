import 'dart:convert';
import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:restaurant_pos/app/data/Device_Roles/device_roles.dart';
import 'package:restaurant_pos/app/data/models/order_model.dart';
import 'package:restaurant_pos/app/data/models/order_type.dart';
import 'package:restaurant_pos/app/data/services/local_hub_client.dart';
import '../../../../helper/snackbar_helper.dart';
import '../../../../local_server_test.dart';
import '../../../data/services/api_endpoints.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../views/dashoard/models/dashboard_models.dart';
import '../views/dashoard/widgets/product_details_dialog.dart';
import 'settings_controller.dart';

class DashboardController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final CartController cartController = Get.find<CartController>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SyncService _syncService = Get.find<SyncService>();
  final categories = <CategoryModel>[].obs;
  final allCategoriesForPrinters = <CategoryModel>[].obs;
  final isFetchingAllCategories = false.obs;
  final selectedCategoryId = ''.obs;
  final isLoadingCategories = false.obs;
  final isMoreLoadingCategories = false.obs;
  final hasMoreCategories = true.obs;
  late final ScrollController categoryScrollController;
  late final TextEditingController searchController;
  late final FocusNode searchFocusNode;
  final filteredFoodItems = <FoodItemModel>[].obs;
  final isLoadingProducts = false.obs;
  final searchKeyword = ''.obs;
  final productUnits = <ProductUnit>[].obs;
  final commonAddons = <AddonModel>[].obs;
  final selectedUnit = Rxn<ProductUnit>();
  final isLoadingDetails = false.obs;
  final favorites = <FavoriteModel>[].obs;
  final selectedFavoriteId = Rxn<int>();
  final isLoadingFavorites = false.obs;
  final vatType = 0.obs;
  RxBool get isSyncing => _syncService.isSyncing;
  bool isDisposed = false;
  int _productRequest = 0;
  final _workers = <Worker>[];
  // Local Snackbar State
  final localErrorTitle = ''.obs;
  final localErrorMessage = ''.obs;
  final showLocalError = false.obs;

  void showError(String title, String message) {
    localErrorTitle.value = title;
    localErrorMessage.value = message;
    showLocalError.value = true;

    Future.delayed(const Duration(seconds: 3), () {
      if (localErrorMessage.value == message) {
        showLocalError.value = false;
      }
    });
  }

  @override
  void onInit() {
    super.onInit();
    categoryScrollController = ScrollController();
    searchController = TextEditingController();
    searchFocusNode = FocusNode();
    _workers.add(debounce(
      searchKeyword,
      (String keyword) {
        if (keyword.isNotEmpty) fetchProducts();
      },
      time: const Duration(milliseconds: 350),
    ));

    // Auto-refresh when settings change
    if (Get.isRegistered<SettingsController>()) {
      final settings = Get.find<SettingsController>();
      _workers.addAll([
        ever(settings.operationMode, (_) => refreshDashboardData()),
        ever(settings.hostIp, (_) => refreshDashboardData()),
        ever(settings.deviceRoleRx, (_) => refreshDashboardData()),
      ]);
    }

    refreshDashboardData();
  }

  @override
  void onReady() {
    super.onReady();
    // Wait for the first frame so the dialog has an overlay to attach to
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 1), () {
        if (!isDisposed) _syncService.checkSyncReminder();
      });
    });
  }

  Future<void> refreshDashboardData() async {
    await fetchVatType();
    await fetchCategories();
    fetchFavorites();
  }

  Future<void> refreshDashboard() async {
    Get.offAllNamed(Routes.SYNC);
  }

  Future<void> fetchVatType() async {
    try {
      final String? localVat = await _dbHelper.getSetting('vat_type');
      if (localVat != null) {
        vatType.value = int.tryParse(localVat) ?? 0;
      } else if (DeviceConfig.operationMode != OperationMode.local ||
          DeviceConfig.role == DeviceRole.server) {
        final response = await _apiService.post(
          ApiEndpoints.getVatType,
          data: {"part_no": 0, "limit": 500, "sync_time": ""},
        );

        if (response.statusCode == 200) {
          final data = response.data['data'];
          if (data != null && data['vat_type'] != null) {
            vatType.value = (data['vat_type'] as num).toInt();
            await _dbHelper.saveSetting('vat_type', vatType.value.toString());
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching vat type: $e");
    }
  }

  Future<void> fetchFavorites() async {
    try {
      isLoadingFavorites.value = true;

      final localFavs = await _dbHelper.getFavorites();
      if (localFavs.isNotEmpty) {
        favorites.assignAll(
          localFavs.map((f) => FavoriteModel.fromJson(f)).toList(),
        );
      }

      if (DeviceConfig.operationMode != OperationMode.local ||
          DeviceConfig.role == DeviceRole.server) {
        final response = await _apiService.post(
          ApiEndpoints.listFavorites,
          data: {"usr_id": int.tryParse(AppState.userId) ?? 0},
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          final favList = data
              .map((json) => FavoriteModel.fromJson(json))
              .toList();
          favorites.assignAll(favList);

          await _dbHelper.insertFavorites(
            data
                .map(
                  (json) => {
                    'id': json['fav_id'] ?? json['favp_id'] ?? json['id'],
                    'name':
                        json['fav_name'] ??
                        json['favp_name'] ??
                        json['name'] ??
                        '',
                    'image':
                        json['fav_img_url'] ??
                        json['favp_img_url'] ??
                        json['image'] ??
                        '',
                  },
                )
                .toList(),
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching favorites: $e");
    } finally {
      isLoadingFavorites.value = false;
    }
  }

  Future<void> fetchAllCategoriesForPrinters() async {
    isFetchingAllCategories.value = true;
    try {
      final localData = await _dbHelper.getCategories();
      final fetchedCategories = localData
          .map(
            (json) => CategoryModel.fromJson({
              'cat_id': json['id'],
              'cat_name': json['name'],
              'cat_pos': json['cat_pos'],
              'cat_token_printer': json['token_printer_id'],
            }),
          )
          .toList();
      allCategoriesForPrinters.assignAll(fetchedCategories);
    } catch (e) {
      debugPrint("Error fetching all categories: $e");
    } finally {
      isFetchingAllCategories.value = false;
    }
  }

  Future<void> fetchCategories({bool isLoadMore = false}) async {
    isLoadingCategories.value = true;
    try {
      final localData = await _dbHelper.getCategories();
      final List<CategoryModel> fetchedCategories = localData
          .map(
            (json) => CategoryModel.fromJson({
              'cat_id': json['id'],
              'cat_name': json['name'],
              'cat_pos': json['cat_pos'],
              'cat_token_printer': json['token_printer_id'],
            }),
          )
          .toList();

      if (DeviceConfig.operationMode == OperationMode.local &&
          DeviceConfig.role == DeviceRole.client) {
        final hostIp = DeviceConfig.hostIp;
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          final hubResult = await LocalHubClient.instance.fetchMasterCategories(
            hostIp: hostIp,
            port: DeviceConfig.hostPort,
          );
          if (hubResult['success'] == true) {
            final List<dynamic> data = hubResult['data'] ?? [];
            await _dbHelper.insertCategories(data.cast<Map<String, dynamic>>());
            final updatedLocal = await _dbHelper.getCategories();
            fetchedCategories.assignAll(
              updatedLocal.map(
                (json) => CategoryModel.fromJson({
                  'cat_id': json['id'],
                  'cat_name': json['name'],
                  'cat_pos': json['cat_pos'],
                  'cat_token_printer': json['token_printer_id'],
                }),
              ),
            );
          }
        }
      } else if (DeviceConfig.operationMode == OperationMode.online ||
          DeviceConfig.role == DeviceRole.server) {
        // Online/Server: If local data is empty, try a one-time fetch from API
        if (fetchedCategories.isEmpty) {
          final response = await _apiService.post(
            ApiEndpoints.downloadCategories,
            data: {"part_no": 0, "limit": 1000, "sync_time": ""},
          );
          if (response.statusCode == 200) {
            final List<dynamic> data = response.data['data'] ?? [];
            final List<Map<String, dynamic>> mapped = data
                .map(
                  (json) => {
                    'id': (json['cat_id'] ?? '').toString(),
                    'name': (json['cat_name'] ?? '').toString(),
                    'cat_pos': (json['cat_pos'] ?? '').toString(),
                    'token_printer_id': (json['cat_token_printer'] as num? ?? 0)
                        .toInt(),
                    'sort_order': 0,
                  },
                )
                .toList();
            await _dbHelper.insertCategories(mapped);
            fetchedCategories.assignAll(
              mapped.map(
                (json) => CategoryModel.fromJson({
                  'cat_id': json['id'],
                  'cat_name': json['name'],
                  'cat_pos': json['cat_pos'],
                  'cat_token_printer': json['token_printer_id'],
                }),
              ),
            );
          }
        }
      }

      final posCategories = fetchedCategories
          .where((cat) => cat.cat_pos == "1")
          .toList();

      categories.clear();
      categories.add(
        CategoryModel(id: '', name: 'All', cat_pos: '1', tokenPrinterId: 0),
      );

      categories.addAll(posCategories);

      if (selectedCategoryId.isEmpty) {
        selectedCategoryId.value = '';
        fetchProducts();
      }

      allCategoriesForPrinters.assignAll(fetchedCategories);
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    } finally {
      isLoadingCategories.value = false;
    }
  }

  Future<void> fetchProducts() async {
    if (isDisposed) return;
    final request = ++_productRequest;
    final pgId = cartController.selectedPriceGroupId.value;
    final categoryId = selectedCategoryId.value;
    final keyword = searchKeyword.value;
    final favoriteId = selectedFavoriteId.value;
    final mode = DeviceConfig.operationMode;
    final role = DeviceConfig.role;
    final hostIp = DeviceConfig.hostIp;
    final hostPort = DeviceConfig.hostPort;
    bool isCurrent() =>
        !isDisposed &&
        request == _productRequest &&
        pgId == cartController.selectedPriceGroupId.value &&
        categoryId == selectedCategoryId.value &&
        keyword == searchKeyword.value &&
        favoriteId == selectedFavoriteId.value &&
        mode == DeviceConfig.operationMode &&
        role == DeviceConfig.role &&
        hostIp == DeviceConfig.hostIp &&
        hostPort == DeviceConfig.hostPort;

    isLoadingProducts.value = true;
    try {
      log("DASHBOARD_CTRL: fetchProducts called with pgId=$pgId, categoryId='${categoryId}', search='${keyword}', orderType=${AppState.orderType.name}");

      Future<bool> loadLocalProducts() async {
        List<Map<String, dynamic>> localProducts;
        if (favoriteId != null) {
          localProducts = await _dbHelper.getFavoriteProducts(
            favoriteId,
            pgId,
            searchQuery: keyword.isNotEmpty ? keyword : null,
          );
        } else if (keyword.isNotEmpty) {
          localProducts = await _dbHelper.searchProducts(
            keyword,
            priceGroupId: pgId,
          );
        } else {
          localProducts = await _dbHelper.getProducts(
            categoryId: categoryId,
            priceGroupId: pgId,
          );
        }

        log("DASHBOARD_CTRL: loadLocalProducts found ${localProducts.length} items for pgId=$pgId");

        final mappedProducts = localProducts
            .map(
              (json) => FoodItemModel.fromJson({
                'prd_id': json['id']?.toString() ?? '',
                'prd_name': json['name'] ?? '',
                'prd_cat_id': json['category_id']?.toString() ?? '',
                'sale_rate':
                    double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
                'prd_tax': json['prd_tax'] ?? 0,
                'prd_img_url': json['image'] ?? '',
                'unit_display': json['unit_display']?.toString() ?? '',
                'prd_tax_cat_id': json['tax_cat_id'],
                'tax_per': json['tax_per'],
                'cat_token_printer': json['cat_token_printer'],
                'prd_is_veg': json['is_veg'],
              }),
            )
            .toList();

        if (isCurrent()) filteredFoodItems.assignAll(mappedProducts);
        return mappedProducts.isEmpty;
      }

      final localResultsEmpty = await loadLocalProducts();
      if (!isCurrent()) return;

      if (mode == OperationMode.local &&
          role == DeviceRole.client) {
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          final hubResult = await LocalHubClient.instance.fetchMasterProducts(
            hostIp: hostIp,
            port: hostPort,
            categoryId: categoryId.isNotEmpty
                ? categoryId
                : null,
            priceGroupId: pgId,
          );
          if (!isCurrent()) return;
          if (hubResult['success'] == true) {
            final List<dynamic> data = hubResult['data'] ?? [];
            await _dbHelper.insertProducts(data.cast<Map<String, dynamic>>());
            await loadLocalProducts();
          }
        }
      } else if ((mode == OperationMode.online ||
              role == DeviceRole.server) &&
          localResultsEmpty) {
        // Online fallback: fetch current category/favorites if local DB is empty
        final response = await _apiService.post(
          ApiEndpoints.getProducts,
          data: {
            "usr_id": int.tryParse(AppState.userId) ?? 0,
            "price_group_id": pgId,
            "category_id": categoryId.isNotEmpty
                ? int.tryParse(categoryId)
                : 0,
            "fav_id": keyword.isNotEmpty ? 0 : (favoriteId ?? 0),
            "keyword": keyword,
          },
        );
        if (!isCurrent()) return;
        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          final String baseUrl = response.data['url']?.toString() ?? "";
          final mapped = data.map((json) {
            String imgUrl = json['prd_img_url']?.toString() ?? '';
            if (imgUrl.isNotEmpty &&
                baseUrl.isNotEmpty &&
                !imgUrl.startsWith('http')) {
              imgUrl = baseUrl + imgUrl;
            }
            return {
              'id': (json['prd_id'] ?? '').toString(),
              'price_group_id': pgId,
              'name': (json['prd_name'] ?? '').toString(),
              'category_id': (json['prd_cat_id']?.toString() ??
                  (categoryId.isNotEmpty
                      ? categoryId
                      : '')),
              'price': (json['sale_rate'] as num? ?? 0.0).toDouble(),
              'prd_tax': (json['prd_tax'] as num? ?? 0.0).toDouble(),
              'image': imgUrl,
              'unit_display': (json['unit_display'] ?? '').toString(),
              'tax_cat_id': (json['prd_tax_cat_id'] as num? ?? 0).toInt(),
              'tax_per': (json['tax_per'] as num? ?? 0.0).toDouble(),
              'is_veg':
                  int.tryParse(json['prd_is_veg']?.toString() ?? "0") ?? 0,
              'sort_order': 0,
            };
          }).toList();
          await _dbHelper.insertProducts(mapped);
          await loadLocalProducts();
        }
      }
    } catch (e) {
      debugPrint("Error fetching products: $e");
    } finally {
      if (!isDisposed && request == _productRequest) {
        isLoadingProducts.value = false;
      }
    }
  }

  Future<ProductUnit> _applyStockRateOverride(
    ProductUnit unit,
    int productId,
    int pgId,
  ) async {
    final Map<String, double>? rateMap = await _dbHelper.getStockUnitRate(
      productId,
      unit.unitId,
      pgId,
    );

    if (rateMap != null) {
      double customRate = rateMap['sur_unit_rate'] ?? 0.0;
      if (customRate <= 0) {
        customRate = rateMap['sur_unit_rate2'] ?? 0.0;
      }
      if (customRate > 0) {
        log("DASHBOARD_CTRL: Stock rate override applied for prdId=$productId, unitId=${unit.unitId}, pgId=$pgId -> rate: $customRate");
        return ProductUnit(
          unitId: unit.unitId,
          unitName: unit.unitName,
          unitDisplay: unit.unitDisplay,
          rate: customRate,
          unitBaseQty: unit.unitBaseQty,
          existAddOns: unit.existAddOns,
        );
      }
    }
    log("DASHBOARD_CTRL: No stock rate override applied for prdId=$productId, unitId=${unit.unitId}, pgId=$pgId -> using unit rate: ${unit.rate}");
    return unit;
  }

  void onProductTapped(FoodItemModel product, {CartItem? existingItem}) async {
    if (Get.find<CartController>().blockIfProcessing()) return;
    if (isLoadingDetails.value) return;
    if (AppState.orderType.id == 0 && !cartController.hasSelectedTable) {
      showError("table_required".tr, "select_table_msg".tr);
      return;
    }

    try {
      isLoadingDetails.value = true;

      final int productId = int.tryParse(product.id) ?? 0;
      final int pgId = cartController.selectedPriceGroupId.value;

      final List<Map<String, dynamic>> localBulkUnits = await _dbHelper
          .getBulkProductUnits(productId);
      if (localBulkUnits.isNotEmpty) {
        productUnits.clear();
        commonAddons.clear();

        for (var u in localBulkUnits) {
          final unit = ProductUnit.fromJson(u);
          ProductUnit resolvedUnit = await _applyStockRateOverride(
            unit,
            productId,
            pgId,
          );
          if (resolvedUnit.rate <= 0) {
            resolvedUnit = resolvedUnit.copyWith(
              rate: product.price * resolvedUnit.unitBaseQty,
            );
          }
          productUnits.add(resolvedUnit);

          if (commonAddons.isEmpty) {
            final String? commonJson = u['common_addons'];
            if (commonJson != null && commonJson.isNotEmpty) {
              try {
                final List<dynamic> commonList = jsonDecode(commonJson);
                commonAddons.assignAll(
                  commonList
                      .where(
                        (e) => (e['prdaddon_flags'] as num? ?? 1).toInt() != 0,
                      )
                      .map((e) {
                        e['commonAddon'] = true;
                        return AddonModel.fromJson(e);
                      })
                      .toList(),
                );
              } catch (_) {}
            }
          }
        }

        if (productUnits.isNotEmpty) {
          _showProductDetails(product, existingItem);
          return;
        }
      }

      final response = await _apiService.post(
        ApiEndpoints.getPosProductUnitsAndAddons,
        data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
          "prd_id": productId,
          "price_group_id": pgId,
        },
      );

      if (response.statusCode == 200) {
        final data = (response.data['data'] as List? ?? [])
            .where((e) => parseInt(e['produnit_flag'], defaultValue: 1) != 0)
            .toList();
        final common = response.data['commonAddon'] as List? ?? [];

        final List<ProductUnit> resolvedUnits = [];
        for (var e in data) {
          final unit = ProductUnit.fromJson(e);
          resolvedUnits.add(
            await _applyStockRateOverride(unit, productId, pgId),
          );
        }
        productUnits.assignAll(resolvedUnits);

        commonAddons.assignAll(
          common
              .where((e) => (e['prdaddon_flags'] as num? ?? 1).toInt() != 0)
              .map((e) {
                e['commonAddon'] = true;
                return AddonModel.fromJson(e);
              })
              .toList(),
        );

        _showProductDetails(product, existingItem);
      }
    } catch (e) {
      debugPrint("Error fetching product details: $e");
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void _showProductDetails(FoodItemModel product, CartItem? existingItem) {
    if (productUnits.isNotEmpty) {
      if (existingItem == null &&
          productUnits.length == 1 &&
          productUnits.first.existAddOns.isEmpty &&
          commonAddons.isEmpty) {
        cartController.addItemWithDetails(product, productUnits.first, []);
        return;
      }

      if (existingItem != null) {
        selectedUnit.value = productUnits.firstWhere(
          (u) => u.unitId == existingItem.unit.unitId,
          orElse: () => productUnits.first,
        );

        for (var addon in selectedUnit.value!.existAddOns) {
          final existingAddon = existingItem.selectedAddons.firstWhereOrNull(
            (a) => a.prdId == addon.prdId,
          );
          addon.quantity.value = existingAddon?.quantity.value ?? 0;
        }

        for (var addon in commonAddons) {
          final existingAddon = existingItem.selectedAddons.firstWhereOrNull(
            (a) => a.prdId == addon.prdId,
          );
          addon.quantity.value = existingAddon?.quantity.value ?? 0;
        }
      } else {
        selectedUnit.value = productUnits.first;
        for (var u in productUnits) {
          for (var a in u.existAddOns) {
            a.quantity.value = a.freeQty;
          }
        }
        for (var a in commonAddons) {
          a.quantity.value = 0;
        }
      }
      Get.dialog(
        ProductDetailsDialog(product: product, existingItem: existingItem),
      );
    }
  }

  void selectCategory(String categoryId) {
    if (selectedCategoryId.value == categoryId) return;
    selectedCategoryId.value = categoryId;
    fetchProducts();
  }

  void triggerManualSync() {
    _syncService.syncPendingOrders();
  }

  void updateSearch(String value) {
    String trimmed = value.trim();
    if (searchKeyword.value == trimmed) return;

    searchKeyword.value = trimmed;
    if (trimmed.isNotEmpty) {
      _productRequest++;
      isLoadingProducts.value = true;
    }
    if (trimmed.isEmpty) {
      fetchProducts();
    }
  }

  void setFavorite(int? id) {
    if (selectedFavoriteId.value == id) {
      selectedFavoriteId.value = null;
    } else {
      selectedFavoriteId.value = id;
    }
    fetchProducts();
  }

  @override
  void onClose() {
    isDisposed = true;
    for (final worker in _workers) {
      worker.dispose();
    }
    searchFocusNode.dispose();
    searchController.dispose();
    categoryScrollController.dispose();
    super.onClose();
  }
}
