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
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';

import '../../../../helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_type.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../cart/controller/cart_controller.dart';
import '../../order_type/controller/order_type_controller.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';
import 'home_controller.dart';

class OrdersController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final orders = <OrderModel>[].obs;
  final isLoading = false.obs;

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

      // 1. Load local unsynced orders first — works fully offline
      final unsyncedData = await _dbHelper.getUnsyncedOrders();
      final List<OrderModel> localUnsyncedOrders = unsyncedData.map((json) {
        List<OrderItem> localItems = [];
        String tableName = json['customer_name'] ?? "Offline Order";
        int chairNumber = 0;
        int? areaId;
        int? priceGroupId;
        int orderType = (json['order_type_id'] as num? ?? 0).toInt();
        String invNo = json['inv_no']?.toString() ?? "LOCAL";
        String orderId = json['server_id']?.toString() ?? json['uuid']?.toString() ?? "";

        try {
          final payloadStr = json['payload'] as String?;
          if (payloadStr != null && payloadStr.isNotEmpty) {
            final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
            
            tableName = payload['table_name'] ?? tableName;
            chairNumber = (payload['no_seats'] as num? ?? 0).toInt();
            orderType = (payload['pos_odr_type'] as num? ?? orderType).toInt();
            
            if (payload['sq_inv_no'] != null && payload['sq_inv_no'].toString() != '0') {
               invNo = payload['sq_inv_no'].toString();
            }

            final resTable = payload['res_table'] as Map<String, dynamic>?;
            if (resTable != null) {
              areaId = (resTable['rt_area_id'] as num?)?.toInt();
              priceGroupId = (resTable['prcgrp_id'] as num?)?.toInt();
            }

            final List<dynamic> saleItems = payload['sale_items'] ?? [];

            // IMPORTANT: Filter out deleted items during reconstruction
            final mainItems = saleItems.where((i) => (i['is_addon'] == 0 || i['is_addon'] == null) && i['is_deleted'] != 1).toList();
            final addonItems = saleItems.where((i) => i['is_addon'] == 1 && i['is_deleted'] != 1).toList();

            for (final si in mainItems) {
              final prdId = si['salesub_prd_id']?.toString() ?? '';
              final unitId = (si['salesub_unit_id'] as num? ?? 0).toInt();
              final addons = addonItems.where((a) {
                return a['addon_parent_prd_id']?.toString() == prdId &&
                    a['addon_parent_unit_id'] == unitId;
              }).map((a) => AddonModel(
                id: (a['salesub_prd_id'] as num? ?? 0).toInt(),
                prdId: (a['salesub_prd_id'] as num? ?? 0).toInt(),
                prdaddon_flags: (a['is_addon'] as num? ?? 1).toInt(),
                name: a['prd_name']?.toString() ?? '',
                price: (a['salesub_rate'] as num? ?? 0.0).toDouble(),
                unitDisplay: a['salesub_unit_display']?.toString() ?? '',
                unitId: (a['salesub_unit_id'] as num? ?? 0).toInt(),
                initialQty: (a['salesub_qty'] as num? ?? 0).toInt(),
                taxPer: (a['salesub_tax_per'] as num? ?? 0.0).toDouble(),
                taxCatId: (a['prd_tax_cat_id'] as num? ?? 0).toInt(),
              )).toList();

              localItems.add(OrderItem(
                product: FoodItemModel(
                  id: prdId,
                  name: si['prd_name']?.toString() ?? '',
                  categoryId: '',
                  price: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
                  prd_tax: (si['salesub_tax_per'] as num? ?? 0.0).toDouble(),
                  image: '',
                  unitDisplay: si['salesub_unit_display']?.toString() ?? '',
                  taxPer: (si['salesub_tax_per'] as num? ?? 0.0).toDouble(),
                  taxCatId: (si['prd_tax_cat_id'] as num? ?? 0).toInt(),
                ),
                unit: ProductUnit(
                  unitId: unitId,
                  unitName: si['salesub_unit_display']?.toString() ?? '',
                  unitDisplay: si['salesub_unit_display']?.toString() ?? '',
                  rate: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
                  unitBaseQty: (si['base_qty'] as num? ?? 1.0).toDouble(),
                  existAddOns: [],
                ),
                selectedAddons: addons,
                quantity: (si['salesub_qty'] as num? ?? 1).toInt(),
                priceAtOrder: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
              ));
            }
          }
        } catch (e) {
          debugPrint("Error parsing local order payload: $e");
        }

        return OrderModel(
          id: orderId,
          invNo: invNo,
          tableId: json['table_id']?.toString() ?? "",
          tableName: tableName,
          chairNumber: chairNumber,
          sales_odr_pos_status: (json['status'] == 'draft') ? 0 : 1,
          items: localItems,
          status: (json['status'] == 'draft') ? OrderStatus.draft : OrderStatus.pending,
          createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
          totalAmount: (json['total_amount'] as num? ?? 0.0).toDouble(),
          totalTax: (json['total_tax'] as num? ?? 0.0).toDouble(),
          isUnsynced: (json['is_synced'] == 0),
          areaId: areaId,
          priceGroupId: priceGroupId,
          sales_odr_order_type: orderType,
        );
      }).toList();

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

      // 3. Merge all sources with Priority
      final List<OrderModel> finalOrders = [];

      // Priority 1: Local unsynced orders (contain the latest local changes/edits)
      finalOrders.addAll(localUnsyncedOrders);

      // Priority 2: Orders fetched from API (only if not already present in unsynced)
      for (var fOrder in fetchedOrders) {
        final bool alreadyPresent = finalOrders.any((o) {
          if (o.invNo != "LOCAL" && fOrder.invNo != "LOCAL" && o.invNo == fOrder.invNo) {
            return true;
          }
          return o.id == fOrder.id; // fallback: match by uuid/server_id
        });
        if (!alreadyPresent) finalOrders.add(fOrder);
      }

      // Priority 3: Orders from processing tables cache
      for (var pOrder in allProcessingOrders) {
        final bool alreadyPresent = finalOrders.any((o) {
          if (o.invNo != "LOCAL" && pOrder.invNo != "LOCAL" && o.invNo == pOrder.invNo) {
            return true;
          }
          return o.id == pOrder.id;
        });
        if (!alreadyPresent) finalOrders.add(pOrder);
      }


      finalOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      orders.assignAll(finalOrders);

    } catch (e) {
      debugPrint("Error fetching orders: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// Manual sync trigger from UI
  Future<void> syncOrders() async {
    final syncService = Get.find<SyncService>();
    await syncService.syncPendingOrders();
    await fetchOrders(); // Refresh list after sync
  }

  Future<void> fetchOrderDetails(OrderModel order) async {
    if (order.isUnsynced) {
      // For unsynced orders, try to refresh details from local payload
      await _loadOrderDetailsFromLocal(order);
      return;
    }
    try {
      final response = await _apiService.post("mobileapp/pos/get_sale_order_details_pos", data: {
        "usr_id": int.tryParse(AppState.userId) ?? 18,
        "sales_odr_inv_no": int.tryParse(order.invNo) ?? 0,
      });
      if (response.statusCode == 200) {
        final data = response.data['data'];
        if (data == null) return;

        final String imageBaseUrl = data['image_url']?.toString() ?? "";
        final List<dynamic> subItems = data['sales_order_sub'] ?? [];
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
          final dashboardController = Get.find<DashboardController>();
          final double quantity = (productJson['salesub_qty'] as num? ?? 1).toDouble();
          final double baseRate = (productJson['rate'] as num? ??
              productJson['sales_ord_sub_amnt'] as num? ?? 0.0).toDouble();
          final double tax = (productJson['sales_ord_sub_tax'] as num? ?? 0.0).toDouble();

          final double price = dashboardController.vatType.value == 1
              ? baseRate + tax
              : baseRate;
          final String prdId = (productJson['sales_ord_sub_prod_id'] ?? 0).toInt().toString();
          final int unitId = (productJson['salesub_unit_id'] as num? ?? 0).toInt();

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
              prdaddon_flags: (addonJson['prd_is_addon'] as num? ?? 1).toInt(),
              name: addonJson['prd_name']?.toString() ?? '',
              price: (addonJson['rate'] as num? ?? addonJson['sales_ord_sub_rate'] as num? ?? 0.0).toDouble(),
              unitDisplay: addonJson['prd_unit_name']?.toString() ?? '',
              unitId: (addonJson['salesub_unit_id'] as num? ?? 0).toInt(),
              initialQty: (addonJson['salesub_qty'] as num? ?? 0).toInt(),
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
              unitDisplay: productJson['prd_unit_name']?.toString() ?? '',
              taxPer: (productJson['sales_ord_sub_tax_per'] as num? ?? 0.0).toDouble(),
              taxCatId: (productJson['sales_ord_sub_taxcat_id'] as num? ?? 0).toInt(),
            ),
            unit: ProductUnit(
              unitId: unitId,
              unitName: productJson['prd_unit_name']?.toString() ?? '',
              unitDisplay: productJson['prd_unit_name']?.toString() ?? '',
              rate: price,
              unitBaseQty: (productJson['base_qty'] as num? ?? 1.0).toDouble(),
              existAddOns: [],
            ),
            selectedAddons: selectedAddons,
            quantity: quantity.toInt(),
            priceAtOrder: price,
          ));
        }

        final index = orders.indexWhere((o) => o.invNo == order.invNo);
        if (index != -1) {
          orders[index] = OrderModel(
            id: order.id,
            invNo: order.invNo,
            tableId: (data['sales_odr_table_id'] ?? orders[index].tableId).toString(),
            tableName: data['sales_odr_table_name']?.toString() ?? orders[index].tableName,
            chairNumber: (data['sales_odr_no_seats'] as num? ?? orders[index].chairNumber).toInt(),
            sales_odr_pos_status: (data['sales_odr_pos_status'] as num? ?? 0).toInt(),
            items: items,
            status: order.status.value,
            createdAt: order.createdAt,
            totalAmount: (data['sales_odr_total'] as num? ?? orders[index].totalAmount).toDouble(),
            totalTax: (data['sales_odr_tax'] as num? ?? 0.0).toDouble(),
            areaId: orders[index].areaId,
            areaName: orders[index].areaName,
            priceGroupId: orders[index].priceGroupId,
            sales_odr_order_type: (data['sales_odr_order_type'] as num? ?? orders[index].sales_odr_order_type).toInt(),
          );
          orders.refresh();
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

      final payloadStr = rows.first['payload'] as String?;
      if (payloadStr == null || payloadStr.isEmpty) return;

      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      
      String tableName = payload['table_name'] ?? order.tableName;
      int chairNumber = (payload['no_seats'] as num? ?? order.chairNumber).toInt();
      int? areaId;
      int? priceGroupId;
      int orderType = (payload['pos_odr_type'] as num? ?? order.sales_odr_order_type).toInt();
      
      final resTable = payload['res_table'] as Map<String, dynamic>?;
      if (resTable != null) {
          areaId = (resTable['rt_area_id'] as num?)?.toInt();
          priceGroupId = (resTable['prcgrp_id'] as num?)?.toInt();
      }

      final List<dynamic> saleItems = payload['sale_items'] ?? [];

      // Filter out deleted items
      final mainItems = saleItems.where((i) => (i['is_addon'] == 0 || i['is_addon'] == null) && i['is_deleted'] != 1).toList();
      final addonItems = saleItems.where((i) => i['is_addon'] == 1 && i['is_deleted'] != 1).toList();

      final List<OrderItem> items = [];
      for (final si in mainItems) {
        final prdId = si['salesub_prd_id']?.toString() ?? '';
        final unitId = (si['salesub_unit_id'] as num? ?? 0).toInt();

        final addons = addonItems.where((a) {
          return a['addon_parent_prd_id']?.toString() == prdId &&
              a['addon_parent_unit_id'] == unitId;
        }).map((a) => AddonModel(
          id: (a['salesub_prd_id'] as num? ?? 0).toInt(),
          prdId: (a['salesub_prd_id'] as num? ?? 0).toInt(),
          prdaddon_flags: (a['is_addon'] as num? ?? 1).toInt(),
          name: a['prd_name']?.toString() ?? '',
          price: (a['salesub_rate'] as num? ?? 0.0).toDouble(),
          unitDisplay: a['salesub_unit_display']?.toString() ?? '',
          unitId: (a['salesub_unit_id'] as num? ?? 0).toInt(),
          initialQty: (a['salesub_qty'] as num? ?? 0).toInt(),
          taxPer: (a['salesub_tax_per'] as num? ?? 0.0).toDouble(),
          taxCatId: (a['prd_tax_cat_id'] as num? ?? 0).toInt(),
        )).toList();

        items.add(OrderItem(
          product: FoodItemModel(
            id: prdId,
            name: si['prd_name']?.toString() ?? '',
            categoryId: '',
            price: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
            prd_tax: (si['salesub_tax_per'] as num? ?? 0.0).toDouble(),
            image: '',
            unitDisplay: si['salesub_unit_display']?.toString() ?? '',
            taxPer: (si['salesub_tax_per'] as num? ?? 0.0).toDouble(),
            taxCatId: (si['prd_tax_cat_id'] as num? ?? 0).toInt(),
          ),
          unit: ProductUnit(
            unitId: unitId,
            unitName: si['salesub_unit_display']?.toString() ?? '',
            unitDisplay: si['salesub_unit_display']?.toString() ?? '',
            rate: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
            unitBaseQty: (si['base_qty'] as num? ?? 1.0).toDouble(),
            existAddOns: [],
          ),
          selectedAddons: addons,
          quantity: (si['salesub_qty'] as num? ?? 1).toInt(),
          priceAtOrder: (si['salesub_rate'] as num? ?? 0.0).toDouble(),
        ));
      }

      final index = orders.indexWhere((o) => o.id == order.id);
      if (index != -1 && items.isNotEmpty) {
        orders[index] = OrderModel(
          id: order.id,
          invNo: order.invNo,
          tableId: order.tableId,
          tableName: tableName,
          chairNumber: chairNumber,
          sales_odr_pos_status: order.sales_odr_pos_status,
          items: items,
          status: order.status.value,
          createdAt: order.createdAt,
          totalAmount: order.totalAmount,
          totalTax: order.totalTax,
          areaId: areaId ?? order.areaId,
          areaName: order.areaName,
          priceGroupId: priceGroupId ?? order.priceGroupId,
          isUnsynced: order.isUnsynced,
          sales_odr_order_type: orderType,
        );
        orders.refresh();
      }
    } catch (e) {
      debugPrint("_loadOrderDetailsFromLocal error: $e");
    }
  }

  OrderModel parseOrderResponse(Map<String, dynamic> responseJson) {
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

      // In OrdersController.parseOrderResponse, replace the quantity/rate calculation block:

      // Get the display unit name to determine if conversion is needed
      String unitDisplay = sub['salesub_unit_display']?.toString() ?? '';
      double rawQty = (sub['sales_ord_sub_qty'] as num? ?? 1).toDouble();
      double rawRate = (sub['sales_ord_sub_rate'] as num? ?? sub['rate'] as num? ?? 0.0).toDouble();
      double baseQty = (sub['unit_base_qty'] as num? ?? 1.0).toDouble();

      int displayQty;
      double displayRate = rawRate;

// Check if this is a bulk unit (like B24, case, box, etc.)
      bool isBulkUnit = unitDisplay.contains(RegExp(r'[B|b]\d+')) ||
          unitDisplay.toLowerCase().contains('case') ||
          unitDisplay.toLowerCase().contains('box') ||
          unitDisplay.toLowerCase().contains('pack');

      if (baseQty > 1.0 && isBulkUnit) {
        // This is a bulk item
        if (rawQty > baseQty) {
          // Quantity is in display units (e.g., 2 B24)
          displayQty = rawQty.toInt();
        } else {
          // Quantity is in base units (e.g., 24 pieces)
          displayQty = (rawQty / baseQty).round();
          if (displayQty < 1 && rawQty > 0) displayQty = 1;
        }
      } else {
        displayQty = rawQty.toInt();
      }

      log("📊 Unit: $unitDisplay, rawQty: $rawQty, baseQty: $baseQty, displayQty: $displayQty");

// Optional: Use cartItem for rate adjustment if still available
      final cartItem = cartController.cartItems.firstWhereOrNull(
              (item) => item.product.id == prdId && item.unit.unitId == unitId && !item.isDeleted.value
      );

      if (cartItem != null && displayRate == rawRate) {
        // Only adjust rate if we haven't already set it
        double cartBaseQty = cartItem.unit.unitBaseQty;
        if (cartBaseQty > 0 && cartBaseQty != 1.0) {
          displayRate = rawRate * cartBaseQty;
        }
      }

      final int flag = (sub['sales_ord_sub_flags'] as num? ?? 1).toInt();
      final bool isRemoved = flag == 0;

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
        tokenPrinterId: (sub['cat_token_printer'] as num?)?.toInt(),
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

    // Prefer data from server/preview response, fallback to cart controller
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
        // For unsynced orders, we must load details from local payload first
        await _loadOrderDetailsFromLocal(order);
    }
    
    try {
      isLoading.value = true;

      if (!order.isUnsynced && order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      final updatedOrder = orders.firstWhere((o) => o.id == order.id, orElse: () => order);

      if (updatedOrder.items.isNotEmpty) {
        // ✅ Set the order type to match the order being edited
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
        showSafeSnackbar("Error", "Could not load order items.",);
      }
    } catch (e) {
      debugPrint("Error editing order: $e");
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
        await _dbHelper.deleteOrder(order.id);
        orders.removeWhere((o) => o.id == order.id);
        showSafeSnackbar("Success", "Offline order deleted successfully");
        return;
      }

      // Synced order cancellation logic
      if (order.items.isEmpty) {
        await fetchOrderDetails(order);
      }

      final updatedOrder = orders.firstWhere((o) => o.invNo == order.invNo, orElse: () => order);
      final originalStatus = order.status.value;

      order.status.value = OrderStatus.cancelled;

      final cartController = Get.find<CartController>();
      bool? success = await cartController.cancelOrder(order.invNo);

      if (success == true) {
        // Also delete from local DB if it exists there
        await _dbHelper.deleteOrder(order.id);
        
        orders.removeWhere((o) => o.invNo == order.invNo);

        showSafeSnackbar(
          "Success",
          "Order #${order.invNo} cancelled successfully",);

        final printerController = Get.find<PrinterController>();
        printerController.printCancelledOrder(updatedOrder).catchError((e) {
          debugPrint("Background printing error: $e");
        });

      } else {
        order.status.value = originalStatus;
        showSafeSnackbar(
          "Error",
          "Failed to cancel order",);
      }
    } catch (e) {
      debugPrint("Error cancelling order: $e");
    }
  }

  void addOrder(OrderModel order) {
    orders.insert(0, order);
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final index = orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      orders[index].status.value = newStatus;
    }
  }

  List<OrderModel> get pendingOrders => orders.where((o) => (o.status.value == OrderStatus.pending || o.status.value == OrderStatus.preparing || o.status.value == OrderStatus.draft) && o.status.value != OrderStatus.paid && o.status.value != OrderStatus.cancelled).toList();
  
  List<OrderModel> get dineInOrders => pendingOrders.where((o) => o.sales_odr_order_type == 0).toList();
  List<OrderModel> get deliveryOrders => pendingOrders.where((o) => o.sales_odr_order_type == 1).toList();
  List<OrderModel> get pickupOrders => pendingOrders.where((o) => o.sales_odr_order_type == 2).toList();
  
  List<OrderModel> get paidOrders => orders.where((o) => o.status.value == OrderStatus.paid).toList();

  List<OrderModel> get completedOrders => orders.where((o) => o.status.value == OrderStatus.served || o.status.value == OrderStatus.paid).toList();
}
