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
      final List<OrderModel> finalOrders = unsyncedData
          .map((json) => _mapJsonToOrderModel(json))
          .where((o) => o.status.value != OrderStatus.paid && o.status.value != OrderStatus.cancelled) // ✅ Filter out paid/cancelled from active list
          .toList();

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

                OrderStatus status;
                if (posStatus == 1) {
                  status = OrderStatus.pending;
                } else if (posStatus == 2) {
                  status = OrderStatus.billed;
                } else {
                  status = OrderStatus.draft;
                }

                allProcessingOrders.add(OrderModel(
                  id: (processing['sales_odr_id'] ?? '').toString(),
                  tableId: (processing['sales_odr_table_id'] ?? table.id).toString(),
                  invNo: (processing['sales_odr_inv_no'] ?? '').toString(),
                  tableName: _resolveName(processing, orderType, table.name),
                  customerName: (processing['sq_cust_name'] ?? processing['customer_name'] ?? processing['cust_name'] ?? processing['ledger_name'])?.toString(),
                  chairNumber: (processing['sales_odr_no_seats'] as num? ?? 0).toInt(),
                  sales_odr_pos_status: posStatus,
                  items: [],
                  status: status,
                  createdAt: DateTime.tryParse(processing['sales_odr_datetime'] ?? '') ?? DateTime.now(),
                  subTotal: (processing['tot_rate'] as num? ?? processing['sub_total'] as num? ?? 0.0).toDouble(),
                  totalAmount: (processing['sales_odr_total'] ?? processing['tot_amount'] ?? processing['total_amount'] as num? ?? 0.0).toDouble(),
                  areaId: area.id,
                  areaName: area.name,
                  priceGroupId: area.priceGroupID,
                  totalTax: (processing['sales_odr_tax'] ?? processing['tot_tax'] ?? processing['total_tax'] as num? ?? 0.0).toDouble(),
                  sales_odr_order_type: orderType,
                  discount: (processing['tot_disc'] ?? processing['discount'] as num? ?? 0.0).toDouble(),
                  roundOff: (processing['sales_odr_roundoff'] as num? ?? 0.0).toDouble(),
                  qrLink: (processing['qr_link'] ?? processing['zatca_qr'] ?? '').toString(),
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

            OrderStatus status;
            if (posStatus == 1) {
              status = OrderStatus.pending;
            } else if (posStatus == 2) {
              status = OrderStatus.billed;
            } else {
              status = OrderStatus.draft;
            }

            final processingOrder = allProcessingOrders.firstWhereOrNull(
                  (o) => o.invNo == (json['sales_odr_inv_no'] ?? '').toString(),
            );

            return OrderModel(
              id: (json['sales_odr_id'] ?? '').toString(),
              tableId: (json['sales_odr_table_id'] ?? processingOrder?.tableId ?? '').toString(),
              invNo: (json['sales_odr_inv_no'] ?? '').toString(),
              tableName: _resolveName(json, orderType, processingOrder?.tableName ?? 'Unknown Table'),
              customerName: (json['sq_cust_name'] ?? json['customer_name'] ?? json['cust_name'] ?? json['ledger_name'] ?? processingOrder?.customerName)?.toString(),
              chairNumber: (json['sales_odr_no_seats'] as num? ??
                  processingOrder?.chairNumber ?? 0).toInt(),
              captainName: (json['usr_name'] ?? json['captain_name'] ?? json['ledger_name'])?.toString(),
              sales_odr_pos_status: posStatus,
              items: [],
              status: status,
              createdAt: DateTime.tryParse(json['sales_odr_datetime'] ?? '') ??
                  processingOrder?.createdAt ?? DateTime.now(),
              subTotal: (json['tot_rate'] as num? ?? json['sub_total'] as num? ?? processingOrder?.subTotal ?? 0.0).toDouble(),
              totalAmount: (json['sales_odr_total'] ?? json['tot_amount'] ?? json['total_amount'] as num? ?? 0.0).toDouble(),
              areaId: processingOrder?.areaId,
              areaName: processingOrder?.areaName,
              priceGroupId: processingOrder?.priceGroupId,
              totalTax: (json['sales_odr_tax'] ?? json['tot_tax'] ?? json['total_tax'] as num? ?? 0.0).toDouble(),
              sales_odr_order_type: orderType,
              discount: (json['tot_disc'] ?? json['discount'] ?? processingOrder?.discount ?? 0.0).toDouble(),
              roundOff: (json['sales_odr_roundoff'] ?? processingOrder?.roundOff ?? 0.0).toDouble(),
              qrLink: (json['qr_link'] ?? json['zatca_qr'] ?? processingOrder?.qrLink ?? '').toString(),
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
          localOrder.discount = serverOrder.discount;
          localOrder.roundOff = serverOrder.roundOff;
          localOrder.subTotal = serverOrder.subTotal;
          localOrder.qrLink = serverOrder.qrLink;
          localOrder.status.value = serverOrder.status.value; // Sync status

          // Auto-repair local DB sync status
          _dbHelper.updateOrderStatusByUuid(
            localOrder.id,
            localOrder.status.value.name,
            isSynced: 1,
            serverId: serverOrder.id,
            invNo: serverOrder.invNo,
            total: serverOrder.totalAmount,
            tax: serverOrder.totalTax,
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
            final int type = (json['sales_odr_order_type'] as num? ?? 0).toInt();
            return OrderModel(
              id: (json['sales_odr_id'] ?? '').toString(),
              invNo: (json['sales_odr_inv_no'] ?? '').toString(),
              tableId: (json['sales_odr_table_id'] ?? '').toString(),
              tableName: _resolveName(json, type, 'Walk-in Customer'),
              customerName: (json['sq_cust_name'] ?? json['customer_name'] ?? json['cust_name'] ?? json['ledger_name'])?.toString(),
              chairNumber: 0,
              sales_odr_pos_status: (json['sales_odr_pos_status'] as num? ?? 3).toInt(),
              items: [],
              status: OrderStatus.paid,
              createdAt: DateTime.tryParse(
                  json['sales_odr_datetime'] ?? json['created_at'] ?? '') ??
                  DateTime.now(),
              subTotal: (json['tot_rate'] as num? ?? json['sub_total'] as num? ?? 0.0).toDouble(),
              totalAmount: (json['sales_odr_total'] ?? json['tot_amount'] ?? json['total_amount'] as num? ?? 0.0).toDouble(),
              totalTax: (json['sales_odr_tax'] ?? json['tot_tax'] ?? json['total_tax'] as num? ?? 0.0).toDouble(),
              discount: (json['tot_disc'] ?? json['discount'] as num? ?? 0.0).toDouble(),
              roundOff: (json['sales_odr_roundoff'] as num? ?? 0.0).toDouble(),
              qrLink: (json['qr_link'] ?? json['zatca_qr'] ?? '').toString(),
              areaId: null,
              areaName: null,
              priceGroupId: null,
              sales_odr_order_type: type,
              isUnsynced: false,
            );
          }).toList();

          await _dbHelper.cacheSoldOrders(data);

          // ── Build a lookup of LOCAL/OFFLINE cached orders → their real
          //    server invNo (read from DB, written by SyncService after sync)
          final Map<String, String> localUuidToRealInvNo = {};
          final db = await _dbHelper.database;
          for (var cached in cachedSoldOrders) {
            if (cached.invNo == "LOCAL" || cached.invNo == "OFFLINE" || cached.invNo.isEmpty) { // ✅ Handle empty invNo
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
                cached.invNo.isNotEmpty && // ✅ Handle empty invNo
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
    String? customerName;
    int chairNumber = 0;
    int? areaId;
    String? areaName;
    int? priceGroupId;
    int orderType = (json['order_type_id'] as num? ?? 0).toInt();
    String invNo = json['inv_no']?.toString() ?? "LOCAL";
    String orderId = json['server_id']?.toString() ?? json['uuid']?.toString() ?? "";
    String tableId = json['table_id']?.toString() ?? "";
    double discount = (json['discount_amount'] as num? ?? 0.0).toDouble();
    double roundOff = (json['roundoff_amount'] as num? ?? 0.0).toDouble();
    double subTotal = (json['sub_total'] as num? ?? json['tot_rate'] as num? ?? 0.0).toDouble();
    double totalAmount = (json['total_amount'] as num? ?? json['tot_amount'] as num? ?? json['sales_odr_total'] as num? ?? 0.0).toDouble();
    double totalTax = (json['total_tax'] as num? ?? json['tot_tax'] as num? ?? json['sales_odr_tax'] as num? ?? 0.0).toDouble();
    String? qrLink;
    String? captainName;

    try {
      final payloadStr = json['payload'] as String?;
      if (payloadStr != null && payloadStr.isNotEmpty) {
        final dynamic decoded = jsonDecode(payloadStr);
        if (decoded is Map<String, dynamic>) {
          final Map<String, dynamic> payload = decoded;
          chairNumber = (payload['no_seats'] ?? payload['sales_odr_no_seats'] as num? ?? 0).toInt();
          orderType = (payload['pos_odr_type'] ?? payload['sales_odr_order_type'] as num? ?? orderType).toInt();
          discount = (payload['tot_disc'] ?? payload['discount'] ?? discount).toDouble();
          roundOff = (payload['sales_odr_roundoff'] ?? roundOff).toDouble();
          subTotal = (payload['tot_rate'] ?? payload['sub_total'] ?? subTotal).toDouble();
          totalAmount = (payload['tot_amount'] ?? payload['sales_odr_total'] ?? payload['total_amount'] ?? totalAmount).toDouble();
          totalTax = (payload['tot_tax'] ?? payload['sales_odr_tax'] ?? payload['total_tax'] ?? totalTax).toDouble();
          qrLink = (payload['qr_link'] ?? payload['zatca_qr'])?.toString();
          customerName = (payload['sq_cust_name'] ?? payload['customer_name'] ?? payload['cust_name'] ?? payload['ledger_name'])?.toString();
          captainName = (payload['agent_name'] ?? payload['sale_agent_name'] ?? payload['captain_name'])?.toString();
          tableName = _resolveName(payload, orderType, tableName);

          if (payload['sq_inv_no'] != null && payload['sq_inv_no'].toString() != '0') {
            invNo = payload['sq_inv_no'].toString();
          }

          final dynamic rawResTable = payload['res_table'];
          if (rawResTable is Map<String, dynamic>) {
            final Map<String, dynamic> resTable = rawResTable;
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
            // if (Get.isRegistered<DashboardController>()) {
            //   final dashboardController = Get.find<DashboardController>();
            //   price = dashboardController.vatType.value == 0 ? baseRate + taxAmt : baseRate;
            // }

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
      }
    } catch (e) {
      debugPrint("Error mapping json to order model: $e");
    }

    String statusStr = json['status'] ?? 'pending';
    OrderStatus status = OrderStatus.pending;
    if (statusStr == 'draft') status = OrderStatus.draft;
    if (statusStr == 'paid') status = OrderStatus.paid;
    if (statusStr == 'cancelled') status = OrderStatus.cancelled;
    if (statusStr == 'billed') status = OrderStatus.billed;

    // Check pos_status if available
    int posStatusFromDb = (json['sales_odr_pos_status'] as num? ?? 0).toInt();
    if (posStatusFromDb == 2) status = OrderStatus.billed;

    return OrderModel(
      id: orderId,
      invNo: invNo,
      tableId: tableId,
      tableName: tableName,
      customerName: customerName,
      chairNumber: chairNumber,
      sales_odr_pos_status: (status == OrderStatus.billed) ? 2 : ((status == OrderStatus.draft) ? 0 : (status == OrderStatus.paid ? 3 : 1)),
      items: localItems,
      status: status,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      subTotal: subTotal,
      totalAmount: totalAmount,
      totalTax: totalTax,
      discount: discount,
      captainName: captainName,
      roundOff: roundOff,
      isUnsynced: (json['is_synced'] == 0),
      qrLink: qrLink ?? json['qr_link'] ?? json['zatca_qr'],
      areaId: areaId,
      areaName: areaName,
      priceGroupId: priceGroupId,
      sales_odr_order_type: orderType,
    );
  }

  void markOrderAsPaidLocally(String orderId) {
    final idx = orders.indexWhere(
          (o) => o.id == orderId || o.invNo == orderId,
    );
    if (idx != -1) {
      // Since OrderModel is likely immutable here, refresh after fetchOrders
      // At minimum, remove the order from active list so it stops showing as open
      orders.removeAt(idx);
      orders.refresh();
    }
  }

  Future<void> printBill(OrderModel order) async {
    try {
      // Ensure items are loaded
      if (order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      final currentOrder = (orders + soldOrders).firstWhere(
            (o) => o.id == order.id,
        orElse: () => order,
      );

      // Update status to 2 (bill printed) on server via updateOrder
      if (!order.isUnsynced) {
        final cartController = Get.find<CartController>();
        // Only call updateOrder if CartController is currently editing this order
        if (cartController.isEditing && cartController.editingOrderId.value == order.id) {
          await cartController.updateOrder(isBill: true);
        } else {
          // Minimal direct API call just to set status=2
          try {
            final body = {
              "usr_id": int.tryParse(AppState.userId) ?? 0,
              "sale_items": [],
              "sq_inv_no": int.tryParse(order.invNo) ?? 0,
              "res_status": 2,
              "is_pos_edit": true,
              "sq_total": order.totalAmount,
              "sq_tax": order.totalTax,
              "sq_disc": order.discount,
              "sales_roundoff": order.roundOff,
              "no_seats": order.chairNumber,
              "pos_odr_type": order.sales_odr_order_type,
              "sale_pay_type": 0,
              "is_pos": true,
              "sales_is_rest_pos": 1,
              "table_name": order.tableName,
              "server_sync_time":
              "${DateFormat('yyMMddHHmmssSSS').format(DateTime.now())}000",
              "res_table": {
                "rt_id": int.tryParse(order.tableId),
                "rt_name": order.tableName,
                "rt_seat_count": order.chairNumber,
                "rt_status": 1,
                "processing_table": [
                  {
                    "sq_id": int.tryParse(order.id),
                    "sq_inv_no": int.tryParse(order.invNo),
                  }
                ],
              },
            };
            await _apiService.post(
              "mobileapp/pos/update_sales_order",
              data: body,
            );
          } catch (e) {
            debugPrint("printBill: status update failed (non-fatal): $e");
            // Non-fatal — still print even if status update fails
          }
        }
      }

      // Update local status to reflect bill-printed (pos_status=2)
      final idx = orders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        orders[idx] = orders[idx].copyWith(sales_odr_pos_status: 2, status: OrderStatus.billed);
        orders.refresh();

        // Update in DB as well
        await _dbHelper.updateOrderStatusByUuid(order.id, 'billed');
      }

      // Now print
      final printerController = Get.find<PrinterController>();
      await printerController.printReceipt(currentOrder, 0, 0, isBill: true);
    } catch (e) {
      debugPrint("Error in printBill: $e");
    }
  }

  /// Helper for robust name resolution across different APIs and order types
  String _resolveName(Map<String, dynamic> data, int type, String fallback) {
    final table = data['sales_odr_table_name']?.toString();
    final ledger = data['ledger_name']?.toString();
    final customer = data['sq_cust_name']?.toString() ?? data['customer_name']?.toString() ?? data['cust_name']?.toString();
    final tableNameField = data['table_name']?.toString();

    // Generic dummy names that should be avoided for Pickup/Delivery
    final List<String> dummyNames = ["Pickup Table", "Delivery Table", "Pickup", "Delivery"];

    if (type == 0) { // Dine In
      if (table != null && table.isNotEmpty) return table;
      if (tableNameField != null && tableNameField.isNotEmpty) return tableNameField;
      if (ledger != null && ledger.isNotEmpty) return ledger;
      if (customer != null && customer.isNotEmpty) return customer;
    } else { // Pickup / Delivery
      // Prioritize identifying names
      if (ledger != null && ledger.isNotEmpty && !dummyNames.contains(ledger)) return ledger;
      if (customer != null && customer.isNotEmpty && !dummyNames.contains(customer)) return customer;
      
      // Secondary check: if fallback was more specific than what we're finding now
      if (fallback.isNotEmpty && !dummyNames.contains(fallback)) return fallback;

      if (table != null && table.isNotEmpty) return table;
      if (tableNameField != null && tableNameField.isNotEmpty) return tableNameField;
    }
    return (fallback.isNotEmpty) ? fallback : "Unknown Customer";
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
      
      // If the updated order is paid or cancelled, remove it from active orders
      if (updatedOrder.status.value == OrderStatus.paid || updatedOrder.status.value == OrderStatus.cancelled) {
        orders.removeAt(activeIndex);
        orders.refresh();
        
        // Add to sold orders if it's paid
        if (updatedOrder.status.value == OrderStatus.paid) {
          updateExistingOrderInList(soldOrders, updatedOrder);
        }
        return;
      }

      // Since existingOrder is a reference, and tableName is final, we must replace the entry
      orders[activeIndex] = existingOrder.copyWith(
        tableName: updatedOrder.tableName,
        customerName: updatedOrder.customerName,
        subTotal: updatedOrder.subTotal,
        totalAmount: updatedOrder.totalAmount,
        totalTax: updatedOrder.totalTax,
        discount: updatedOrder.discount,
        roundOff: updatedOrder.roundOff,
        sales_odr_order_type: updatedOrder.sales_odr_order_type,
        sales_odr_pos_status: updatedOrder.sales_odr_pos_status,
        isUnsynced: updatedOrder.isUnsynced,
        items: updatedOrder.items.isNotEmpty ? updatedOrder.items : existingOrder.items,
        status: updatedOrder.status.value,
        qrLink: updatedOrder.qrLink,
      );

      orders.refresh();
      debugPrint("✅ Updated existing active order: ${updatedOrder.invNo} (Synced: ${!existingOrder.isUnsynced})");
      return;
    }

    // Check in sold orders
    updateExistingOrderInList(soldOrders, updatedOrder);
    
    // If not found in either and it's not paid/cancelled, add to active
    if (activeIndex == -1 && updatedOrder.status.value != OrderStatus.paid && updatedOrder.status.value != OrderStatus.cancelled) {
      orders.insert(0, updatedOrder);
      debugPrint("✅ Added new order: ${updatedOrder.invNo}");
    }
  }

  void updateExistingOrderInList(RxList<OrderModel> list, OrderModel updatedOrder) {
    final index = list.indexWhere((o) =>
    o.id == updatedOrder.id ||
        (o.invNo.isNotEmpty && updatedOrder.invNo.isNotEmpty && o.invNo == updatedOrder.invNo)
    );

    if (index != -1) {
      final existingOrder = list[index];
      list[index] = existingOrder.copyWith(
        tableName: updatedOrder.tableName,
        customerName: updatedOrder.customerName,
        subTotal: updatedOrder.subTotal,
        totalAmount: updatedOrder.totalAmount,
        totalTax: updatedOrder.totalTax,
        discount: updatedOrder.discount,
        roundOff: updatedOrder.roundOff,
        sales_odr_order_type: updatedOrder.sales_odr_order_type,
        sales_odr_pos_status: updatedOrder.sales_odr_pos_status,
        isUnsynced: updatedOrder.isUnsynced,
        items: updatedOrder.items.isNotEmpty ? updatedOrder.items : existingOrder.items,
        status: updatedOrder.status.value,
        qrLink: updatedOrder.qrLink,
      );
      list.refresh();
      debugPrint("✅ Updated existing order in list: ${updatedOrder.invNo}");
    } else if (updatedOrder.status.value == OrderStatus.paid) {
      list.insert(0, updatedOrder);
      list.refresh();
      debugPrint("✅ Added new paid order to list: ${updatedOrder.invNo}");
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

        final double authoritativeTotal = (preview['tot_amount'] ?? preview['sales_odr_total'] ?? preview['total_amount'] as num? ?? 0.0).toDouble();
        final double authoritativeTax = (preview['tot_tax'] ?? preview['sales_odr_tax'] ?? preview['total_tax'] as num? ?? 0.0).toDouble();

        // Cache detailed order data locally
        await _dbHelper.updateOrderStatusByUuid(
          order.id,
          order.status.value.name,
          payload: jsonEncode(preview),
          isSynced: 1,
          invNo: order.invNo,
          serverId: order.id,
          total: authoritativeTotal,
          tax: authoritativeTax,
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
          // if (Get.isRegistered<DashboardController>()) {
          //   final dashboardController = Get.find<DashboardController>();
          //   price = dashboardController.vatType.value == 0 ? baseRate + taxAmt : baseRate;
          // }

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

        var activeIndex = orders.indexWhere((o) => o.invNo == order.invNo);
        if (activeIndex != -1) {
          final current = orders[activeIndex];
          final int type = (preview['sales_odr_order_type'] as num? ?? current.sales_odr_order_type).toInt();
          final int posStatus = (preview['sales_odr_pos_status'] as num? ?? current.sales_odr_pos_status).toInt();
          final String resolvedTableName = _resolveName(preview, type, current.tableName);

          OrderStatus updatedStatus = current.status.value;
          if (posStatus == 2) updatedStatus = OrderStatus.billed;

          orders[activeIndex] = current.copyWith(
            tableName: resolvedTableName,
            customerName: (preview['sq_cust_name'] ?? preview['customer_name'] ?? preview['cust_name'] ?? preview['ledger_name'])?.toString(),
            sales_odr_pos_status: posStatus,
            items: items,
            status: updatedStatus,
            subTotal: (preview['tot_rate'] as num? ?? preview['sub_total'] as num? ?? preview['tot_subtotal'] as num? ?? preview['sales_odr_subtotal'] as num? ?? current.subTotal).toDouble(),
            totalAmount: authoritativeTotal,
            totalTax: authoritativeTax,
            discount: (preview['tot_disc'] ?? preview['discount'] ?? current.discount).toDouble(),
            roundOff: (preview['sales_odr_roundoff'] ?? current.roundOff).toDouble(),
            sales_odr_order_type: type,
            captainName: (preview['agent_name'] ?? preview['usr_name'] ??
                data['agent']?['ledger_name'])?.toString(),
            isUnsynced: false,
            qrLink: (preview['qr_link'] ?? preview['zatca_qr'] ?? data['qr_link'] ?? data['zatca_qr'] ?? current.qrLink).toString(),
          );
          orders.refresh();
        } else {
          var soldIndex = soldOrders.indexWhere((o) => o.invNo == order.invNo);
          if (soldIndex != -1) {
            final current = soldOrders[soldIndex];
            final int type = (preview['sales_odr_order_type'] as num? ?? current.sales_odr_order_type).toInt();
            final int posStatus = (preview['sales_odr_pos_status'] as num? ?? current.sales_odr_pos_status).toInt();
            final String resolvedTableName = _resolveName(preview, type, current.tableName);

            soldOrders[soldIndex] = current.copyWith(
              tableName: resolvedTableName,
              customerName: (preview['sq_cust_name'] ?? preview['customer_name'] ?? preview['cust_name'] ?? preview['ledger_name'])?.toString(),
              sales_odr_pos_status: posStatus,
              items: items,
              status: current.status.value,
              captainName: (preview['agent_name'] ?? preview['usr_name'] ??
                  data['agent']?['ledger_name'])?.toString(),
              subTotal: (preview['tot_rate'] as num? ?? preview['sub_total'] as num? ?? preview['tot_subtotal'] as num? ?? preview['sales_odr_subtotal'] as num? ?? current.subTotal).toDouble(),
              totalAmount: authoritativeTotal,
              totalTax: authoritativeTax,
              discount: (preview['tot_disc'] ?? preview['discount'] ?? current.discount).toDouble(),
              roundOff: (preview['sales_odr_roundoff'] ?? current.roundOff).toDouble(),
              sales_odr_order_type: type,
              isUnsynced: false,
              qrLink: (preview['qr_link'] ?? preview['zatca_qr'] ?? data['qr_link'] ?? data['zatca_qr'] ?? current.qrLink).toString(),
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

// AFTER
  OrderModel parseOrderResponse(
      Map<String, dynamic> responseJson, {
        String fallbackTableName = "",
        int fallbackChairCount = 0,
      }) {
    debugPrint("--- PARSING ORDER RESPONSE FOR PRINTING ---");
    final bool isOffline = responseJson['offline'] == true;
    final preview = (responseJson['preview'] is Map) ? responseJson['preview'] : responseJson;
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

      if (!isOffline && baseQty > 1.0) {
        displayQty = (rawQty / baseQty).round();
        if (displayQty < 1 && rawQty > 0) displayQty = 1;
      } else {
        displayQty = rawQty.toInt();
      }

      log("📊 Unit: $unitDisplay, rawQty: $rawQty, baseQty: $baseQty, displayQty: $displayQty");

      final cartItem = cartController.cartItems.firstWhereOrNull(
              (item) => item.product.id == prdId && item.unit.unitId == unitId && !item.isDeleted.value
      );

      // if (cartItem != null && displayRate == rawRate) {
      //   double cartBaseQty = cartItem.unit.unitBaseQty;
      //   if (cartBaseQty > 0 && cartBaseQty != 1.0) {
      //     displayRate = rawRate * cartBaseQty;
      //   }
      // }

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

    final String dateStr = preview['sq_date']?.toString() ?? preview['sales_odr_date']?.toString() ?? '';
    final String timeStr = preview['sq_time']?.toString() ?? preview['sales_odr_time']?.toString() ?? '';
    DateTime createdAt = DateTime.now();
    try {
      if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
        createdAt = DateTime.parse("${dateStr}T$timeStr");
      }
    } catch (_) {}

    final String orderId = (preview['sales_odr_id'] ?? '').toString();
    final String invNo = (preview['sales_odr_inv_no'] ?? preview['sq_inv_no'] ?? '').toString();
    final String localUuid = (preview['local_uuid'] ?? '').toString();

    final int orderType = (preview['sales_odr_order_type'] as num? ?? 0).toInt();
    final int posStatus = (preview['sales_odr_pos_status'] as num? ?? 0).toInt();
  final String cartTableFallback = fallbackTableName.isNotEmpty
      ? fallbackTableName
      : cartController.selectedTableName.value;
  final String tableName = _resolveName(preview, orderType, cartTableFallback);
  final String? customerName = (preview['sq_cust_name'] ?? preview['customer_name'] ?? preview['cust_name'] ?? preview['ledger_name'])?.toString();
    final String? captainName = (preview['agent_name'] ?? preview['usr_name'])?.toString(); // ✅ ADD

  final int cartChairFallback = fallbackChairCount > 0
      ? fallbackChairCount
      : cartController.selectedChairCount.value;
  final int chairNumber = (preview['sales_odr_no_seats'] as num? ??
      preview['no_seats'] as num? ??
      preview['res_table']?['rt_seat_count'] as num? ??
      cartChairFallback).toInt();

    return OrderModel(
      id: orderId.isEmpty ? localUuid : orderId,
      invNo: invNo.isEmpty ? "OFFLINE" : invNo,
      tableId: (preview['sales_odr_table_id'] ?? cartController.selectedTableId.value).toString(),
      tableName: tableName,
      customerName: customerName,
      chairNumber: chairNumber,
      sales_odr_pos_status: posStatus,
      items: items,
      status: (posStatus == 2) ? OrderStatus.billed : OrderStatus.pending,
      createdAt: createdAt,
      subTotal: (preview['tot_rate'] as num? ?? preview['sub_total'] as num? ?? preview['tot_subtotal'] as num? ?? preview['sales_odr_subtotal'] as num? ?? 0.0).toDouble(),
      totalAmount: (preview['tot_amount'] ?? preview['sales_odr_total'] ?? preview['total_amount'] as num? ?? 0.0).toDouble(),
      totalTax: (preview['tot_tax'] ?? preview['sales_odr_tax'] ?? preview['total_tax'] as num? ?? 0.0).toDouble(),
      discount: (preview['tot_disc'] ?? preview['discount'] ?? 0.0).toDouble(),
      roundOff: (preview['sales_odr_roundoff'] ?? 0.0).toDouble(),
      qrLink: (preview['qr_link'] ?? preview['zatca_qr'] ?? responseJson['qr_link'] ?? responseJson['zatca_qr'])?.toString(),
      captainName: captainName,  // ✅ ADD
      areaId: (preview['rt_area_id'] as num? ?? cartController.selectedAreaId.value).toInt(),
      areaName: cartController.selectedAreaName.value,
      priceGroupId: (preview['prcgrp_id'] as num? ?? cartController.selectedPriceGroupId.value).toInt(),
      isUnsynced: isOffline,
      sales_odr_order_type: orderType,
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
        final updatedOrder = (orders + soldOrders).firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );
        
        final printerController = Get.find<PrinterController>();
        if (updatedOrder.status.value != OrderStatus.draft) {
          await printerController.printCancelledOrder(updatedOrder).catchError((e) {
            debugPrint("Offline cancellation print error: $e");
          });
        }

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
        if (originalStatus != OrderStatus.draft) {
          final printerController = Get.find<PrinterController>();
          printerController.printCancelledOrder(updatedOrder).catchError((e) {
            debugPrint("Background printing error: $e");
          });
        }
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
      o.status.value == OrderStatus.draft ||
      o.status.value == OrderStatus.billed) &&
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
