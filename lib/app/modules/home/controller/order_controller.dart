import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import '../../../../helper/snackbar_helper.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_type.dart';
import '../../../data/services/api_endpoints.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../../order_type/controller/order_type_controller.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';
import 'home_controller.dart';
enum OrderDetailsState { loading, loaded, failed }
class OrdersController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final orders = <OrderModel>[].obs;
  final soldOrders = <OrderModel>[].obs;
  final isLoading = false.obs;
  final loadingOrderDetailsIds = <String>{}.obs;
  final printingOrderIds = <String>{}.obs;
  final detailsFailedIds = <String>{}.obs;
  final Map<String, List<OrderItem>> _itemsCache = {};
  final Map<String, double> _itemsCacheTotal = {};
  final selectedSoldDate = DateTime
      .now()
      .obs;

  Timer? _timer;
  final currentTime = DateTime
      .now()
      .obs;

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

  bool _sameOrder(OrderModel a, OrderModel b) =>
      a.id == b.id ||
          (_isRealInvNo(a.invNo) && _isRealInvNo(b.invNo) && a.invNo == b.invNo);

  String _orderKey(OrderModel o) =>
      _isRealInvNo(o.invNo) ? 'inv:${o.invNo}' : 'id:${o.id}';

  void _rememberItems(OrderModel o) {
    if (o.items.isEmpty) return;
    _itemsCache[_orderKey(o)] = List<OrderItem>.from(o.items);
    _itemsCacheTotal[_orderKey(o)] = o.totalAmount;
  }

  /// Cached items, only if the order hasn't changed since (same total).
  List<OrderItem>? _cachedItemsFor(OrderModel o) {
    final key = _orderKey(o);
    final items = _itemsCache[key];
    final total = _itemsCacheTotal[key];
    if (items == null || total == null) return null;
    return (total - o.totalAmount).abs() < 0.01 ? items : null;
  }

  /// Single source of truth for "the best version of this order we have".
  /// Safe to call inside Obx.
  OrderModel resolveOrder(OrderModel ref) {
    final matches = [...orders, ...soldOrders].where((o) => _sameOrder(o, ref));
    final withItems = matches.firstWhereOrNull((o) => o.items.isNotEmpty);
    if (withItems != null) return withItems;

    final base = matches.isNotEmpty ? matches.first : ref;
    if (base.items.isNotEmpty) return base;

    final cached = _cachedItemsFor(base);
    return cached != null ? base.copyWith(items: cached) : base;
  }

  /// loading / loaded / failed, derived, never guessed from items.isEmpty alone.
  OrderDetailsState detailsState(OrderModel ref) {
    final o = resolveOrder(ref);
    if (o.items.isNotEmpty) return OrderDetailsState.loaded;
    final loading = loadingOrderDetailsIds.contains(o.id) ||
        (o.invNo.isNotEmpty && loadingOrderDetailsIds.contains(o.invNo));
    if (loading) return OrderDetailsState.loading;
    if (detailsFailedIds.contains(o.id)) return OrderDetailsState.failed;
    return OrderDetailsState.loading; // not started yet, so no flash of the error
  }

  String getElapsedTime(DateTime createdAt) {
    final diff = currentTime.value.difference(createdAt);
    if (diff.isNegative) return "00:00";

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);

    if (hours > 0) {
      return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(
          2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(
        2, '0')}";
  }

  Future<void> fetchOrders() async {
    try {
      isLoading.value = true;
      await Future.wait([_fetchActiveOrders(), _fetchSoldOrders()]);
    } catch (e) {
      debugPrint("Error fetching orders: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchOrdersSafely() async {
    await fetchOrders();
  }

  DateTime _parseOrderTime(Map<String, dynamic> map) {
    final dateStr = map['sales_odr_date']?.toString() ??
        map['sales_odr_datetime']?.toString().split(' ')[0] ??
        map['created_at']?.toString().split(' ')[0] ??
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final timeStr = map['sales_odr_time']?.toString() ??
        map['sales_odr_datetime']?.toString().split(' ').last ??
        map['created_at']?.toString().split(' ').last ??
        '00:00:00';

    final dateTimeStr = '$dateStr $timeStr';
    return DateTime.tryParse(dateTimeStr) ?? DateTime.now();
  }

  String _firstNonEmptyValue(List<dynamic> values) {
    for (final v in values) {
      if (v != null && v
          .toString()
          .isNotEmpty && v.toString() != 'null') {
        return v.toString();
      }
    }
    return '';
  }

  /// Server keeps edit history: superseded rows have sales_ord_sub_flags == 0.
  bool _isSupersededRow(dynamic r) {
    if (r is! Map) return false;
    final f = r['sales_ord_sub_flags'];
    if (f == null) return false; // local/hub payloads (sale_items) have no flag
    return (int.tryParse(f.toString()) ?? 1) == 0;
  }

  Map<dynamic, dynamic> _resolveAddonOwners(List<dynamic> rows) {
    final owners = Map<dynamic, dynamic>.identity();
    for (var index = 0; index < rows.length; index++) {
      final addon = rows[index];
      if (!_isAddonRow(addon)) continue;

      final productId = (addon['addon_parent_prd_id'] ??
              addon['sales_odr_sub_addon_parent_prd_id'])
          ?.toString();
      final unitId = (addon['addon_parent_unit_id'] ??
              addon['sales_odr_sub_addon_parent_unit_id'] ??
              0)
          .toString();
      final superseded = _isSupersededRow(addon);

      bool matches(dynamic row) {
        if (_isAddonRow(row)) return false;
        final product = (row['salesub_prd_id'] ??
                row['sales_ord_sub_prod_id'] ??
                row['salesub_prd'])
            ?.toString();
        final unit = (row['salesub_unit_id'] ??
                row['sales_ord_sub_unit_id'] ??
                0)
            .toString();
        return productId != null &&
            product == productId &&
            (unitId == '0' || unit == '0' || unit == unitId);
      }

      final previous = rows
          .take(index)
          .lastWhereOrNull((row) => matches(row) &&
              (!superseded || _isSupersededRow(row)));
      if (previous != null && _isSupersededRow(previous) == superseded) {
        owners[addon] = previous;
        continue;
      }

      // Edits append replacement parent rows, but unchanged add-ons keep
      // their original IDs and can still precede the replacement.
      final replacement = rows.skip(index + 1).firstWhereOrNull(
        (row) => matches(row) && _isSupersededRow(row) == superseded,
      );
      if (replacement != null) owners[addon] = replacement;
    }
    return owners;
  }

  Future<void> _fetchActiveOrders() async {
    try {
      final bool isLocalHost =
          DeviceConfig.operationMode == OperationMode.local &&
              DeviceConfig.role == DeviceRole.server;

      final bool readLocalAll =
          isLocalHost || DeviceConfig.operationMode == OperationMode.online ||
              DeviceConfig.operationMode == OperationMode.local;
      final ordersData = readLocalAll
          ? await _dbHelper.getActiveLocalOrders()
          : await _dbHelper.getUnsyncedOrders();

      final List<OrderModel> finalOrders = ordersData
          .map((json) => _mapJsonToOrderModel(json))
          .where(
            (o) =>
        o.status.value != OrderStatus.paid &&
            o.status.value != OrderStatus.cancelled,
      ).toList();
      List<OrderModel> allProcessingOrders = [];
      try {
        final tablesController = Get.find<TablesController>();
        await tablesController.fetchTables();

        for (var area in tablesController.areas) {
          for (var table in area.tables) {
            for (var processing in table.processingTable) {
              if (processing is Map<String, dynamic> &&
                  _isVisibleServerOrder(processing)) {
                final orderType =
                (processing['sales_odr_order_type'] as num? ?? 0).toInt();
                int posStatus =
                    (processing['sales_odr_pos_status'] as num? ??
                            processing['res_status'] as num? ??
                            0)
                        .toInt();

                OrderStatus status;
                if (posStatus == 1) {
                  status = OrderStatus.pending;
                } else if (posStatus == 2) {
                  status = OrderStatus.billed;
                } else {
                  status = OrderStatus.draft;
                }

                allProcessingOrders.add(
                  OrderModel(
                    id: (processing['sales_odr_id'] ?? '').toString(),
                    tableId: (processing['sales_odr_table_id'] ?? table.id)
                        .toString(),
                    invNo: (processing['sales_odr_inv_no'] ?? '').toString(),
                    branchInv: _firstNonEmptyValue([
                      processing['sales_odr_sales_branch_inv'],
                      processing['sales_odr_branch_inv'],
                      processing['sales_branch_inv'],
                    ]),
                    tableName: _resolveName(processing, orderType, table.name),
                    customerName:
                    (processing['sq_cust_name'] ??
                        processing['customer_name'] ??
                        processing['cust_name'] ??
                        '')
                        ?.toString(),
                    tokenNo: processing['sales_odr_token_no']?.toString(),
                    chairNumber: (processing['sales_odr_no_seats'] as num? ?? 0)
                        .toInt(),
                    sales_odr_pos_status: posStatus,
                    items: [],
                    status: status,
                    createdAt: DateTime.tryParse(processing['sales_odr_datetime'] ?? '',) ?? DateTime.now(),
                    orderTime: _parseOrderTime(processing),
                    subTotal:
                    (processing['tot_rate'] as num? ??
                        processing['sub_total'] as num? ??
                        0.0)
                        .toDouble(),
                    totalAmount:
                    (processing['sales_odr_total'] ??
                        processing['tot_amount'] ??
                        processing['total_amount'] ??
                        processing['sq_total'] as num? ??
                        0.0)
                        .toDouble(),
                    areaId: area.id,
                    areaName: area.name,
                    priceGroupId: area.priceGroupID,
                    totalTax:
                    (processing['sales_odr_tax'] ??
                        processing['tot_tax'] ??
                        processing['total_tax'] as num? ??
                        0.0)
                        .toDouble(),
                    totalCgst: (processing['tot_cgst_tax'] as num? ?? 0.0)
                        .toDouble(),
                    totalSgst: (processing['tot_sgst_tax'] as num? ?? 0.0)
                        .toDouble(),
                    sales_odr_order_type: orderType,
                    discount:
                    (processing['tot_disc'] ??
                        processing['discount'] as num? ??
                        0.0)
                        .toDouble(),
                    roundOff: (processing['sales_odr_roundoff'] as num? ?? 0.0)
                        .toDouble(),
                    qrLink:
                    (processing['qr_link'] ?? processing['zatca_qr'] ?? '')
                        .toString(),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint("fetchOrders: Could not load tables (offline?): $e");
      }

      List<OrderModel> fetchedOrders = [];
      bool hubFetchFailed = false;

      if (DeviceConfig.operationMode == OperationMode.local) {
        if (DeviceConfig.role == DeviceRole.client) {
          final hostIp = DeviceConfig.hostIp;
          if (hostIp != null &&
              hostIp
                  .trim()
                  .isNotEmpty &&
              DeviceConfig.hasAuthToken) {
            try {
              final hubResult = await LocalHubClient.instance.fetchActiveOrders(
                hostIp: hostIp,
                port: DeviceConfig.hostPort,
              );
              final List<dynamic> rows = hubResult['data'] ?? [];
              fetchedOrders = rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                    _mapJsonToOrderModel(Map<String, dynamic>.from(row)),
              )
                  .toList();
            } catch (e) {
              debugPrint("fetchOrders: Local Hub fetch failed (client): $e");
              hubFetchFailed = true;
            }
          } else {
            hubFetchFailed = true;
          }
        }
      } else {
        try {
          final response = await _apiService.post(
            ApiEndpoints.listOrders,
            data: {"usr_id": int.tryParse(AppState.userId) ?? 18},
          );

          if (response.statusCode == 200) {
            final data = (response.data['data'] as List? ?? [])
                .where(_isVisibleServerOrder)
                .toList();
            try {
              await _dbHelper.cacheServerOrders(data);
            } catch (e) {
              debugPrint("Error caching fetched online orders: $e");
            }
            fetchedOrders = data.map((json) {
              final orderType = (json['sales_odr_order_type'] as num? ?? 0)
                  .toInt();
              int posStatus =
                  (json['sales_odr_pos_status'] as num? ??
                          json['res_status'] as num? ??
                          0)
                      .toInt();

              OrderStatus status;
              if (posStatus == 1) {
                status = OrderStatus.pending;
              } else if (posStatus == 2) {
                status = OrderStatus.billed;
              } else {
                status = OrderStatus.draft;
              }

              final processingOrder = allProcessingOrders.firstWhereOrNull(
                    (o) =>
                o.invNo == (json['sales_odr_inv_no'] ?? '').toString(),
              );

              return OrderModel(
                id: (json['sales_odr_id'] ?? '').toString(),
                tableId:
                (json['sales_odr_table_id'] ??
                    processingOrder?.tableId ??
                    '')
                    .toString(),
                invNo: (json['sales_odr_inv_no'] ?? '').toString(),
                branchInv: _firstNonEmptyValue([
                  json['sales_odr_sales_branch_inv'],
                  json['sales_odr_branch_inv'],
                  json['sales_branch_inv'],
                  processingOrder?.branchInv,
                ]),
                tableName: _resolveName(
                  json,
                  orderType,
                  processingOrder?.tableName ?? 'unknown_table'.tr,
                ),
                customerName:
                (json['sq_cust_name'] ??
                    json['customer_name'] ??
                    json['cust_name'] ??
                    processingOrder?.customerName)
                    ?.toString(),
                tokenNo:
                (json['sales_odr_token_no'] ?? processingOrder?.tokenNo)
                    ?.toString(),
                chairNumber:
                (json['sales_odr_no_seats'] as num? ??
                    processingOrder?.chairNumber ??
                    0)
                    .toInt(),
                captainName:
                (json['usr_name'] ??
                    json['captain_name'] ??
                    json['ledger_name'])
                    ?.toString(),
                sales_odr_pos_status: posStatus,
                items: [],
                status: status,
                createdAt:
                DateTime.tryParse(json['sales_odr_datetime'] ?? '') ??
                    processingOrder?.createdAt ??
                    DateTime.now(),
                orderTime: _parseOrderTime(json),
                subTotal:
                (json['tot_rate'] as num? ??
                    json['sub_total'] as num? ??
                    processingOrder?.subTotal ??
                    0.0)
                    .toDouble(),
                totalAmount:
                (json['sales_odr_total'] ??
                    json['tot_amount'] ??
                    json['total_amount'] ??
                    json['sq_total'] as num? ??
                    processingOrder?.totalAmount ??
                    0.0)
                    .toDouble(),
                areaId: processingOrder?.areaId,
                areaName: processingOrder?.areaName,
                priceGroupId: processingOrder?.priceGroupId,
                totalTax:
                (json['sales_odr_tax'] ??
                    json['tot_tax'] ??
                    json['total_tax'] as num? ??
                    0.0)
                    .toDouble(),
                totalCgst:
                (json['tot_cgst_tax'] as num? ??
                    processingOrder?.totalCgst ??
                    0.0)
                    .toDouble(),
                totalSgst:
                (json['tot_sgst_tax'] as num? ??
                    processingOrder?.totalSgst ??
                    0.0)
                    .toDouble(),
                sales_odr_order_type: orderType,
                discount:
                (json['tot_disc'] ??
                    json['discount'] ??
                    processingOrder?.discount ??
                    0.0)
                    .toDouble(),
                roundOff:
                (json['sales_odr_roundoff'] ??
                    processingOrder?.roundOff ??
                    0.0)
                    .toDouble(),
                qrLink:
                (json['qr_link'] ??
                    json['zatca_qr'] ??
                    processingOrder?.qrLink ??
                    '')
                    .toString(),
              );
            }).toList();
          }
        } catch (e) {
          debugPrint("fetchOrders: Could not load order list (offline?): $e");
        }
      }

      if (DeviceConfig.operationMode == OperationMode.local &&
          DeviceConfig.role == DeviceRole.client &&
          hubFetchFailed) {
        return;
      }

      void reconcileOrder(OrderModel serverOrder) {
        if (!_isVisibleOrder(serverOrder)) return;
        final int existingIndex = finalOrders.indexWhere((o) {
          if (o.invNo != "LOCAL" &&
              o.invNo != "OFFLINE" &&
              serverOrder.invNo != "LOCAL" &&
              serverOrder.invNo != "OFFLINE" &&
              o.invNo == serverOrder.invNo) {
            return true;
          }
          return o.id == serverOrder.id;
        });

        if (existingIndex != -1) {
          finalOrders[existingIndex].isUnsynced = false;
          final localOrder = finalOrders[existingIndex];
          if (localOrder.items.isNotEmpty && serverOrder.items.isEmpty) {} else
          if (serverOrder.items.isNotEmpty) {
            localOrder.items.clear();
            localOrder.items.addAll(serverOrder.items);
          }
          localOrder.discount = serverOrder.discount;
          localOrder.roundOff = serverOrder.roundOff;
          localOrder.subTotal = serverOrder.subTotal;
          localOrder.qrLink = serverOrder.qrLink;
          localOrder.totalCgst = serverOrder.totalCgst;
          localOrder.totalSgst = serverOrder.totalSgst;
          localOrder.status.value = serverOrder.status.value;

          _dbHelper.updateOrderStatusByUuid(
            localOrder.id,
            localOrder.status.value.name,
            isSynced: 1,
            serverId: serverOrder.id,
            invNo: serverOrder.invNo,
            branchInv: serverOrder.branchInv,
            total: serverOrder.totalAmount,
            tax: serverOrder.totalTax,
          );
        } else {
          finalOrders.add(serverOrder);
        }
      }

      for (var fOrder in fetchedOrders) {
        reconcileOrder(fOrder);
      }

      for (var pOrder in allProcessingOrders) {
        reconcileOrder(pOrder);
      }

      finalOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      List<OrderModel> visibleOrders = finalOrders;
      if (DeviceConfig.operationMode == OperationMode.local &&
          DeviceConfig.showMyOrdersOnly) {
        visibleOrders = finalOrders
            .where((o) => o.createdByDeviceId == DeviceConfig.deviceId)
            .toList();
      }
      for (final o in visibleOrders) {
        if (o.items.isEmpty) {
          final cached = _cachedItemsFor(o);
          if (cached != null) o.items.addAll(cached);
        }
      }
      orders.assignAll(visibleOrders.where(_isVisibleOrder));
    } catch (e) {
      debugPrint("Error fetching active orders: $e");
    }
  }

  Future<void> downloadAllOrders({int soldDays = 1}) async {
    if (DeviceConfig.operationMode == OperationMode.local) return;
    try {
      final res = await _apiService.post(
        ApiEndpoints.listOrders,
        data: {"usr_id": int.tryParse(AppState.userId) ?? 18},
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = res.data['data'] ?? [];
        await _dbHelper.cacheServerOrders(data);
        await _dbHelper.pruneSyncedActiveOrders(
          data.map((o) => (o['sales_odr_id'] ?? '').toString()).toSet(),
        );
      }

      for (int i = 0; i < soldDays; i++) {
        final d = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().subtract(Duration(days: i)));
        final r = await _apiService.post(
          ApiEndpoints.listSoldOrders,
          data: {"usr_id": int.tryParse(AppState.userId) ?? 18, "date": d},
        );
        if (r.statusCode == 200)
          await _dbHelper.cacheSoldOrders(r.data['data'] ?? []);
      }

      final db = await _dbHelper.database;
      final rows = await db.query(
        'orders',
        where:
        "is_synced = 1 AND (payload IS NULL OR payload NOT LIKE '%sales_order_sub%')",
        limit: 200,
      );
      for (final row in rows) {
        await fetchOrderDetails(_mapJsonToOrderModel(row));
      }
    } catch (e) {
      debugPrint("downloadAllOrders failed (offline?): $e");
    }
  }

  bool _isAddonRow(dynamic i) {
    final flag =
        int.tryParse(
          (i['is_addon'] ?? i['sales_odr_sub_is_addon'] ?? 0).toString(),
        ) ??
            0;
    final parent =
        int.tryParse(
          (i['addon_parent_prd_id'] ??
              i['sales_odr_sub_addon_parent_prd_id'] ??
              0)
              .toString(),
        ) ??
            0;
    return flag == 1 || parent > 0;
  }

  Future<void> _fetchSoldOrders() async {
    try {
      final cachedSoldData = await _dbHelper.getOrdersByStatus(['paid']);
      final List<OrderModel> cachedSoldOrders = cachedSoldData
          .map((json) => _mapJsonToOrderModel(json))
          .toList();

      if (cachedSoldOrders.isNotEmpty) {
        soldOrders.assignAll(cachedSoldOrders.where(_isVisibleOrder));
      }

      if (DeviceConfig.operationMode == OperationMode.local) {
        if (DeviceConfig.role == DeviceRole.client) {
          final hostIp = DeviceConfig.hostIp;
          if (hostIp != null &&
              hostIp
                  .trim()
                  .isNotEmpty &&
              DeviceConfig.hasAuthToken) {
            try {
              final String dateStr = DateFormat(
                'yyyy-MM-dd',
              ).format(selectedSoldDate.value);
              final hubResult = await LocalHubClient.instance.fetchSoldOrders(
                hostIp: hostIp,
                port: DeviceConfig.hostPort,
                date: dateStr,
              );
              final List<dynamic> rows = hubResult['data'] ?? [];
              final hubSoldOrders = rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                    _mapJsonToOrderModel(Map<String, dynamic>.from(row)),
              )
                  .toList();

              final hubIds = hubSoldOrders.map((o) => o.id).toSet();
              final mergedList = [
                ...hubSoldOrders,
                ...cachedSoldOrders.where((c) => !hubIds.contains(c.id)),
              ];
              mergedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              soldOrders.assignAll(mergedList.where(_isVisibleOrder));
            } catch (e) {
              log("OrdersController: Local Hub sold fetch failed: $e");
            }
          }
        }
        return;
      }

      try {
        final String dateStr = DateFormat(
          'yyyy-MM-dd',
        ).format(selectedSoldDate.value);
        final response = await _apiService.post(
          ApiEndpoints.listSoldOrders,
          data: {
            "usr_id": int.tryParse(AppState.userId) ?? 18,
            "date": dateStr,
          },
        );

        if (response.statusCode == 200) {
          final data = (response.data['data'] as List? ?? [])
              .where(_isVisibleServerOrder)
              .toList();

          final List<OrderModel> apiSoldOrders = data.map((json) {
            final int type = (json['sales_odr_order_type'] as num? ?? 0)
                .toInt();
            return OrderModel(
              id: (json['sales_odr_id'] ?? '').toString(),
              invNo: (json['sales_odr_inv_no'] ?? '').toString(),
              branchInv:
              (json['sales_odr_branch_inv'] ??
                  json['sales_branch_inv'] ??
                  json['sales_odr_sales_branch_inv'] ??
                  '')
                  .toString(),
              tableId: (json['sales_odr_table_id'] ?? '').toString(),
              tableName: _resolveName(json, type, 'cash_customer'.tr),
              customerName:
              (json['sq_cust_name'] ??
                  json['customer_name'] ??
                  json['cust_name'] ??
                  '')
                  ?.toString(),
              tokenNo: json['sales_odr_token_no']?.toString(),
              chairNumber: 0,
              sales_odr_pos_status: (json['sales_odr_pos_status'] as num? ?? 3)
                  .toInt(),
              items: [],
              status: OrderStatus.paid,
              createdAt:
              DateTime.tryParse(
                json['sales_odr_datetime'] ?? json['created_at'] ?? '',
              ) ??
                  DateTime.now(),
              orderTime: _parseOrderTime(json),
              subTotal:
              (json['tot_rate'] as num? ?? json['sub_total'] as num? ?? 0.0)
                  .toDouble(),
              totalAmount:
              (json['sales_odr_total'] ??
                  json['tot_amount'] ??
                  json['total_amount'] as num? ??
                  0.0)
                  .toDouble(),
              totalTax:
              (json['sales_odr_tax'] ??
                  json['tot_tax'] ??
                  json['total_tax'] as num? ??
                  0.0)
                  .toDouble(),
              totalCgst: (json['tot_cgst_tax'] as num? ?? 0.0).toDouble(),
              totalSgst: (json['tot_sgst_tax'] as num? ?? 0.0).toDouble(),
              discount: (json['tot_disc'] ?? json['discount'] as num? ?? 0.0)
                  .toDouble(),
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

          final Map<String, String> localUuidToRealInvNo = {};
          final db = await _dbHelper.database;
          for (var cached in cachedSoldOrders) {
            if (cached.invNo == "LOCAL" ||
                cached.invNo == "OFFLINE" ||
                cached.invNo.isEmpty) {
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

          final Set<String> apiInvNos = apiSoldOrders
              .map((o) => o.invNo)
              .toSet();
          final List<OrderModel> mergedList = [];
          mergedList.addAll(apiSoldOrders);
          for (var cached in cachedSoldOrders) {
            if (cached.invNo != "LOCAL" &&
                cached.invNo != "OFFLINE" &&
                cached.invNo.isNotEmpty &&
                apiInvNos.contains(cached.invNo)) {
              continue;
            }
            final realInvNo = localUuidToRealInvNo[cached.id];
            if (realInvNo != null && apiInvNos.contains(realInvNo)) {
              await _dbHelper.deleteOrder(cached.id);
              continue;
            }
            if (apiSoldOrders.any((api) => api.id == cached.id)) {
              continue;
            }
            mergedList.add(cached);
          }

          List<OrderModel> visibleSold = mergedList;
          if (DeviceConfig.operationMode == OperationMode.local &&
              DeviceConfig.showMyOrdersOnly) {
            visibleSold = mergedList
                .where((o) => o.createdByDeviceId == DeviceConfig.deviceId)
                .toList();
          }
          soldOrders.assignAll(visibleSold.where(_isVisibleOrder));

          _backgroundFetchSoldOrderDetails(apiSoldOrders);
        }
      } catch (e) {
        log("OrderController: API fetch failed (Sold), using cache: $e");
      }
    } catch (e) {
      debugPrint("Error fetching sold orders: $e");
    }
  }

  Future<void> _backgroundFetchSoldOrderDetails(
      List<OrderModel> apiSoldOrders,) async {
    for (var order in apiSoldOrders) {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'orders',
        columns: ['payload'],
        where: 'uuid = ?',
        whereArgs: [order.id],
      );

      if (rows.isNotEmpty &&
          (rows.first['payload'] == null ||
              (rows.first['payload'] as String).isEmpty)) {
        await fetchOrderDetails(order);
      }
    }
  }


  String _fullImageUrl(dynamic raw, String base) {
    final img = raw?.toString() ?? '';
    if (img.isEmpty || img == 'null') return '';
    if (img.startsWith('http') || base.isEmpty) return img;
    return base + img;
  }

  OrderModel _mapJsonToOrderModel(Map<String, dynamic> json) {
    List<OrderItem> localItems = [];
    String tableName = json['customer_name'] ?? 'offline_order'.tr;
    String? customerName;
    String? tokenNo = json['token_no']?.toString();
    int chairNumber = 0;
    int? areaId;
    String? areaName;
    int? priceGroupId;
    int orderType = (json['order_type_id'] as num? ?? 0).toInt();
    String invNo = json['inv_no']?.toString() ?? "LOCAL";
    String branchInv = json['branch_inv']?.toString() ?? "";
    String? createdByDeviceId = json['created_by_device_id']?.toString();
    String orderId =
        json['server_id']?.toString() ?? json['uuid']?.toString() ?? "";
    String tableId = json['table_id']?.toString() ?? "";
    double discount = (json['discount_amount'] as num? ?? 0.0).toDouble();
    double roundOff = (json['roundoff_amount'] as num? ?? 0.0).toDouble();
    double subTotal =
    (json['sub_total'] as num? ?? json['tot_rate'] as num? ?? 0.0)
        .toDouble();
    double totalAmount =
    (json['total_amount'] as num? ??
        json['tot_amount'] as num? ??
        json['sales_odr_total'] as num? ??
        0.0)
        .toDouble();
    double totalTax =
    (json['total_tax'] as num? ??
        json['tot_tax'] as num? ??
        json['sales_odr_tax'] as num? ??
        0.0)
        .toDouble();
    double totalCgst = (json['tot_cgst_tax'] as num? ?? 0.0).toDouble();
    double totalSgst = (json['tot_sgst_tax'] as num? ?? 0.0).toDouble();
    String? qrLink;
    String? captainName;
    int? offlineSeq = json['offline_seq'] != null
        ? (json['offline_seq'] as num).toInt()
        : null;
    int? payloadPosStatus;
    Map<String, dynamic>? payloadMap;
    try {
      final payloadStr = json['payload'] as String?;
      if (payloadStr != null && payloadStr.isNotEmpty) {
        final dynamic decoded = jsonDecode(payloadStr);
        if (decoded is Map<String, dynamic>) {
          payloadMap = decoded;
          final Map<String, dynamic> payload = decoded;
          final String imageBaseUrl = payload['image_url']?.toString() ?? '';
          payloadPosStatus =
              (payload['sales_odr_pos_status'] as num? ??
                      payload['res_status'] as num?)
                  ?.toInt();
          final resolvedBranchInv = _firstNonEmptyValue([
            payload['sales_odr_sales_branch_inv'],
            payload['sales_odr_branch_inv'],
            payload['sales_branch_inv'],
          ]);
          chairNumber =
              (payload['no_seats'] ??
                  payload['sales_odr_no_seats'] as num? ??
                  0)
                  .toInt();
          orderType =
              (payload['pos_odr_type'] ??
                  payload['sales_odr_order_type'] as num? ??
                  orderType)
                  .toInt();
          discount = (payload['tot_disc'] ?? payload['discount'] ?? discount)
              .toDouble();
          roundOff = (payload['sales_odr_roundoff'] ?? roundOff).toDouble();
          subTotal = (payload['tot_rate'] ?? payload['sub_total'] ?? subTotal)
              .toDouble();
          totalAmount =
              (payload['tot_amount'] ??
                  payload['sales_odr_total'] ??
                  payload['total_amount'] ??
                  payload['sq_total'] ??
                  totalAmount)
                  .toDouble();
          totalTax =
              (payload['tot_tax'] ??
                  payload['sales_odr_tax'] ??
                  payload['total_tax'] ??
                  totalTax)
                  .toDouble();
          totalCgst = (payload['tot_cgst_tax'] ?? totalCgst).toDouble();
          totalSgst = (payload['tot_sgst_tax'] ?? totalSgst).toDouble();
          qrLink = (payload['qr_link'] ?? payload['zatca_qr'])?.toString();
          customerName =
              (payload['sq_cust_name'] ??
                  payload['customer_name'] ??
                  payload['cust_name'] ??
                  '')
                  ?.toString();
          captainName =
              (payload['agent_name'] ??
                  payload['sale_agent_name'] ??
                  payload['captain_name'])
                  ?.toString();
          tokenNo =
              (payload['sales_odr_token_no'] ??
                  payload['sales_odr_token'] ??
                  tokenNo)
                  ?.toString();
          tableName = _resolveName(payload, orderType, tableName);

          if (payload['sq_inv_no'] != null &&
              payload['sq_inv_no'].toString() != '0') {
            invNo = payload['sq_inv_no'].toString();
          }

          if (resolvedBranchInv.isNotEmpty) {
            branchInv = resolvedBranchInv;
          }
          if (branchInv.isEmpty) {
            branchInv = _firstNonEmptyValue([
              payload['branch_inv'],
              payload['branch_ref_no'],
            ]);
          }

          final dynamic rawResTable = payload['res_table'];
          if (rawResTable is Map<String, dynamic>) {
            final Map<String, dynamic> resTable = rawResTable;
            tableId = (resTable['rt_id'] ?? tableId).toString();
            areaId = (resTable['rt_area_id'] as num?)?.toInt();
            priceGroupId = (resTable['prcgrp_id'] as num?)?.toInt();
          } else if (payload['sales_odr_table_id'] != null) {
            tableId = payload['sales_odr_table_id'].toString();
          }

          if (Get.isRegistered<TablesController>()) {
            final tablesCtrl = Get.find<TablesController>();
            AreaModel? area;
            if (areaId != null && areaId > 0) {
              area = tablesCtrl.areas.firstWhereOrNull((a) => a.id == areaId);
            }
            if (area == null && tableId.isNotEmpty) {
              final tId = int.tryParse(tableId) ?? 0;
              if (tId > 0) {
                area = tablesCtrl.areas.firstWhereOrNull(
                  (a) => a.tables.any((t) => t.id == tId),
                );
              }
            }
            if (area != null) {
              areaName = area.name;
              areaId ??= area.id;
              priceGroupId ??= area.priceGroupID;
            }
          }

          final List<dynamic> ordered =
              [...(payload['sale_items'] ?? payload['sales_order_sub'] ?? [])];

          int subIdOf(dynamic row) => int.tryParse(
                (row['sales_ord_sub_id'] ?? row['salesub_id']).toString(),
              ) ?? 0;
          final ids = ordered.map(subIdOf).toList();
          if (ids.every((id) => id > 0) && ids.toSet().length == ids.length) {
            ordered.sort((a, b) => subIdOf(a).compareTo(subIdOf(b)));
          }

          final ownerOf = _resolveAddonOwners(ordered);
          final liveRows = ordered.where((row) => !_isSupersededRow(row));
          // Some sold/reprint payloads flag every parent as superseded.
          final saleItems =
              liveRows.any((row) => !_isAddonRow(row)) ? liveRows : ordered;
          final mainItems = saleItems.where((row) => !_isAddonRow(row));
          final addonItems = saleItems.where(_isAddonRow);

          for (final si in mainItems) {
            final prdId =
                (si['salesub_prd_id'] ?? si['sales_ord_sub_prod_id'])
                    ?.toString() ??
                    '';
            final dynamic rawUnitId =
                si['salesub_unit_id'] ?? si['sales_ord_sub_unit_id'];
            final int unitId = rawUnitId is num
                ? rawUnitId.toInt()
                : int.tryParse(rawUnitId?.toString() ?? '') ?? 0;
            final dynamic rawSubId = si['sales_ord_sub_id'] ?? si['salesub_id'];
            final int subId = rawSubId is num
                ? rawSubId.toInt()
                : int.tryParse(rawSubId?.toString() ?? '') ?? 0;
            int? tokenPrinterId = si['cat_token_printer'] is num
                ? (si['cat_token_printer'] as num).toInt()
                : int.tryParse(si['cat_token_printer']?.toString() ?? '');
            final bool isDeleted = (si['is_deleted'] ?? 0) == 1;

            if (isDeleted) {
              if (tokenPrinterId == null || tokenPrinterId == 0) {
                if (Get.isRegistered<CartController>()) {
                  final cartCtrl = Get.find<CartController>();
                  final cartItem = cartCtrl.cartItems.firstWhereOrNull(
                    (ci) => ci.product.id.toString() == prdId.toString(),
                  );
                  if (cartItem != null) {
                    tokenPrinterId = cartItem.product.tokenPrinterId;
                  }
                }
                if ((tokenPrinterId == null || tokenPrinterId == 0) &&
                    Get.isRegistered<DashboardController>()) {
                  final dashCtrl = Get.find<DashboardController>();
                  final match = dashCtrl.filteredFoodItems.firstWhereOrNull(
                    (p) => p.id.toString() == prdId.toString(),
                  );
                  if (match != null) {
                    tokenPrinterId = (match.tokenPrinterId ?? 0) > 0
                        ? match.tokenPrinterId
                        : int.tryParse(match.categoryId.toString()) ?? 0;
                  }
                }
              }
            }
            final double baseRate =
            (si['salesub_rate'] ??
                si['sales_ord_sub_rate'] ??
                si['rate'] as num? ??
                0.0)
                .toDouble();
            final double taxAmt =
            (si['salesub_tax'] ??
                si['sales_ord_sub_tax'] ??
                si['sales_ord_sub_tax_rate'] as num? ??
                0.0)
                .toDouble();
            final double cgstRate =
            (si['sales_ord_sub_cgst_rate'] as num? ?? 0.0).toDouble();
            final double sgstRate =
            (si['sales_ord_sub_sgst_rate'] as num? ?? 0.0).toDouble();

            final bool isServerRows = payload['sale_items'] == null;
            final double unitBase =
            ((si['base_qty'] ?? si['unit_base_qty'] ?? 1.0) as num)
                .toDouble();
            final bool derived = unitBase > 1.0;

            final double rawQty =
            ((si['salesub_qty'] ?? si['sales_ord_sub_qty'] ?? 1) as num)
                .toDouble();
            final double rawRate =
            ((si['salesub_rate'] ??
                si['sales_ord_sub_rate'] ??
                si['rate'] ??
                0.0)
            as num)
                .toDouble();

            final double quantity = (isServerRows && derived)
                ? (rawQty / unitBase).roundToDouble().clamp(1.0, 1e9)
                : rawQty;
            final double price = (isServerRows && derived)
                ? rawRate * unitBase
                : rawRate;

            final double productBaseRate = derived ? price / unitBase : price;
            final addons = addonItems
                .where((a) => identical(ownerOf[a], si))
                .map((a) {
              final addonBaseRate =
              (a['salesub_rate'] ??
                  a['sales_ord_sub_rate'] ??
                  a['rate'] as num? ??
                  0.0)
                  .toDouble();

              final dynamic rawAddonSubId =
                  a['sales_ord_sub_id'] ?? a['salesub_id'];
              final int addonSubId = rawAddonSubId is num
                  ? rawAddonSubId.toInt()
                  : int.tryParse(rawAddonSubId?.toString() ?? '') ?? 0;

              final dynamic rawAddonPrdId =
                  a['salesub_prd_id'] ?? a['sales_ord_sub_prod_id'] ?? a['salesub_prd'];
              final int addonPrdId = rawAddonPrdId is num
                  ? rawAddonPrdId.toInt()
                  : int.tryParse(rawAddonPrdId?.toString() ?? '') ?? 0;

              final dynamic rawTaxCatId =
                  a['prd_tax_cat_id'] ?? a['sales_ord_sub_taxcat_id'];
              final int taxCatId = rawTaxCatId is num
                  ? rawTaxCatId.toInt()
                  : int.tryParse(rawTaxCatId?.toString() ?? '') ?? 0;

              final int addonQty = (a['salesub_qty'] ?? a['sales_ord_sub_qty'] as num? ?? 1).toInt();

              return AddonModel(
                id: addonPrdId,
                subId: addonSubId == 0 ? null : addonSubId,
                prdId: addonPrdId,
                prdaddon_flags: (a['is_addon'] is num)
                    ? (a['is_addon'] as num).toInt()
                    : int.tryParse(a['is_addon']?.toString() ?? '') ?? 1,
                name: a['prd_name']?.toString() ?? '',
                price: addonBaseRate,
                unitDisplay:
                (a['salesub_unit_display'] ??
                    a['prd_unit_name'] ??
                    a['unit_display'] ??
                    '')
                    .toString(),
                unitId: () {
                  final v = a['salesub_unit_id'] ?? a['sales_ord_sub_unit_id'];
                  return v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
                }(),
                initialQty: addonQty,
                freeQty: addonBaseRate == 0 ? addonQty : 0,
                taxPer:
                (a['salesub_tax_per'] ??
                    a['sales_ord_sub_tax_per'] as num? ??
                    0.0)
                    .toDouble(),
                taxCatId: taxCatId,
              );
            })
                .toList();
            localItems.add(
              OrderItem(
                subId: subId == 0 ? null : subId,
                tokenPrinterId: tokenPrinterId,
                isRemoved: isDeleted,
                notes:
                si['item_desc']?.toString() ??
                    si['sales_ord_sub_notes'] ??
                    '',
                product: FoodItemModel(
                  id: prdId,
                  name: si['prd_name']?.toString() ?? 'unknown'.tr,
                  categoryId: (si['prd_cat_id'] ?? '').toString(),
                  price: productBaseRate,
                  prd_tax:
                  (si['salesub_tax_per'] ??
                      si['sales_ord_sub_tax_per'] as num? ??
                      0.0)
                      .toDouble(),
                  image: _fullImageUrl(si['prd_img_url'], imageBaseUrl),
                  unitDisplay:
                  (si['salesub_unit_display'] ??
                      si['prd_unit_name'] ??
                      si['unit_display'] ??
                      '')
                      .toString(),
                  taxPer:
                  (si['salesub_tax_per'] ??
                      si['sales_ord_sub_tax_per'] as num? ??
                      0.0)
                      .toDouble(),
                  taxCatId:
                  (si['prd_tax_cat_id'] ??
                      si['sales_ord_sub_taxcat_id'] as num? ??
                      0)
                      .toInt(),
                  tokenPrinterId:
                  (tokenPrinterId == null || tokenPrinterId == 0)
                      ? null
                      : tokenPrinterId,
                ),
                unit: ProductUnit(
                  unitId: unitId,
                  unitName:
                  (si['salesub_unit_display'] ??
                      si['prd_unit_name'] ??
                      si['unit_display'] ??
                      '')
                      .toString(),
                  unitDisplay:
                  (si['salesub_unit_display'] ??
                      si['prd_unit_name'] ??
                      si['unit_display'] ??
                      '')
                      .toString(),
                  rate: price,
                  unitBaseQty: unitBase,
                  existAddOns: [],
                ),
                selectedAddons: addons,
                quantity: quantity.toInt(),
                priceAtOrder: price,
                cgstRate: cgstRate,
                sgstRate: sgstRate,
              ),
            );
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

    final int? posStatusFromDb =
        (json['sales_odr_pos_status'] as num? ?? payloadPosStatus)?.toInt();
    if (posStatusFromDb == 0) status = OrderStatus.draft;
    if (posStatusFromDb == 2) status = OrderStatus.billed;
    if (posStatusFromDb == 3) status = OrderStatus.paid;
    if (posStatusFromDb == 4) status = OrderStatus.cancelled;

    return OrderModel(
      id: orderId,
      invNo: invNo,
      branchInv: branchInv,
      createdByDeviceId: createdByDeviceId,
      tableId: tableId,
      tableName: tableName,
      customerName: customerName,
      tokenNo: tokenNo,
      chairNumber: chairNumber,
      sales_odr_pos_status: (status == OrderStatus.billed)
          ? 2
          : ((status == OrderStatus.draft)
          ? 0
          : (status == OrderStatus.paid ? 3 : 1)),
      items: localItems,
      status: status,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      orderTime: _parseOrderTime({...json, ...(payloadMap ?? {})}),
      subTotal: subTotal,
      totalAmount: totalAmount,
      totalTax: totalTax,
      totalCgst: totalCgst,
      totalSgst: totalSgst,
      discount: discount,
      captainName: captainName,
      roundOff: roundOff,
      isUnsynced: (json['is_synced'] == 0),
      qrLink: qrLink ?? json['qr_link'] ?? json['zatca_qr'],
      areaId: areaId,
      areaName: areaName,
      priceGroupId: priceGroupId,
      sales_odr_order_type: orderType,
      offlineSeq: offlineSeq,
    );
  }

  void markOrderAsPaidLocally(String orderId) {
    final idx = orders.indexWhere((o) => o.id == orderId || o.invNo == orderId);
    if (idx != -1) {
      orders.removeAt(idx);
      orders.refresh();
    }
  }

  Future<void> _printBill(OrderModel order, VoidCallback onRetry) async {
    try {
      final printerController = Get.find<PrinterController>();
      final printSuccess = await printerController.printReceipt(
        order,
        0,
        0,
        isBill: true,
      );

      if (!printSuccess) {
        // Printer failed! Preserve the pending state and notify user.
        await _showPrintFailureDialog(
          title: "Bill Print Failed",
          message:
              "Printer is unavailable, disconnected, or out of paper. The order remains in pending state until printing succeeds.",
          onRetry: onRetry,
        );
        return;
      }

      if (!order.isUnsynced) {
        final cartController = Get.find<CartController>();
        if (cartController.isEditing &&
            cartController.editingOrderId.value == order.id) {
          final result = await cartController.updateOrder(isBill: true);
          if (result == null) return;
        } else {
          try {
            final body = {
              "usr_id": int.tryParse(AppState.userId) ?? 0,
              "cust_type": "1",
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
                  },
                ],
              },
            };
            final response = await _apiService.post(
              ApiEndpoints.updateSalesOrder,
              data: body,
            );
            if (response.statusCode != 200) {
              throw StateError(
                'Order update returned HTTP ${response.statusCode}',
              );
            }
          } catch (e) {
            debugPrint("printBill: status update failed: $e");
            showSafeSnackbar(
              "Bill status update failed",
              "The bill was sent to the printer, but the server did not confirm "
                  "the order update.",
            );
            return;
          }
        }
      }
      final idx = orders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        orders[idx] = orders[idx].copyWith(
          sales_odr_pos_status: 2,
          status: OrderStatus.billed,
        );
        orders.refresh();
        await _dbHelper.updateOrderStatusByUuid(order.id, 'billed');
      }
    } catch (e) {
      debugPrint("Error in printBill: $e");
    }
  }

  String _resolveName(Map<String, dynamic> data, int type, String fallback) {
    final table = data['sales_odr_table_name']?.toString();
    final ledger = data['ledger_name']?.toString();
    final customer =
        data['sq_cust_name']?.toString() ??
            data['customer_name']?.toString() ??
            data['cust_name']?.toString();
    final tableNameField = data['table_name']?.toString();

    final List<String> dummyNames = [
      'pickup_tab'.tr,
      'delivery'.tr,
      "Pickup Table",
      "Delivery Table",
      "Pickup",
      "Delivery",
    ];

    if (type == 0) {
      if (table != null && table.isNotEmpty) return table;
      if (tableNameField != null && tableNameField.isNotEmpty)
        return tableNameField;
      if (ledger != null && ledger.isNotEmpty) return ledger;
      if (customer != null && customer.isNotEmpty) return customer;
    } else {
      if (ledger != null && ledger.isNotEmpty && !dummyNames.contains(ledger))
        return ledger;
      if (customer != null &&
          customer.isNotEmpty &&
          !dummyNames.contains(customer))
        return customer;

      if (fallback.isNotEmpty && !dummyNames.contains(fallback))
        return fallback;

      if (table != null && table.isNotEmpty) return table;
      if (tableNameField != null && tableNameField.isNotEmpty)
        return tableNameField;
    }
    return (fallback.isNotEmpty) ? fallback : 'cash_customer'.tr;
  }

  bool _isRealInvNo(String invNo) =>
      invNo.isNotEmpty &&
          invNo != "LOCAL" &&
          invNo != "OFFLINE" &&
          invNo != "0";

  void updateExistingOrder(OrderModel updatedOrder) {
    _rememberItems(updatedOrder);
    final activeIndex = orders.indexWhere(
          (o) =>
      o.id == updatedOrder.id ||
          (_isRealInvNo(o.invNo) &&
              _isRealInvNo(updatedOrder.invNo) &&
              o.invNo == updatedOrder.invNo),
    );

    if (activeIndex != -1) {
      final existingOrder = orders[activeIndex];

      if (updatedOrder.status.value == OrderStatus.paid ||
          updatedOrder.status.value == OrderStatus.cancelled) {
        orders.removeAt(activeIndex);
        orders.refresh();

        if (updatedOrder.status.value == OrderStatus.paid) {
          updateExistingOrderInList(soldOrders, updatedOrder);
        }
        return;
      }

      orders[activeIndex] = existingOrder.copyWith(
        tableName: updatedOrder.tableName,
        customerName: updatedOrder.customerName,
        tokenNo: updatedOrder.tokenNo,
        subTotal: updatedOrder.subTotal,
        totalAmount: updatedOrder.totalAmount,
        totalTax: updatedOrder.totalTax,
        totalCgst: updatedOrder.totalCgst,
        totalSgst: updatedOrder.totalSgst,
        discount: updatedOrder.discount,
        roundOff: updatedOrder.roundOff,
        sales_odr_order_type: updatedOrder.sales_odr_order_type,
        sales_odr_pos_status: updatedOrder.sales_odr_pos_status,
        isUnsynced: updatedOrder.isUnsynced,
        items: updatedOrder.items.isNotEmpty
            ? updatedOrder.items
            : existingOrder.items,
        status: updatedOrder.status.value,
        qrLink: updatedOrder.qrLink,
        offlineSeq: updatedOrder.offlineSeq,
        branchInv: updatedOrder.branchInv!.isNotEmpty
            ? updatedOrder.branchInv
            : existingOrder.branchInv,
      );

      orders.refresh();
      return;
    }

    updateExistingOrderInList(soldOrders, updatedOrder);

    if (activeIndex == -1 &&
        updatedOrder.status.value != OrderStatus.paid &&
        updatedOrder.status.value != OrderStatus.cancelled) {
      orders.insert(0, updatedOrder);
    }
  }

  void updateExistingOrderInList(RxList<OrderModel> list,
      OrderModel updatedOrder,) {
    _rememberItems(updatedOrder);
    final index = list.indexWhere(
          (o) =>
      o.id == updatedOrder.id ||
          (_isRealInvNo(o.invNo) &&
              _isRealInvNo(updatedOrder.invNo) &&
              o.invNo == updatedOrder.invNo),
    );

    if (index != -1) {
      final existingOrder = list[index];
      list[index] = existingOrder.copyWith(
        tableName: updatedOrder.tableName,
        customerName: updatedOrder.customerName,
        tokenNo: updatedOrder.tokenNo,
        subTotal: updatedOrder.subTotal,
        totalAmount: updatedOrder.totalAmount,
        totalTax: updatedOrder.totalTax,
        totalCgst: updatedOrder.totalCgst,
        totalSgst: updatedOrder.totalSgst,
        discount: updatedOrder.discount,
        roundOff: updatedOrder.roundOff,
        sales_odr_order_type: updatedOrder.sales_odr_order_type,
        sales_odr_pos_status: updatedOrder.sales_odr_pos_status,
        isUnsynced: updatedOrder.isUnsynced,
        items: updatedOrder.items.isNotEmpty
            ? updatedOrder.items
            : existingOrder.items,
        status: updatedOrder.status.value,
        qrLink: updatedOrder.qrLink,
        offlineSeq: updatedOrder.offlineSeq,
        branchInv: updatedOrder.branchInv!.isNotEmpty
            ? updatedOrder.branchInv
            : existingOrder.branchInv,
      );
      list.refresh();
    } else if (updatedOrder.status.value == OrderStatus.paid) {
      list.insert(0, updatedOrder);
      list.refresh();
    }
  }

  Future<void> syncOrders() async {
    final syncService = Get.find<SyncService>();
    await syncService.syncPendingOrders();
    await fetchOrders();
  }

  Future<void> fetchOrderDetails(OrderModel order) async {
    detailsFailedIds.remove(order.id);
    loadingOrderDetailsIds.add(order.id);
    if (order.invNo.isNotEmpty) loadingOrderDetailsIds.add(order.invNo);

    try {
      if (order.isUnsynced) {
        await _loadOrderDetailsFromLocal(order);
        return;
      }

      bool loadedRemotely = false;

      // 1. Try Local Hub Client if in local hub mode (client)
      if (DeviceConfig.operationMode == OperationMode.local &&
          DeviceConfig.role == DeviceRole.client) {
        final hostIp = DeviceConfig.hostIp;
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          try {
            final hubResult = await LocalHubClient.instance.fetchOrderDetails(
              hostIp: hostIp,
              port: DeviceConfig.hostPort,
              orderId: order.id,
            );
            if (hubResult['success'] == true) {
              final data = hubResult['data'];
              updateExistingOrder(
                _mapJsonToOrderModel(Map<String, dynamic>.from(data)),
              );
              loadedRemotely = true;
            }
          } catch (e) {
            debugPrint("fetchOrderDetails: Local Hub fetch failed (client): $e");
          }
        }
      }

      // 2. Fallback: Try Online API (even in local mode for online orders)
      if (!loadedRemotely) {
        try {
          final bool isPaid = order.status.value == OrderStatus.paid;
          final String endpoint = isPaid
              ? ApiEndpoints.getSoldOrderDetails
              : ApiEndpoints.getOrderDetails;

          final Map<String, dynamic> requestData = {
            "usr_id": int.tryParse(AppState.userId) ?? 18,
            "sales_odr_inv_no": int.tryParse(order.invNo) ?? 0,
            "cmp_tax": AppState.cmpTaxType,
          };

          if (isPaid) {
            requestData["is_reprint"] = 1;
          }

          final response = await _apiService.post(endpoint, data: requestData);

          if (response.statusCode == 200) {
            final data = response.data['data'];
            if (data != null) {
              final preview = isPaid ? data['preview'] : data;
              if (preview != null) {
                final double authoritativeTotal =
                    (preview['tot_amount'] ??
                            preview['sales_odr_total'] ??
                            preview['total_amount'] as num? ??
                            0.0)
                        .toDouble();
                final double authoritativeTax =
                    (preview['tot_tax'] ??
                            preview['sales_odr_tax'] ??
                            preview['total_tax'] as num? ??
                            0.0)
                        .toDouble();

                final updated = await _dbHelper.updateOrderStatusByUuid(
                  order.id,
                  order.status.value.name,
                  payload: jsonEncode(preview),
                  isSynced: 1,
                  refreshingCache: true,
                  invNo: order.invNo,
                  branchInv: _firstNonEmptyValue([
                    preview['sales_odr_sales_branch_inv'],
                    preview['sales_odr_branch_inv'],
                    preview['sales_branch_inv'],
                  ]),
                  serverId: order.id,
                  total: authoritativeTotal,
                  tax: authoritativeTax,
                );

                if (updated == 0 && !isPaid) {
                  await _dbHelper.cacheServerOrders([preview]);
                }
                loadedRemotely = true;
              }
            }
          }
        } catch (e) {
          debugPrint("fetchOrderDetails: Online API fetch fallback failed: $e");
        }
      }

      // 3. Load from local DB (which now has the full payload with items)
      await _loadOrderDetailsFromLocal(order);
    } catch (e) {
      debugPrint("Error in fetchOrderDetails: $e");
      await _loadOrderDetailsFromLocal(order);
    } finally {
      if (resolveOrder(order).items.isEmpty) detailsFailedIds.add(order.id);
      loadingOrderDetailsIds.remove(order.id);
      if (order.invNo.isNotEmpty) loadingOrderDetailsIds.remove(order.invNo);
    }
  }
  //   } catch (e) {
  //     debugPrint("Error fetching order details: $e");
  //     await _loadOrderDetailsFromLocal(order);
  //   } finally {
  //     loadingOrderDetailsIds.remove(order.id);
  //     if (order.invNo.isNotEmpty) loadingOrderDetailsIds.remove(order.invNo);
  //   }
  // }

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
        _rememberItems(mappedOrder);
        final activeIndex = orders.indexWhere((o) => _sameOrder(o, order));
        if (activeIndex != -1) {
          orders[activeIndex] = mappedOrder;
          orders.refresh();
        } else {
          final soldIndex = soldOrders.indexWhere((o) => _sameOrder(o, order));
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

  OrderModel parseOrderResponse(
      Map<String, dynamic> responseJson, {
        String fallbackTableName = "",
        int fallbackChairCount = 0,
      }) {
    final bool isOffline = responseJson['offline'] == true;
    final preview = (responseJson['preview'] is Map)
        ? responseJson['preview']
        : responseJson;
    final seenSubIds = <String>{};
    final List<dynamic> subItemsJson = (() {
      final list = (preview['sales_order_sub'] as List? ?? []).where((s) {
        final id = (s['sales_ord_sub_id'] ?? '').toString();
        if (id.isEmpty || id == '0' || id == 'null') return true;
        return seenSubIds.add(id);
      }).toList();
      if (!isOffline) {
        int sid(dynamic r) => (r['sales_ord_sub_id'] as num?)?.toInt() ?? 0;
        if (list.every((r) => sid(r) > 0)) {
          list.sort((a, b) => sid(a).compareTo(sid(b)));
        }
      }
      return list;
    })();

    final String imageBaseUrl =
        responseJson['image_url']?.toString() ??
            preview['image_url']?.toString() ??
            "";

    final cartController = Get.find<CartController>();
    List<OrderItem> items = [];

    final mainItemsJson = subItemsJson.where((i) => !_isAddonRow(i)).toList();
    final addonItemsJson = subItemsJson.where((i) => _isAddonRow(i)).toList();
    int _toInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

    String _mainPrdId(dynamic m) =>
        (m['sales_ord_sub_prod_id'] ?? m['salesub_prd_id'] ?? m['salesub_prd'] ?? 0)
            .toString();
    int _mainUnitId(dynamic m) =>
        _toInt(m['sales_ord_sub_unit_id'] ?? m['salesub_unit_id']);
    int _flagOf(dynamic r) => _toInt(r['sales_ord_sub_flags'] ?? 1);

    final ownerOf = _resolveAddonOwners(subItemsJson);

    for (var sub in mainItemsJson) {
      final String prdId = _mainPrdId(sub);
      final int unitId = _mainUnitId(sub);

      String unitDisplay =
          sub['salesub_unit_display']?.toString() ??
              sub['unit_display']?.toString() ??
              '';
      double rawQty =
      (sub['sales_ord_sub_qty'] as num? ?? sub['salesub_qty'] as num? ?? 1)
          .toDouble();
      double rawRate =
      (sub['sales_ord_sub_rate'] as num? ??
          sub['salesub_rate'] as num? ??
          sub['rate'] as num? ??
          0.0)
          .toDouble();
      double baseQty = (sub['unit_base_qty'] as num? ?? 1.0).toDouble();
      double cgstRate =
      (sub['sales_ord_sub_cgst_rate'] as num? ?? 0.0).toDouble();
      double sgstRate =
      (sub['sales_ord_sub_sgst_rate'] as num? ?? 0.0).toDouble();

      int displayQty;
      double displayRate = rawRate;

      if (!isOffline && baseQty > 1.0) {
        displayQty = (rawQty / baseQty).round();
        if (displayQty < 1 && rawQty > 0) displayQty = 1;
        displayRate = rawRate * baseQty;
      } else {
        displayQty = rawQty.toInt();
      }

      final cartItem = cartController.cartItems.firstWhereOrNull(
            (item) =>
        item.product.id == prdId &&
            item.unit.unitId == unitId &&
            !item.isDeleted.value,
      );

      final int flag = _flagOf(sub);
      final bool isRemoved = flag == 0;
      int? tokenPrinterId = (sub['cat_token_printer'] as num?)?.toInt();
      if (tokenPrinterId == null || tokenPrinterId == 0) {
        final ci = cartController.cartItems.firstWhereOrNull(
              (ci) => ci.product.id == prdId,
        );
        tokenPrinterId = ci?.product.tokenPrinterId;
      }
      final String prdImgUrl = sub['prd_img_url']?.toString() ?? "";
      String fullImgPath = prdImgUrl;
      if (prdImgUrl.isNotEmpty &&
          imageBaseUrl.isNotEmpty &&
          !prdImgUrl.startsWith('http')) {
        fullImgPath = imageBaseUrl + prdImgUrl;
      }

      // Only the addon rows that belong to THIS parent row
      final List<dynamic> matchingAddonsForSub = addonItemsJson
          .where((a) => identical(ownerOf[a], sub))
          .toList();

      final List<AddonModel> rawSelectedAddons = matchingAddonsForSub.map((
          addonJson,
          ) {
        final int addonSubId = _toInt(
          addonJson['sales_ord_sub_id'] ?? addonJson['salesub_id'],
        );
        final int addonPrdId = _toInt(
          addonJson['sales_ord_sub_prod_id'] ??
              addonJson['salesub_prd_id'] ??
              addonJson['salesub_prd'],
        );
        final int addonUnitId = _toInt(
          addonJson['sales_ord_sub_unit_id'] ?? addonJson['salesub_unit_id'],
        );
        final int addonQty = _toInt(
          addonJson['sales_ord_sub_qty'] ?? addonJson['salesub_qty'] ?? 1,
        );
        final double addonRate =
        (addonJson['sales_ord_sub_rate'] ??
            addonJson['salesub_rate'] ??
            addonJson['rate'] ??
            0.0 as num)
            .toDouble();

        return AddonModel(
          id: (addonSubId > 0) ? addonSubId : addonPrdId,
          subId: addonSubId == 0 ? null : addonSubId,
          prdId: addonPrdId,
          prdaddon_flags: 1,
          name: addonJson['prd_name']?.toString() ?? '',
          price: addonRate,
          unitDisplay:
          (addonJson['unit_display'] ??
              addonJson['salesub_unit_display'] ??
              addonJson['prd_unit_name'] ??
              '')
              .toString(),
          unitId: addonUnitId,
          initialQty: addonQty,
          freeQty: addonRate == 0 ? addonQty : 0,
          taxPer:
          (addonJson['sales_ord_sub_tax_per'] ??
              addonJson['salesub_tax_per'] as num? ??
              0.0)
              .toDouble(),
          taxCatId: _toInt(
            addonJson['sales_ord_sub_taxcat_id'] ??
                addonJson['prd_tax_cat_id'],
          ),
        );
      }).toList();

      // Preserve the saved prices and row IDs for receipts and order edits.

      items.add(
        OrderItem(
          subId: (sub['sales_ord_sub_id'] as num? ?? 0).toInt(),
          quantity: displayQty,
          priceAtOrder: displayRate,
          tokenPrinterId: tokenPrinterId,
          selectedAddons: rawSelectedAddons,
          isRemoved: isRemoved,
          cgstRate: cgstRate,
          sgstRate: sgstRate,
          notes:
          sub['item_desc']?.toString() ?? sub['sales_ord_sub_notes'] ?? '',
          product: FoodItemModel(
            id: prdId,
            name:
            sub['prd_name']?.toString() ??
                cartItem?.product.name ??
                'unknown'.tr,
            categoryId:
            (sub['prd_cat_id'] ?? cartItem?.product.categoryId ?? '')
                .toString(),
            price: (baseQty > 1.0)
                ? (isOffline ? rawRate / baseQty : rawRate)
                : rawRate,
            prd_tax:
            (sub['sales_ord_sub_tax_per'] as num?)?.toDouble() ??
                cartItem?.product.prd_tax ??
                0.0,
            image: fullImgPath.isNotEmpty
                ? fullImgPath
                : (cartItem?.product.image ?? ''),
            unitDisplay: unitDisplay,
            taxPer:
            (sub['sales_ord_sub_tax_per'] as num? ??
                cartItem?.product.taxPer ??
                0.0)
                .toDouble(),
            taxCatId:
            (sub['sales_ord_sub_taxcat_id'] as num? ??
                cartController.cartItems
                    .firstWhereOrNull((i) => i.product.id == prdId)
                    ?.product
                    .taxCatId ??
                0)
                .toInt(),
            tokenPrinterId: tokenPrinterId ?? cartItem?.product.tokenPrinterId,
          ),
          unit:
          cartItem?.unit ??
              ProductUnit(
                unitId: unitId,
                unitName: unitDisplay,
                unitDisplay: unitDisplay,
                rate: displayRate,
                unitBaseQty: cartItem?.unit.unitBaseQty ?? 1.0,
                existAddOns: [],
              ),
        ),
      );
    }

    final settlementDate = preview['sq_date']?.toString().trim();
    final settlementTime = preview['sq_time']?.toString().trim();
    final settlementTimestamp = settlementDate != null && settlementTime != null
        ? DateTime.tryParse('${settlementDate}T$settlementTime')
        : null;

    final String dateStr =
        preview['sq_date']?.toString() ??
            preview['sales_odr_date']?.toString() ??
            '';
    final String timeStr =
        preview['sq_time']?.toString() ??
            preview['sales_odr_time']?.toString() ??
            '';
    DateTime createdAt = DateTime.now();
    try {
      if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
        createdAt = DateTime.parse("${dateStr}T$timeStr");
      }
    } catch (_) {}

    final String orderId = (preview['sales_odr_id'] ?? '').toString();
    final String invNo =
    (preview['sales_odr_inv_no'] ?? preview['sq_inv_no'] ?? '').toString();
    final String branchInv = _firstNonEmptyValue([
      preview['sales_odr_sales_branch_inv'],
      preview['sales_odr_branch_inv'],
      preview['sales_branch_inv'],
    ]);
    final String? createdByDeviceId = preview['created_by_device_id']
        ?.toString();
    final String localUuid = (preview['local_uuid'] ?? '').toString();

    final int orderType = (preview['sales_odr_order_type'] as num? ?? 0)
        .toInt();
    final int posStatus =
    (preview['sales_odr_pos_status'] as num? ??
        preview['res_status'] as num? ??
        responseJson['res_status'] as num? ??
        0)
        .toInt();
    final String cartTableFallback = fallbackTableName.isNotEmpty
        ? fallbackTableName
        : cartController.selectedTableName.value;
    final String tableName = _resolveName(
      preview,
      orderType,
      cartTableFallback,
    );
    final String? customerName =
    (preview['sq_cust_name'] ??
        preview['customer_name'] ??
        preview['cust_name'] ??
        '')
        ?.toString();
    final String? captainName = (preview['agent_name'] ?? preview['usr_name'])
        ?.toString();
    final String? tokenNo =
    (preview['sales_odr_token_no'] ?? preview['sales_odr_token'])
        ?.toString();

    final int cartChairFallback = fallbackChairCount > 0
        ? fallbackChairCount
        : cartController.selectedChairCount.value;
    final int chairNumber =
    (preview['sales_odr_no_seats'] as num? ??
        preview['no_seats'] as num? ??
        preview['res_table']?['rt_seat_count'] as num? ??
        cartChairFallback)
        .toInt();

    final int? areaIdFromPreview =
    (preview['rt_area_id'] ?? preview['res_table']?['rt_area_id'] as num?)
        ?.toInt();
    final String? areaNameFromPreview =
        preview['rt_area_name']?.toString() ?? preview['area_name']?.toString();
    int resolvedAreaId =
        areaIdFromPreview ?? cartController.selectedAreaId.value;
    String resolvedAreaName = areaNameFromPreview ?? '';
    final String tableIdFromPreview =
    (preview['sales_odr_table_id'] ?? preview['res_table']?['rt_id'] ?? '')
        .toString();

    if ((resolvedAreaName.isEmpty || resolvedAreaId == 0) &&
        Get.isRegistered<TablesController>()) {
      final tablesCtrl = Get.find<TablesController>();
      AreaModel? area;
      if (resolvedAreaId > 0) {
        area = tablesCtrl.areas.firstWhereOrNull((a) => a.id == resolvedAreaId);
      }
      if (area == null && tableIdFromPreview.isNotEmpty) {
        final tId = int.tryParse(tableIdFromPreview) ?? 0;
        if (tId > 0) {
          area = tablesCtrl.areas.firstWhereOrNull(
                (a) => a.tables.any((t) => t.id == tId),
          );
        }
      }
      if (area != null) {
        resolvedAreaName = area.name;
        resolvedAreaId = area.id;
      }
    }
    if (resolvedAreaName.isEmpty) {
      resolvedAreaName = cartController.selectedAreaName.value;
    }

    return OrderModel(
      id: orderId.isEmpty ? localUuid : orderId,
      invNo: invNo.isEmpty ? "OFFLINE" : invNo,
      branchInv: branchInv,
      createdByDeviceId: createdByDeviceId,
      tableId:
      (preview['sales_odr_table_id'] ??
          cartController.selectedTableId.value)
          .toString(),
      tableName: tableName,
      customerName: customerName,
      tokenNo: tokenNo,
      chairNumber: chairNumber,
      sales_odr_pos_status: posStatus,
      items: items,
      status: posStatus == 2
          ? OrderStatus.billed
          : posStatus == 3
          ? OrderStatus.paid
          : posStatus == 0
          ? OrderStatus.draft
          : OrderStatus.pending,
      createdAt: createdAt,
      subTotal:
      (preview['tot_rate'] as num? ??
          preview['sub_total'] as num? ??
          preview['tot_subtotal'] as num? ??
          preview['sales_odr_subtotal'] as num? ??
          0.0)
          .toDouble(),
      totalAmount:
      (preview['tot_amount'] ??
          preview['sales_odr_total'] ??
          preview['total_amount'] ??
          preview['sq_total'] as num? ??
          0.0)
          .toDouble(),
      totalTax:
      (preview['tot_tax'] ??
          preview['sales_odr_tax'] ??
          preview['total_tax'] as num? ??
          0.0)
          .toDouble(),
      totalCgst: (preview['tot_cgst_tax'] as num? ?? 0.0).toDouble(),
      totalSgst: (preview['tot_sgst_tax'] as num? ?? 0.0).toDouble(),
      discount: (preview['tot_disc'] ?? preview['discount'] ?? 0.0).toDouble(),
      roundOff: (preview['sales_odr_roundoff'] ?? 0.0).toDouble(),
      qrLink:
      (preview['qr_link'] ??
          preview['zatca_qr'] ??
          responseJson['qr_link'] ??
          responseJson['zatca_qr'])
          ?.toString(),
      branchTin: preview['branch_tin']?.toString(),
      branchName: preview['branch_name']?.toString(),
      branchPhone: preview['branch_phone']?.toString(),
      branchMob: preview['branch_mob']?.toString(),
      branchAddress: preview['branch_address']?.toString(),
      Taxpercentage:
      ((preview['gst'] is List && (preview['gst'] as List).isNotEmpty)
          ? (preview['gst'][0]['Taxpercentage'] as num? ?? 0.0)
          : 0.0)
          .toDouble(),
      captainName: captainName,
      orderTime: settlementTimestamp ??
          _parseOrderTime(preview.isNotEmpty ? preview : responseJson),
      areaId: resolvedAreaId,
      areaName: resolvedAreaName,
      priceGroupId:
      (preview['prcgrp_id'] as num? ??
          cartController.selectedPriceGroupId.value)
          .toInt(),
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
        showSafeSnackbar('error'.tr, 'load_items_error'.tr);
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
        showSafeSnackbar('error'.tr, 'load_items_error'.tr);
      }
    } catch (e) {
      debugPrint("Error going to cashier: $e");
    } finally {
      isLoading.value = false;
    }
  }

  final _cancellingOrders = <String>{};
  final _cancelledOrderKeys = <String>{};

  bool _wasCancelled(String id, String invNo) =>
      _cancelledOrderKeys.contains('id:$id') ||
      (_isRealInvNo(invNo) && _cancelledOrderKeys.contains('inv:$invNo'));

  bool _isVisibleOrder(OrderModel order) =>
      order.status.value != OrderStatus.cancelled &&
      !_wasCancelled(order.id, order.invNo);

  bool _isVisibleServerOrder(dynamic row) =>
      (row['sales_odr_pos_status'] ?? row['res_status']).toString() != '4' &&
      !_wasCancelled(
        (row['sales_odr_id'] ?? '').toString(),
        (row['sales_odr_inv_no'] ?? '').toString(),
      );

  void _removeCancelledOrder(OrderModel order, {bool matchInvoice = false}) {
    if (order.id.isNotEmpty) _cancelledOrderKeys.add('id:${order.id}');
    if (matchInvoice) _cancelledOrderKeys.add(_orderKey(order));
    orders.removeWhere((o) => !_isVisibleOrder(o));
    soldOrders.removeWhere((o) => !_isVisibleOrder(o));
  }

  Future<bool> _printCancellation(
    OrderModel order, {
    bool checkConnections = false,
  }) async {
    try {
      return order.items.isNotEmpty &&
          await Get.find<PrinterController>().printCancelledOrder(
            order,
            checkConnections: checkConnections,
          );
    } catch (e) {
      debugPrint("Cancellation print error: $e");
      return false;
    }
  }

  Future<void> cancelOrder(OrderModel order) async {
    final key = _orderKey(order);
    if (!_isVisibleOrder(order) || !_cancellingOrders.add(key)) return;
    try {
      bool? confirm = await Get.dialog<bool>(
        AlertDialog(
          title: Text('cancel_confirm_title'.tr),
          content: Text(
            'cancel_confirm_msg'.trParams({'order': order.isUnsynced ? "(Offline)" : "#${order.branchInv}"}),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('no'.tr),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: Text('yes'.tr, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final requiresPrinting = DeviceConfig.requireOrderPrinting;
      if (order.isUnsynced &&
          (DeviceConfig.isLocal || !_isRealInvNo(order.invNo))) {
        if (order.items.isEmpty) {
          await _loadOrderDetailsFromLocal(order);
        }
        final updatedOrder = (orders + soldOrders).firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );

        final shouldPrint = updatedOrder.status.value != OrderStatus.draft;
        if (requiresPrinting && shouldPrint &&
            !await _printCancellation(updatedOrder)) {
          showSafeSnackbar(
            'Printing required',
            'The order was not cancelled. Check the printer and try again.',
          );
          return;
        }

        await _dbHelper.deleteOrder(order.id);
        _removeCancelledOrder(order);
        showSafeSnackbar('success'.tr, 'offline_cancel_success'.tr);
        if (!requiresPrinting && shouldPrint) {
          unawaited(_printCancellation(updatedOrder));
        }
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
      final online = DeviceConfig.isOnline;
      if (requiresPrinting && originalStatus != OrderStatus.draft &&
          !await _printCancellation(updatedOrder, checkConnections: online)) {
        showSafeSnackbar(
          'Printing required',
          'The order was not cancelled. Check the printer and try again.',
        );
        return;
      }
      final cartController = Get.find<CartController>();
      final success = await cartController.cancelOrder(order.invNo);

      if (success) {
        _removeCancelledOrder(order, matchInvoice: true);
        await _dbHelper.deleteOrder(order.id, invNo: order.invNo);
        showSafeSnackbar(
          'success'.tr,
          'order_cancel_success'.trParams({'inv': order.invNo}),
        );

        if ((!requiresPrinting || online) &&
            originalStatus != OrderStatus.draft) {
          unawaited(_printCancellation(updatedOrder));
        }
      } else {
        showSafeSnackbar('error'.tr, 'order_cancel_error'.tr);
      }
    } catch (e) {
      debugPrint("Error cancelling order: $e");
      showSafeSnackbar('error'.tr, 'order_cancel_error'.tr);
    } finally {
      _cancellingOrders.remove(key);
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

  List<OrderModel> get pendingOrders => orders
      .where(
        (o) =>
            (o.status.value == OrderStatus.pending ||
                o.status.value == OrderStatus.preparing ||
                o.status.value == OrderStatus.ready ||
                o.status.value == OrderStatus.served ||
                o.status.value == OrderStatus.draft ||
                o.status.value == OrderStatus.billed) &&
            o.status.value != OrderStatus.paid &&
            o.status.value != OrderStatus.cancelled,
      )
      .toList();

  List<OrderModel> get dineInOrders =>
      pendingOrders.where((o) => o.sales_odr_order_type == 0).toList();
  List<OrderModel> get deliveryOrders =>
      pendingOrders.where((o) => o.sales_odr_order_type == 1).toList();
  List<OrderModel> get pickupOrders =>
      pendingOrders.where((o) => o.sales_odr_order_type == 2).toList();

  List<OrderModel> get paidOrders {
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedSoldDate.value);
    return soldOrders
        .where((o) => DateFormat('yyyy-MM-dd').format(o.createdAt) == dateStr)
        .toList();
  }

  List<OrderModel> get completedOrders => paidOrders;

  void changeSoldDate(DateTime date) {
    selectedSoldDate.value = date;
    _fetchSoldOrders();
  }

  Future<void> handlePrint(OrderModel ref, {bool isBill = false}) async {
    if (printingOrderIds.contains(ref.id)) return;

    var order = resolveOrder(ref);
    if (order.items.isEmpty) {
      await fetchOrderDetails(order);
      order = resolveOrder(order);
      if (order.items.isEmpty) {
        showSafeSnackbar('error'.tr, 'load_items_error'.tr);
        return;
      }
    }

    final printKeys = {order.id, if (_isRealInvNo(order.invNo)) order.invNo};
    if (printKeys.any(printingOrderIds.contains)) return;
    printingOrderIds.addAll(printKeys);

    var retryRequested = false;
    void requestRetry() {
      retryRequested = true;
    }
    try {
      final p = Get.find<PrinterController>();
      if (order.status.value == OrderStatus.paid) {
        final ok = await p.printReceipt(
          order,
          order.totalAmount,
          0,
          roundOff: order.roundOff,
          discount: order.discount,
        );
        if (!ok) {
          await _showPrintFailureDialog(
            title: "Receipt Print Failed",
            message:
                "Printer is unavailable, disconnected, or out of paper. Please check the printer and retry.",
            onRetry: requestRetry,
          );
        }
      } else if (isBill) {
        if (order.status.value != OrderStatus.billed) {
          await _printBill(order, requestRetry);
        } else {
          final ok = await p.printReceipt(order, 0, 0, isBill: true);
          if (!ok) {
            await _showPrintFailureDialog(
              title: "Bill Print Failed",
              message:
                  "Printer is unavailable, disconnected, or out of paper. Please check the printer and retry.",
              onRetry: requestRetry,
            );
          }
        }
      } else {
        final ok = await p.printKOT(order);
        if (!ok) {
          await _showPrintFailureDialog(
            title: "KOT Print Failed",
            message:
                "Printer is unavailable, disconnected, or out of paper. Please check the printer and retry.",
            onRetry: requestRetry,
          );
        }
      }
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      printingOrderIds.removeAll(printKeys);
    }
    if (retryRequested) await handlePrint(ref, isBill: isBill);
  }

  Future<void> _showPrintFailureDialog({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) async {
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    await showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.print_disabled, color: Colors.red, size: 36),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              onRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

}