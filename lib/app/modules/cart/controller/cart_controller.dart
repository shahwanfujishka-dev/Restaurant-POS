import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math; // Fixed conflict with log()
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart'; // Import SyncService
import '../../../data/utils/AppState.dart';
import 'package:get_storage/get_storage.dart';

import '../../home/controller/dashboard_controller.dart';
import '../../home/controller/table_controller.dart';
import '../../home/views/dashoard/models/dashboard_models.dart';

class CartItem {
  final int? subId;
  final int? addonprntId;
  final int? addonuntId;
  final int? originalUnitId; // Store original unit ID from order
  final double? originalBaseQty; // Store original unit's base_qty
  final FoodItemModel product;
  ProductUnit unit;
  List<AddonModel> selectedAddons;
  List<AddonModel>? originalAddons; // Track original addons from order
  final RxInt quantity;
  final int initialQty;
  final RxDouble priceAtAdd = 0.0.obs;
  final RxBool isDeleted = false.obs;

  CartItem({
    this.subId,
    this.addonprntId,
    this.addonuntId,
    this.originalUnitId,
    this.originalBaseQty,
    required this.product,
    required this.unit,
    this.selectedAddons = const [],
    this.originalAddons,
    int qty = 1,
    int? initialQty,
    double? priceAtAdd,
    bool deleted = false,
  }) : quantity = qty.obs,
       initialQty = initialQty ?? qty {
    this.priceAtAdd.value = priceAtAdd ?? unit.rate;
    isDeleted.value = deleted;
  }

  double _catalogPrice(AddonModel addon) {
    final ea = unit.existAddOns.firstWhereOrNull((e) => e.prdId == addon.prdId);
    return ea?.price ?? addon.price;
  }

  /// Returns the real freeQty per parent unit.
  /// Cloned selectedAddon may have freeQty=0 if it was lost during cloning.
  int _resolvedFreeQty(AddonModel addon) {
    final ea = unit.existAddOns.firstWhereOrNull((e) => e.prdId == addon.prdId);
    return ea?.freeQty ?? addon.freeQty;
  }

  /// Chargeable qty = total qty − (freeQty × parentQty), clamped to 0.
  /// Uses catalog values from existAddOns so the UI matches the API payload.
  int _chargeableQty(AddonModel addon) {
    final int freeThreshold = _resolvedFreeQty(addon) * quantity.value;
    return (addon.quantity.value - freeThreshold).clamp(0, 99999);
  }

  double get totalAddonsPrice => selectedAddons.fold(0.0, (sum, addon) {
    final double price = _catalogPrice(addon);
    return sum + price * _chargeableQty(addon);
  });

  double get unitPrice => priceAtAdd.value;

  double get subtotal => (unitPrice * quantity.value) + totalAddonsPrice;

  double get unitPriceWithTax =>
      unitPrice + (unitPrice * product.prd_tax / 100);

  double get totalTax {
    final double itemTax = (unitPrice * product.prd_tax / 100) * quantity.value;
    final double addonsTax = selectedAddons.fold(0.0, (sum, addon) {
      final double price = _catalogPrice(addon);
      final int chargeable = _chargeableQty(addon);
      return sum + (price * addon.taxPer / 100) * chargeable;
    });
    return itemTax + addonsTax;
  }

  double get subtotalWithTax {
    try {
      final dc = Get.find<DashboardController>();
      return dc.vatType.value == 0 ? subtotal + totalTax : subtotal;
    } catch (_) {
      return subtotal + totalTax;
    }
  }

  bool get isEdited => subId != null && quantity.value != initialQty;

  bool get hasUnitChanged =>
      originalUnitId != null && originalUnitId != unit.unitId;

  // Helper to check if any addon changed
  bool hasAddonChanges() {
    if (originalAddons == null) return selectedAddons.isNotEmpty;

    // Create maps for easy comparison
    final originalMap = {for (var a in originalAddons!) a.prdId: a};
    final currentMap = {for (var a in selectedAddons) a.prdId: a};

    // Check for removed addons
    for (var id in originalMap.keys) {
      if (!currentMap.containsKey(id)) return true;
    }

    // Check for added or changed addons
    for (var addon in selectedAddons) {
      final original = originalMap[addon.prdId];
      if (original == null) return true; // New addon
      if (original.quantity.value != addon.quantity.value)
        return true; // Quantity changed
    }

    return false;
  }

  // Helper to create a deep copy for original state
  CartItem copyWithOriginalAddons() {
    return CartItem(
      subId: subId,
      addonprntId: addonprntId,
      addonuntId: addonuntId,
      originalUnitId: originalUnitId,
      originalBaseQty: originalBaseQty,
      product: product,
      unit: unit,
      selectedAddons: selectedAddons.map((a) => a.copyWith()).toList(),
      originalAddons: originalAddons?.map((a) => a.copyWith()).toList(),
      qty: quantity.value,
      initialQty: initialQty,
      priceAtAdd: priceAtAdd.value,
      deleted: isDeleted.value,
    );
  }
}

class CartController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final cartItems = <CartItem>[].obs;
  final originalItems = <OrderItem>[].obs;

  final selectedTableId = "".obs;
  final selectedTableName = "".obs;
  final selectedChairCount = 0.obs;

  final selectedAreaId = 0.obs;
  final selectedAreaName = "".obs;
  final selectedPriceGroupId = 0.obs;

  final editingOrderId = "".obs;
  final editingInvNo = "".obs;
  final wasDraft = false.obs;

  // Track original metadata for change detection
  final originalTableId = "".obs;
  final originalChairCount = 0.obs;
  final originalOrderType = 0.obs;

  bool get isEditing => editingOrderId.value.isNotEmpty;
  List<Map<String, dynamic>> originalRawSubItems = [];
  final isProcessing = false.obs;

  String _generateUuid() {
    final random = math.Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'ORD-$timestamp-${random.nextInt(10000)}';
  }

  void _clearDashboardSearch() {
    if (Get.isRegistered<DashboardController>()) {
      final dashboard = Get.find<DashboardController>();

      if (dashboard.isDisposed) return; // ✅ prevent crash

      dashboard.searchKeyword.value = "";
      dashboard.searchController.clear();
      dashboard.fetchProducts();
    }
  }

  void setTable({
    required String tableId,
    required String tableName,
    required int chairCount,
    required int areaId,
    required String areaName,
    required int priceGroupId,
  }) {
    selectedTableId.value = tableId;
    selectedTableName.value = tableName;
    selectedChairCount.value = chairCount;
    selectedAreaId.value = areaId;
    selectedAreaName.value = areaName;
    selectedPriceGroupId.value = priceGroupId;
    _clearDashboardSearch();
    print(selectedPriceGroupId);
  }

  void clearTable() {
    selectedTableId.value = "";
    selectedTableName.value = "";
    selectedChairCount.value = 0;
    selectedAreaId.value = 0;
    selectedAreaName.value = "";
    selectedPriceGroupId.value = 0;

    try {
      if (Get.isRegistered<TablesController>()) {
        Get.find<TablesController>().fetchTables();
      }
    } catch (e) {
      debugPrint("Error refreshing tables: $e");
    }
    _clearDashboardSearch();
  }

  Map<String, dynamic> _buildProcessingTable(OrderModel order) {
    return {
      "rt_id": int.tryParse(order.tableId),
      "rt_area_id": order.areaId,
      "rt_name": order.tableName,
      "rt_seat_count": order.chairNumber,
      "rt_status": 1,
      "prcgrp_id": order.priceGroupId,

      /// 🔥 IMPORTANT → existing order identity
      "sq_id": int.tryParse(order.id),
      "sq_inv_no": int.tryParse(order.invNo),

      /// Optional but safe
      "created_at": order.createdAt.toIso8601String(),
      "total_amount": order.totalAmount,
    };
  }

  void startEditingOrder(OrderModel order) {
    editingOrderId.value = order.id;
    editingInvNo.value = order.invNo;
    wasDraft.value = order.sales_odr_pos_status == 0;
    originalItems.assignAll(order.items);
    editingOrderFullData = _buildProcessingTable(order);

    // Store original metadata
    originalTableId.value = order.tableId;
    originalChairCount.value = order.chairNumber;
    originalOrderType.value = order.sales_odr_order_type;

    setTable(
      tableId: order.tableId,
      tableName: order.tableName,
      chairCount: order.chairNumber,
      areaId: order.areaId ?? 0,
      areaName: order.areaName ?? "",
      priceGroupId: order.priceGroupId ?? 0,
    );

    clearCart();

    for (var item in order.items) {
      // Clone addons with their original state
      // In startEditingOrder, replace the cloning block:

      final clonedAddons = item.selectedAddons
          .map(
            (a) => AddonModel(
              id: a.id,
              subId: a.subId,
              prdId: a.prdId,
              prdaddon_flags: a.prdaddon_flags,
              name: a.name,
              price: a.price,
              unitDisplay: a.unitDisplay,
              unitId: a.unitId,
              taxCatId: a.taxCatId,
              taxPer: a.taxPer,
              unitBaseQty: a.unitBaseQty,
              initialQty: a.quantity.value,
              isDefault: a.isDefault,
              freeQty: a.freeQty,
            ),
          )
          .toList();

      // ✅ Also capture free addons (existAddOns with flags==1) that have a subId
      // These come from the server response's sales_order_sub as addon entries
      final freeAddonOriginals = item.unit.existAddOns
          .where((ea) => ea.prdaddon_flags == 1 && ea.subId != null)
          .map(
            (ea) => AddonModel(
              id: ea.id,
              subId: ea.subId, // ✅ subId from server
              prdId: ea.prdId,
              prdaddon_flags: ea.prdaddon_flags,
              name: ea.name,
              price: 0,
              unitDisplay: ea.unitDisplay,
              unitId: ea.unitId,
              taxCatId: ea.taxCatId,
              taxPer: ea.taxPer,
              unitBaseQty: ea.unitBaseQty,
              initialQty: item.quantity, // ✅ mirrors parent qty
              isDefault: 1,
              freeQty: ea.freeQty,
            ),
          )
          .toList();

      // ✅ originalAddons = selectedAddons + free addons from existAddOns
      final originalAddonsCopy = [
        ...clonedAddons.map((a) => a.copyWith()),
        ...freeAddonOriginals,
      ];

      cartItems.add(
        CartItem(
          subId: item.subId,
          addonprntId: item.addonParentPrdId,
          addonuntId: item.addonParentUnitId,
          originalUnitId: item.unitId, // Store original unit ID
          originalBaseQty: item.unit.unitBaseQty, // Store original base_qty
          product: item.product,
          unit: item.unit,
          selectedAddons: clonedAddons,
          originalAddons: originalAddonsCopy,
          qty: item.quantity,
          initialQty: item.quantity,
          priceAtAdd: item.unit.rate,
        ),
      );
    }

    cartItems.refresh();
  }

  void stopEditing() {
    editingOrderId.value = "";
    editingInvNo.value = "";
    wasDraft.value = false;
    originalItems.clear();
    originalTableId.value = "";
    originalChairCount.value = 0;
    originalOrderType.value = 0;
    clearCart();
    clearTable();
  }

  bool get hasSelectedTable => selectedTableId.value.isNotEmpty;

  void addItem(FoodItemModel product) {}

  void addItemWithDetails(
    FoodItemModel product,
    ProductUnit unit,
    List<AddonModel> addons,
  ) {
    // Check for existing deleted item first
    final existingDeletedIndex = cartItems.indexWhere((item) {
      bool sameProduct = item.product.id == product.id;
      bool sameUnit = item.unit.unitId == unit.unitId;
      bool sameAddons = _areAddonsEqual(item.selectedAddons, addons);
      return sameProduct && sameUnit && sameAddons && item.isDeleted.value;
    });

    // In addItemWithDetails method, when reactivating a deleted item:
    if (existingDeletedIndex != -1) {
      // Reactivate the deleted item
      final existingItem = cartItems[existingDeletedIndex];
      existingItem.isDeleted.value = false;
      existingItem.quantity.value = 1;
      existingItem.priceAtAdd.value = unit.rate;
      existingItem.unit = unit;

      // Clear and update addons
      existingItem.selectedAddons.clear();
      for (var a in addons) {
        existingItem.selectedAddons.add(
          AddonModel(
            id: a.id,
            prdId: a.prdId,
            prdaddon_flags: a.prdaddon_flags,
            name: a.name,
            price: a.price,
            unitDisplay: a.unitDisplay,
            unitId: a.unitId,
            taxCatId: a.taxCatId,
            taxPer: a.taxPer,
            unitBaseQty: a.unitBaseQty,
            initialQty: a.quantity.value,
            freeQty: a.freeQty,
          ),
        );
      }

      // IMPORTANT: Reset originalAddons to match current state
      existingItem.originalAddons = existingItem.selectedAddons
          .map((a) => a.copyWith())
          .toList();

      cartItems.refresh();
      showSafeSnackbar(
        "Added to Cart",
        "${product.name} (${unit.unitDisplay}) added back successfully",
      );
      return;
    }

    // Check for existing active item
    final existingIndex = cartItems.indexWhere((item) {
      bool sameProduct = item.product.id == product.id;
      bool sameUnit = item.unit.unitId == unit.unitId;
      bool sameAddons = _areAddonsEqual(item.selectedAddons, addons);
      return sameProduct && sameUnit && sameAddons && !item.isDeleted.value;
    });

    if (existingIndex != -1) {
      updateQuantity(
        cartItems[existingIndex],
        cartItems[existingIndex].quantity.value + 1,
      );
    } else {
      cartItems.add(
        CartItem(
          product: product,
          unit: unit,
          selectedAddons: List.from(
            addons.map(
              (a) => AddonModel(
                id: a.id,
                prdId: a.prdId,
                prdaddon_flags: a.prdaddon_flags,
                name: a.name,
                price: a.price,
                unitDisplay: a.unitDisplay,
                unitId: a.unitId,
                taxCatId: a.taxCatId,
                taxPer: a.taxPer,
                unitBaseQty: a.unitBaseQty,
                initialQty: a.quantity.value,
                freeQty: a.freeQty,
              ),
            ),
          ),
        ),
      );
    }

    showSafeSnackbar(
      "Added to Cart",
      "${product.name} (${unit.unitDisplay}) added successfully",
    );
  }

  // Helper method to compare addons
  bool _areAddonsEqual(List<AddonModel> addons1, List<AddonModel> addons2) {
    if (addons1.length != addons2.length) return false;

    final sorted1 = List<AddonModel>.from(addons1)
      ..sort((a, b) => a.prdId.compareTo(b.prdId));
    final sorted2 = List<AddonModel>.from(addons2)
      ..sort((a, b) => a.prdId.compareTo(b.prdId));

    for (int i = 0; i < sorted1.length; i++) {
      if (sorted1[i].prdId != sorted2[i].prdId) return false;
      if (sorted1[i].quantity.value != sorted2[i].quantity.value) return false;
    }
    return true;
  }

  void updateItemDetails(
    CartItem item,
    ProductUnit unit,
    List<AddonModel> addons,
  ) {
    item.unit = unit;
    item.priceAtAdd.value = unit.rate;

    // Build a set of prdIds that are still selected (qty > 0)
    final selectedPrdIds = addons.map((a) => a.prdId).toSet();

    // Remove addons that are no longer selected
    item.selectedAddons.removeWhere(
      (existing) => !selectedPrdIds.contains(existing.prdId),
    );

    // Update or add remaining addons
    for (var newAddon in addons) {
      final index = item.selectedAddons.indexWhere(
        (a) => a.prdId == newAddon.prdId,
      );

      if (index != -1) {
        // Update quantity
        item.selectedAddons[index].quantity.value = newAddon.quantity.value;
      } else {
        // Add new addon
        item.selectedAddons.add(
          AddonModel(
            id: newAddon.id,
            prdId: newAddon.prdId,
            prdaddon_flags: newAddon.prdaddon_flags,
            name: newAddon.name,
            price: newAddon.price,
            unitDisplay: newAddon.unitDisplay,
            unitId: newAddon.unitId,
            taxCatId: newAddon.taxCatId,
            taxPer: newAddon.taxPer,
            unitBaseQty: newAddon.unitBaseQty,
            initialQty: newAddon.quantity.value,
            freeQty: newAddon.freeQty,
          ),
        );
      }
    }

    cartItems.refresh();
    showSafeSnackbar("Item Updated", "${item.product.name} details updated");
  }

  void updateQuantity(CartItem item, int newQty) {
    final int oldQty = item.quantity.value;
    if (newQty <= 0) {
      newQty =
          0; // Allow 0 to handle deletion logic if needed, but usually clamped to 1
    }

    if (newQty != oldQty && oldQty > 0) {
      // Scale free/default addons proportionally
      for (var addon in item.selectedAddons) {
        if (addon.price == 0 || addon.isDefault == 1 || addon.freeQty > 0) {
          int scaledQty = (addon.quantity.value * newQty / oldQty).round();
          // If parent is being deleted (qty 0), addons should be 0 too
          if (newQty == 0) {
            scaledQty = 0;
          } else if (scaledQty < 1 && addon.quantity.value > 0) {
            scaledQty = 1;
          }
          addon.quantity.value = scaledQty;
        }
      }
    }

    item.quantity.value = newQty;

    // If quantity reaches 0, mark as deleted if editing, or remove if new
    if (newQty == 0) {
      removeItem(item);
    }

    cartItems.refresh();
  }

  void removeItem(CartItem item) {
    if (isEditing && item.subId != null) {
      // Mark the parent item as deleted
      item.isDeleted.value = true;
      item.quantity.value = 0; // Ensure quantity is 0

      // Also mark all addons for deletion by setting their quantity to 0
      for (var addon in item.selectedAddons) {
        addon.quantity.value = 0;
      }

      cartItems.refresh();
    } else {
      cartItems.remove(item);
    }
  }

  void decreaseQuantity(CartItem item) {
    if (item.quantity.value > 1) {
      updateQuantity(item, item.quantity.value - 1);
    } else {
      // Validation message instead of removal
      showSafeSnackbar(
        "Quantity Warning",
        "Minimum quantity is 1. Tap the delete icon to remove the item.",
      );
    }
  }

  void removeAddon(CartItem item, AddonModel addon) {
    item.selectedAddons.remove(addon);
    cartItems.refresh();
  }

  void decreaseAddonQuantity(CartItem item, AddonModel addon) {
    if (addon.quantity.value > 1) {
      addon.quantity.value--;
    } else {
      // Validation message instead of removal for addons if desired,
      // but usually addons can be removed via decrease if they are optional.
      // Keeping it consistent with parent item:
      showSafeSnackbar(
        "Quantity Warning",
        "Minimum quantity is 1. Tap the remove icon if you want to delete this addon.",
      );
    }
    cartItems.refresh();
  }

  void clearCart() {
    cartItems.clear();
  }

  double get totalAmount => cartItems
      .where((i) => !i.isDeleted.value)
      .fold(0.0, (sum, item) => sum + item.subtotal);
  double get totalTaxAmount => cartItems
      .where((i) => !i.isDeleted.value)
      .fold(0.0, (sum, item) => sum + item.totalTax);
  double get grandTotal => totalAmount + totalTaxAmount;
  int get totalItemsCount => cartItems
      .where((i) => !i.isDeleted.value)
      .fold(0, (sum, item) => sum + item.quantity.value);

  Future<Map<String, dynamic>?> placeOrder({bool isDraft = false}) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final syncTime = "${DateFormat('yyMMddHHmmssSSS').format(now)}000";
      final orderUuid = _generateUuid();

      List<Map<String, dynamic>> saleItems = [];
      List<Map<String, dynamic>> localItems = [];

      final DashboardController dashboardController =
          Get.find<DashboardController>();
      final bool isVatDisabled = dashboardController.vatType.value == 1;
      double totalTax = 0;
      double totalWithTax = 0;

      for (var item in cartItems.where((i) => !i.isDeleted.value)) {
        double itemRate = item.priceAtAdd.value;
        double itemTaxPer = isVatDisabled ? 0 : item.product.prd_tax;

        int itemQty = item.quantity.value;
        double itemSubtotal = itemRate * itemQty;

        double itemTaxAmount = isVatDisabled
            ? 0
            : (itemRate * itemTaxPer) / 100;
        double itemTotalWithTax = isVatDisabled
            ? itemSubtotal
            : (itemRate + itemTaxAmount) * itemQty;

        totalTax += isVatDisabled ? 0 : itemTaxAmount * itemQty;
        totalWithTax += itemTotalWithTax;

        saleItems.add({
          "sales_ord_sub_id": "",
          "prd_name": item.product.name,
          "salesub_prd_id": int.tryParse(item.product.id),
          "salesub_rate": itemRate,
          "salesub_rate_tmp": itemRate,
          "salesub_price": itemRate,
          "salesub_tax": itemTaxAmount,
          "salesub_tax_per": isVatDisabled ? 0 : itemTaxPer,
          "salesub_qty": itemQty,
          "count": itemQty,
          "sale_total_amount": itemTotalWithTax,
          "salesub_tax_amnt": itemTaxAmount * itemQty,
          "base_qty": item.unit.unitBaseQty,
          "item_disc": 0,
          "salesub_unit_id": item.unit.unitId,
          "prd_tax_cat_id": item.product.taxCatId,
          "salesub_gd_id": 0,
          "salesub_unit_display": item.unit.unitDisplay,
          "taxvalperqty": itemTaxAmount,
          "salesub_amnt": itemSubtotal,
          "is_addon": 0,
          "addon_parent_prd_id": null,
          "addon_parent_unit_id": null,
        });

        localItems.add({
          "order_uuid": orderUuid,
          "product_id": item.product.id,
          "name": item.product.name,
          "quantity": itemQty,
          "price": itemRate,
          "tax": itemTaxAmount * itemQty,
          "subtotal": itemTotalWithTax,
          "is_printed": 0,
        });

        // Addons logic: Combine default free addons and selected ones
        final Map<int, AddonModel> allAddons = {};

        // 1. Collect default free addons from unit
        for (var ea in item.unit.existAddOns) {
          if (ea.prdaddon_flags == 1) {
            allAddons[ea.prdId] = ea;
          }
        }

        // 2. Override/add with selected addons
        for (var sa in item.selectedAddons) {
          allAddons[sa.prdId] = sa;
        }

        for (var addon in allAddons.values) {
          int totalQty = addon.quantity.value;

          // Fallback to freeQty for default addons not explicitly adjusted
          if (totalQty == 0 &&
              addon.freeQty > 0 &&
              !item.selectedAddons.any((sa) => sa.prdId == addon.prdId)) {
            totalQty = item.quantity.value * addon.freeQty;
          }

          if (totalQty <= 0) continue;

          int freeQtyLimit = addon.freeQty * item.quantity.value;
          int freePart = totalQty < freeQtyLimit ? totalQty : freeQtyLimit;
          int paidPart = totalQty - freePart;

          final existSource = item.unit.existAddOns.firstWhereOrNull(
            (ea) => ea.prdId == addon.prdId,
          );
          final double catalogPrice = existSource?.price ?? addon.price;
          final bool isUserSelected = item.selectedAddons.any(
            (sa) => sa.prdId == addon.prdId,
          );

          double paidRate = addon.price;
          if (paidPart > 0) {
            // If it's a free addon overflow, use catalog price
            if (addon.price == 0 && addon.freeQty > 0 && freePart < totalQty) {
              paidRate = catalogPrice;
            }
            // If user selected a paid addon, use their price
            else if (isUserSelected && addon.price > 0) {
              paidRate = addon.price;
            }
            // For free addons with overflow, ensure we have a valid rate
            else if (paidRate == 0 && catalogPrice > 0) {
              paidRate = catalogPrice;
            }
          }

          // Free portion entry (rate 0)
          if (freePart > 0) {
            double rate = 0;
            double taxPer = isVatDisabled ? 0 : addon.taxPer;
            double taxAmntPerUnit = 0; // rate is 0

            saleItems.add({
              "sales_ord_sub_id": "",
              "prd_name": addon.name,
              "salesub_prd_id": addon.prdId,
              "salesub_rate": rate,
              "salesub_rate_tmp": rate,
              "salesub_price": rate,
              "salesub_tax": taxAmntPerUnit,
              "salesub_tax_per": isVatDisabled ? 0 : taxPer,
              "salesub_qty": freePart,
              "count": freePart,
              "sale_total_amount": 0,
              "salesub_tax_amnt": 0,
              "base_qty": addon.unitBaseQty,
              "item_disc": 0,
              "salesub_unit_id": addon.unitId,
              "prd_tax_cat_id": addon.taxCatId,
              "salesub_gd_id": 0,
              "salesub_unit_display": addon.unitDisplay,
              "taxvalperqty": 0,
              "salesub_amnt": 0,
              "is_addon": 1,
              "addon_parent_prd_id": int.tryParse(item.product.id),
              "addon_parent_unit_id": item.unit.unitId,
              "is_default": 1,
            });

            localItems.add({
              "order_uuid": orderUuid,
              "product_id": addon.prdId.toString(),
              "name": addon.name,
              "quantity": freePart,
              "price": 0.0,
              "tax": 0.0,
              "subtotal": 0.0,
              "is_printed": 0,
            });
          }

          // Paid portion entry (full rate)
          if (paidPart > 0) {
            double rate = addon.price;
            double taxPer = isVatDisabled ? 0 : addon.taxPer;
            double taxAmntPerUnit = (rate * taxPer) / 100;
            double subtotal = rate * paidPart;
            double totalWithTaxLine = (rate + taxAmntPerUnit) * paidPart;

            saleItems.add({
              "sales_ord_sub_id": "",
              "prd_name": addon.name,
              "salesub_prd_id": addon.prdId,
              "salesub_rate": rate,
              "salesub_rate_tmp": rate,
              "salesub_price": rate,
              "salesub_tax": taxAmntPerUnit,
              "salesub_tax_per": isVatDisabled ? 0 : taxPer,
              "salesub_qty": paidPart,
              "count": paidPart,
              "sale_total_amount": totalWithTaxLine,
              "salesub_tax_amnt": taxAmntPerUnit * paidPart,
              "base_qty": addon.unitBaseQty,
              "item_disc": 0,
              "salesub_unit_id": addon.unitId,
              "prd_tax_cat_id": addon.taxCatId,
              "salesub_gd_id": 0,
              "salesub_unit_display": addon.unitDisplay,
              "taxvalperqty": taxAmntPerUnit,
              "salesub_amnt": subtotal,
              "is_addon": 0,
              "addon_parent_prd_id": int.tryParse(item.product.id),
              "addon_parent_unit_id": item.unit.unitId,
            });

            localItems.add({
              "order_uuid": orderUuid,
              "product_id": addon.prdId.toString(),
              "name": addon.name,
              "quantity": paidPart,
              "price": rate,
              "tax": taxAmntPerUnit * paidPart,
              "subtotal": totalWithTaxLine,
              "is_printed": 0,
            });

            totalTax += taxAmntPerUnit * paidPart;
            totalWithTax += totalWithTaxLine;
          }
        }
      }

      final body = {
        "usr_id": int.tryParse(AppState.userId) ?? 0,
        "cust_type": "1",
        "cust_id": null,
        "cust_name": "Cash Customer",
        "saleqt_date": dateStr,
        "sale_items": saleItems,
        "sq_total": totalWithTax,
        "advance_amount": 0,
        "sale_pay_type": 0,
        "balance_amount": 0,
        "sale_acc_ledger_id": 0,
        "sq_tax": totalTax,
        "inv_type": 2,
        "pos_odr_type": AppState.orderType.id,
        "address": null,
        "phone_no": null,
        "vat_no": null,
        "no_seats": selectedChairCount.value,
        "sale_agent": GetStorage().read('ledger_id'),
        "is_pos": true,
        "salesub_gd_id": 0,
        "res_table": {
          "rt_id": int.tryParse(selectedTableId.value),
          "rt_area_id": selectedAreaId.value,
          "rt_name": selectedTableName.value,
          "rt_seat_count": selectedChairCount.value,
          "rt_image": null,
          "rt_is_default": 0,
          "rt_avl_seat": selectedChairCount.value,
          "rt_status": 1,
          "prcgrp_id": selectedPriceGroupId.value,
        },
        "res_status": isDraft ? 0 : 1,
        "sq_inv_no": isEditing ? int.tryParse(editingOrderId.value) ?? 0 : 0,
        "sq_disc": 0,
        "sale_acc_ledger_id_bank": null,
        "sale_acc_ledger_id_cash": null,
        "card_amnt": null,
        "cash_amnt": null,
        "sales_roundoff": 0,
        "table_name": selectedTableName.value,
        "sales_is_rest_pos": 1,
        "is_compliment": 0,
        "is_pos_edit": isEditing,
        "is_split": false,
        "split_amnt": [],
        "split_count": null,
        "server_sync_time": syncTime,
      };
      // --- SAVE TO LOCAL DB FIRST ---
      try {
        await _dbHelper.insertOrder({
          "uuid": orderUuid,
          "order_type_id": AppState.orderType.id,
          "table_id": int.tryParse(selectedTableId.value),
          "customer_name": "Cash Customer",
          "total_amount": totalWithTax,
          "total_tax": totalTax,
          "status": isDraft ? 'draft' : 'pending',
          "is_synced": 0,
          "payload": jsonEncode(body),
          "created_at": now.toIso8601String(),
          "inv_no": null, // explicitly null; filled after server sync
        }, localItems);
        debugPrint("✅ Order saved locally: $orderUuid");
      } catch (dbError) {
        log("❌ Local DB Error: $dbError");
      }

      // --- TRY API CALL ---
      // --- TRY API CALL ---
      try {
        log("📡 Sending API request...");
        log("📦 BODY: ${jsonEncode(body)}");
        final response = await _apiService.post(
          "mobileapp/pos/add_sales_order",
          data: body,
        );

        if (response.statusCode == 200) {
          dynamic data = response.data;
          if (data is String) {
            data = jsonDecode(data);
          }

          if (data is Map && data['message'] != null) {
            final message = data['message'];
            if (message is Map && message['status'] == 0) {
              if (Get.isDialogOpen == true) Get.back();
              Future.delayed(const Duration(milliseconds: 100), () {
                showSafeSnackbar(
                  "Error",
                  message['msg'] ?? "Seat not available",
                );
              });
            }
          }
          // Mark as synced locally with server's real ID
          final String serverId =
              data['id']?.toString() ??
              data['preview']?['sales_odr_id']?.toString() ??
              "";
          await _dbHelper.updateOrderStatusByUuid(
            orderUuid,
            isDraft ? 'draft' : 'pending',
            isSynced: 1,
            serverId: serverId,
          );

          _clearDashboardSearch();
          return data;
        }
      } catch (apiError) {
        log("⚠️ API Failed (Offline): $apiError. Order preserved in local DB.");

        // Ensure the local record has the correct status
        await _dbHelper.updateOrderStatusByUuid(
          orderUuid,
          isDraft ? 'draft' : 'pending',
          isSynced: 0,
        );

        final syntheticResponse = _buildOfflineResponse(
          orderUuid: orderUuid,
          body: body,
          totalWithTax: totalWithTax,
          totalTax: totalTax,
          saleItems: saleItems,
          isDraft: isDraft,
          now: now,
        );
        _clearDashboardSearch();
        return syntheticResponse;
      }

      return null;
    } catch (e) {
      log("Error in placeOrder: $e");
      if (Get.isDialogOpen == true) Get.back();
      return null;
    }
  }

  Map<String, dynamic>? editingOrderFullData;

  Future<Map<String, dynamic>?> updateOrder({bool isDraft = false}) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final syncTime = "${DateFormat('yyMMddHHmmssSSS').format(now)}000";
      List<Map<String, dynamic>> saleItems = [];
      final DashboardController dashboardController =
          Get.find<DashboardController>();
      final bool isVatDisabled = dashboardController.vatType.value == 1;
      double totalTax = 0;
      double totalWithTax = 0;
      bool hasAnyChange = false;
      // ✅ Check for status change (Draft <-> Order)

      if (wasDraft.value != isDraft) {
        hasAnyChange = true;
        log("║ Status changed: wasDraft ${wasDraft.value} -> isDraft $isDraft");
      }

      if (selectedTableId.value != originalTableId.value ||
          selectedChairCount.value != originalChairCount.value) {
        hasAnyChange = true;
        log(
          "║ Metadata changed: Table ${originalTableId.value} -> ${selectedTableId.value}, Seats ${originalChairCount.value} -> ${selectedChairCount.value}",
        );
      }

      // ✅ Check for order type change
      if (AppState.orderType.id != originalOrderType.value) {
        hasAnyChange = true;
        log(
          "║ Order type changed: ${originalOrderType.value} -> ${AppState.orderType.id}",
        );
      }

      log("╔══════════════════════════════════════════");
      log("║ updateOrder() START");
      log("║ isVatDisabled: $isVatDisabled");
      log("║ editingInvNo: ${editingInvNo.value}");
      log("║ totalCartItems: ${cartItems.length}");
      log("╚══════════════════════════════════════════");

      for (var item in cartItems) {
        log("┌─ ITEM: ${item.product.name}");
        log("│  subId: ${item.subId}");
        log("│  originalUnitId: ${item.originalUnitId}");
        log("│  originalBaseQty: ${item.originalBaseQty}");
        log("│  current unitId: ${item.unit.unitId}");
        log("│  current unitDisplay: ${item.unit.unitDisplay}");
        log("│  current unitBaseQty: ${item.unit.unitBaseQty}");
        log("│  current rate: ${item.unit.rate}");
        log("│  qty: ${item.quantity.value}  initialQty: ${item.initialQty}");
        log("│  isDeleted: ${item.isDeleted.value}");
        log("│  hasUnitChanged: ${item.hasUnitChanged}");
        log(
          "│  selectedAddons: ${item.selectedAddons.length}  originalAddons: ${item.originalAddons?.length ?? 'null'}",
        );
        log("│  existAddOns (free): ${item.unit.existAddOns.length}");

        // ── Deleted item handling ────────────────────────────────────────────────
        if (item.isDeleted.value || item.quantity.value == 0) {
          hasAnyChange = true;
          log("│  ITEM IS DELETED - marking for deletion");

          final double deletedRate = item.unit.rate;
          final double deletedTaxPer = item.product.prd_tax;
          final double deletedTaxAmount = isVatDisabled
              ? 0
              : (deletedRate * deletedTaxPer) / 100;
          final double deletedSubtotal = deletedRate * item.initialQty;
          final double deletedTotalWithTax = isVatDisabled
              ? deletedSubtotal
              : (deletedRate + deletedTaxAmount) * item.initialQty;

          saleItems.add({
            "sales_ord_sub_id": item.subId,
            "prd_name": item.product.name,
            "salesub_prd_id": int.tryParse(item.product.id),
            "salesub_rate": deletedRate,
            "salesub_rate_tmp": deletedRate,
            "salesub_price": deletedRate,
            "salesub_tax": deletedTaxAmount,
            "salesub_tax_per": deletedTaxPer,
            "salesub_qty": item.initialQty,
            "count": item.initialQty,
            "sale_total_amount": deletedTotalWithTax,
            "salesub_tax_amnt": deletedTaxAmount * item.initialQty,
            "base_qty": item.originalBaseQty ?? 1.0,
            "item_disc": 0,
            "salesub_unit_id": item.originalUnitId ?? 1,
            "prd_tax_cat_id": item.product.taxCatId,
            "salesub_gd_id": 0,
            "salesub_unit_display": item.unit.unitDisplay,
            "taxvalperqty": deletedTaxAmount,
            "salesub_amnt": deletedSubtotal,
            "is_addon": 0,
            "addon_parent_prd_id": item.addonprntId,
            "addon_parent_unit_id": item.addonuntId,
            "is_edited": false,
            "oldqty": item.initialQty,
            "Item_descp": "",
            "is_deleted": 1,
          });

          if (item.originalAddons != null) {
            for (var originalAddon in item.originalAddons!) {
              if (originalAddon.subId == null) {
                log("│  SKIP addon ${originalAddon.name} - no subId");
                continue;
              }

              final bool isFreeAddon =
                  originalAddon.price == 0 ||
                  item.unit.existAddOns.any(
                    (ea) => ea.id == originalAddon.id && ea.prdaddon_flags == 1,
                  );

              final int addonQty = originalAddon.quantity.value > 0
                  ? originalAddon.quantity.value
                  : 1;

              log(
                "│  >>> DELETING ADDON WITH PARENT: ${originalAddon.name}  subId: ${originalAddon.subId}  isFree: $isFreeAddon  qty: $addonQty",
              );

              saleItems.add({
                "sales_ord_sub_id": originalAddon.subId,
                "prd_name": originalAddon.name,
                "salesub_prd_id": originalAddon.prdId,
                "salesub_rate": 0,
                "salesub_rate_tmp": 0,
                "salesub_price": 0,
                "salesub_tax": 0,
                "salesub_tax_per": 0,
                "salesub_qty": addonQty,
                "count": addonQty,
                "sale_total_amount": 0,
                "salesub_tax_amnt": 0,
                "base_qty": originalAddon.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": originalAddon.unitId,
                "prd_tax_catId": originalAddon.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": originalAddon.unitDisplay,
                "taxvalperqty": 0,
                "salesub_amnt": 0,
                "is_addon": isFreeAddon ? 1 : 0,
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.originalUnitId ?? 1,
                "is_edited": false,
                "oldqty": addonQty,
                "Item_descp": "",
                "is_deleted": 1,
              });
            }
          }

          log("└─ ITEM MARKED FOR DELETION");
          continue;
        }

        // ── Active item — quantities & rates ─────────────────────────────────────
        final bool unitChanged = item.hasUnitChanged;
        final int newQty = item.quantity.value;
        final int oldQty = item.initialQty;
        final double rate = item.unit.rate;
        final double baseQty = item.unit.unitBaseQty;
        final double itemTaxPer = isVatDisabled ? 0 : item.product.prd_tax;
        final double itemTaxAmountPerUnit = isVatDisabled
            ? 0
            : (rate * itemTaxPer) / 100;
        final double itemSubtotal = rate * newQty;
        final double itemTotalWithTax = isVatDisabled
            ? itemSubtotal
            : (rate + itemTaxAmountPerUnit) * newQty;

        totalTax += itemTaxAmountPerUnit * newQty;
        totalWithTax += itemTotalWithTax;

        final parentPrdId = item.addonprntId;
        final parentUnitId = item.addonuntId;

        bool parentChanged = false;
        String changeReason = "NO_CHANGE";

        if (item.subId == null) {
          parentChanged = true;
          hasAnyChange = true;
          changeReason = "NEW_ITEM";
        } else if (unitChanged) {
          parentChanged = true;
          hasAnyChange = true;
          changeReason =
              "UNIT_CHANGED (${item.originalUnitId} → ${item.unit.unitId})";
        } else if (newQty != oldQty) {
          parentChanged = true;
          hasAnyChange = true;
          changeReason = "QTY_CHANGED ($oldQty → $newQty)";
        } else if (item.hasAddonChanges()) {
          // We also check addons below, but we need to know if parent needs to be sent
          // because its child addons changed.
          // hasAddonChanges is a helper in CartItem.
          hasAnyChange = true;
        }

        log("│  parentChanged: $parentChanged  reason: $changeReason");
        log("│  newQty: $newQty  oldQty: $oldQty  baseQty: $baseQty");
        log("│  rate: $rate  itemTaxPer: $itemTaxPer");

        saleItems.add({
          "sales_ord_sub_id": item.subId,
          "prd_name": item.product.name,
          "salesub_prd_id": int.tryParse(item.product.id),
          "salesub_rate": rate,
          "salesub_rate_tmp": rate,
          "salesub_price": rate,
          "salesub_tax": itemTaxAmountPerUnit,
          "salesub_tax_per": itemTaxPer,
          "salesub_qty": newQty,
          "count": oldQty,
          "sale_total_amount": itemTotalWithTax,
          "salesub_tax_amnt": itemTaxAmountPerUnit * newQty,
          "base_qty": baseQty,
          "item_disc": 0,
          "salesub_unit_id": item.unit.unitId,
          "prd_tax_cat_id": item.product.taxCatId,
          "salesub_gd_id": 0,
          "salesub_unit_display": item.unit.unitDisplay,
          "taxvalperqty": itemTaxAmountPerUnit,
          "salesub_amnt": itemSubtotal,
          "is_addon": 0,
          "addon_parent_prd_id": parentPrdId,
          "addon_parent_unit_id": parentUnitId,
          "is_edited": item.subId != null && (unitChanged || newQty != oldQty),
          "oldqty": oldQty,
          "Item_descp": "",
          "is_deleted": 0,
        });

        if (parentChanged) {
          log("│  >>> Added PARENT (CHANGED) to saleItems");
        } else {
          log("│  >>> Added PARENT (unchanged - context) to saleItems");
        }

        // ── Build original addon map ─────────────────────────────────────────────
        final Map<int, AddonModel> originalByPrdId = {};
        if (item.originalAddons != null) {
          for (var oa in item.originalAddons!) {
            originalByPrdId[oa.prdId] = oa;
          }
        }

        // ── existAddOns lookup map (source of truth for freeQty & paid price) ────
        // When a user touches a free addon and increments it beyond the free threshold,
        // the selectedAddon copy may have price=0 and freeQty=0 (lost during cloning).
        // Always resolve freeQty and the addon's actual catalog price from existAddOns.
        final Map<int, AddonModel> existAddOnMap = {};
        for (var ea in item.unit.existAddOns) {
          existAddOnMap[ea.prdId] = ea;
        }

        // ── Current addon map: selectedAddons override existAddOns ───────────────
        final Map<int, AddonModel> currentAddonMap = {};
        for (var ea in item.unit.existAddOns) {
          if (ea.prdaddon_flags == 1) currentAddonMap[ea.prdId] = ea;
        }
        for (var sa in item.selectedAddons) {
          currentAddonMap[sa.prdId] = sa; // user selection wins
        }

        bool anyAddonChanged = false;
        final Set<int> processedPrdIds = {};

        for (var addon in currentAddonMap.values) {
          if (processedPrdIds.contains(addon.prdId)) continue;
          processedPrdIds.add(addon.prdId);

          final bool userTouched = item.selectedAddons.any(
            (sa) => sa.prdId == addon.prdId,
          );

          // ── Resolve selected version ─────────────────────────────────────────
          final AddonModel? selectedVersion = item.selectedAddons
              .firstWhereOrNull((sa) => sa.prdId == addon.prdId);

          // ── SOURCE OF TRUTH: always read freeQty & catalog price from existAddOns ──
          // The selectedAddon copy can lose freeQty (cloned as 0) and price (cloned as 0
          // for free addons) — both are needed to correctly split free vs paid portions.
          final AddonModel? existSource = existAddOnMap[addon.prdId];
          final int resolvedFreeQty = existSource?.freeQty ?? addon.freeQty;
          // catalogPrice = the price charged per unit BEYOND the free threshold.
          // For a free addon (prdaddon_flags==1), this is existAddOn.price (may be > 0).
          // For an explicitly paid addon selected by the user, use selectedVersion.price.
          final double catalogPrice = existSource?.price ?? addon.price;

          // effectivePrice: what the user explicitly chose to pay (0 if it's a free addon
          // they just incremented, > 0 if they picked a paid variant).
          // effectivePrice: what the user explicitly chose to pay.
          // IMPORTANT: If the addon has a free threshold (resolvedFreeQty > 0) or is flagged
          // as a free/default addon (prdaddon_flags == 1), it must stay effectivePrice = 0
          // so the free/paid split logic correctly allocates qty ≤ freeLimit as FREE
          // and only the overflow as PAID (at catalogPrice). Setting effectivePrice > 0
          // would incorrectly send ALL qty as paid with no free portion.
          // AFTER — only resolvedFreeQty determines free-type:
          final bool isFreeAddonType = resolvedFreeQty > 0;

          final double effectivePrice = (userTouched && !isFreeAddonType)
              ? (selectedVersion?.price ?? addon.price)
              : (isFreeAddonType ? 0.0 : addon.price);

          // ── Current qty ──────────────────────────────────────────────────────
          int currentQty;
          if (!userTouched && resolvedFreeQty > 0) {
            currentQty = newQty * resolvedFreeQty; // mirrors parent qty
          } else {
            currentQty = addon.quantity.value;
          }

          // ── Old qty from initialQty snapshot ─────────────────────────────────
          final originalAddon = originalByPrdId[addon.prdId];
          final int oldQtySnapshot = unitChanged
              ? 0
              : (originalAddon?.initialQty ?? 0);
          final String addonSubId = unitChanged
              ? ""
              : (originalAddon?.subId?.toString() ?? "");

          // ── Free / paid split ─────────────────────────────────────────────────
          // Rules:
          //  • effectivePrice > 0  → user picked an explicitly paid addon: ALL qty is paid.
          //  • effectivePrice == 0 AND resolvedFreeQty > 0
          //      → qty ≤ freeLimit is FREE, qty > freeLimit is PAID OVERFLOW
          //        (charged at catalogPrice, which comes from existAddOns).
          //  • effectivePrice == 0 AND resolvedFreeQty == 0 → all qty is free (no cap).

          final bool hasFreeThreshold = resolvedFreeQty > 0;
          final int freeLimit = hasFreeThreshold
              ? (newQty * resolvedFreeQty)
              : 0;

          final int currentFreePart = (effectivePrice == 0 && hasFreeThreshold)
              ? currentQty.clamp(0, freeLimit)
              : (effectivePrice == 0 && !hasFreeThreshold)
              ? currentQty // purely free, no cap
              : 0; // paid addon: no free portion

          final int currentPaidPart = (effectivePrice > 0)
              ? currentQty // explicitly paid: all qty is paid
              : (hasFreeThreshold
                    ? (currentQty - currentFreePart).clamp(0, 99999) // overflow
                    : 0); // purely free: no paid portion

          // Old split (same logic against oldQtySnapshot)
          final int oldFreeLimit = hasFreeThreshold
              ? (oldQty * resolvedFreeQty)
              : 0;
          final int oldFreePart = (effectivePrice == 0 && hasFreeThreshold)
              ? oldQtySnapshot.clamp(0, oldFreeLimit)
              : (effectivePrice == 0 && !hasFreeThreshold)
              ? oldQtySnapshot
              : 0;
          final int oldPaidPart = (effectivePrice > 0)
              ? oldQtySnapshot
              : (hasFreeThreshold
                    ? (oldQtySnapshot - oldFreePart).clamp(0, 99999)
                    : 0);

          log(
            "│  ADDON: ${addon.name}  userTouched: $userTouched"
            "  effectivePrice: $effectivePrice  catalogPrice: $catalogPrice"
            "  resolvedFreeQty: $resolvedFreeQty  currentQty: $currentQty  oldQty: $oldQtySnapshot",
          );
          log(
            "│         freeLimit: $freeLimit  currentFree: $currentFreePart  currentPaid: $currentPaidPart",
          );
          log(
            "│         oldFreeLimit: $oldFreeLimit  oldFree: $oldFreePart  oldPaid: $oldPaidPart  subId: $addonSubId",
          );

          // ── Free portion ─────────────────────────────────────────────────────
          final bool freeChanged =
              currentFreePart != oldFreePart || unitChanged;

          if (currentFreePart > 0 || oldFreePart > 0) {
            if (freeChanged) {
              anyAddonChanged = true;
              hasAnyChange = true;
            }

            if (currentFreePart > 0 && (freeChanged || parentChanged)) {
              log(
                "│  >>> FREE PART: ${addon.name}  qty: $currentFreePart  oldQty: $oldFreePart  subId: $addonSubId",
              );
              saleItems.add({
                "sales_ord_sub_id": addonSubId,
                "prd_name": addon.name,
                "salesub_prd_id": addon.prdId,
                "salesub_rate": 0,
                "salesub_rate_tmp": 0,
                "salesub_price": 0,
                "salesub_tax": 0,
                "salesub_tax_per": isVatDisabled ? 0 : addon.taxPer,
                "salesub_qty": currentFreePart,
                "count": oldFreePart,
                "sale_total_amount": 0,
                "salesub_tax_amnt": 0,
                "base_qty": addon.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": addon.unitId,
                "prd_tax_cat_id": addon.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": addon.unitDisplay,
                "taxvalperqty": 0,
                "salesub_amnt": 0,
                "is_addon": 1,
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.unit.unitId,
                "is_default": 1,
                "is_edited":
                    addonSubId.isNotEmpty && currentFreePart != oldFreePart,
                "oldqty": oldFreePart,
                "Item_descp": "",
                "is_deleted": 0,
              });
            } else if (currentFreePart == 0 &&
                oldFreePart > 0 &&
                addonSubId.isNotEmpty) {
              log(
                "│  >>> DELETE FREE PART: ${addon.name}  subId: $addonSubId  oldQty: $oldFreePart",
              );
              anyAddonChanged = true;
              hasAnyChange = true;
              saleItems.add({
                "sales_ord_sub_id": addonSubId,
                "prd_name": addon.name,
                "salesub_prd_id": addon.prdId,
                "salesub_rate": 0,
                "salesub_rate_tmp": 0,
                "salesub_price": 0,
                "salesub_tax": 0,
                "salesub_tax_per": 0,
                "salesub_qty": 0,
                "count": oldFreePart,
                "sale_total_amount": 0,
                "salesub_tax_amnt": 0,
                "base_qty": addon.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": addon.unitId,
                "prd_tax_cat_id": addon.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": addon.unitDisplay,
                "taxvalperqty": 0,
                "salesub_amnt": 0,
                "is_addon": 1,
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.unit.unitId,
                "is_default": 1,
                "is_edited": false,
                "oldqty": oldFreePart,
                "Item_descp": "",
                "is_deleted": 1,
              });
            } else if (!freeChanged && !parentChanged) {
              log("│  SKIP free part ${addon.name} - no change");
            }
          }

          // ── Paid portion ──────────────────────────────────────────────────────
          // paidRate:
          //   • Explicitly paid addon (effectivePrice > 0) → use effectivePrice.
          //   • Free addon overflow (effectivePrice == 0, qty > freeLimit)
          //     → use catalogPrice from existAddOns (the real per-unit charge).
          final bool paidChanged =
              currentPaidPart != oldPaidPart || unitChanged;

          if (currentPaidPart > 0 || oldPaidPart > 0) {
            final double paidRate = effectivePrice > 0
                ? effectivePrice
                : catalogPrice;
            final double addonTaxPerUnit = isVatDisabled
                ? 0
                : (paidRate * addon.taxPer) / 100;

            // subId resolution:
            //  • Explicitly paid addon → look for original paid record.
            //  • Free-addon overflow   → no prior paid sub record → "" (server creates new).
            final AddonModel? originalPaidRecord = item.originalAddons
                ?.firstWhereOrNull(
                  (a) => a.prdId == addon.prdId && a.price > 0,
                );

            final String paidSubId = unitChanged
                ? ""
                : (originalPaidRecord?.subId?.toString() ??
                      (effectivePrice > 0 ? addonSubId : ""));

            if (paidChanged) {
              anyAddonChanged = true;
              hasAnyChange = true;
            }

            if (currentPaidPart > 0 && (paidChanged || parentChanged)) {
              log(
                "│  >>> PAID PART: ${addon.name}  qty: $currentPaidPart  oldQty: $oldPaidPart"
                "  paidRate: $paidRate  subId: $paidSubId"
                "  (overflow: ${effectivePrice == 0 && hasFreeThreshold})",
              );
              saleItems.add({
                "sales_ord_sub_id": paidSubId,
                "prd_name": addon.name,
                "salesub_prd_id": addon.prdId,
                "salesub_rate": paidRate,
                "salesub_rate_tmp": paidRate,
                "salesub_price": paidRate,
                "salesub_tax": addonTaxPerUnit,
                "salesub_tax_per": isVatDisabled ? 0 : addon.taxPer,
                "salesub_qty": currentPaidPart,
                "count": oldPaidPart,
                "sale_total_amount":
                    (paidRate + addonTaxPerUnit) * currentPaidPart,
                "salesub_tax_amnt": addonTaxPerUnit * currentPaidPart,
                "base_qty": addon.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": addon.unitId,
                "prd_tax_cat_id": addon.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": addon.unitDisplay,
                "taxvalperqty": addonTaxPerUnit,
                "salesub_amnt": paidRate * currentPaidPart,
                "is_addon": 0, // paid portion is never free
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.unit.unitId,
                "is_default": 0,
                "is_edited":
                    paidSubId.isNotEmpty && currentPaidPart != oldPaidPart,
                "oldqty": oldPaidPart,
                "Item_descp": "",
                "is_deleted": 0,
              });
              totalTax += addonTaxPerUnit * currentPaidPart;
              totalWithTax += (paidRate + addonTaxPerUnit) * currentPaidPart;
            } else if (currentPaidPart == 0 &&
                oldPaidPart > 0 &&
                paidSubId.isNotEmpty) {
              log(
                "│  >>> DELETE PAID PART: ${addon.name}  subId: $paidSubId  oldQty: $oldPaidPart",
              );
              anyAddonChanged = true;
              hasAnyChange = true;
              saleItems.add({
                "sales_ord_sub_id": paidSubId,
                "prd_name": addon.name,
                "salesub_prd_id": addon.prdId,
                "salesub_rate": 0,
                "salesub_rate_tmp": 0,
                "salesub_price": 0,
                "salesub_tax": 0,
                "salesub_tax_per": 0,
                "salesub_qty": 0,
                "count": oldPaidPart,
                "sale_total_amount": 0,
                "salesub_tax_amnt": 0,
                "base_qty": addon.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": addon.unitId,
                "prd_tax_cat_id": addon.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": addon.unitDisplay,
                "taxvalperqty": 0,
                "salesub_amnt": 0,
                "is_addon": 1,
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.unit.unitId,
                "is_default": 0,
                "is_edited": false,
                "oldqty": oldPaidPart,
                "Item_descp": "",
                "is_deleted": 1,
              });
            } else if (!paidChanged && !parentChanged) {
              log("│  SKIP paid part ${addon.name} - no change");
              totalTax += addonTaxPerUnit * currentPaidPart;
              totalWithTax += (paidRate + addonTaxPerUnit) * currentPaidPart;
            }
          }
        }

        // ── Addons removed entirely (in originalAddons but not in currentAddonMap) ─
        if (item.originalAddons != null && !unitChanged) {
          for (var oa in item.originalAddons!) {
            if (oa.subId == null) continue;
            if (!currentAddonMap.containsKey(oa.prdId) && oa.initialQty > 0) {
              hasAnyChange = true;
              anyAddonChanged = true;
              final bool wasFree = oa.price == 0;
              log(
                "│  >>> REMOVED ADDON: ${oa.name}  subId: ${oa.subId}  oldQty: ${oa.initialQty}",
              );
              saleItems.add({
                "sales_ord_sub_id": oa.subId,
                "prd_name": oa.name,
                "salesub_prd_id": oa.prdId,
                "salesub_rate": 0,
                "salesub_rate_tmp": 0,
                "salesub_price": 0,
                "salesub_tax": 0,
                "salesub_tax_per": oa.taxPer,
                "salesub_qty": 0,
                "count": oa.initialQty,
                "sale_total_amount": 0,
                "salesub_tax_amnt": 0,
                "base_qty": oa.unitBaseQty,
                "item_disc": 0,
                "salesub_unit_id": oa.unitId,
                "prd_tax_cat_id": oa.taxCatId,
                "salesub_gd_id": 0,
                "salesub_unit_display": oa.unitDisplay,
                "taxvalperqty": 0,
                "salesub_amnt": 0,
                "is_addon": 1,
                "addon_parent_prd_id": int.tryParse(item.product.id),
                "addon_parent_unit_id": item.originalUnitId ?? item.unit.unitId,
                "is_default": wasFree ? 1 : 0,
                "is_edited": false,
                "oldqty": oa.initialQty,
                "Item_descp": "",
                "is_deleted": 1,
              });
            }
          }
        }

        if (!parentChanged && anyAddonChanged && item.subId != null) {
          log(
            "│  >>> ADDONS CHANGED - parent already included above as context ✅",
          );
        }

        log("└─ END ITEM: ${item.product.name}");
      }

      // ── Final summary log ─────────────────────────────────────────────────────
      log("╔══════════════════════════════════════════");
      log("║ FINAL SUMMARY");
      log("║ saleItems count: ${saleItems.length}");
      log("║ totalTax: $totalTax");
      log("║ totalWithTax: $totalWithTax");
      log("╠══════════════════════════════════════════");
      for (var si in saleItems) {
        log("║ → ${si['prd_name']}");
        log(
          "║     qty: ${si['salesub_qty']}  count: ${si['count']}  base_qty: ${si['base_qty']}",
        );
        log(
          "║     unitId: ${si['salesub_unit_id']}  unitDisplay: ${si['salesub_unit_display']}",
        );
        log("║     addonParentUnit: ${si['addon_parent_unit_id']}");
        log(
          "║     deleted: ${si['is_deleted']}  isAddon: ${si['is_addon']}  subId: ${si['sales_ord_sub_id']}",
        );
      }
      log("╚══════════════════════════════════════════");

      if (!hasAnyChange) {
        log("No changes detected");
        _clearDashboardSearch();
        return {"no_change": true};
      }

      final body = {
        "usr_id": int.tryParse(AppState.userId) ?? 0,
        "cust_type": "1",
        "cust_id": null,
        "cust_name": "Cash Customer",
        "saleqt_date": dateStr,
        "sale_items": saleItems,
        "sq_total": totalWithTax,
        "advance_amount": 0,
        "sale_pay_type": 2,
        "balance_amount": 0,
        "sale_acc_ledger_id": 0,
        "sq_tax": totalTax,
        "inv_type": 2,
        "pos_odr_type": AppState.orderType.id,
        "address": null,
        "phone_no": null,
        "vat_no": null,
        "no_seats": selectedChairCount.value,
        "sale_agent": GetStorage().read('ledger_id'),
        "is_pos": true,
        "salesub_gd_id": 0,
        "res_table": {
          "rt_id": int.tryParse(selectedTableId.value),
          "rt_area_id": selectedAreaId.value,
          "rt_name": selectedTableName.value,
          "rt_seat_count": selectedChairCount.value,
          "rt_image": null,
          "rt_is_default": 0,
          "rt_avl_seat": selectedChairCount.value,
          "rt_status": 1,
          "processing_table": editingOrderFullData != null
              ? [editingOrderFullData]
              : [],
          "prcgrp_id": selectedPriceGroupId.value,
        },
        "res_status": isDraft ? 0 : 1,
        "sq_inv_no": int.tryParse(editingInvNo.value) ?? 0,
        "sq_disc": 0,
        "sale_acc_ledger_id_bank": null,
        "sale_acc_ledger_id_cash": null,
        "card_amnt": null,
        "cash_amnt": null,
        "sales_roundoff": 0,
        "table_name": selectedTableName.value,
        "sales_is_rest_pos": 1,
        "is_compliment": 0,
        "is_pos_edit": true,
        "is_split": false,
        "split_amnt": [],
        "split_count": null,
        "server_sync_time": syncTime,
      };

      log("Final Body with ${saleItems.length} items");
      log('Api Body: ${jsonEncode(body)}');

      // --- LOCAL DB UPDATE ---
      try {
        final bool editingUnsyncedOrder =
            editingOrderId.value.startsWith('ORD-') ||
            editingInvNo.value.isEmpty ||
            editingInvNo.value == 'OFFLINE' ||
            (int.tryParse(editingInvNo.value) ?? 0) == 0;

        // ✅ Override is_pos_edit in the payload so SyncService picks the right endpoint
        final Map<String, dynamic> payloadToSave = {
          ...body,
          'is_pos_edit': !editingUnsyncedOrder, // false = add, true = update
        };
        await _dbHelper.updateOrderStatusByServerId(
          editingOrderId.value,
          isDraft ? 'draft' : 'pending',
          isSynced: 0,
          total: totalWithTax,
          tax: totalTax,
          payload: jsonEncode(payloadToSave),
        );
      } catch (dbError) {
        log("❌ Local DB Update Error: $dbError");
      }

      // --- TRY API CALL ---
      try {
        final response = await _apiService.post(
          "mobileapp/pos/update_sales_order",
          data: body,
        );

        if (response.statusCode == 200) {
          dynamic data = response.data;
          if (data is String) {
            data = jsonDecode(data);
          }

          if (data is Map && data['message'] != null) {
            final message = data['message'];
            if (message is Map && message['status'] == 0) {
              showSafeSnackbar("Error", message['msg'] ?? "Update failed");
              return null;
            }
          }

          final prettyResponse = const JsonEncoder.withIndent(
            '  ',
          ).convert(data);
          log("✅ SUCCESS RESPONSE (updateOrder):\n$prettyResponse");

          // Mark as synced locally
          await _dbHelper.updateOrderStatusByServerId(
            editingOrderId.value,
            isDraft ? 'draft' : 'pending',
            isSynced: 1,
          );

          _clearDashboardSearch();
          return data;
        }
      } catch (apiError) {
        log(
          "⚠️ API Update Failed (Offline): $apiError. Update preserved locally.",
        );
        _clearDashboardSearch();

        // Build a proper synthetic response so parseOrderResponse + KOT printing work
        final syntheticResponse = _buildOfflineUpdateResponse(
          body: body,
          saleItems: saleItems,
          totalWithTax: totalWithTax,
          totalTax: totalTax,
          isDraft: isDraft,
          now: now,
        );
        return syntheticResponse;
      }

      return null;
    } catch (e) {
      log("❌ Error in updateOrder: $e");
      return null;
    } finally {
      // isProcessing.value = false; // Handled in UI for better UX
    }
  }

  Future<bool> cancelOrder(String invNo) async {
    try {
      final body = {
        "usr_id": int.tryParse(AppState.userId) ?? 18,
        "sales_odr_inv_no": int.tryParse(invNo) ?? 0,
      };

      final response = await _apiService.post(
        "mobileapp/pos/cancel_sales_order",
        data: body,
      );

      if (response.statusCode == 200) {
        if (editingInvNo.value == invNo) {
          stopEditing();
        }
        return true;
      }
      return false;
    } catch (e) {
      log("❌ Error in cancelOrder: $e");
      return false;
    }
  }

  /// Constructs a synthetic server response for offline orders.
  /// Shape matches the real add_sales_order response so all consumers
  /// (parseOrderResponse, KOT printer, OrdersController) work identically.
  Map<String, dynamic> _buildOfflineResponse({
    required String orderUuid,
    required Map<String, dynamic> body,
    required double totalWithTax,
    required double totalTax,
    required List<Map<String, dynamic>> saleItems,
    required bool isDraft,
    required DateTime now,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    // Build sales_order_sub from saleItems so the printer has full item data
    final List<Map<String, dynamic>> orderSub = [];
    int fakeSubId = 1;
    for (final item in saleItems) {
      orderSub.add({
        "sales_ord_sub_id": fakeSubId++,
        "sales_ord_sub_ord_id": 0, // unknown until synced
        "sales_ord_sub_sales_inv_no": 0, // unknown until synced
        "sales_ord_sub_prod_id": item["salesub_prd_id"],
        "sales_ord_sub_rate": item["salesub_rate"],
        "sales_ord_sub_qty": item["salesub_qty"],
        "sales_ord_sub_rem_qty": item["salesub_qty"],
        "sales_ord_sub_discount": 0,
        "sales_ord_sub_date": dateStr,
        "sales_ord_sub_flags": 1,
        "sales_ord_sub_unit_id": item["salesub_unit_id"],
        "sales_ord_sub_tax_per": item["salesub_tax_per"],
        "sales_ord_sub_taxcat_id": item["prd_tax_cat_id"],
        "sales_ord_sub_tax_rate": item["salesub_tax"],
        "sales_odr_sub_is_addon": item["is_addon"],
        "sales_odr_sub_is_compliment": 0,
        "sales_ord_sub_is_kot_printed": 0,
        "sales_odr_sub_addon_parent_prd_id": item["addon_parent_prd_id"] ?? 0,
        "sales_odr_sub_addon_parent_unit_id": item["addon_parent_unit_id"] ?? 0,
        "prd_name": item["prd_name"],
        "unit_display": item["salesub_unit_display"],
        "unit_base_qty": item["base_qty"],
        "cat_token_printer": _getTokenPrinterForItem(item),
      });
    }

    final resTable = body["res_table"] as Map<String, dynamic>? ?? {};

    return {
      "status": 200,
      "message": "Sales Order Added successfully (offline)",
      "id": null,
      "offline": true, // flag so callers can show "pending sync" if needed
      "preview": {
        "sales_odr_id": null, // filled after SyncService pushes it
        "sales_odr_inv_no": null,
        "sales_odr_date": dateStr,
        "sales_odr_time": timeStr,
        "sales_odr_total": totalWithTax,
        "sales_odr_tax": totalTax,
        "sales_odr_pos_status": isDraft ? 0 : 1,
        "sales_odr_table_id": resTable["rt_id"],
        "sales_odr_table_name": body["table_name"],
        "sales_odr_no_seats": body["no_seats"],
        "sales_odr_order_type": AppState.orderType.id,
        // store uuid so callers can identify the local record
        "local_uuid": orderUuid,
        "sales_order_sub": orderSub,
      },
    };
  }

  Map<String, dynamic> _buildOfflineUpdateResponse({
    required Map<String, dynamic> body,
    required List<Map<String, dynamic>> saleItems,
    required double totalWithTax,
    required double totalTax,
    required bool isDraft,
    required DateTime now,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    int fakeSubId = 1;
    final List<Map<String, dynamic>> orderSub = [];

    for (final si in saleItems) {
      // Skip items marked for deletion — they shouldn't appear on the KOT
      final int isDeleted = (si['is_deleted'] as num? ?? 0).toInt();
      if (isDeleted == 1) continue;

      final int qty = (si['salesub_qty'] as num? ?? 0).toInt();
      if (qty <= 0) continue;

      final int isAddon = (si['is_addon'] as num? ?? 0).toInt();
      final String prdId = si['salesub_prd_id']?.toString() ?? '';
      final int unitId = (si['salesub_unit_id'] as num? ?? 0).toInt();

      // Resolve the existing sub ID — for edits this is the real server sub ID,
      // for new items added during the edit it will be empty/null.
      final existingSubId = si['sales_ord_sub_id'];
      final int resolvedSubId =
          (existingSubId != null &&
              existingSubId.toString().isNotEmpty &&
              existingSubId.toString() != 'null')
          ? int.tryParse(existingSubId.toString()) ?? fakeSubId++
          : fakeSubId++;

      // Find matching cart item for token printer routing
      final cartItem = cartItems.firstWhereOrNull(
        (c) =>
            c.product.id == prdId &&
            c.unit.unitId == unitId &&
            !c.isDeleted.value,
      );

      orderSub.add({
        // Server response field names (what parseOrderResponse reads)
        "sales_ord_sub_id": resolvedSubId,
        "sales_ord_sub_ord_id": 0,
        "sales_ord_sub_sales_inv_no": 0,
        "sales_ord_sub_prod_id": si['salesub_prd_id'],
        "sales_ord_sub_rate": si['salesub_rate'],
        "sales_ord_sub_qty": qty,
        "sales_ord_sub_rem_qty": qty,
        "sales_ord_sub_discount": 0,
        "sales_ord_sub_date": dateStr,
        // is_edited items get flags==2 on server; we use 1 for offline display
        "sales_ord_sub_flags": 1,
        "sales_ord_sub_unit_id": si['salesub_unit_id'],
        "sales_ord_sub_tax_per": si['salesub_tax_per'],
        "sales_ord_sub_taxcat_id": si['prd_tax_cat_id'],
        "sales_ord_sub_tax_rate": si['salesub_tax'],
        "sales_odr_sub_is_addon": isAddon,
        "sales_odr_sub_is_compliment": 0,
        "sales_ord_sub_is_kot_printed": 0,
        "sales_odr_sub_addon_parent_prd_id": si['addon_parent_prd_id'] ?? 0,
        "sales_odr_sub_addon_parent_unit_id": si['addon_parent_unit_id'] ?? 0,
        // Display fields
        "prd_name": si['prd_name'],
        "unit_display": si['salesub_unit_display'],
        "baseUnitDis": si['salesub_unit_display'],
        "unit_base_qty": si['base_qty'] ?? 1.0,
        "prd_img_url": cartItem?.product.image ?? '',
        "prd_cat_id": cartItem?.product.categoryId ?? '',
        "cat_token_printer": cartItem != null
            ? _getTokenPrinterForItem(si)
            : null,
        // Aliases parseOrderResponse also reads
        "rate": si['salesub_rate'],
        "sales_ord_sub_amnt": si['salesub_amnt'],
        "salesub_qty": qty,
        "salesub_unit_id": si['salesub_unit_id'],
      });
    }

    final resTable = body["res_table"] as Map<String, dynamic>? ?? {};
    final processingTableList =
        resTable["processing_table"] as List<dynamic>? ?? [];
    final processingTable = processingTableList.isNotEmpty
        ? processingTableList.first as Map<String, dynamic>?
        : null;

    // For edits, the real server ID is in processing_table.sq_id
    final String? realServerId =
        processingTable?['sq_id']?.toString() ??
        processingTable?['sales_odr_id']?.toString();
    final String? realInvNo =
        processingTable?['sq_inv_no']?.toString() ??
        processingTable?['sales_odr_inv_no']?.toString();

    return {
      "status": 200,
      "offline": true,
      "message": {"status": 1, "msg": "Update saved locally (Offline)"},
      "id": realServerId,
      "preview": {
        "sales_odr_id": realServerId,
        "sales_odr_inv_no": realInvNo ?? editingInvNo.value,
        "sales_odr_date": dateStr,
        "sales_odr_time": timeStr,
        "sales_odr_total": totalWithTax,
        "sales_odr_tax": totalTax,
        "sales_odr_pos_status": isDraft ? 0 : 1,
        "sales_odr_table_id": resTable["rt_id"],
        "sales_odr_table_name": body["table_name"],
        "sales_odr_no_seats": body["no_seats"],
        "sales_odr_order_type": AppState.orderType.id,
        "sales_order_sub": orderSub,
      },
    };
  }

  /// Look up the token_printer_id for a sale item from the cart.
  int? _getTokenPrinterForItem(Map<String, dynamic> item) {
    final prdId = item["salesub_prd_id"]?.toString();
    if (prdId == null) return null;

    // Find the item in the current cart to get its tokenPrinterId
    final cartItem = cartItems.firstWhereOrNull(
      (c) => c.product.id == prdId && !c.isDeleted.value,
    );

    return cartItem?.product.tokenPrinterId;
  }
}
