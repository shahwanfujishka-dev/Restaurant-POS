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
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../views/dashoard/models/dashboard_models.dart';
import '../views/dashoard/widgets/product_details_dialog.dart';

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
    debounce(searchKeyword, (_) => fetchProducts(), time: const Duration(milliseconds: 350));
    refreshDashboardData();
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
      } else if (DeviceConfig.operationMode != OperationMode.local || DeviceConfig.role == DeviceRole.server) {
        final response = await _apiService.post("mobileapp/sales_settings/vat_type", data: {
          "part_no": 0,
          "limit": 500,
          "sync_time": "",
        });

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
        favorites.assignAll(localFavs.map((f) => FavoriteModel.fromJson(f)).toList());
      } 
      
      if (DeviceConfig.operationMode != OperationMode.local || DeviceConfig.role == DeviceRole.server) {
        final response = await _apiService.post("mobileapp/pos/list_favorite", data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
        });

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          final favList = data.map((json) => FavoriteModel.fromJson(json)).toList();
          favorites.assignAll(favList);

          await _dbHelper.insertFavorites(data.map((json) => {
            'id': json['fav_id'] ?? json['favp_id'] ?? json['id'],
            'name': json['fav_name'] ?? json['favp_name'] ?? json['name'] ?? '',
            'image': json['fav_img_url'] ?? json['favp_img_url'] ?? json['image'] ?? '',
          }).toList());
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
      final fetchedCategories = localData.map((json) => CategoryModel.fromJson({
        'cat_id': json['id'],
        'cat_name': json['name'],
        'cat_pos': json['cat_pos'],
        'cat_token_printer': json['token_printer_id'],
      })).toList();
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
      final List<CategoryModel> fetchedCategories = localData.map((json) => CategoryModel.fromJson({
        'cat_id': json['id'],
        'cat_name': json['name'],
        'cat_pos': json['cat_pos'],
        'cat_token_printer': json['token_printer_id'],
      })).toList();

      if (DeviceConfig.operationMode == OperationMode.local && DeviceConfig.role == DeviceRole.client) {
        final hostIp = DeviceConfig.hostIp;
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          final hubResult = await LocalHubClient.instance.fetchMasterCategories(hostIp: hostIp, port: DeviceConfig.hostPort);
          if (hubResult['success'] == true) {
            final List<dynamic> data = hubResult['data'] ?? [];
            await _dbHelper.insertCategories(data.cast<Map<String, dynamic>>());
            final updatedLocal = await _dbHelper.getCategories();
            fetchedCategories.assignAll(updatedLocal.map((json) => CategoryModel.fromJson({
              'cat_id': json['id'],
              'cat_name': json['name'],
              'cat_pos': json['cat_pos'],
              'cat_token_printer': json['token_printer_id'],
            })));
          }
        }
      }

      final posCategories = fetchedCategories.where((cat) => cat.cat_pos == "1").toList();

      categories.clear();
      categories.add(CategoryModel(
        id: '',
        name: 'All',
        cat_pos: '1',
        tokenPrinterId: 0,
      ));

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
    isLoadingProducts.value = true;
    try {
      final pgId = cartController.selectedPriceGroupId.value;

      Future<void> loadLocalProducts() async {
        List<Map<String, dynamic>> localProducts;
        if (selectedFavoriteId.value != null) {
          localProducts = await _dbHelper.getFavoriteProducts(selectedFavoriteId.value!, pgId);
        } else if (searchKeyword.value.isNotEmpty) {
          localProducts = await _dbHelper.searchProducts(searchKeyword.value, priceGroupId: pgId);
        } else {
          localProducts = await _dbHelper.getProducts(categoryId: selectedCategoryId.value, priceGroupId: pgId);
        }

        final mappedProducts = localProducts.map((json) => FoodItemModel.fromJson({
          'prd_id': json['id']?.toString() ?? '',
          'prd_name': json['name'] ?? '',
          'prd_cat_id': json['category_id']?.toString() ?? '',
          'sale_rate': double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
          'prd_tax': json['prd_tax'] ?? 0,
          'prd_img_url': json['image'] ?? '',
          'unit_display': json['unit_display']?.toString() ?? '',
          'prd_tax_cat_id': json['tax_cat_id'],
          'tax_per': json['tax_per'],
          'cat_token_printer': json['cat_token_printer'],
          'prd_is_veg': json['is_veg'],
        })).toList();
        
        filteredFoodItems.assignAll(mappedProducts);
      }

      await loadLocalProducts();

      if (DeviceConfig.operationMode == OperationMode.local && DeviceConfig.role == DeviceRole.client) {
        final hostIp = DeviceConfig.hostIp;
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          final hubResult = await LocalHubClient.instance.fetchMasterProducts(
            hostIp: hostIp, 
            port: DeviceConfig.hostPort,
            categoryId: selectedCategoryId.value.isNotEmpty ? selectedCategoryId.value : null,
            priceGroupId: pgId,
          );
          if (hubResult['success'] == true) {
            final List<dynamic> data = hubResult['data'] ?? [];
            await _dbHelper.insertProducts(data.cast<Map<String, dynamic>>());
            await loadLocalProducts();
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching products: $e");
    } finally {
      isLoadingProducts.value = false;
    }
  }

  Future<ProductUnit> _applyStockRateOverride(ProductUnit unit, int productId, int pgId) async {
    final Map<String, double>? rateMap = await _dbHelper.getStockUnitRate(productId, unit.unitId, pgId);

    if (rateMap != null) {
      double customRate = rateMap['sur_unit_rate'] ?? 0.0;
      if (customRate <= 0) {
        customRate = rateMap['sur_unit_rate2'] ?? 0.0;
      }
      if (customRate > 0) {
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
    return unit;
  }

  void onProductTapped(FoodItemModel product, {CartItem? existingItem}) async {
    if (isLoadingDetails.value) return;

    if (AppState.orderType.id == 0 && !cartController.hasSelectedTable) {
      showError("table_required".tr, "select_table_msg".tr);
      return;
    }

    try {
      isLoadingDetails.value = true;

      final int productId = int.tryParse(product.id) ?? 0;
      final int pgId = cartController.selectedPriceGroupId.value;

      final List<Map<String, dynamic>> localBulkUnits = await _dbHelper.getBulkProductUnits(productId);
      if (localBulkUnits.isNotEmpty) {
        productUnits.clear();
        commonAddons.clear();

        for (var u in localBulkUnits) {
          final unit = ProductUnit.fromJson(u);
          ProductUnit resolvedUnit = await _applyStockRateOverride(unit, productId, pgId);
          if (resolvedUnit.rate <= 0) {
            resolvedUnit = resolvedUnit.copyWith(rate: product.price * resolvedUnit.unitBaseQty);
          }
          productUnits.add(resolvedUnit);

          if (commonAddons.isEmpty) {
            final String? commonJson = u['common_addons'];
            if (commonJson != null && commonJson.isNotEmpty) {
              try {
                final List<dynamic> commonList = jsonDecode(commonJson);
                commonAddons.assignAll(commonList.where((e) => (e['prdaddon_flags'] as num? ?? 1).toInt() != 0).map((e) {
                  e['commonAddon'] = true;
                  return AddonModel.fromJson(e);
                }).toList());
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
        "mobileapp/pos/get_product_unit_and_addon",
        data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
          "prd_id": productId,
          "price_group_id": pgId,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as List? ?? [];
        final common = response.data['commonAddon'] as List? ?? [];

        final List<ProductUnit> resolvedUnits = [];
        for (var e in data) {
          final unit = ProductUnit.fromJson(e);
          resolvedUnits.add(await _applyStockRateOverride(unit, productId, pgId));
        }
        productUnits.assignAll(resolvedUnits);

        commonAddons.assignAll(common.where((e) => (e['prdaddon_flags'] as num? ?? 1).toInt() != 0).map((e) {
          e['commonAddon'] = true;
          return AddonModel.fromJson(e);
        }).toList());

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
            orElse: () => productUnits.first
        );

        for (var addon in selectedUnit.value!.existAddOns) {
          final existingAddon = existingItem.selectedAddons.firstWhereOrNull((a) => a.prdId == addon.prdId);
          addon.quantity.value = existingAddon?.quantity.value ?? 0;
        }

        for (var addon in commonAddons) {
          final existingAddon = existingItem.selectedAddons.firstWhereOrNull((a) => a.prdId == addon.prdId);
          addon.quantity.value = existingAddon?.quantity.value ?? 0;
        }
      } else {
        selectedUnit.value = productUnits.first;
        for (var u in productUnits) {
          for (var a in u.existAddOns) {
            a.quantity.value = a.freeQty;
          }
        }
        for (var a in commonAddons) { a.quantity.value = 0; }
      }
      Get.dialog(ProductDetailsDialog(product: product, existingItem: existingItem));
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
    searchFocusNode.unfocus();
    super.onClose();
  }
}
