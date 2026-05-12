import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import 'package:shimmer/shimmer.dart';

import '../../../../helper/screen_type.dart';
import '../../../data/models/order_type.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../controller/order_type_controller.dart';

class OrderTypeView extends GetView<OrderTypeController> {
  const OrderTypeView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.text),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'order_type'.tr.isEmpty ? 'Order Type' : 'order_type'.tr,
          style: TextStyle(color: colors.text),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: ScreenType.isMobile() ? 400.w : 200.w),
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Obx(() {
              if (controller.isLoading.value) {
                return _buildShimmerLoading(context);
              }
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'select_order_type'.tr.isEmpty ? 'Select Order Type' : 'select_order_type'.tr,
                    style: AppTypography.headline1.copyWith(
                      color: AppTheme.primaryGreen,
                      fontSize: 12.sp,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'order_type_desc'.tr.isEmpty
                        ? 'How would you like to serve the customer?'
                        : 'order_type_desc'.tr,
                    style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20.h),
                  _buildTypeCard(
                    context: context,
                    type: OrderType.dineIn,
                    icon: Icons.restaurant,
                    color: Colors.blue.shade600,
                    description: 'serve_at_table'.tr.isEmpty ? 'Serve at the table' : 'serve_at_table'.tr,
                    isSelected: controller.selectedType.value == OrderType.dineIn,
                  ),
                  SizedBox(height: 16.h),
                  _buildTypeCard(
                    context: context,
                    type: OrderType.pickUp,
                    icon: Icons.takeout_dining,
                    color: Colors.orange.shade600,
                    description: 'customer_collects'.tr.isEmpty ? 'Customer collects the order' : 'customer_collects'.tr,
                    isSelected: controller.selectedType.value == OrderType.pickUp,
                  ),
                  SizedBox(height: 16.h),
                  _buildTypeCard(
                    context: context,
                    type: OrderType.delivery,
                    icon: Icons.delivery_dining,
                    color: Colors.purple.shade600,
                    description: 'send_to_address'.tr.isEmpty ? 'Send to customer address' : 'send_to_address'.tr,
                    isSelected: controller.selectedType.value == OrderType.delivery,
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(BuildContext context) {
    final colors = AppColors.of(context);
    return Shimmer.fromColors(
      baseColor: colors.border.withOpacity(0.3),
      highlightColor: colors.card,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 20.h,
            width: 150.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            height: 15.h,
            width: 250.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
          SizedBox(height: 24.h),
          _buildShimmerCard(),
          SizedBox(height: 16.h),
          _buildShimmerCard(),
          SizedBox(height: 16.h),
          _buildShimmerCard(),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      height: 70.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
    );
  }

  Widget _buildTypeCard({
    required BuildContext context,
    required OrderType type,
    required IconData icon,
    required Color color,
    required String description,
    bool isSelected = false,
  }) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: () => controller.selectOrderType(type),
      borderRadius: BorderRadius.circular(20.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.all(AppTypography.sizeText),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : colors.border,
            width: isSelected ? 2.5 : 1,
          ),
          color: isSelected ? AppTheme.primaryGreen.withOpacity(0.08) : colors.card,
          boxShadow: [
            BoxShadow(
              color: isSelected ? AppTheme.primaryGreen.withOpacity(0.15) : Colors.black.withOpacity(colors.isDark ? 0.2 : 0.03),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(AppTypography.smallText),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryGreen : color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15.r),
              ),
              child: Icon(
                  icon,
                  color: isSelected ? Colors.white : color,
                  size: 12.sp
              ),
            ),
            SizedBox(width: 20.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      type.displayName,
                      style: AppTypography.headline2.copyWith(
                        color: isSelected ? AppTheme.primaryGreen : colors.text,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      )
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    description,
                    style: AppTypography.cardSubtitle.copyWith(
                      color: isSelected ? AppTheme.primaryGreen.withOpacity(0.7) : colors.subtext,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 10.sp,
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                color: colors.subtext.withOpacity(0.3),
                size: 10.sp,
              ),
          ],
        ),
      ),
    );
  }
}
