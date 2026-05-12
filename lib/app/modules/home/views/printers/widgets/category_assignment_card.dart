import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_navigation/src/root/parse_route.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../controller/printer_controller.dart';
import '../../dashoard/models/dashboard_models.dart';

class CategoryAssignmentCard extends StatelessWidget {
  final CategoryModel category;
  final PrinterController controller;

  const CategoryAssignmentCard({
    super.key,
    required this.category,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18.r,
            backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
            child: Text(
              category.name.isNotEmpty ? category.name[0] : "?",
              style: const TextStyle(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: AppTypography.cardTitle.copyWith(fontSize: 14.sp),
                ),
                Text(
                  "Token ID: ${category.tokenPrinterId}",
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Obx(() {
            final assignment = controller.tokenPrinterAssignments
                .firstWhereOrNull((a) => a.tokenPrinterId == category.tokenPrinterId);

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: assignment != null ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                assignment != null ? assignment.printerName.value : "Not Assigned",
                style: TextStyle(
                  fontSize: 12.sp,
                  color: assignment != null ? AppTheme.primaryGreen : Colors.grey,
                  fontWeight: assignment != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
