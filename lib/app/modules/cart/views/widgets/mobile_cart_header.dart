import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/models/order_type.dart';
import '../../../../data/utils/AppState.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../../home/controller/home_controller.dart';
import '../../../order_type/controller/order_type_controller.dart';
import '../../controller/cart_controller.dart';

class MobileCartHeader extends StatelessWidget {
  final CartController controller;

  const MobileCartHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final orderTypeController = Get.find<OrderTypeController>();

    return Obx(() {
      final currentType = orderTypeController.selectedType.value ?? AppState.orderType;
      
      if (currentType != OrderType.dineIn) {
        return const SizedBox.shrink();
      }
      if (!controller.hasSelectedTable) return const SizedBox.shrink();

      return Container(
        margin: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGreen.withOpacity(0.1),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: AppTheme.primaryGreen.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            Get.back();
            Get.find<HomeController>().changeIndex(1);
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: Row(
              children: [
                _buildTableIcon(),
                SizedBox(width: 12.w),
                _buildTableDetails(),
                _buildCloseButton(),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTableIcon() {
    return Stack(
      children: [
        Container(
          padding: EdgeInsets.all(10.w),
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
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.table_restaurant,
            color: Colors.white,
            size: 22.sp,
          ),
        ),
        if (controller.cartItems.isNotEmpty)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.all(4.w),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${controller.cartItems.length}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTableDetails() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.selectedTableName.value,
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
              fontSize: 16.sp,
            ),
          ),
          SizedBox(height: 4.h),
          Row(
            children: [
              Icon(
                Icons.chair,
                size: 14.sp,
                color: Colors.grey.shade500,
              ),
              SizedBox(width: 4.w),
              Text(
                '${controller.selectedChairCount.value} ${controller.selectedChairCount.value > 1 ? 'Chairs' : 'Chair'}',
                style: AppTypography.cardSubtitle.copyWith(
                  fontSize: 12.sp,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: IconButton(
        icon: Icon(
          Icons.close,
          size: 18.sp,
          color: Colors.grey.shade600,
        ),
        onPressed: () => controller.clearTable(),
        constraints: const BoxConstraints(),
        padding: EdgeInsets.all(8.w),
      ),
    );
  }
}
