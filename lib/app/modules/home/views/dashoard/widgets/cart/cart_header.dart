import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../../../../../../data/models/order_type.dart';
import '../../../../../../data/utils/AppState.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../../order_type/controller/order_type_controller.dart';
import '../../../../controller/home_controller.dart';

class CartHeader extends StatelessWidget {
  final CartController controller;

  const CartHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Access the reactive OrderTypeController outside the Obx
    final orderTypeController = Get.find<OrderTypeController>();

    return Obx(() {
      // 1. ALWAYS access reactive variables at the top of Obx to ensure GetX tracks them as dependencies.
      // This prevents the "improper use of GetX" error even if we return early.
      final currentType = orderTypeController.selectedType.value ?? AppState.orderType;
      final tableId = controller.selectedTableId.value;
      final areaName = controller.selectedAreaName.value;
      final tableName = controller.selectedTableName.value;
      final chairCount = controller.selectedChairCount.value;

      // 2. Hide table header for Delivery and Pick Up orders
      if (currentType != OrderType.dineIn) {
        return const SizedBox.shrink();
      }

      // 3. Hide if no table is selected
      if (tableId.isEmpty) {
        return const SizedBox.shrink();
      }

      return Container(
        margin: EdgeInsets.all(2.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGreen.withOpacity(0.1),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: AppTheme.primaryGreen.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.05),
              blurRadius: 8.r,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            Get.find<HomeController>().changeIndex(1);
          },
          borderRadius: BorderRadius.circular(8.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: Row(
              children: [
                _buildTableIcon(),
                SizedBox(width: 6.w),
                _buildTableDetails(areaName, tableName, chairCount),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTableIcon() {
    return Container(
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen,
            AppTheme.primaryGreen.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(0.3),
            blurRadius: 8.r,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.table_restaurant,
        color: Colors.white,
        size: 6.sp,
      ),
    );
  }

  Widget _buildTableDetails(String area, String table, int chairs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "($area)",
                style: AppTypography.cardSubtitle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              ),
              Text(
                " - $table",
                style: AppTypography.cardSubtitle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Icon(
                Icons.chair,
                size: 4.sp,
                color: Colors.grey.shade500,
              ),
              Text(
                '  $chairs ${chairs > 1 ? 'Chairs' : 'Chair'}',
                style: AppTypography.cardSubtitle.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.cartItems.isNotEmpty) _buildClearCartButton(),
        SizedBox(width: 2.w),
        _buildClearTableButton(),
      ],
    );
  }

  Widget _buildClearCartButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: IconButton(
        icon: Icon(
          Icons.delete_sweep,
          size: 6.sp,
          color: Colors.red.shade400,
        ),
        onPressed: () {
          Get.defaultDialog(
            title: "Clear Cart",
            titleStyle: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.w600,
            ),
            middleText: "Remove all items from current order?",
            middleTextStyle: AppTypography.cardSubtitle,
            radius: 16.r,
            textConfirm: "Clear All",
            textCancel: "Cancel",
            confirmTextColor: Colors.white,
            buttonColor: Colors.red,
            cancelTextColor: Colors.grey.shade700,
            onConfirm: () {
              controller.clearCart();
              Get.back();
            },
          );
        },
        constraints: const BoxConstraints(),
        padding: EdgeInsets.all(3.w),
      ),
    );
  }

  Widget _buildClearTableButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: IconButton(
        icon: Icon(
          Icons.close,
          size: 6.sp,
          color: Colors.grey.shade600,
        ),
        onPressed: () => controller.clearTable(),
        constraints: const BoxConstraints(),
        padding: EdgeInsets.all(3.w),
      ),
    );
  }
}
