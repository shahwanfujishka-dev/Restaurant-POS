import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;

import '../../../../../../../helper/snackbar_helper.dart';
import '../../../../../../data/models/order_model.dart';
import '../../../../../../routes/app_pages.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../../widgets/reusable_button.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../controller/dashboard_controller.dart';
import '../../../../controller/home_controller.dart';
import '../../../../controller/order_controller.dart';
import '../../../../controller/printer_controller.dart';
import '../../../../../../data/utils/AppState.dart';
import '../../../../../../../helper/screen_type.dart';

class CartSummary extends StatelessWidget {
  final CartController controller;

  const CartSummary({super.key, required this.controller});

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
      Get.find<DashboardController>().showError("table_required".tr, "select_table_msg".tr);
      return;
    }

    final hasValidItems = controller.cartItems.any(
          (item) => !item.isDeleted.value && item.quantity.value > 0,
    );

    if (!hasValidItems) {
      showSafeSnackbar(
        "Empty Order",
        "Please add at least one item before updating or cancel the edit.",
      );
      return;
    }
    if (controller.selectedCaptainId.value == null) {
      showSafeSnackbar("Captain Required", "Please select a captain before placing the order.");
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
        showSafeSnackbar("Error", "Failed to process order. Please try again.");
        return;
      }

      log("Order Success Response: $responseData");
      // log(message)

      // ✅ CHECK FOR ERROR STATUS IN RESPONSE
      bool hasError = false;
      String errorMessage = "";

      // Check if response contains error status
      if (responseData is Map) {
        // Check for message.status == 0 (error)
        if (responseData['message'] is Map) {
          final messageMap = responseData['message'] as Map;
          if (messageMap['status'] == 0) {
            hasError = true;
            errorMessage = messageMap['msg'] ?? "Order processing failed";
          }
        }
        // Also check for direct status field
        else if (responseData['status'] == 0) {
          hasError = true;
          errorMessage = responseData['message']?.toString() ?? "Order processing failed";
        }
      }

      // If there's an error, show message and stop processing without navigation
      if (hasError) {
        showSafeSnackbar("Error", errorMessage);
        return;
      }

      if (responseData is Map && responseData['no_change'] == true) {
        controller.stopEditing();
        showSafeSnackbar("No Change", "No changes to apply.");
        return;
      }

      // AFTER
      final ordersController = Get.find<OrdersController>();
      final bool wasEditing = controller.isEditing;
      final bool wasDraftVal = controller.wasDraft.value;
      final List<OrderItem> originalItemsCopy = List<OrderItem>.from(controller.originalItems);

// ✅ Capture BEFORE stopEditing/clearTable wipes these values
      final String snapshotTableName = controller.selectedTableName.value;
      final int snapshotChairCount = controller.selectedChairCount.value;

      if (wasEditing) {
        showSafeSnackbar(
          isDraft ? "Draft Updated" : "Order Updated",
          isDraft ? "Draft updated successfully." : "Order updated successfully.",
        );
        controller.stopEditing();
      } else {
        showSafeSnackbar(
          isDraft ? "Draft Saved" : "order_placed".tr,
          isDraft ? "Order saved as draft." : "Order successfully created.",
        );
        controller.clearCart();
        controller.clearTable();
      }

      Get.offAllNamed(ScreenType.isMobile() ? Routes.ORDER_TYPE : Routes.HOME);

      _runBackgroundTasks(
        responseData: responseData,
        isDraft: isDraft,
        wasEditing: wasEditing,
        wasDraft: wasDraftVal,
        originalItems: originalItemsCopy,
        ordersController: ordersController,
        snapshotTableName: snapshotTableName,    // ✅ new
        snapshotChairCount: snapshotChairCount,  // ✅ new
        shouldPrintReceipt: shouldPrintReceipt,
      );

    } catch (e) {
      debugPrint("Order processing error: $e");
      showSafeSnackbar("Error", "An unexpected error occurred. Please try again.");
    } finally {
      controller.isProcessing.value = false;
    }
  }

  void _navigateToCashier() {
    if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

    if (AppState.orderType.id == 0 && !controller.hasSelectedTable) {
      Get.find<DashboardController>().showError("table_required".tr, "select_table_msg".tr);
      return;
    }

    final hasValidItems = controller.cartItems.any(
          (item) => !item.isDeleted.value && item.quantity.value > 0,
    );

    if (!hasValidItems) {
      showSafeSnackbar(
        "Empty Order",
        "Please add at least one item before proceeding to receipt.",
      );
      return;
    }

    final dashboardController = Get.find<DashboardController>();
    final bool showTax = dashboardController.vatType.value == 0;

    // Use current totals from cart
    final double totalTax = showTax ? controller.totalTaxAmount : 0.0;
    final double totalWithTax = showTax ? controller.grandTotal : controller.totalAmount;

    // Map cart items to order items to pass to cashier view
    final items = controller.cartItems
        .where((ci) => !ci.isDeleted.value && ci.quantity.value > 0)
        .map((ci) => OrderItem(
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
            ))
        .toList();

    // Construct a temporary OrderModel to pass to CashierView
    final tempOrder = OrderModel(
      id: controller.editingOrderId.value.isEmpty ? "PENDING" : controller.editingOrderId.value,
      invNo: controller.editingInvNo.value.isEmpty ? "NEW" : controller.editingInvNo.value,
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
    String snapshotTableName = "",    // ✅ new
    int snapshotChairCount = 0,       // ✅ new
    bool shouldPrintReceipt = false,
  }) async {
    if (!isDraft) {
      try {
        final printerController = Get.find<PrinterController>();
        final OrderModel liveOrder = ordersController.parseOrderResponse(
          responseData,
          fallbackTableName: snapshotTableName,
          fallbackChairCount: snapshotChairCount,
        );
        debugPrint("🖨️ liveOrder.items.length = ${liveOrder.items.length}"); // ADD
        debugPrint("🖨️ liveOrder.invNo = ${liveOrder.invNo}");
        List<OrderItem>? oldItemsForKOT;
        if (wasEditing && !wasDraft) {
          oldItemsForKOT = originalItems;
        }

        await printerController.printKOT(
          liveOrder,
          oldItems: oldItemsForKOT,
        );

        if (shouldPrintReceipt) {
          await printerController.printReceipt(liveOrder, 0, 0);
        }
      } catch (e) {
        debugPrint("Background Printing failed: $e");
      }
    }

    try {
      await ordersController.fetchOrders();
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
      final double grandTotalValue = showTax ? controller.grandTotal : controller.totalAmount;

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
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical :3.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryHeader(context),
              SizedBox(height: 1.h),
              _buildTotalRow(context, label: 'subtotal'.tr,
                  value: controller.totalAmount,
                  isBold: false),
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
                    label: 'CGST',
                    value: (controller.totalTaxAmount/2),
                    isBold: false,
                  ),
                  _buildTotalRow(
                    context,
                    label: 'SGST',
                    value: (controller.totalTaxAmount/2),
                    isBold: false,
                  ),
                ]
              ],
              SizedBox(height: 2.h),
              _buildDivider(context),
              SizedBox(height: 2.h),
              _buildTotalRow(
                  context,
                  label: 'grand_total'.tr,
                  value: grandTotalValue,
                  isBold: true
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
                      color: colors.isDark ? Colors.orange.shade900 : Colors
                          .orange.shade700,
                      text: "Hold",
                      // icon: Icons.pause,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      onPressed: () =>
                          _handlePlaceOrUpdateOrder(isDraft: false),
                      text: controller.isEditing ? "Update KOT" : 'place_order'
                          .tr,
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
                      onPressed: () => _handlePlaceOrUpdateOrder(isDraft: false, shouldPrintReceipt: true),
                      color: Colors.blueGrey,
                      text: "KOT & Print",
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      height: 48.h,
                      onPressed: () {
                        if (controller.selectedCaptainId.value == null) {
                          showSafeSnackbar("Captain Required", "Please select a captain before placing the order.");
                          return;
                        }
                        _navigateToCashier();
                      },
                      color: colors.isDark ? Colors.redAccent.shade700 : Colors.redAccent.shade400,
                      text: "Receipt",
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
                  child: const Text(
                      "Cancel Edit", style: TextStyle(color: Colors.red)),
                )
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
          controller.isEditing ? "Edit Order Summary" : 'bill_summary'.tr,
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
          colors: [
            Colors.transparent,
            colors.border,
            Colors.transparent
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context, {required String label, required double value, required bool isBold}) {
    final colors = AppColors.of(context);
    final accentColor = controller.isEditing ? Colors.blue : AppTheme.primaryGreen;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w600, color: colors.text)
              : AppTypography.cardTitle.copyWith(color: colors.subtext, fontSize: AppTypography.sizeText),
        ),
        Text(
          value.toStringAsFixed(2),
          style: isBold
              ? AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: accentColor)
              : AppTypography.cardTitle.copyWith(color: colors.text),
        ),
      ],
    );
  }
}
