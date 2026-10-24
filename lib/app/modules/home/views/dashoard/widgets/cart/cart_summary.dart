import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import '../../../../../../../helper/snackbar_helper.dart';
import '../../../../../../data/Device_Roles/device_roles.dart';
import '../../../../../../data/models/order_model.dart';
import '../../../../../../data/services/local_hub_client.dart';
import '../../../../../../routes/app_pages.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../../widgets/reusable_button.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../controller/dashboard_controller.dart';
import '../../../../controller/order_controller.dart';
import '../../../../controller/printer_controller.dart';
import '../../../../../../data/utils/AppState.dart';
import '../../../../../../../helper/screen_type.dart';

class CartSummary extends StatelessWidget {
  final CartController controller;

  const CartSummary({super.key, required this.controller});

  bool get _isLocalClient =>
      DeviceConfig.operationMode == OperationMode.local &&
      DeviceConfig.role == DeviceRole.client;

  Future<bool> _validateClientReady() async {
    if (!_isLocalClient) return true; // host / online: nothing to check

    final ip = DeviceConfig.hostIp;
    if (ip == null || ip.trim().isEmpty) {
      showSafeSnackbar(
        'main_cashier_not_set'.tr,
        'main_cashier_ip_hint'.tr,
      );
      return false;
    }

    if (!DeviceConfig.hasAuthToken) {
      showSafeSnackbar(
        'device_not_registered'.tr,
        'connect_to_hub_msg'.tr,
      );
      return false;
    }

    try {
      await LocalHubClient.instance
          .testConnection(hostIp: ip, port: DeviceConfig.hostPort)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Warn but allow: placeOrder saves locally and SyncService retries later
      showSafeSnackbar(
        'hub_unreachable'.tr,
        'offline_save_msg'.tr,
      );
    }
    return true;
  }

  Future<bool> _validatePrinterReady() async {
    final printerController = Get.find<PrinterController>();

    // 1. Bluetooth permission check (no-op/true on non-Android platforms)
    final hasPermission = await printerController.checkPermissions();
    if (!hasPermission) {
      showSafeSnackbar(
        'permissions_required'.tr,
        'bt_permission_kot_msg'.tr,
      );
      await printerController.requestBluetoothPermissions();
      return false;
    }

    // 2. At least one printer must actually be assigned to a token
    final hasAssignedPrinter = printerController.tokenPrinterAssignments.any(
      (a) => a.printerAddress.value.isNotEmpty,
    );
    if (!hasAssignedPrinter) {
      showSafeSnackbar(
        'no_printer_assigned'.tr,
        'no_printer_assigned_msg'.tr,
      );
      return false;
    }

    return true;
  }

  void _handlePlaceOrUpdateOrder({
    bool isDraft = false,
    int? payType,
    double? cashAmt,
    double? cardAmt,
    bool isCompliment = false,
    bool shouldPrintReceipt = false,
  }) async {
    if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

    // ✅ Table/Chair validation only required for Dine-In (id: 0)
    if (AppState.orderType.id == 0 && !controller.hasSelectedTable) {
      Get.find<DashboardController>().showError(
        'table_required'.tr,
        'select_table_msg'.tr,
      );
      return;
    }

    final hasValidItems = controller.cartItems.any(
      (item) => !item.isDeleted.value && item.quantity.value > 0,
    );

    if (!hasValidItems) {
      showSafeSnackbar(
        'empty_order'.tr,
        'empty_order_msg'.tr,
      );
      return;
    }
    if (controller.selectedCaptainId.value == null) {
      showSafeSnackbar(
        'captain_required'.tr,
        'captain_required_msg'.tr,
      );
      return;
    }

    try {
      controller.isProcessing.value = true;

      final responseData = controller.isEditing
          ? await controller.updateOrder(
              isDraft: isDraft,
              payType: payType,
              cashAmt: cashAmt,
              cardAmt: cardAmt,
              isCompliment: isCompliment,
            )
          : await controller.placeOrder(
              isDraft: isDraft,
              payType: payType,
              cashAmt: cashAmt,
              cardAmt: cardAmt,
              isCompliment: isCompliment,
            );

      if (responseData == null) {
        showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
        return;
      }

      log("Order Success Response: $responseData");
      if (DeviceConfig.operationMode == OperationMode.local) {
        final localOrdersController = Get.find<OrdersController>();
        final parsedOrder = localOrdersController.parseOrderResponse(
          responseData,
        );
        localOrdersController.updateExistingOrder(parsedOrder);
      }

      // ✅ CHECK FOR ERROR STATUS IN RESPONSE
      bool hasError = false;
      String errorMessage = "";

      if (responseData is Map) {
        if (responseData['message'] is Map) {
          final messageMap = responseData['message'] as Map;
          if (messageMap['status'] == 0) {
            hasError = true;
            errorMessage = messageMap['msg'] ?? "Order processing failed";
          }
        }
        else if (responseData['status'] == 0) {
          hasError = true;
          errorMessage =
              responseData['message']?.toString() ?? "Order processing failed";
        }
      }

      if (hasError) {
        showSafeSnackbar('error'.tr, errorMessage);
        return;
      }

      if (responseData is Map && responseData['no_change'] == true) {
        controller.stopEditing();
        showSafeSnackbar('no_change'.tr, 'no_change_msg'.tr);
        return;
      }

      final ordersController = Get.find<OrdersController>();
      final bool wasEditing = controller.isEditing;
      final bool wasDraftVal = controller.wasDraft.value;
      final List<OrderItem> originalItemsCopy = List<OrderItem>.from(
        controller.originalItems,
      );

      final String snapshotTableName = controller.selectedTableName.value;
      final int snapshotChairCount = controller.selectedChairCount.value;
      OrderModel? liveOrder;
      try {
        liveOrder = ordersController.parseOrderResponse(
          responseData,
          fallbackTableName: snapshotTableName,
          fallbackChairCount: snapshotChairCount,
        );
      } catch (e) {
        debugPrint("Pre-clear parse failed: $e");
      }
      if (wasEditing) {
        showSafeSnackbar(
          isDraft ? 'draft_updated'.tr : 'order_updated'.tr,
          isDraft
              ? 'draft_updated_msg'.tr
              : 'order_updated_msg'.tr,
        );
        controller.stopEditing();
      } else {
        showSafeSnackbar(
          isDraft ? 'draft_saved'.tr : 'order_placed'.tr,
          isDraft ? 'draft_saved_msg'.tr : 'order_placed_msg'.tr,
        );
        controller.clearCart();
        controller.clearTable();
      }

      Get.offAllNamed(ScreenType.isMobile() ? Routes.ORDER_TYPE : Routes.HOME);

      _runBackgroundTasks(
        liveOrder: liveOrder,
        responseData: responseData,
        isDraft: isDraft,
        wasEditing: wasEditing,
        wasDraft: wasDraftVal,
        originalItems: originalItemsCopy,
        ordersController: ordersController,
        snapshotTableName: snapshotTableName,
        snapshotChairCount: snapshotChairCount,
        shouldPrintReceipt: shouldPrintReceipt,
      );
    } catch (e) {
      debugPrint("Order processing error: $e");
      showSafeSnackbar(
        'error'.tr,
        'unexpected_error'.tr,
      );
    } finally {
      controller.isProcessing.value = false;
    }
  }

  void _navigateToCashier() {
    if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

    if (AppState.orderType.id == 0 && !controller.hasSelectedTable) {
      Get.find<DashboardController>().showError(
        'table_required'.tr,
        'select_table_msg'.tr,
      );
      return;
    }

    final hasValidItems = controller.cartItems.any(
      (item) => !item.isDeleted.value && item.quantity.value > 0,
    );

    if (!hasValidItems) {
      showSafeSnackbar(
        'empty_order'.tr,
        'empty_order_msg'.tr,
      );
      return;
    }

    final dashboardController = Get.find<DashboardController>();
    final bool showTax = dashboardController.vatType.value == 0;
    final double totalTax = showTax ? controller.totalTaxAmount : 0.0;
    final double totalWithTax = showTax
        ? controller.grandTotal
        : controller.totalAmount;
    final items = controller.cartItems
        .where((ci) => !ci.isDeleted.value && ci.quantity.value > 0)
        .map(
          (ci) => OrderItem(
            subId: ci.subId,
            product: ci.product,
            unit: ci.unit,
            selectedAddons: List.from(ci.selectedAddons),
            quantity: ci.quantity.value,
            priceAtOrder: ci.unit.rate,
            addonParentPrdId: ci.addonprntId,
            addonParentUnitId: ci.addonuntId,
            unitId: ci.unit.unitId,
            notes: ci.note.value,
          ),
        )
        .toList();

    final tempOrder = OrderModel(
      id: controller.editingOrderId.value.isEmpty
          ? "PENDING"
          : controller.editingOrderId.value,
      invNo: controller.editingInvNo.value.isEmpty
          ? "NEW"
          : controller.editingInvNo.value,
      tableId: controller.selectedTableId.value,
      tableName: controller.selectedTableName.value,
      chairNumber: controller.selectedChairCount.value,
      sales_odr_pos_status: 1,
      items: items,
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
      totalAmount: totalWithTax,
      totalTax: totalTax,
      sales_odr_order_type: AppState.orderType.id,
      areaId: controller.selectedAreaId.value,
      priceGroupId: controller.selectedPriceGroupId.value,
    );

    Get.toNamed(Routes.CASHIER, arguments: tempOrder);
  }

  void _runBackgroundTasks({
    required dynamic responseData,
    required bool isDraft,
    required bool wasEditing,
    required bool wasDraft,
    required List<OrderItem> originalItems,
    required OrdersController ordersController,
    String snapshotTableName = "",
    int snapshotChairCount = 0,
    bool shouldPrintReceipt = false,
    OrderModel? liveOrder,
  }) async {
    if (!isDraft) {
      try {
        final printerController = Get.find<PrinterController>();

        final OrderModel order =
            liveOrder ??
            ordersController.parseOrderResponse(
              responseData,
              fallbackTableName: snapshotTableName,
              fallbackChairCount: snapshotChairCount,
            );

        List<OrderItem>? oldItemsForKOT;
        if (wasEditing && !wasDraft) {
          oldItemsForKOT = originalItems;
        }

        await printerController.printKOT(order, oldItems: oldItemsForKOT);

        if (shouldPrintReceipt) {
          await printerController.printReceipt(order, 0, 0);
        }
      } catch (e) {
        debugPrint("Background Printing failed: $e");
      }
    }

    try {
      if (DeviceConfig.operationMode != OperationMode.local) {
        await ordersController.fetchOrdersSafely();
      }
    } catch (e) {
      debugPrint("Background Fetch Orders failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardController = Get.find<DashboardController>();
    final colors = AppColors.of(context);

    return Obx(() {
      if (controller.cartItems.isEmpty) return const SizedBox.shrink();

      final showTax = dashboardController.vatType.value == 0;
      final double grandTotalValue = showTax
          ? controller.grandTotal
          : controller.totalAmount;

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.card,
              controller.isEditing
                  ? Colors.blue.withOpacity(0.08)
                  : AppTheme.primaryGreen.withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
              blurRadius: 10.r,
              offset: const Offset(0, -5),
            ),
          ],
          border: Border.all(
            color: controller.isEditing
                ? Colors.blue.withOpacity(0.2)
                : AppTheme.primaryGreen.withOpacity(0.2),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 3.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryHeader(context),
              SizedBox(height: 1.h),
              _buildTotalRow(
                context,
                label: 'subtotal'.tr,
                value: controller.totalAmount,
                isBold: false,
              ),
              if (showTax) ...[
                SizedBox(height: 4.h),
                if (AppState.cmpTaxType == 1) ...[
                  _buildTotalRow(
                    context,
                    label: 'tax'.tr,
                    value: controller.totalTaxAmount,
                    isBold: false,
                  ),
                ] else ...[
                  _buildTotalRow(
                    context,
                    label: 'cgst'.tr,
                    value: (controller.totalTaxAmount / 2),
                    isBold: false,
                  ),
                  _buildTotalRow(
                    context,
                    label: 'sgst'.tr,
                    value: (controller.totalTaxAmount / 2),
                    isBold: false,
                  ),
                ],
              ],
              SizedBox(height: 2.h),
              _buildDivider(context),
              SizedBox(height: 2.h),
              _buildTotalRow(
                context,
                label: 'grand_total'.tr,
                value: grandTotalValue,
                isBold: true,
              ),
              SizedBox(height: 3.h),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      height: 48.h,
                      onPressed: () => _handlePlaceOrUpdateOrder(isDraft: true),
                      color: colors.isDark
                          ? Colors.orange.shade900
                          : Colors.orange.shade700,
                      text: 'hold'.tr,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      onPressed: () async {
                        if (!await _validateClientReady()) return;
                        final ready = await _validatePrinterReady();
                        if (!ready) return;
                        _handlePlaceOrUpdateOrder(isDraft: false);
                      },
                      text: controller.isEditing
                          ? 'update_kot'.tr
                          : 'place_order'.tr,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2.h),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      height: 48.h,
                      onPressed: () async {
                        final ready = await _validatePrinterReady();
                        if (!ready) return;
                        _handlePlaceOrUpdateOrder(
                          isDraft: false,
                          shouldPrintReceipt: true,
                        );
                      },
                      color: Colors.blueGrey,
                      text: 'kot_and_print'.tr,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      height: 48.h,
                      onPressed: () {
                        if (controller.selectedCaptainId.value == null) {
                          showSafeSnackbar(
                            'captain_required'.tr,
                            'captain_required_msg'.tr,
                          );
                          return;
                        }
                        _navigateToCashier();
                      },
                      color: colors.isDark
                          ? Colors.redAccent.shade700
                          : Colors.redAccent.shade400,
                      text: 'receipt'.tr,
                    ),
                  ),
                ],
              ),
              if (controller.isEditing && !controller.isProcessing.value)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.all(3.w),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: controller.stopEditing,
                  child: Text(
                    'cancel_edit'.tr,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildSummaryHeader(BuildContext context) {
    final colors = AppColors.of(context);
    final color = controller.isEditing ? Colors.blue : AppTheme.primaryGreen;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(2.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(Icons.receipt_long, size: 6.sp, color: color),
        ),
        SizedBox(width: 2.w),
        Text(
          controller.isEditing ? 'edit_order_summary'.tr : 'bill_summary'.tr,
          style: AppTypography.cardTitle.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, colors.border, Colors.transparent],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    BuildContext context, {
    required String label,
    required double value,
    required bool isBold,
  }) {
    final colors = AppColors.of(context);
    final accentColor = controller.isEditing
        ? Colors.blue
        : AppTheme.primaryGreen;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? AppTypography.cardTitle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                )
              : AppTypography.cardTitle.copyWith(
                  color: colors.subtext,
                  fontSize: AppTypography.sizeText,
                ),
        ),
        Text(
          value.toStringAsFixed(2),
          style: isBold
              ? AppTypography.cardTitle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                )
              : AppTypography.cardTitle.copyWith(color: colors.text),
        ),
      ],
    );
  }
}
