import 'package:flutter/material.dart';
import 'package:restaurant_pos/app/widgets/order_follow_up.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import '../../../../../../../helper/network_helper.dart';
import '../../../../../../../helper/snackbar_helper.dart';
import '../../../../../../data/Device_Roles/device_roles.dart';
import '../../../../../../data/models/order_model.dart';
import '../../../../../../routes/app_pages.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../../widgets/reusable_button.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../controller/dashboard_controller.dart';
import '../../../../../../data/utils/AppState.dart';
import '../../../../../../../helper/screen_type.dart';

class CartSummary extends StatelessWidget {
  final CartController controller;

  const CartSummary({super.key, required this.controller});

  void _navigateToCashier() async {
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

    if (DeviceConfig.isOnline && !await NetworkHelper.hasInternetConnection()) {
      showSafeSnackbar('no_internet'.tr, 'check_network_msg'.tr);
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
      orderTime: DateTime.now(),
      totalAmount: totalWithTax,
      totalTax: totalTax,
      sales_odr_order_type: AppState.orderType.id,
      areaId: controller.selectedAreaId.value,
      priceGroupId: controller.selectedPriceGroupId.value,
    );

    Get.toNamed(Routes.CASHIER, arguments: tempOrder);
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
                      onPressed: () => submitCartOrder(
                        controller: controller,
                        destination: ScreenType.isMobile()
                            ? Routes.ORDER_TYPE
                            : Routes.HOME,
                        requireCaptain: true,
                        isDraft: true,
                      ),
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
                      onPressed: () => submitCartOrder(
                        controller: controller,
                        destination: ScreenType.isMobile()
                            ? Routes.ORDER_TYPE
                            : Routes.HOME,
                        requireCaptain: true,
                        validateClient: true,
                      ),
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
                      onPressed: () => submitCartOrder(
                        controller: controller,
                        destination: ScreenType.isMobile()
                            ? Routes.ORDER_TYPE
                            : Routes.HOME,
                        requireCaptain: true,
                        shouldPrintReceipt: true,
                      ),
                      color: Colors.blueGrey,
                      text: 'kot_and_print'.tr,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: PrimaryButton(
                      isLoading: controller.isProcessing.value,
                      height: 48.h,
                      onPressed: () async {
                        if (controller.selectedCaptainId.value == null) {
                          showSafeSnackbar(
                            'captain_required'.tr,
                            'captain_required_msg'.tr,
                          );
                          return;
                        }
                        if (DeviceConfig.isOnline &&
                            !await NetworkHelper.hasInternetConnection()) {
                          showSafeSnackbar(
                            'no_internet'.tr,
                            'check_network_msg'.tr,
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
