import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../controller/printer_controller.dart';

class PrinterStatusCard extends StatelessWidget {
  final PrinterController controller;

  const PrinterStatusCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final total =
          controller.bluetoothPrinters.length + controller.wifiPrinters.length;
      return Container(
        width: double.infinity,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'available_printers'.tr,
              style: AppTypography.cardTitle.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12.h),
            _buildPrinterStatusRow(
              'bluetooth'.tr,
              controller.bluetoothPrinters.length,
              Colors.blue,
            ),
            SizedBox(height: 8.h),
            _buildPrinterStatusRow(
              'wifi'.tr,
              controller.wifiPrinters.length,
              Colors.orange,
            ),
            if (total == 0 &&
                (controller.scanningBluetooth.value ||
                    controller.scanningWifi.value))
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(color: AppTheme.primaryGreen),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildPrinterStatusRow(String label, int count, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.cardSubtitle.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Text(
            'n_found'.trParams({'count': count.toString()}),
            style: TextStyle(
              color: color,
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
