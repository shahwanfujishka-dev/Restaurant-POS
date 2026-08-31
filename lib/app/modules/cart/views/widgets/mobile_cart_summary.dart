import 'dart:convert';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../../helper/snackbar_helper.dart';
import '../../../../data/models/order_model.dart';
import '../../../../data/utils/AppState.dart';
import '../../../../routes/app_pages.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../../../widgets/reusable_button.dart';
import '../../../home/controller/dashboard_controller.dart';
import '../../../home/controller/home_controller.dart';
import '../../../home/controller/order_controller.dart';
import '../../../home/controller/printer_controller.dart';
import '../../controller/cart_controller.dart';

class MobileCartSummary extends StatelessWidget {
  final CartController controller;

  MobileCartSummary({super.key, required this.controller});

  void _handlePlaceOrUpdateOrder({
    bool isDraft = false,
    int? payType,
    int? cashLedgerId,
    double? cashAmt,
    double? cardAmt,
    bool isCompliment = false,
    bool shouldPrintReceipt = false,
  }) async {
    if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

    if (AppState.orderType.id == 0 && !controller.hasSelectedTable) {
      showSafeSnackbar("table_required".tr, "select_table_msg".tr);
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
        cashLedgerId: cashLedgerId,
        cashAmt: cashAmt,
        cardAmt: cardAmt,
        isCompliment: isCompliment,
      );

      if (responseData == null) {
        showSafeSnackbar("Error", "Failed to process order. Please try again.");
        return;
      }

      // ✅ Log Success Response to Console
      log("Order Success Response: ${jsonEncode(responseData)}");

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
            isDraft ? "Draft updated successfully." : "Order updated successfully."
        );
        controller.stopEditing();
      } else {
        showSafeSnackbar(
            isDraft ? "Draft Saved" : "order_placed".tr,
            isDraft ? "Order saved as draft." : "Order successfully created."
        );
        controller.clearCart();
        controller.clearTable();
      }

      Get.offAllNamed(Routes.ORDER_TYPE);

      _runBackgroundTasks(
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
      showSafeSnackbar("Error", "An unexpected error occurred. Please try again.");
    } finally {
      controller.isProcessing.value = false;
    }
  }

  void _navigateToCashier() {
    if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

    if (AppState.orderType.id == 0 && !controller.hasSelectedTable) {
      showSafeSnackbar("table_required".tr, "select_table_msg".tr);
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

    final List<OrderItem> items = controller.cartItems
        .where((ci) => !ci.isDeleted.value && ci.quantity.value > 0)
        .map((ci) => OrderItem(
              subId: ci.subId,
              product: ci.product,
              unit: ci.unit,
              selectedAddons: ci.selectedAddons,
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
      totalAmount: controller.grandTotal,
      totalTax: controller.totalTaxAmount,
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
  }) async {
    if (!isDraft) {
      try {
        final printerController = Get.find<PrinterController>();
        final OrderModel liveOrder = ordersController.parseOrderResponse(
          responseData,
          fallbackTableName: snapshotTableName,
          fallbackChairCount: snapshotChairCount,
        );

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
    final colors = AppColors.of(context);

    return Obx(() {
      if (controller.cartItems.isEmpty) {
        return const SizedBox.shrink();
      }

      final bottomInset = MediaQuery.of(context).viewPadding.bottom;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          left: 8.w,
          right: 8.w,
          top: 6.w,
          bottom: bottomInset > 0 ? bottomInset : 8.h,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.35 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),

        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _buildSummaryCard(context),
        ),
      );
    });
  }

  Widget _buildSummaryCard(BuildContext context) {
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
          padding: EdgeInsets.all(3.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryHeader(context),
              SizedBox(height: 4.h),
              _buildTotalRow(context, label: 'subtotal'.tr, value: controller.totalAmount, isBold: false),
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
              SizedBox(height: 4.h),
              _buildDivider(context),
              SizedBox(height: 7.h),
              _buildTotalRow(
                  context,
                  label: 'grand_total'.tr,
                  value: grandTotalValue,
                  isBold: true
              ),
              SizedBox(height: 5.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            isLoading: controller.isProcessing.value,
                            height: 48.h,
                            onPressed: () => _handlePlaceOrUpdateOrder(isDraft: true),
                            color: colors.isDark ? Colors.orange.shade900 : Colors.orange.shade700,
                            text: "Hold",
                            icon: Icons.pause,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            isLoading: controller.isProcessing.value,
                            onPressed: () => _handlePlaceOrUpdateOrder(isDraft: false),
                            text: controller.isEditing ? "Update KOT" : 'place_order'.tr,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            isLoading: controller.isProcessing.value,
                            height: 48.h,
                            onPressed: () => _handlePlaceOrUpdateOrder(isDraft: false, shouldPrintReceipt: true),
                            color: Colors.blueGrey,
                            text: "KOT & Print",
                            icon: Icons.print,
                          ),
                        ),
                        SizedBox(width: 8.w),
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
                            icon: Icons.receipt,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (controller.isEditing && !controller.isProcessing.value)
                TextButton(
                  onPressed: controller.stopEditing,
                  child: const Text("Cancel Edit", style: TextStyle(color: Colors.red)),
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r)),
          child: Icon(Icons.receipt_long, size: 20.sp, color: color),
        ),
        SizedBox(width: 8.w),
        Text(controller.isEditing ? "Edit Order Summary" : 'bill_summary'.tr,
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16.sp,
              color: colors.text,
            )),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: 1,
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.transparent,
            colors.border,
            Colors.transparent
          ])),
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
              : AppTypography.cardSubtitle.copyWith(color: colors.subtext),
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
