import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';

class EmptyCartView extends StatelessWidget {
  const EmptyCartView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: colors.textField,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.border,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 10.sp,
              color: colors.subtext.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'empty_cart'.tr,
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}
