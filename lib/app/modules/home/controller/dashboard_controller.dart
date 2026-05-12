import 'dart:convert';
import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:restaurant_pos/app/data/models/order_model.dart';
import 'package:restaurant_pos/app/data/models/order_type.dart';
import '../../../../helper/snackbar_helper.dart';
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

  // Dedicated list for all categories (used by PrinterController for token mappings)
  final allCategoriesForPrinters = <CategoryModel>[].obs;
  final isFetchingAllCategories = false.obs;

  final selectedCategoryId = ''.obs;
  final isLoadingCategories = false.obs;
  final isMoreLoadingCategories = false.obs;
  final hasMoreCategories = true.obs;
  
  // UI Controllers
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

  // Vat Type Setting
  final vatType = 0.obs;

  // Sync Status
  RxBool get isSyncing => _syncService.isSyncing;
  bool isDisposed = false;

  @override
  void onInit() {
    super.onInit();
    categoryScrollController = ScrollController();
    searchController = TextEditingController();
    searchFocusNode = FocusNode();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
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
      } else {
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
        favorites.assignAll(localFavs.map((f) => FavoriteModel.fromJson({
          'favp_id': f['id'],
          'favp_name': f['name'],
          'favp_img_url': f['image'],
        })).toList());
      } else {
        final response = await _apiService.post("mobileapp/pos/list_favorite", data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
        });

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          final favList = data.map((json) => FavoriteModel.fromJson(json)).toList();
          favorites.assignAll(favList);

          await _dbHelper.insertFavorites(data.map((json) => {
            'id': json['fav_id'],
            'name': json['fav_name'],
            'image': json['fav_img_url'] ?? '',
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

      final fetchedCategories = localData.map((json) => CategoryModel.fromJson({
        'cat_id': json['id'],
        'cat_name': json['name'],
        'cat_pos': json['cat_pos'],
        'cat_token_printer': json['token_printer_id'],
      })).toList();

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
      debugPrint("Error fetching categories from DB: $e");
    } finally {
      isLoadingCategories.value = false;
    }
  }

  Future<void> fetchProducts() async {
    isLoadingProducts.value = true;
    filteredFoodItems.clear();

    try {
      if (selectedFavoriteId.value != null) {
        final response = await _apiService.post("mobileapp/pos/get_product_list", data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
          "fav_id": selectedFavoriteId.value,
          "price_group_id": cartController.selectedPriceGroupId.value,
        });

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          final String imageBaseUrl = response.data['url']?.toString() ?? "";
          final fetchedProducts = data.map((json) => FoodItemModel.fromJson(json, baseUrl: imageBaseUrl)).toList();
          filteredFoodItems.assignAll(fetchedProducts);
        }
      } else {
        List<Map<String, dynamic>> localProducts;
        final pgId = cartController.selectedPriceGroupId.value;

        if (searchKeyword.value.isNotEmpty) {
          localProducts = await _dbHelper.searchProducts(searchKeyword.value, priceGroupId: pgId);
        } else {
          localProducts = await _dbHelper.getProducts(categoryId: selectedCategoryId.value, priceGroupId: pgId);
        }

        final fetchedProducts = localProducts.map((json) => FoodItemModel.fromJson({
          'prd_id': json['id'],
          'prd_name': json['name'],
          'prd_cat_id': json['category_id'],
          'sale_rate': json['price'],
          'prd_tax': json['prd_tax'],
          'prd_img_url': json['image'],
          'unit_display': json['unit_display'],
          'prd_tax_cat_id': json['tax_cat_id'],
          'tax_per': json['tax_per'],
          'cat_token_printer': json['cat_token_printer'],
        })).toList();

        filteredFoodItems.assignAll(fetchedProducts);
      }
    } catch (e) {
      debugPrint("Error fetching products: $e");
    } finally {
      isLoadingProducts.value = false;
    }
  }

  Future<ProductUnit> _applyStockRateOverride(ProductUnit unit, int productId, int pgId) async {
    log("🔍 getStockUnitRate → prd_id: $productId, unit_id: ${unit.unitId}, pg_id: $pgId");

    final Map<String, double>? rateMap = await _dbHelper.getStockUnitRate(productId, unit.unitId, pgId);

    log("📦 rateMap result: $rateMap");

    if (rateMap != null) {
      double customRate = rateMap['sur_unit_rate'] ?? 0.0;
      if (customRate <= 0) {
        customRate = rateMap['sur_unit_rate2'] ?? 0.0;
      }
      log("💰 customRate resolved: $customRate");
      if (customRate > 0) {
        log("✅ Overriding unit ${unit.unitId} rate → $customRate");
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
    log("⚠️ No override applied for unit ${unit.unitId}, keeping rate: ${unit.rate}");
    return unit;
  }

  void onProductTapped(FoodItemModel product, {CartItem? existingItem}) async {
    if (isLoadingDetails.value) return;

    // ✅ Table/Chair validation only required for Dine-In (id: 0)
    if (AppState.orderType.id == 0 && !cartController.hasSelectedTable) {
      showSafeSnackbar("table_required".tr, "select_table_msg".tr);
      return;
    }

    try {
      isLoadingDetails.value = true;

      final int productId = int.tryParse(product.id) ?? 0;
      final int pgId = cartController.selectedPriceGroupId.value;

      // 1. Load from local bulk DB
      final List<Map<String, dynamic>> localBulkUnits = await _dbHelper.getBulkProductUnits(productId);

      if (localBulkUnits.isNotEmpty) {
        log("DashboardController: Loaded units from Local Bulk DB");
        productUnits.clear();
        commonAddons.clear();

        for (var u in localBulkUnits) {
          final unit = ProductUnit.fromJson(u);

          // ✅ Apply stock rate override for BOTH pgId AND pgId=0 as fallback
          ProductUnit resolvedUnit = await _applyStockRateOverride(unit, productId, pgId);
          if (resolvedUnit.rate <= 0 && pgId != 0) {
            resolvedUnit = await _applyStockRateOverride(unit, productId, 0);
          }
          productUnits.add(resolvedUnit);

          // Load common addons once
          if (commonAddons.isEmpty) {
            final String? commonJson = u['common_addons'];
            if (commonJson != null && commonJson.isNotEmpty) {
              try {
                final List<dynamic> commonList = jsonDecode(commonJson);
                commonAddons.assignAll(commonList.where((e) {
                  final flag = (e['prdaddon_flags'] as num? ?? 1).toInt();
                  return flag != 0;
                }).map((e) {
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

      // 2. Fallback to API
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

        // ✅ Apply stock rate override to API units too
        final List<ProductUnit> resolvedUnits = [];
        for (var e in data) {
          final unit = ProductUnit.fromJson(e);
          ProductUnit resolvedUnit = await _applyStockRateOverride(unit, productId, pgId);
          if (resolvedUnit.rate <= 0 && pgId != 0) {
            resolvedUnit = await _applyStockRateOverride(unit, productId, 0);
          }
          resolvedUnits.add(resolvedUnit);
        }
        productUnits.assignAll(resolvedUnits);

        commonAddons.assignAll(common.where((e) {
          final flag = (e['prdaddon_flags'] as num? ?? 1).toInt();
          return flag != 0;
        }).map((e) {
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
          for (var a in u.existAddOns) { a.quantity.value = 0; }
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
    searchKeyword.value = value;
    fetchProducts();
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
    // Safely unfocus before disposal to prevent "attached" errors
    searchFocusNode.unfocus();
    
    // We remove manual disposal of TextEditingController and ScrollController 
    // because it often conflicts with the widget tree lifecycle in GetX during transitions.
    // They will be cleaned up when the controller instance is garbage collected.

    super.onClose();
  }
}
