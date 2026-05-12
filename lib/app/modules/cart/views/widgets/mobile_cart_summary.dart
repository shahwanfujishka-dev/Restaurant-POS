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

  const MobileCartSummary({super.key, required this.controller});

  void _handlePlaceOrUpdateOrder({bool isDraft = false}) async {
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
          ? await controller.updateOrder(isDraft: isDraft)
          : await controller.placeOrder(isDraft: isDraft);

      if (responseData == null) {
        showSafeSnackbar("Error", "Failed to process order. Please try again.");
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
      );

    } catch (e) {
      debugPrint("Order processing error: $e");
    } finally {
      controller.isProcessing.value = false;
    }
  }

  void _runBackgroundTasks({
    required dynamic responseData,
    required bool isDraft,
    required bool wasEditing,
    required bool wasDraft,
    required List<OrderItem> originalItems,
    required OrdersController ordersController,
  }) async {
    if (!isDraft) {
      try {
        final printerController = Get.find<PrinterController>();
        final OrderModel liveOrder = ordersController.parseOrderResponse(responseData);

        List<OrderItem>? oldItemsForKOT;
        if (wasEditing && !wasDraft) {
          oldItemsForKOT = originalItems;
        }

        await printerController.printKOT(
          liveOrder,
          oldItems: oldItemsForKOT,
        );
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
      if (controller.cartItems.isEmpty) return const SizedBox.shrink();

      return Container(
        height: MediaQuery.of(context).size.height * 0.34,
        decoration: BoxDecoration(
          color: colors.card,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(colors.isDark ? 0.3 : 0.05),
                blurRadius: 20,
                offset: const Offset(0, -5)),
          ],
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r), topRight: Radius.circular(24.r)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(6.w),
            child: Column(
              children: [
                _buildSummaryCard(context),
              ],
            ),
          ),
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
              SizedBox(height: 8.h),
              _buildTotalRow(context, label: 'subtotal'.tr, value: controller.totalAmount, isBold: false),
              if (showTax) ...[
                SizedBox(height: 5.h),
                _buildTotalRow(context, label: 'tax'.tr, value: controller.totalTaxAmount, isBold: false),
              ],
              SizedBox(height: 5.h),
              _buildDivider(context),
              SizedBox(height: 12.h),
              _buildTotalRow(
                  context,
                  label: 'grand_total'.tr,
                  value: showTax ? controller.grandTotal : controller.totalAmount,
                  isBold: true
              ),
              SizedBox(height: 10.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Row(
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: isBold
                ? AppTypography.cardTitle.copyWith(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  )
                : AppTypography.cardSubtitle.copyWith(
                    fontSize: 14.sp,
                    color: colors.subtext,
                  )),
        Text(value.toStringAsFixed(2),
            style: isBold
                ? AppTypography.cardTitle.copyWith(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: controller.isEditing ? Colors.blue : AppTheme.primaryGreen,
                  )
                : AppTypography.cardTitle.copyWith(
                    fontSize: 15.sp,
                    color: colors.text,
                  )),
      ],
    );
  }
}
