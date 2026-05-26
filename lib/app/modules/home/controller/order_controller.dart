import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:intl/intl.dart';
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import '../../../../helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_type.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../../order_type/controller/order_type_controller.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';
import 'home_controller.dart';

class OrdersController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final orders = <OrderModel>[].obs;
  final soldOrders = <OrderModel>[].obs; // ✅ Add separate list for sold orders
  final isLoading = false.obs;

  // Filter for sold orders
  final selectedSoldDate = DateTime.now().obs;

  // Timer for running clock
  Timer? _timer;
  final currentTime = DateTime.now().obs;

  @override
  void onInit() {
    super.onInit();
    fetchOrders();
    _startTimer();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value = DateTime.now();
    });
  }

  String getElapsedTime(DateTime createdAt) {
    final diff = currentTime.value.difference(createdAt);
    if (diff.isNegative) return "00:00";

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);

    if (hours > 0) {
      return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  Future<void> fetchOrders() async {
    try {
      isLoading.value = true;

      // Fetch active and sold orders in parallel
      await Future.wait([
        _fetchActiveOrders(),
        _fetchSoldOrders(),
      ]);
    } catch (e) {
      debugPrint("Error fetching orders: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchActiveOrders() async {
    try {
      // 1. Load local unsynced orders first — works fully offline
      final unsyncedData = await _dbHelper.getUnsyncedOrders();
      final List<OrderModel> finalOrders = unsyncedData.map((json) => _mapJsonToOrderModel(json)).toList();

      // 2. Load server orders and processing tables
      List<OrderModel> allProcessingOrders = [];
      try {
        final tablesController = Get.find<TablesController>();
        await tablesController.fetchTables();

        for (var area in tablesController.areas) {
          for (var table in area.tables) {
            for (var processing in table.processingTable) {
              if (processing is Map<String, dynamic>) {
                final orderType = (processing['sales_odr_order_type'] as num? ?? 0).toInt();
                int posStatus = (processing['sales_odr_pos_status'] as num? ?? 0).toInt();
                OrderStatus status = (posStatus == 1) ? OrderStatus.pending : OrderStatus.draft;

                allProcessingOrders.add(OrderModel(
                  id: (processing['sales_odr_id'] ?? '').toString(),
                  tableId: (processing['sales_odr_table_id'] ?? table.id).toString(),
                  invNo: (processing['sales_odr_inv_no'] ?? '').toString(),
                  tableName: processing['sales_odr_table_name']?.toString() ?? table.name,
                  chairNumber: (processing['sales_odr_no_seats'] as num? ?? 0).toInt(),
                  sales_odr_pos_status: posStatus,
                  items: [],
                  status: status,
                  createdAt: DateTime.tryParse(processing['sales_odr_datetime'] ?? '') ?? DateTime.now(),
                  totalAmount: (processing['sales_odr_total'] as num? ?? 0.0).toDouble(),
                  areaId: area.id,
                  areaName: area.name,
                  priceGroupId: area.priceGroupID,
                  totalTax: (processing['sales_odr_tax'] as num? ?? 0.0).toDouble(),
                  sales_odr_order_type: orderType,
                ));
              }
            }
          }
        }
      } catch (e) {
        debugPrint("fetchOrders: Could not load tables (offline?): $e");
      }

      List<OrderModel> fetchedOrders = [];
      try {
        final response = await _apiService.post("mobileapp/pos/get_pos_order_list", data: {
          "usr_id": int.tryParse(AppState.userId) ?? 18,
        });

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];
          fetchedOrders = data.map((json) {
            final orderType = (json['sales_odr_order_type'] as num? ?? 0).toInt();
            int posStatus = (json['sales_odr_pos_status'] as num? ?? 0).toInt();
            OrderStatus status = (posStatus == 1) ? OrderStatus.pending : OrderStatus.draft;

            final processingOrder = allProcessingOrders.firstWhereOrNull(
                  (o) => o.invNo == (json['sales_odr_inv_no'] ?? '').toString(),
            );

            return OrderModel(
              id: (json['sales_odr_id'] ?? '').toString(),
              tableId: (json['sales_odr_table_id'] ?? processingOrder?.tableId ?? '').toString(),
              invNo: (json['sales_odr_inv_no'] ?? '').toString(),
              tableName: json['sales_odr_table_name']?.toString() ??
                  json['ledger_name']?.toString() ??
                  processingOrder?.tableName ?? 'Unknown Table',
              chairNumber: (json['sales_odr_no_seats'] as num? ??
                  processingOrder?.chairNumber ?? 0).toInt(),
              sales_odr_pos_status: posStatus,
              items: [],
              status: status,
              createdAt: DateTime.tryParse(json['sales_odr_datetime'] ?? '') ??
                  processingOrder?.createdAt ?? DateTime.now(),
              totalAmount: (json['sales_odr_total'] as num? ?? 0.0).toDouble(),
              areaId: processingOrder?.areaId,
              areaName: processingOrder?.areaName,
              priceGroupId: processingOrder?.priceGroupId,
              totalTax: (json['sales_odr_tax'] as num? ?? 0.0).toDouble(),
              sales_odr_order_type: orderType,
            );
          }).toList();
        }
      } catch (e) {
        debugPrint("fetchOrders: Could not load order list (offline?): $e");
      }

      // Reusable reconciliation function
      void reconcileOrder(OrderModel serverOrder) {
        final int existingIndex = finalOrders.indexWhere((o) {
          if (o.invNo != "LOCAL" && o.invNo != "OFFLINE" && serverOrder.invNo != "LOCAL" && serverOrder.invNo != "OFFLINE" && o.invNo == serverOrder.invNo) {
            return true;
          }
          return o.id == serverOrder.id;
        });

        if (existingIndex != -1) {
          // If the order is in any API result, it's SYNCED on the server.
          finalOrders[existingIndex].isUnsynced = false;

          // Use server data but keep local items if they were loaded
          final localOrder = finalOrders[existingIndex];
          if (localOrder.items.isNotEmpty && serverOrder.items.isEmpty) {
             // Keep local items
          } else if (serverOrder.items.isNotEmpty) {
             localOrder.items.clear();
             localOrder.items.addAll(serverOrder.items);
          }

          // Auto-repair local DB sync status
          _dbHelper.updateOrderStatusByUuid(
            localOrder.id,
            localOrder.status.value.name,
            isSynced: 1,
            serverId: serverOrder.id,
            invNo: serverOrder.invNo,
          );
        } else {
          finalOrders.add(serverOrder);
        }
      }

      // 3. Merge server sources into finalOrders with Priority
      // Priority 2: Orders fetched from API
      for (var fOrder in fetchedOrders) {
        reconcileOrder(fOrder);
      }

      // Priority 3: Orders from processing tables cache
      for (var pOrder in allProcessingOrders) {
        reconcileOrder(pOrder);
      }

      finalOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      orders.assignAll(finalOrders);

    } catch (e) {
      debugPrint("Error fetching active orders: $e");
    }
  }

  Future<void> _fetchSoldOrders() async {
    try {
      final cachedSoldData = await _dbHelper.getOrdersByStatus(['paid']);
      final List<OrderModel> cachedSoldOrders = cachedSoldData
          .map((json) => _mapJsonToOrderModel(json))
          .toList();

      if (cachedSoldOrders.isNotEmpty) {
        soldOrders.assignAll(cachedSoldOrders);
      }

      try {
        final String dateStr = DateFormat('yyyy-MM-dd').format(selectedSoldDate.value);
        final response = await _apiService.post(
          "mobileapp/pos/get_sold_pos_order_list",
          data: {
            "usr_id": int.tryParse(AppState.userId) ?? 18,
            "date": dateStr,
          },
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data['data'] ?? [];

          final List<OrderModel> apiSoldOrders = data.map((json) {
            return OrderModel(
              id: (json['sales_odr_id'] ?? '').toString(),
              invNo: (json['sales_odr_inv_no'] ?? '').toString(),
              tableId: (json['sales_odr_table_id'] ?? '').toString(),
              tableName: json['ledger_name']?.toString() ??
                  json['sales_odr_table_name']?.toString() ??
                  'Walk-in Customer',
              chairNumber: 0,
              sales_odr_pos_status: (json['sales_odr_pos_status'] as num? ?? 3).toInt(),
              items: [],
              status: OrderStatus.paid,
              createdAt: DateTime.tryParse(
                  json['sales_odr_datetime'] ?? json['created_at'] ?? '') ??
                  DateTime.now(),
              totalAmount: (json['sales_odr_total'] as num? ?? 0.0).toDouble(),
              totalTax: (json['sales_odr_tax'] as num? ?? 0.0).toDouble(),
              areaId: null,
              areaName: null,
              priceGroupId: null,
              sales_odr_order_type:
              (json['sales_odr_order_type'] as num? ?? 0).toInt(),
              isUnsynced: false,
            );
          }).toList();

          await _dbHelper.cacheSoldOrders(data);

          // ── Build a lookup of LOCAL/OFFLINE cached orders → their real
          //    server invNo (read from DB, written by SyncService after sync)
          final Map<String, String> localUuidToRealInvNo = {};
          final db = await _dbHelper.database;
          for (var cached in cachedSoldOrders) {
            if (cached.invNo == "LOCAL" || cached.invNo == "OFFLINE") {
              final rows = await db.query(
                'orders',
                columns: ['inv_no', 'is_synced'],
                where: 'uuid = ? OR server_id = ?',
                whereArgs: [cached.id, cached.id],
                limit: 1,
              );
              if (rows.isNotEmpty) {
                final dbInvNo = rows.first['inv_no']?.toString() ?? '';
                final isSynced = rows.first['is_synced'] as int? ?? 0;
                if (isSynced == 1 &&
                    dbInvNo.isNotEmpty &&
                    dbInvNo != "LOCAL" &&
                    dbInvNo != "OFFLINE") {
                  localUuidToRealInvNo[cached.id] = dbInvNo;
                }
              }
            }
          }

          // ── Merge: API is authoritative; suppress any cached entry that
          //    maps to an invNo already covered by the API result
          final Set<String> apiInvNos =
          apiSoldOrders.map((o) => o.invNo).toSet();

          final List<OrderModel> mergedList = [];

          // 1. Add API orders first
          mergedList.addAll(apiSoldOrders);

          // 2. Add cached orders only when they have no API counterpart
          for (var cached in cachedSoldOrders) {
            // Direct invNo match → API already has it
            if (cached.invNo != "LOCAL" &&
                cached.invNo != "OFFLINE" &&
                apiInvNos.contains(cached.invNo)) {
              continue;
            }

            // LOCAL/OFFLINE entry whose real invNo is now known → API has it
            final realInvNo = localUuidToRealInvNo[cached.id];
            if (realInvNo != null && apiInvNos.contains(realInvNo)) {
              // Clean up the stale LOCAL record from DB
              await _dbHelper.deleteOrder(cached.id);
              continue;
            }

            // ID match → API already has it
            if (apiSoldOrders.any((api) => api.id == cached.id)) {
              continue;
            }

            // Genuinely offline-only order not yet on server → keep it
            mergedList.add(cached);
          }

          mergedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          soldOrders.assignAll(mergedList);

          _backgroundFetchSoldOrderDetails(apiSoldOrders);
        }
      } catch (e) {
        log("OrderController: API fetch failed (Sold), using cache: $e");
      }
    } catch (e) {
      debugPrint("Error fetching sold orders: $e");
    }
  }
  /// Background fetcher to ensure sold order details (get_sold_pos_data) are stored locally
  Future<void> _backgroundFetchSoldOrderDetails(List<OrderModel> apiSoldOrders) async {
    for (var order in apiSoldOrders) {
      // If we don't have items, check if we have them in local DB payload
      final db = await _dbHelper.database;
      final rows = await db.query('orders', columns: ['payload'], where: 'uuid = ?', whereArgs: [order.id]);
      
      if (rows.isNotEmpty && (rows.first['payload'] == null || (rows.first['payload'] as String).isEmpty)) {
        // Fetch details if missing in local DB
        log("Background fetching details for sold order: ${order.invNo}");
        await fetchOrderDetails(order);
      }
    }
  }

  OrderModel _mapJsonToOrderModel(Map<String, dynamic> json) {
    List<OrderItem> localItems = [];
    String tableName = json['customer_name'] ?? "Offline Order";
    int chairNumber = 0;
    int? areaId;
    String? areaName;
    int? priceGroupId;
    int orderType = (json['order_type_id'] as num? ?? 0).toInt();
    String invNo = json['inv_no']?.toString() ?? "LOCAL";
    String orderId = json['server_id']?.toString() ?? json['uuid']?.toString() ?? "";
    String tableId = json['table_id']?.toString() ?? "";

    try {
      final payloadStr = json['payload'] as String?;
      if (payloadStr != null && payloadStr.isNotEmpty) {
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

        tableName = payload['table_name'] ?? payload['sales_odr_table_name'] ?? tableName;
        chairNumber = (payload['no_seats'] ?? payload['sales_odr_no_seats'] as num? ?? 0).toInt();
        orderType = (payload['pos_odr_type'] ?? payload['sales_odr_order_type'] as num? ?? orderType).toInt();

        if (payload['sq_inv_no'] != null && payload['sq_inv_no'].toString() != '0') {
          invNo = payload['sq_inv_no'].toString();
        }

        final resTable = payload['res_table'] as Map<String, dynamic>?;
        if (resTable != null) {
          tableId = (resTable['rt_id'] ?? tableId).toString();
          areaId = (resTable['rt_area_id'] as num?)?.toInt();
          priceGroupId = (resTable['prcgrp_id'] as num?)?.toInt();

          if (areaId != null && Get.isRegistered<TablesController>()) {
            final area = Get.find<TablesController>().areas.firstWhereOrNull((a) => a.id == areaId);
            areaName = area?.name;
          }
        } else if (payload['sales_odr_table_id'] != null) {
          tableId = payload['sales_odr_table_id'].toString();
        }

        final List<dynamic> saleItems = payload['sale_items'] ?? payload['sales_order_sub'] ?? [];

        final mainItems = saleItems.where((i) {
          final isAddon = (i['is_addon'] ?? i['sales_odr_sub_is_addon'] as num? ?? 0).toInt();
          return isAddon == 0; // Removed: && (i['is_deleted'] ?? 0) != 1
        }).toList();

        final addonItems = saleItems.where((i) {
          final isAddon = (i['is_addon'] ?? i['sales_odr_sub_is_addon'] as num? ?? 0).toInt();
          return isAddon == 1; // Removed: && (i['is_deleted'] ?? 0) != 1
        }).toList();

        for (final si in mainItems) {
          final prdId = (si['salesub_prd_id'] ?? si['sales_ord_sub_prod_id'])?.toString() ?? '';
          final dynamic rawUnitId = si['salesub_unit_id'] ?? si['sales_ord_sub_unit_id'];
          final int unitId = rawUnitId is num ? rawUnitId.toInt() : int.tryParse(rawUnitId?.toString() ?? '') ?? 0;
          final dynamic rawSubId = si['sales_ord_sub_id'] ?? si['salesub_id'];
          final int subId = rawSubId is num ? rawSubId.toInt() : int.tryParse(rawSubId?.toString() ?? '') ?? 0;
          int? tokenPrinterId = si['cat_token_printer'] is num
              ? (si['cat_token_printer'] as num).toInt()
              : int.tryParse(si['cat_token_printer']?.toString() ?? '');
final bool isDeleted = (si['is_deleted'] ?? 0) == 1;

          if (isDeleted) {
            log("🔍 DELETED ITEM DETECTED: ${si['prd_name']}");
            log("   Initial tokenPrinterId from JSON: $tokenPrinterId");

            // If tokenPrinterId is 0 or null, recover it from local storage
            if ((tokenPrinterId == null || tokenPrinterId == 0) &&
                Get.isRegistered<CartController>()) {

              final cartCtrl = Get.find<CartController>();

              // Try to find the list of items. In your project, it is likely named 'products' or 'foodItems'
              // We use dynamic to avoid the 'allItems' compilation error
              final List<dynamic> allProductsList = (cartCtrl as dynamic).products ?? [];

              log("   ⚠️ Token ID is 0/null. Attempting recovery from CartController items...");

              final match = allProductsList.firstWhereOrNull((p) =>
              p.id.toString() == prdId.toString());

              if (match != null) {
                // Recover the ID. Usually stored in categoryId or a specific printer field
                tokenPrinterId = int.tryParse(match.categoryId.toString()) ?? 0;
                log("   ✅ Recovered Token ID: $tokenPrinterId from Master Product List");
              } else {
                log("   ❌ Could not find product $prdId in CartController cache");
              }
            }
          }
          final double quantity = (si['salesub_qty'] ?? si['sales_ord_sub_qty'] as num? ?? 1).toDouble();
          final double baseRate = (si['salesub_rate'] ?? si['sales_ord_sub_rate'] ?? si['rate'] as num? ?? 0.0).toDouble();
          final double taxAmt = (si['salesub_tax'] ?? si['sales_ord_sub_tax'] ?? si['sales_ord_sub_tax_rate'] as num? ?? 0.0).toDouble();
          // final bool isDeleted = (si['is_deleted'] ?? 0) == 1;
          // Use DashboardController to determine if VAT is included in price
          double price = baseRate;
          if (Get.isRegistered<DashboardController>()) {
            final dashboardController = Get.find<DashboardController>();
            price = dashboardController.vatType.value == 1 ? baseRate + taxAmt : baseRate;
          }

          final addons = addonItems.where((a) {
            final parentPrdId = (a['addon_parent_prd_id'] ?? a['sales_odr_sub_addon_parent_prd_id'])?.toString();
            final parentUnitId = (a['addon_parent_unit_id'] ?? a['sales_odr_sub_addon_parent_unit_id'] as num? ?? 0).toInt();
            return parentPrdId == prdId && parentUnitId == unitId;
          }).map((a) {
            final addonBaseRate = (a['salesub_rate'] ?? a['sales_ord_sub_rate'] ?? a['rate'] as num? ?? 0.0).toDouble();

            // Fix: Safely parse addonSubId
            final dynamic rawAddonSubId = a['sales_ord_sub_id'] ?? a['salesub_id'];
            final int addonSubId = rawAddonSubId is num ? rawAddonSubId.toInt() : int.tryParse(rawAddonSubId?.toString() ?? '') ?? 0;

            // Fix: Safely parse addonPrdId
            final dynamic rawAddonPrdId = a['salesub_prd_id'] ?? a['sales_ord_sub_prod_id'];
            final int addonPrdId = rawAddonPrdId is num ? rawAddonPrdId.toInt() : int.tryParse(rawAddonPrdId?.toString() ?? '') ?? 0;

            // Fix: Safely parse taxCatId (The most likely culprit)
            final dynamic rawTaxCatId = a['prd_tax_cat_id'] ?? a['sales_ord_sub_taxcat_id'];
            final int taxCatId = rawTaxCatId is num ? rawTaxCatId.toInt() : int.tryParse(rawTaxCatId?.toString() ?? '') ?? 0;

            return AddonModel(
              id: addonPrdId,
              subId: addonSubId == 0 ? null : addonSubId,
              prdId: addonPrdId,
              // Fix: Safely parse addon flags
              prdaddon_flags: (a['is_addon'] is num)
                  ? (a['is_addon'] as num).toInt()
                  : int.tryParse(a['is_addon']?.toString() ?? '') ?? 1,
              name: a['prd_name']?.toString() ?? '',
              price: addonBaseRate,
              unitDisplay: (a['salesub_unit_display'] ?? a['prd_unit_name'] ?? a['unit_display'] ?? '').toString(),
              unitId: (a['salesub_unit_id'] is num)
                  ? (a['salesub_unit_id'] as num).toInt()
                  : int.tryParse(a['salesub_unit_id']?.toString() ?? '') ?? 0,
              initialQty: (a['salesub_qty'] is num)
                  ? (a['salesub_qty'] as num).toInt()
                  : int.tryParse(a['salesub_qty']?.toString() ?? '') ?? 0,
              taxPer: (a['salesub_tax_per'] ?? a['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              taxCatId: taxCatId,
            );
          }).toList();

          localItems.add(OrderItem(
            subId: subId == 0 ? null : subId,
            tokenPrinterId: tokenPrinterId,
            isRemoved: isDeleted,
            product: FoodItemModel(
              id: prdId,
              name: si['prd_name']?.toString() ?? '',
              categoryId: (si['prd_cat_id'] ?? '').toString(),
              price: price,
              prd_tax: (si['salesub_tax_per'] ?? si['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              image: '',
              unitDisplay: (si['salesub_unit_display'] ?? si['prd_unit_name'] ?? si['unit_display'] ?? '').toString(),
              taxPer: (si['salesub_tax_per'] ?? si['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              taxCatId: (si['prd_tax_cat_id'] ?? si['sales_ord_sub_taxcat_id'] as num? ?? 0).toInt(),
            ),
            unit: ProductUnit(
              unitId: unitId,
              unitName: (si['salesub_unit_display'] ?? si['prd_unit_name'] ?? si['unit_display'] ?? '').toString(),
              unitDisplay: (si['salesub_unit_display'] ?? si['prd_unit_name'] ?? si['unit_display'] ?? '').toString(),
              rate: price,
              unitBaseQty: (si['base_qty'] ?? si['unit_base_qty'] as num? ?? 1.0).toDouble(),
              existAddOns: [],
            ),
            selectedAddons: addons,
            quantity: quantity.toInt(),
            priceAtOrder: price,
          ));
        }
      }
    } catch (e) {
      debugPrint("Error mapping json to order model: $e");
    }

    String statusStr = json['status'] ?? 'pending';
    OrderStatus status = OrderStatus.pending;
    if (statusStr == 'draft') status = OrderStatus.draft;
    if (statusStr == 'paid') status = OrderStatus.paid;
    if (statusStr == 'cancelled') status = OrderStatus.cancelled;

    return OrderModel(
      id: orderId,
      invNo: invNo,
      tableId: tableId,
      tableName: tableName,
      chairNumber: chairNumber,
      sales_odr_pos_status: (status == OrderStatus.draft) ? 0 : (status == OrderStatus.paid ? 3 : 1),
      items: localItems,
      status: status,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      totalAmount: (json['total_amount'] as num? ?? 0.0).toDouble(),
      totalTax: (json['total_tax'] as num? ?? 0.0).toDouble(),
      isUnsynced: (json['is_synced'] == 0),
      areaId: areaId,
      areaName: areaName,
      priceGroupId: priceGroupId,
      sales_odr_order_type: orderType,
    );
  }

  /// Update an existing order without creating duplicates
  void updateExistingOrder(OrderModel updatedOrder) {
    // Check in active orders
    final activeIndex = orders.indexWhere((o) =>
    o.id == updatedOrder.id ||
        (o.invNo.isNotEmpty && updatedOrder.invNo.isNotEmpty && o.invNo == updatedOrder.invNo)
    );

    if (activeIndex != -1) {
      final existingOrder = orders[activeIndex];
      existingOrder.totalAmount = updatedOrder.totalAmount;
      existingOrder.totalTax = updatedOrder.totalTax;
      existingOrder.isUnsynced = updatedOrder.isUnsynced; // ✅ Update sync status

      if (updatedOrder.items.isNotEmpty) {
        existingOrder.items.clear();
        existingOrder.items.addAll(updatedOrder.items);
      }

      if (existingOrder.status.value != updatedOrder.status.value) {
        existingOrder.status.value = updatedOrder.status.value;
      }

      orders.refresh();
      debugPrint("✅ Updated existing active order: ${updatedOrder.invNo} (Synced: ${!existingOrder.isUnsynced})");
      return;
    }

    // Check in sold orders
    final soldIndex = soldOrders.indexWhere((o) =>
    o.id == updatedOrder.id ||
        (o.invNo.isNotEmpty && updatedOrder.invNo.isNotEmpty && o.invNo == updatedOrder.invNo)
    );

    if (soldIndex != -1) {
      final existingOrder = soldOrders[soldIndex];
      existingOrder.totalAmount = updatedOrder.totalAmount;
      existingOrder.totalTax = updatedOrder.totalTax;
      existingOrder.isUnsynced = updatedOrder.isUnsynced; // ✅ Update sync status

      if (updatedOrder.items.isNotEmpty) {
        existingOrder.items.clear();
        existingOrder.items.addAll(updatedOrder.items);
      }

      if (existingOrder.status.value != updatedOrder.status.value) {
        existingOrder.status.value = updatedOrder.status.value;
      }

      soldOrders.refresh();
      debugPrint("✅ Updated existing sold order: ${updatedOrder.invNo} (Synced: ${!existingOrder.isUnsynced})");
    } else {
      // If order doesn't exist, add it to active orders
      orders.insert(0, updatedOrder);
      debugPrint("✅ Added new order: ${updatedOrder.invNo}");
    }
  }

  /// Manual sync trigger from UI
  Future<void> syncOrders() async {
    final syncService = Get.find<SyncService>();
    await syncService.syncPendingOrders();
    await fetchOrders();
  }

  Future<void> fetchOrderDetails(OrderModel order) async {
    if (order.isUnsynced) {
      await _loadOrderDetailsFromLocal(order);
      return;
    }
    try {
      final bool isPaid = order.status.value == OrderStatus.paid;
      final String endpoint = isPaid
          ? "mobileapp/pos/get_sold_pos_data"
          : "mobileapp/pos/get_sale_order_details_pos";

      final Map<String, dynamic> requestData = {
        "usr_id": int.tryParse(AppState.userId) ?? 18,
        "sales_odr_inv_no": int.tryParse(order.invNo) ?? 0,
      };

      if (isPaid) {
        requestData["is_reprint"] = 1;
      }

      final response = await _apiService.post(endpoint, data: requestData);

      if (response.statusCode == 200) {
        final data = response.data['data'];
        if (data == null) return;

        // Paid API wraps preview data differently
        final preview = isPaid ? data['preview'] : data;
        if (preview == null) return;

        // Cache detailed order data locally
        await _dbHelper.updateOrderStatusByUuid(
          order.id,
          order.status.value.name,
          payload: jsonEncode(preview),
          isSynced: 1,
          invNo: order.invNo,
          serverId: order.id,
        );

        final String imageBaseUrl = preview['image_url']?.toString() ??
                                  data['image_url']?.toString() ?? "";
        final List<dynamic> subItems = preview['sales_order_sub'] ?? [];
        List<OrderItem> items = [];

        final mainItems = subItems.where((item) {
          final isAddon = int.tryParse(item['sales_odr_sub_is_addon']?.toString() ?? '0') ?? 0;
          return isAddon == 0;
        }).toList();

        final addonItems = subItems.where((item) {
          final isAddon = int.tryParse(item['sales_odr_sub_is_addon']?.toString() ?? '0') ?? 0;
          return isAddon == 1;
        }).toList();

        for (var productJson in mainItems) {
          final double quantity = (productJson['salesub_qty'] ?? productJson['sales_ord_sub_qty'] as num? ?? 1).toDouble();
          final double baseRate = (productJson['rate'] ?? productJson['sales_ord_sub_rate'] as num? ?? 0.0).toDouble();
          final double taxAmt = (productJson['sales_ord_sub_tax'] ?? productJson['sales_ord_sub_tax_rate'] as num? ?? 0.0).toDouble();

          double price = baseRate;
          if (Get.isRegistered<DashboardController>()) {
            final dashboardController = Get.find<DashboardController>();
            price = dashboardController.vatType.value == 1 ? baseRate + taxAmt : baseRate;
          }

          final String prdId = (productJson['sales_ord_sub_prod_id'] ?? 0).toInt().toString();
          final int unitId = (productJson['salesub_unit_id'] ?? productJson['sales_ord_sub_unit_id'] as num? ?? 0).toInt();

          final String prdImgUrl = productJson['prd_img_url']?.toString() ?? "";
          String fullImgPath = prdImgUrl;
          if (prdImgUrl.isNotEmpty && imageBaseUrl.isNotEmpty && !prdImgUrl.startsWith('http')) {
            fullImgPath = imageBaseUrl + prdImgUrl;
          }

          final List<AddonModel> selectedAddons = addonItems.where((addon) {
            final parentPrdId = (addon['sales_odr_sub_addon_parent_prd_id'] as num? ?? 0).toInt().toString();
            final parentUnitId = (addon['sales_odr_sub_addon_parent_unit_id'] as num? ?? 0).toInt();
            return parentPrdId == prdId && parentUnitId == unitId;
          }).map((addonJson) {
            return AddonModel(
              id: (addonJson['sales_ord_sub_prod_id'] as num? ?? 0).toInt(),
              subId: (addonJson['sales_ord_sub_id'] as num? ?? 0).toInt(),
              prdId: (addonJson['sales_ord_sub_prod_id'] as num? ?? 0).toInt(),
              prdaddon_flags: (addonJson['prd_is_addon'] ?? addonJson['sales_odr_sub_is_addon'] as num? ?? 1).toInt(),
              name: addonJson['prd_name']?.toString() ?? '',
              price: (addonJson['rate'] ?? addonJson['sales_ord_sub_rate'] as num? ?? 0.0).toDouble(),
              unitDisplay: (addonJson['prd_unit_name'] ?? addonJson['unit_display'] ?? '').toString(),
              unitId: (addonJson['salesub_unit_id'] ?? addonJson['sales_ord_sub_unit_id'] as num? ?? 0).toInt(),
              initialQty: (addonJson['salesub_qty'] ?? addonJson['sales_ord_sub_qty'] as num? ?? 0).toInt(),
              taxPer: (addonJson['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              taxCatId: (addonJson['sales_ord_sub_taxcat_id'] as num? ?? 0).toInt(),
            );
          }).toList();

          items.add(OrderItem(
            subId: (productJson['sales_ord_sub_id'] as num? ?? 0).toInt(),
            addonParentPrdId: (productJson['sales_odr_sub_addon_parent_prd_id'] as num? ?? 0).toInt(),
            addonParentUnitId: (productJson['sales_odr_sub_addon_parent_unit_id'] as num? ?? 0).toInt(),
            unitId: unitId,
            tokenPrinterId: (productJson['cat_token_printer'] as num?)?.toInt(),
            isRemoved: productJson['sales_ord_sub_flags'] == 0,
            isKotModified: productJson['sales_ord_sub_flags'] == 1,
            product: FoodItemModel(
              id: prdId,
              name: productJson['prd_name']?.toString() ?? '',
              categoryId: (productJson['prd_cat_id'] ?? '').toString(),
              price: price,
              prd_tax: (productJson['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              image: fullImgPath,
              unitDisplay: (productJson['prd_unit_name'] ?? productJson['unit_display'] ?? '').toString(),
              taxPer: (productJson['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              taxCatId: (productJson['sales_ord_sub_taxcat_id'] as num? ?? 0).toInt(),
            ),
            unit: ProductUnit(
              unitId: unitId,
              unitName: (productJson['prd_unit_name'] ?? productJson['unit_display'] ?? '').toString(),
              unitDisplay: (productJson['prd_unit_name'] ?? productJson['unit_display'] ?? '').toString(),
              rate: price,
              unitBaseQty: (productJson['base_qty'] ?? productJson['unit_base_qty'] as num? ?? 1.0).toDouble(),
              existAddOns: [],
            ),
            selectedAddons: selectedAddons,
            quantity: quantity.toInt(),
            priceAtOrder: price,
          ));
        }

        // Update in both lists if found
        var activeIndex = orders.indexWhere((o) => o.invNo == order.invNo);
        if (activeIndex != -1) {
          orders[activeIndex] = OrderModel(
            id: order.id,
            invNo: order.invNo,
            tableId: (preview['sales_odr_table_id'] ?? orders[activeIndex].tableId).toString(),
            tableName: preview['sales_odr_table_name']?.toString() ?? orders[activeIndex].tableName,
            chairNumber: (preview['sales_odr_no_seats'] as num? ?? orders[activeIndex].chairNumber).toInt(),
            sales_odr_pos_status: (preview['sales_odr_pos_status'] as num? ?? 0).toInt(),
            items: items,
            status: order.status.value,
            createdAt: order.createdAt,
            totalAmount: (preview['sales_odr_total'] ?? preview['tot_amount'] as num? ?? orders[activeIndex].totalAmount).toDouble(),
            totalTax: (preview['sales_odr_tax'] ?? preview['tot_tax'] as num? ?? 0.0).toDouble(),
            areaId: orders[activeIndex].areaId,
            areaName: orders[activeIndex].areaName,
            priceGroupId: orders[activeIndex].priceGroupId,
            sales_odr_order_type: (preview['sales_odr_order_type'] as num? ?? orders[activeIndex].sales_odr_order_type).toInt(),
            isUnsynced: false, // Successfully fetched from server
          );
          orders.refresh();
        } else {
          var soldIndex = soldOrders.indexWhere((o) => o.invNo == order.invNo);
          if (soldIndex != -1) {
            soldOrders[soldIndex] = OrderModel(
              id: order.id,
              invNo: order.invNo,
              tableId: (preview['sales_odr_table_id'] ?? soldOrders[soldIndex].tableId).toString(),
              tableName: preview['sales_odr_table_name']?.toString() ?? soldOrders[soldIndex].tableName,
              chairNumber: (preview['sales_odr_no_seats'] as num? ?? soldOrders[soldIndex].chairNumber).toInt(),
              sales_odr_pos_status: (preview['sales_odr_pos_status'] as num? ?? 0).toInt(),
              items: items,
              status: soldOrders[soldIndex].status.value,
              createdAt: soldOrders[soldIndex].createdAt,
              totalAmount: (preview['sales_odr_total'] ?? preview['tot_amount'] as num? ?? soldOrders[soldIndex].totalAmount).toDouble(),
              totalTax: (preview['sales_odr_tax'] ?? preview['tot_tax'] as num? ?? 0.0).toDouble(),
              areaId: soldOrders[soldIndex].areaId,
              areaName: soldOrders[soldIndex].areaName,
              priceGroupId: soldOrders[soldIndex].priceGroupId,
              sales_odr_order_type: (preview['sales_odr_order_type'] as num? ?? soldOrders[soldIndex].sales_odr_order_type).toInt(),
              isUnsynced: false, // Successfully fetched from server
            );
            soldOrders.refresh();
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching order details: $e");
      await _loadOrderDetailsFromLocal(order);
    }
  }

  Future<void> _loadOrderDetailsFromLocal(OrderModel order) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'orders',
        where: 'uuid = ? OR server_id = ?',
        whereArgs: [order.id, order.id],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final Map<String, dynamic> row = rows.first;
      final payloadStr = row['payload'] as String?;
      if (payloadStr == null || payloadStr.isEmpty) return;

      final mappedOrder = _mapJsonToOrderModel(row);

      if (mappedOrder.items.isNotEmpty) {
         // Update both lists if found
        var activeIndex = orders.indexWhere((o) => o.id == order.id);
        if (activeIndex != -1) {
          orders[activeIndex] = mappedOrder;
          orders.refresh();
        } else {
          var soldIndex = soldOrders.indexWhere((o) => o.id == order.id);
          if (soldIndex != -1) {
            soldOrders[soldIndex] = mappedOrder;
            soldOrders.refresh();
          }
        }
      }
    } catch (e) {
      debugPrint("_loadOrderDetailsFromLocal error: $e");
    }
  }

  OrderModel parseOrderResponse(Map<String, dynamic> responseJson) {
    // ... (keep your existing parseOrderResponse implementation)
    debugPrint("--- PARSING ORDER RESPONSE FOR PRINTING ---");
    final bool isOffline = responseJson['offline'] == true;
    final preview = responseJson['preview'] ?? {};
    final List<dynamic> subItemsJson = preview['sales_order_sub'] ?? [];

    final String imageBaseUrl = responseJson['image_url']?.toString() ??
        preview['image_url']?.toString() ?? "";

    final cartController = Get.find<CartController>();
    List<OrderItem> items = [];

    final mainItemsJson = subItemsJson.where((item) {
      final isAddon = int.tryParse(item['sales_odr_sub_is_addon']?.toString() ?? '0') ?? 0;
      return isAddon == 0;
    }).toList();

    final addonItemsJson = subItemsJson.where((item) {
      final isAddon = int.tryParse(item['sales_odr_sub_is_addon']?.toString() ?? '0') ?? 0;
      return isAddon == 1;
    }).toList();

    for (var sub in mainItemsJson) {
      final String prdId = (sub['sales_ord_sub_prod_id'] ?? 0).toString();
      final int unitId = (sub['sales_ord_sub_unit_id'] ?? 0).toInt();

      String unitDisplay = sub['salesub_unit_display']?.toString() ?? '';
      double rawQty = (sub['sales_ord_sub_qty'] as num? ?? 1).toDouble();
      double rawRate = (sub['sales_ord_sub_rate'] as num? ?? sub['rate'] as num? ?? 0.0).toDouble();
      double baseQty = (sub['unit_base_qty'] as num? ?? 1.0).toDouble();

      int displayQty;
      double displayRate = rawRate;

      // bool isBulkUnit =
      //     unitDisplay.toLowerCase().contains('b') || // optional
      //         unitDisplay.toLowerCase().contains('case') ||
      //         unitDisplay.toLowerCase().contains('box') ||
      //         unitDisplay.toLowerCase().contains('pack');

      if (baseQty > 1.0) {
        displayQty = (rawQty / baseQty).round();
        if (displayQty < 1 && rawQty > 0) displayQty = 1;
      } else {
        displayQty = rawQty.toInt();
      }

      log("📊 Unit: $unitDisplay, rawQty: $rawQty, baseQty: $baseQty, displayQty: $displayQty");

      final cartItem = cartController.cartItems.firstWhereOrNull(
              (item) => item.product.id == prdId && item.unit.unitId == unitId && !item.isDeleted.value
      );

      if (cartItem != null && displayRate == rawRate) {
        double cartBaseQty = cartItem.unit.unitBaseQty;
        if (cartBaseQty > 0 && cartBaseQty != 1.0) {
          displayRate = rawRate * cartBaseQty;
        }
      }

      final int flag = (sub['sales_ord_sub_flags'] as num? ?? 1).toInt();
      final bool isRemoved = flag == 0;
      int? tokenPrinterId = (sub['cat_token_printer'] as num?)?.toInt();
      if (tokenPrinterId == null || tokenPrinterId == 0) {
        final cartItem = cartController.cartItems.firstWhereOrNull(
              (ci) => ci.product.id == prdId,
        );
        tokenPrinterId = cartItem?.product.tokenPrinterId;
      }
      final String prdImgUrl = sub['prd_img_url']?.toString() ?? "";
      String fullImgPath = prdImgUrl;
      if (prdImgUrl.isNotEmpty && imageBaseUrl.isNotEmpty && !prdImgUrl.startsWith('http')) {
        fullImgPath = imageBaseUrl + prdImgUrl;
      }

      final List<AddonModel> selectedAddons = addonItemsJson.where((addon) {
        final parentPrdId = (addon['sales_odr_sub_addon_parent_prd_id'] as num? ?? 0).toInt().toString();
        final parentUnitId = (addon['sales_odr_sub_addon_parent_unit_id'] as num? ?? 0).toInt();
        final addonFlag = (addon['sales_ord_sub_flags'] as num? ?? 1).toInt();
        return parentPrdId == prdId && parentUnitId == unitId && addonFlag == flag;
      }).map((addonJson) {
        return AddonModel(
          id: (addonJson['sales_ord_sub_id'] as num? ?? 0).toInt(),
          prdId: (addonJson['sales_ord_sub_prod_id'] as num? ?? 0).toInt(),
          prdaddon_flags: (addonJson['prdaddon_flags'] as num? ?? 1).toInt(),
          name: addonJson['prd_name']?.toString() ?? '',
          price: (addonJson['rate'] as num? ?? 0.0).toDouble(),
          unitDisplay: addonJson['unit_display']?.toString() ?? '',
          unitId: (addonJson['sales_ord_sub_unit_id'] as num? ?? 0).toInt(),
          initialQty: (addonJson['sales_ord_sub_qty'] as num? ?? 0).toInt(),
          taxPer: (addonJson['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
          taxCatId: (addonJson['sales_ord_sub_taxcat_id'] as num? ?? 0).toInt(),
        );
      }).toList();

      items.add(OrderItem(
        subId: (sub['sales_ord_sub_id'] as num? ?? 0).toInt(),
        quantity: displayQty,
        priceAtOrder: displayRate,
        tokenPrinterId: tokenPrinterId,
        selectedAddons: selectedAddons,
        isRemoved: isRemoved,
        product: FoodItemModel(
          id: prdId,
          name: sub['prd_name']?.toString() ?? cartItem?.product.name ?? 'Unknown',
          categoryId: (sub['prd_cat_id'] ?? cartItem?.product.categoryId ?? '').toString(),
          price: displayRate,
          prd_tax: (sub['sales_ord_sub_tax_per'] as num?)?.toDouble()
              ?? cartItem?.product.prd_tax
              ?? 0.0,
          image: fullImgPath.isNotEmpty ? fullImgPath : (cartItem?.product.image ?? ''),
          unitDisplay: sub['unit_display']?.toString() ?? cartItem?.product.unitDisplay ?? '',
          taxPer: (sub['sales_ord_sub_tax_per'] as num? ?? cartItem?.product.taxPer ?? 0.0).toDouble(),
          taxCatId: (sub['sales_ord_sub_taxcat_id'] as num? ?? cartController.cartItems.firstWhereOrNull((i)=>i.product.id == prdId)?.product.taxCatId ?? 0).toInt(),
        ),
        unit: cartItem?.unit ?? ProductUnit(
          unitId: unitId,
          unitName: sub['unit_display']?.toString() ?? '',
          unitDisplay: sub['unit_display']?.toString() ?? '',
          rate: displayRate,
          unitBaseQty: cartItem?.unit.unitBaseQty ?? 1.0,
          existAddOns: [],
        ),
      ));
    }

    final String dateStr = preview['sales_odr_date']?.toString() ?? '';
    final String timeStr = preview['sales_odr_time']?.toString() ?? '';
    DateTime createdAt = DateTime.now();
    try {
      if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
        createdAt = DateTime.parse("${dateStr}T$timeStr");
      }
    } catch (_) {}

    final String orderId = (preview['sales_odr_id'] ?? '').toString();
    final String invNo = (preview['sales_odr_inv_no'] ?? '').toString();
    final String localUuid = (preview['local_uuid'] ?? '').toString();

    final String tableName = preview['sales_odr_table_name']?.toString() ??
        preview['table_name']?.toString() ??
        cartController.selectedTableName.value;

    final int chairNumber = (preview['sales_odr_no_seats'] as num? ??
        preview['no_seats'] as num? ??
        cartController.selectedChairCount.value).toInt();

    return OrderModel(
      id: orderId.isEmpty ? localUuid : orderId,
      invNo: invNo.isEmpty ? "OFFLINE" : invNo,
      tableId: (preview['sales_odr_table_id'] ?? cartController.selectedTableId.value).toString(),
      tableName: tableName,
      chairNumber: chairNumber,
      sales_odr_pos_status: (preview['sales_odr_pos_status'] as num? ?? 0).toInt(),
      items: items,
      status: OrderStatus.pending,
      createdAt: createdAt,
      totalAmount: (preview['sales_odr_total'] as num? ?? 0.0).toDouble(),
      totalTax: (preview['sales_odr_tax'] as num? ?? 0.0).toDouble(),
      areaId: (preview['rt_area_id'] as num? ?? cartController.selectedAreaId.value).toInt(),
      areaName: cartController.selectedAreaName.value,
      priceGroupId: (preview['prcgrp_id'] as num? ?? cartController.selectedPriceGroupId.value).toInt(),
      isUnsynced: isOffline,
      sales_odr_order_type: (preview['sales_odr_order_type'] as num? ?? 0).toInt(),
    );
  }

  Future<void> editOrder(OrderModel order) async {
    if (order.isUnsynced && order.items.isEmpty) {
      await _loadOrderDetailsFromLocal(order);
    }

    try {
      isLoading.value = true;

      if (!order.isUnsynced && order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      // Check both active and sold orders
      final updatedOrder = (orders + soldOrders).firstWhere(
            (o) => o.id == order.id,
        orElse: () => order,
      );

      if (updatedOrder.items.isNotEmpty) {
        final orderType = OrderType.values.firstWhere(
              (e) => e.id == updatedOrder.sales_odr_order_type,
          orElse: () => OrderType.dineIn,
        );
        AppState.orderType = orderType;
        if (Get.isRegistered<OrderTypeController>()) {
          Get.find<OrderTypeController>().selectedType.value = orderType;
        }

        final cartController = Get.find<CartController>();
        final homeController = Get.find<HomeController>();

        cartController.startEditingOrder(updatedOrder);
        homeController.changeIndex(0);
      } else {
        showSafeSnackbar("Error", "Could not load order items.");
      }
    } catch (e) {
      debugPrint("Error editing order: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> goToCashier(OrderModel order) async {
    try {
      isLoading.value = true;
      if (!order.isUnsynced && order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      final updatedOrder = (orders + soldOrders).firstWhere(
            (o) => o.id == order.id,
        orElse: () => order,
      );

      if (updatedOrder.items.isNotEmpty) {
        final orderType = OrderType.values.firstWhere(
              (e) => e.id == updatedOrder.sales_odr_order_type,
          orElse: () => OrderType.dineIn,
        );
        AppState.orderType = orderType;
        if (Get.isRegistered<OrderTypeController>()) {
          Get.find<OrderTypeController>().selectedType.value = orderType;
        }

        final cartController = Get.find<CartController>();
        cartController.startEditingOrder(updatedOrder);
        Get.toNamed(Routes.CASHIER, arguments: updatedOrder);
      } else {
        showSafeSnackbar("Error", "Could not load order items.");
      }
    } catch (e) {
      debugPrint("Error going to cashier: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> cancelOrder(OrderModel order) async {
    try {
      bool? confirm = await Get.dialog<bool>(
        AlertDialog(
          title: Text('cancel_order'.tr),
          content: Text('Are you sure you want to cancel order ${order.isUnsynced ? "(Offline)" : "#${order.invNo}"}?'),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: Text('no'.tr)),
            TextButton(
                onPressed: () => Get.back(result: true),
                child: Text('yes'.tr, style: const TextStyle(color: Colors.red))
            ),
          ],
        ),
      );

      if (confirm != true) return;

      if (order.isUnsynced) {
        if (order.items.isEmpty) {
          await _loadOrderDetailsFromLocal(order);
        }
        
        // Find the latest version from controller lists
        final updatedOrder = (orders + soldOrders).firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );
        
        final printerController = Get.find<PrinterController>();
        await printerController.printCancelledOrder(updatedOrder).catchError((e) {
          debugPrint("Offline cancellation print error: $e");
        });

        await _dbHelper.deleteOrder(order.id);
        orders.removeWhere((o) => o.id == order.id);
        showSafeSnackbar("Success", "Offline order cancelled successfully");
        return;
      }

      if (order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      final updatedOrder = (orders + soldOrders).firstWhere(
            (o) => o.invNo == order.invNo,
        orElse: () => order,
      );
      final originalStatus = order.status.value;

      order.status.value = OrderStatus.cancelled;

      final cartController = Get.find<CartController>();
      bool? success = await cartController.cancelOrder(order.invNo);

      if (success == true) {
        await _dbHelper.deleteOrder(order.id);
        orders.removeWhere((o) => o.invNo == order.invNo);
        soldOrders.removeWhere((o) => o.invNo == order.invNo);
        showSafeSnackbar("Success", "Order #${order.invNo} cancelled successfully");
        final printerController = Get.find<PrinterController>();
        printerController.printCancelledOrder(updatedOrder).catchError((e) {
          debugPrint("Background printing error: $e");
        });
      } else {
        order.status.value = originalStatus;
        showSafeSnackbar("Error", "Failed to cancel order");
      }
    } catch (e) {
      debugPrint("Error cancelling order: $e");
    }
  }

  void addOrder(OrderModel order) {
    orders.insert(0, order);
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    var index = orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      orders[index].status.value = newStatus;
    } else {
      index = soldOrders.indexWhere((o) => o.id == orderId);
      if (index != -1) {
        soldOrders[index].status.value = newStatus;
      }
    }
  }

  List<OrderModel> get pendingOrders => orders.where((o) =>
  (o.status.value == OrderStatus.pending ||
      o.status.value == OrderStatus.preparing ||
      o.status.value == OrderStatus.ready ||
      o.status.value == OrderStatus.served ||
      o.status.value == OrderStatus.draft) &&
      o.status.value != OrderStatus.paid &&
      o.status.value != OrderStatus.cancelled
  ).toList();

  List<OrderModel> get dineInOrders => pendingOrders.where((o) => o.sales_odr_order_type == 0).toList();
  List<OrderModel> get deliveryOrders => pendingOrders.where((o) => o.sales_odr_order_type == 1).toList();
  List<OrderModel> get pickupOrders => pendingOrders.where((o) => o.sales_odr_order_type == 2).toList();

  // Paid orders filtered by date
  List<OrderModel> get paidOrders {
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedSoldDate.value);
    return soldOrders.where((o) => 
      DateFormat('yyyy-MM-dd').format(o.createdAt) == dateStr
    ).toList();
  }

  List<OrderModel> get completedOrders => paidOrders;

  void changeSoldDate(DateTime date) {
    selectedSoldDate.value = date;
    _fetchSoldOrders();
  }
}
