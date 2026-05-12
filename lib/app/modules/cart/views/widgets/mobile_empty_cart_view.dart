import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../../../../theme/app_typography.dart';

class MobileEmptyCartView extends StatelessWidget {
  const MobileEmptyCartView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(30.w),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.shade200,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 50.sp,
              color: Colors.grey.shade400,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Your cart is empty',
            style: AppTypography.cardTitle.copyWith(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'add_items_msg'.tr,
            style: AppTypography.cardSubtitle.copyWith(
              fontSize: 14.sp,
              color: Colors.grey.shade500,
            ),
          ),
          // SizedBox(height: 30.h),
          // ElevatedButton(
          //   onPressed: () => Get.back(),
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: AppTheme.primaryGreen,
          //     foregroundColor: Colors.white,
          //     padding: EdgeInsets.symmetric(
          //       horizontal: 30.w,
          //       vertical: 12.h,
          //     ),
          //     shape: RoundedRectangleBorder(
          //       borderRadius: BorderRadius.circular(30.r),
          //     ),
          //   ),
          //   child: Text(
          //     'Browse Menu',
          //     style: TextStyle(fontSize: 14.sp),
          //   ),
          // ),
        ],
      ),
    );
  }
}
