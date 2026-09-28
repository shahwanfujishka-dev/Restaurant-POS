import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:restaurant_pos/app/modules/home/controller/dashboard_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/home_controller.dart';
import 'package:restaurant_pos/app/modules/cart/controller/cart_controller.dart';
import 'package:restaurant_pos/app/widgets/reusable_button.dart';
import '../../../../helper/snackbar_helper.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/utils/AppState.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

enum TableStatus { vacant, partiallyOccupied, fullyOccupied }

class AreaModel {
  final int id;
  final String name;
  final int isDefault;
  final int priceGroupID;
  final List<TableModel> tables;

  AreaModel({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.priceGroupID,
    required this.tables,
  });

  factory AreaModel.fromJson(Map<String, dynamic> json) {
    return AreaModel(
      id: (json['ra_id'] as num? ?? 0).toInt(),
      name: json['ra_name']?.toString() ?? '',
      isDefault: (json['ra_is_default'] as num? ?? 0).toInt(),
      priceGroupID: (json['ra_prcgrp_id'] as num? ?? 0).toInt(),
      tables: (json['pos_tables'] as List? ?? [])
          .map((t) => TableModel.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TableModel {
  final int id;
  final String name;
  final int chairCount;
  final List<dynamic> processingTable;

  TableModel({
    required this.id,
    required this.name,
    required this.chairCount,
    required this.processingTable,
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    return TableModel(
      id: (json['rt_id'] as num? ?? (json['id'] as num? ?? 0)).toInt(),
      name: (json['rt_name'] ?? (json['name'] ?? '')).toString(),
      chairCount: (json['rt_seat_count'] as num? ?? (json['chair_count'] as num? ?? 0)).toInt(),
      processingTable: json['processing_table'] is String
          ? jsonDecode(json['processing_table'])
          : (json['processing_table'] is List ? json['processing_table'] : []),
    );
  }

  TableStatus getStatus(int occupiedCount) {
    if (occupiedCount == 0) return TableStatus.vacant;
    if (occupiedCount < chairCount) return TableStatus.partiallyOccupied;
    return TableStatus.fullyOccupied;
  }
}

class TablesController extends GetxController with WidgetsBindingObserver {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ApiService _apiService = Get.find<ApiService>();

  final areas = <AreaModel>[].obs;
  final selectedArea = Rxn<AreaModel>();
  final isLoading = false.obs;

  final selectedChairCount = 0.obs;

  // Track occupancy from local, unsynced orders
  final localOrdersOccupancy = <int, int>{}.obs;
  // Track which orders have a pending local update to avoid double counting with Hub/Cloud data
  final pendingUpdateIds = <String>{}.obs;

  Timer? _pollingTimer;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    fetchTables();
    _startPolling();
  }

  @override
  void onClose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchTables(silent: true);
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Fast polling in local mode to ensure multi-device sync
    final duration = DeviceConfig.operationMode == OperationMode.local ? const Duration(seconds: 5) : const Duration(seconds: 20);
    _pollingTimer = Timer.periodic(duration, (_) {
      fetchTables(silent: true);
    });
  }

  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // Dual-Load Strategy: Load from DB first (instant), then API for fresh status
  Future<void> fetchTables({bool silent = false}) async {
    try {
      if (!silent) {
        await _updateLocalOccupancy();
        await _loadFromLocalDB();
        if (areas.isEmpty) isLoading.value = true;
      }

      List<dynamic> dataList = [];

      if (DeviceConfig.operationMode == OperationMode.local && DeviceConfig.role == DeviceRole.client) {
        // LOCAL HUB MODE (Client)
        final hostIp = DeviceConfig.hostIp;
        if (hostIp != null && hostIp.isNotEmpty && DeviceConfig.hasAuthToken) {
          try {
            final hubResult = await LocalHubClient.instance.fetchMasterTables(
              hostIp: hostIp,
              port: DeviceConfig.hostPort,
            );
            if (hubResult['success'] == true) {
              dataList = hubResult['data'] ?? [];
            }
          } catch (e) {
            debugPrint("fetchTables: Local Hub failed: $e");
          }
        }
      } else {
        // CLOUD MODE (or Local Hub Host)
        final Map<String, dynamic> requestBody = {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
        };
        try {
          final response = await _apiService.post('mobileapp/pos/get_pos_table', data: requestBody);
          if (response.statusCode == 200) {
            if (response.data is Map && response.data['data'] is List) {
              dataList = response.data['data'];
            } else if (response.data is List) {
              dataList = response.data;
            }
          }
        } catch (e) {
          debugPrint("fetchTables: Cloud API failed, using local cache: $e");
          return;
        }
      }

      if (dataList.isNotEmpty) {
        // Update Cache
        await _dbHelper.insertAreas(dataList.cast<Map<String, dynamic>>());
        await _updateLocalOccupancy();
        await _loadFromLocalDB();
      }
    } catch (e) {
      debugPrint('Error fetching tables: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _updateLocalOccupancy() async {
    try {
      final unsynced = await _dbHelper.getUnsyncedOrders();
      final Map<int, int> occupancy = {};
      final Set<String> skipIds = {};
      final cartController = Get.find<CartController>();

      for (var order in unsynced) {
        final status = order['status']?.toString().toLowerCase();
        if (status == 'paid' || status == 'cancelled' || status == 'deleted') continue;

        final tableId = (order['table_id'] as num?)?.toInt();
        if (tableId == null) continue;
        if (cartController.isEditing && order['uuid'] == cartController.editingOrderId.value) {
          continue;
        }
        
        // Mark both UUID and server_id to avoid double counting with Host data
        final uuid = order['uuid']?.toString();
        if (uuid != null) skipIds.add(uuid);
        
        final serverId = order['server_id']?.toString();
        if (serverId != null && serverId.isNotEmpty) {
          skipIds.add(serverId);
        }

        int seats = 0;
        final payloadStr = order['payload'] as String?;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final payload = jsonDecode(payloadStr);
            seats = _safeInt(payload['no_seats'] ?? payload['sales_odr_no_seats']);
          } catch (e) {}
        }
        occupancy[tableId] = (occupancy[tableId] ?? 0) + seats;
      }
      localOrdersOccupancy.assignAll(occupancy);
      pendingUpdateIds.assignAll(skipIds);
    } catch (e) {
      debugPrint("Error updating local occupancy: $e");
    }
  }

  Future<void> _loadFromLocalDB() async {
    final localAreas = await _dbHelper.getAreas();
    List<AreaModel> fetchedAreas = [];

    for (var areaMap in localAreas) {
      final tablesMap = await _dbHelper.getTablesForArea(areaMap['id']);

      fetchedAreas.add(AreaModel(
        id: areaMap['id'],
        name: areaMap['name'],
        isDefault: areaMap['is_default'],
        priceGroupID: areaMap['price_group_id'],
        tables: tablesMap.map((t) => TableModel.fromJson(t)).toList(),
      ));
    }

    if (fetchedAreas.isNotEmpty) {
      areas.assignAll(fetchedAreas);
      if (areas.isNotEmpty) {
        selectedArea.value ??= areas.first;
      }
      // Preserve selection if possible
      if (selectedArea.value != null) {
        selectedArea.value = areas.firstWhere((a) => a.id == selectedArea.value!.id, orElse: () => areas.first);
      } else {
        selectedArea.value = areas.firstWhere((a) => a.isDefault == 1, orElse: () => areas.first);
      }
    }
  }

  void selectArea(AreaModel area) {
    selectedArea.value = area;
  }

  int getOccupiedCountForTable(TableModel table, {bool includeCurrentSelection = true}) {
    final cartController = Get.find<CartController>();
    int occupied = 0;

    // 1. Count from server-synced processing tables
    for (var order in table.processingTable) {
      if (order is Map) {
        final String? orderInvNo = order['sales_odr_inv_no']?.toString() ?? order['sq_inv_no']?.toString();
        final String? orderId = (order['sales_odr_id'] ?? order['sq_id'] ?? order['uuid'] ?? order['local_uuid'])?.toString();

        // Skip current editing order's seats in occupied calculation
        if (cartController.isEditing &&
            ((orderInvNo != null && orderInvNo == cartController.editingInvNo.value) ||
                (orderId != null && orderId == cartController.editingOrderId.value))) {
          continue;
        }

        // Skip orders that have a pending local update (we use the local count instead)
        if (orderId != null && pendingUpdateIds.contains(orderId)) {
          continue;
        }

        occupied += _safeInt(order['sales_odr_no_seats'] ?? order['no_seats']);
      }
    }

    // 2. Count from local unsynced (offline) orders
    occupied += localOrdersOccupancy[table.id] ?? 0;

    // 3. Count current active selection in Cart
    if (includeCurrentSelection && cartController.selectedTableId.value == table.id.toString()) {
      occupied += cartController.selectedChairCount.value;
    }

    return occupied;
  }

  void selectTable(TableModel table) {
    final cartController = Get.find<CartController>();

    // Calculate occupied seats excluding current cart selection
    int baseOccupiedCount = getOccupiedCountForTable(table, includeCurrentSelection: false);

    if (baseOccupiedCount < table.chairCount) {
      if (cartController.selectedTableId.value == table.id.toString()) {
        selectedChairCount.value = cartController.selectedChairCount.value;
      } else {
        selectedChairCount.value = 0;
      }
      Get.dialog(ChairSelectionDialog(table: table, occupiedCount: baseOccupiedCount));
    } else {
      Get.snackbar("table_full".tr, "table_full_msg".tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.redAccent,
          colorText: Colors.white);
    }
  }

  void confirmSelection(TableModel table) {
    if (selectedChairCount.value == 0) {
      showSafeSnackbar("selection_required".tr,  "select_chair_msg".tr);
      return;
    }

    final cartController = Get.find<CartController>();
    final area = selectedArea.value;

    cartController.setTable(
      tableId: table.id.toString(),
      tableName: table.name,
      chairCount: selectedChairCount.value,
      areaId: area?.id ?? 0,
      areaName: area?.name ?? "",
      priceGroupId: area?.priceGroupID ?? 0,
    );

    Get.back();
    Get.find<HomeController>().changeIndex(0);
  }
}

class ChairSelectionDialog extends GetView<TablesController> {
  final TableModel table;
  final int occupiedCount;

  const ChairSelectionDialog({super.key, required this.table, required this.occupiedCount});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AlertDialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(table.name, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: colors.text)),
          SizedBox(height: 4.h),
          Text(
            'select_chair_count'.tr,
            style: AppTypography.cardInfo.copyWith(color: colors.subtext),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Obx(() => Wrap(
            spacing: AppTypography.smallText,
            runSpacing:AppTypography.smallText,
            children: List.generate(table.chairCount, (index) {
              final chairNum = index + 1;
              final bool isAlreadyOccupied = chairNum <= occupiedCount;

              // Correct logic as requested: Tapping chair X means selecting X - occupiedCount chairs.
              // Highlights ONLY the tapped chair.
              // final bool isCurrentlySelected = controller.selectedChairCount.value > 0 &&
              //                                 (occupiedCount + controller.selectedChairCount.value == chairNum);
              final bool isCurrentlySelected =
                  chairNum > occupiedCount &&
                      chairNum <= occupiedCount + controller.selectedChairCount.value;

              return InkWell(
                onTap: isAlreadyOccupied ? null : () {
                   controller.selectedChairCount.value = chairNum - occupiedCount;
                },
                child: Container(
                  width: AppTypography.iconXL,
                  height:  AppTypography.iconXL,
                  decoration: BoxDecoration(
                    color: isCurrentlySelected
                        ? AppTheme.primaryGreen
                        : (isAlreadyOccupied ? Colors.red.withOpacity(0.2) : colors.textField),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: isCurrentlySelected ? AppTheme.primaryGreen : colors.border,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      chairNum.toString(),
                      style: TextStyle(
                        color: isCurrentlySelected
                            ? Colors.white
                            : (isAlreadyOccupied ? Colors.red : colors.text),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),
          )),
          SizedBox(height: 24.h),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  text: 'cancel'.tr,
                  onPressed: () => Get.back(),
                  color: Colors.grey.shade200,
                  style: TextStyle(color: Colors.black87),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: PrimaryButton(
                  text: 'confirm'.tr,
                  onPressed: () => controller.confirmSelection(table),
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
