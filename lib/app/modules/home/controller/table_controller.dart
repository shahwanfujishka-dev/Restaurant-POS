import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_navigation/src/snackbar/snackbar.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../../../../helper/snackbar_helper.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/reusable_button.dart';
import '../../cart/controller/cart_controller.dart';
import 'home_controller.dart';

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

class TablesController extends GetxController {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ApiService _apiService = Get.find<ApiService>();

  final areas = <AreaModel>[].obs;
  final selectedArea = Rxn<AreaModel>();
  final isLoading = false.obs;

  final selectedChairCount = 0.obs;

  // Track occupancy from local, unsynced orders
  final localOrdersOccupancy = <int, int>{}.obs;
  // Track which server-known orders have a pending local update to avoid double counting
  final pendingUpdateServerIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    fetchTables();
  }

  // Dual-Load Strategy: Load from DB first (instant), then API for fresh status
  Future<void> fetchTables() async {
    try {
      await _updateLocalOccupancy();
      await _loadFromLocalDB();
      if (areas.isEmpty) isLoading.value = true;

      final Map<String, dynamic> requestBody = {
        "usr_id": int.tryParse(AppState.userId) ?? 0,
      };

      final response = await _apiService.post('mobileapp/pos/get_pos_table', data: requestBody);

      if (response.statusCode == 200) {
        List<dynamic> dataList = [];
        if (response.data is Map && response.data['data'] is List) {
          dataList = response.data['data'];
        } else if (response.data is List) {
          dataList = response.data;
        }

        // Update Cache
        await _dbHelper.insertAreas(dataList.cast<Map<String, dynamic>>());

        // Refresh UI from fresh data
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
        final tableId = (order['table_id'] as num?)?.toInt();
        if (tableId == null) continue;

        // Skip if this is the order we are currently editing in the cart
        if (cartController.isEditing && order['uuid'] == cartController.editingOrderId.value) {
          continue;
        }

        // Track server IDs that have local updates to avoid double counting
        final serverId = order['server_id']?.toString();
        if (serverId != null && serverId.isNotEmpty) {
          skipIds.add(serverId);
        }

        int seats = 0;
        final payloadStr = order['payload'] as String?;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final payload = jsonDecode(payloadStr);
            seats = (payload['no_seats'] as num? ?? 0).toInt();
          } catch (e) {
            debugPrint("Error parsing local order payload for occupancy: $e");
          }
        }
        occupancy[tableId] = (occupancy[tableId] ?? 0) + seats;
      }
      localOrdersOccupancy.assignAll(occupancy);
      pendingUpdateServerIds.assignAll(skipIds);
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
        final String? orderId = order['sales_odr_id']?.toString() ?? order['sq_id']?.toString();

        // Skip current editing order's seats in occupied calculation
        if (cartController.isEditing &&
            ((orderInvNo != null && orderInvNo == cartController.editingInvNo.value) ||
                (orderId != null && orderId == cartController.editingOrderId.value))) {
          continue;
        }

        // Skip orders that have a pending local update (we use the local count instead)
        if (orderId != null && pendingUpdateServerIds.contains(orderId)) {
          continue;
        }

        occupied += (order['sales_odr_no_seats'] as num? ?? 0).toInt();
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
            spacing: 2.w,
            runSpacing: 2.h,
            alignment: WrapAlignment.center,
            children: List.generate(table.chairCount, (index) {
              final chairNum = index + 1;
              final isOccupied = chairNum <= occupiedCount;
              final isSelected = !isOccupied &&
                  chairNum <= (occupiedCount + controller.selectedChairCount.value);

              final bgColor = isOccupied
                  ? (colors.isDark ? colors.bg : Colors.grey.shade200)
                  : isSelected
                  ? AppTheme.primaryGreen
                  : colors.card;

              final borderColor = isOccupied
                  ? (colors.isDark ? colors.border : Colors.grey.shade300)
                  : isSelected
                  ? AppTheme.primaryGreen
                  : colors.border;

              final textColor = isOccupied
                  ? colors.subtext.withOpacity(0.5)
                  : isSelected
                  ? Colors.white
                  : colors.text;

              return GestureDetector(
                onTap: isOccupied
                    ? null
                    : () {
                  controller.selectedChairCount.value = chairNum - occupiedCount;
                },
                child: Container(
                  width: AppTypography.iconXL,
                  height: AppTypography.iconXL,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: borderColor,
                      width: 1.5,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ] : null,
                  ),
                  child: Text(
                    '$chairNum',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTypography.sizeText,
                      decoration: isOccupied
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              );
            }),
          )),
          if (occupiedCount > 0) ...[
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12.r,
                  height: 12.r,
                  decoration: BoxDecoration(
                    color: colors.isDark ? colors.bg : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4.r),
                    border: Border.all(color: colors.isDark ? colors.border : Colors.grey.shade300),
                  ),
                ),
                SizedBox(width: 8.w),
                Text('occupied'.tr, style: AppTypography.cardInfo.copyWith(color: colors.subtext)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr, style: TextStyle(color: colors.subtext))),
        PrimaryButton(
          onPressed: () => controller.confirmSelection(table),
          text: 'confirm'.tr,
        ),
      ],
    );
  }
}
