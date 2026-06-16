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
        favorites.assignAll(localFavs.map((f) => FavoriteModel.fromJson(f)).toList());
      } else {
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
      final pgId = cartController.selectedPriceGroupId.value;

      if (selectedFavoriteId.value != null) {
        final List<Map<String, dynamic>> localFavProducts =
        await _dbHelper.getFavoriteProducts(selectedFavoriteId.value!, pgId);

        if (localFavProducts.isNotEmpty) {
          final fetchedProducts = localFavProducts.map((json) => FoodItemModel.fromJson(json)).toList();
          filteredFoodItems.assignAll(fetchedProducts);
        } else {
          final response = await _apiService.post("mobileapp/pos/get_product_list", data: {
            "usr_id": int.tryParse(AppState.userId) ?? 0,
            "fav_id": selectedFavoriteId.value,
            "price_group_id": pgId,
          });

          if (response.statusCode == 200) {
            final List<dynamic> data = response.data['data'] ?? [];
            final String imageBaseUrl = response.data['url']?.toString() ?? "";
            final fetchedProducts = data.map((json) => FoodItemModel.fromJson(json, baseUrl: imageBaseUrl)).toList();
            filteredFoodItems.assignAll(fetchedProducts);
          }
        }
      } else {
        List<Map<String, dynamic>> localProducts;

        if (searchKeyword.value.isNotEmpty) {
          localProducts = await _dbHelper.searchProducts(searchKeyword.value, priceGroupId: pgId);
        } else {
          localProducts = await _dbHelper.getProducts(categoryId: selectedCategoryId.value, priceGroupId: pgId);
        }

        final fetchedProducts = localProducts.map((json) {
          // Safe mapping to ensure no null types break the model
          return FoodItemModel.fromJson({
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
          });
        }).toList();

        filteredFoodItems.assignAll(fetchedProducts);
      }
    } catch (e) {
      debugPrint("Error fetching products: $e");
    } finally {
      isLoadingProducts.value = false;
    }
  }


  Future<double?> _getOverrideRate(int productId, int unitId, int pgId) async {
    final Map<String, double>? rateMap = await _dbHelper.getStockUnitRate(productId, unitId, pgId);
    if (rateMap != null) {
      double customRate = rateMap['sur_unit_rate'] ?? 0.0;
      if (customRate <= 0) {
        customRate = rateMap['sur_unit_rate2'] ?? 0.0;
      }
      if (customRate > 0) return customRate;
    }
    return null;
  }

  void onProductTapped(FoodItemModel product, {CartItem? existingItem}) async {
    if (isLoadingDetails.value) return;

    log("onProductTapped: ${product.name} (ID: ${product.id})");

    if (AppState.orderType.id == 0 && !cartController.hasSelectedTable) {
      showSafeSnackbar("table_required".tr, "select_table_msg".tr);
      return;
    }

    try {
      isLoadingDetails.value = true;

      // Use String for product units query and Int for bulk query to cover all DB schemas
      final String productIdStr = product.id.toString();
      final int productIdInt = int.tryParse(productIdStr) ?? 0;
      final int pgId = cartController.selectedPriceGroupId.value;

      productUnits.clear();
      commonAddons.clear();

      // ─── 1. Bulk product units table ────────────────────────────────────────
      final List<Map<String, dynamic>> localBulkUnits = await _dbHelper.getBulkProductUnits(productIdInt);

      if (localBulkUnits.isNotEmpty) {
        for (var u in localBulkUnits) {
          final unit = ProductUnit.fromJson(u);
          double? overrideRate = await _getOverrideRate(productIdInt, unit.unitId, pgId);
          if (overrideRate == null && pgId != 0) {
            overrideRate = await _getOverrideRate(productIdInt, unit.unitId, 0);
          }
          double finalRate = overrideRate ?? unit.rate;
          if (finalRate <= 0) finalRate = product.price * unit.unitBaseQty;

          productUnits.add(unit.copyWith(rate: finalRate));

          // Load common addons once
          if (commonAddons.isEmpty && u['common_addons'] != null) {
            try {
              final List<dynamic> commonList = jsonDecode(u['common_addons']);
              commonAddons.assignAll(commonList.map((e) {
                e['commonAddon'] = true;
                return AddonModel.fromJson(e);
              }));
            } catch (_) {}
          }
        }
      }

      // ─── 2. Fallback: product_units table (With Price Group Fallback) ─────────
      if (productUnits.isEmpty) {
        log("Trying product_units table for $productIdStr with PG $pgId");
        List<Map<String, dynamic>> localPgUnits = await _dbHelper.getProductUnits(productIdStr, pgId);
        log("=== OFFLINE UNIT DEBUG for ${product.name} (id: ${product.id}) ===");
        log("productIdInt: $productIdInt, pgId: $pgId");

// Check what's actually in the DB
        final bulkCheck = await _dbHelper.getBulkProductUnits(productIdInt);
        log("bulk_product_units rows: ${bulkCheck.length}");
        for (var r in bulkCheck) {
          log("  produnit_id=${r['produnit_id']} produnit_prod_id=${r['produnit_prod_id']} rate=${r['rate']} common_addons=${r['common_addons']}");
        }

        final pgCheck = await _dbHelper.getProductUnits(product.id, pgId);
        log("product_units rows (pg=$pgId): ${pgCheck.length}");

        final pg0Check = await _dbHelper.getProductUnits(product.id, 0);
        log("product_units rows (pg=0): ${pg0Check.length}");
        // FIX: If no units found for specific price group, try default price group (0)
        if (localPgUnits.isEmpty && pgId != 0) {
          log("No units for PG $pgId, falling back to PG 0");
          localPgUnits = await _dbHelper.getProductUnits(productIdStr, 0);
        }

        if (localPgUnits.isNotEmpty) {
          for (var u in localPgUnits) {
            final unit = ProductUnit.fromJson(u);
            double? overrideRate = await _getOverrideRate(productIdInt, unit.unitId, pgId);
            if (overrideRate == null && pgId != 0) {
              overrideRate = await _getOverrideRate(productIdInt, unit.unitId, 0);
            }
            double finalRate = overrideRate ?? unit.rate;
            if (finalRate <= 0) finalRate = product.price * unit.unitBaseQty;

            productUnits.add(unit.copyWith(rate: finalRate));
          }

          // Load common addons from dedicated table for this fallback path
          final List<Map<String, dynamic>> dbCommonAddons = await _dbHelper.getCommonAddons();
          if (dbCommonAddons.isNotEmpty) {
            commonAddons.assignAll(dbCommonAddons.map((e) {
              var m = Map<String, dynamic>.from(e);
              m['commonAddon'] = true;
              return AddonModel.fromJson(m);
            }));
          }
        }
      }

      // ─── 3. Fallback: API (Only if offline fails) ───────────────────────────
      if (productUnits.isEmpty) {
        try {
          final response = await _apiService.post("mobileapp/pos/get_product_unit_and_addon", data: {
            "usr_id": int.tryParse(AppState.userId) ?? 0,
            "prd_id": productIdInt,
            "price_group_id": pgId,
          }).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = response.data['data'] as List? ?? [];
            for (var e in data) {
              final unit = ProductUnit.fromJson(e);
              productUnits.add(unit);
            }
          }
        } catch (e) {
          log("Offline: API unit fetch skipped or failed.");
        }
      }

      // ─── 4. Last resort: Synthetic unit (Guarantees the product is clickable) ──
      if (productUnits.isEmpty) {
        log("Creating emergency synthetic unit for ${product.name}");
        // Even if price is 0, we add a unit so the item can be added to cart (e.g., open price items)
        productUnits.add(ProductUnit(
          unitId: 0,
          unitName: (product.unitDisplay.isEmpty) ? "Unit" : product.unitDisplay,
          unitDisplay: (product.unitDisplay.isEmpty) ? "Unit" : product.unitDisplay,
          rate: product.price,
          unitBaseQty: 1.0,
          existAddOns: [],
        ));
      }

      if (productUnits.isNotEmpty) {
        _showProductDetails(product, existingItem);
      } else {
        showSafeSnackbar("Error", "Could not load units for ${product.name}");
      }
    } catch (e) {
      log("onProductTapped Unexpected Error: $e");
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void _showProductDetails(FoodItemModel product, CartItem? existingItem) {
    if (productUnits.isNotEmpty) {
      log("_showProductDetails: Showing details for ${product.name}");
      if (existingItem == null &&
          productUnits.length == 1 &&
          productUnits.first.existAddOns.isEmpty &&
          commonAddons.isEmpty) {
        log("_showProductDetails: Direct add to cart");
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
    searchFocusNode.unfocus();
    super.onClose();
  }
}