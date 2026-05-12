import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../controller/table_controller.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;

  const TableCard({
    super.key,
    required this.table,
    required this.onTap,
  });

  Color _getCardColor(TableStatus status, AppColors colors) {
    if (colors.isDark) {
      switch (status) {
        case TableStatus.vacant:
          return colors.card;
        case TableStatus.partiallyOccupied:
          // Subtle green tint for dark mode
          return AppTheme.primaryGreen.withOpacity(0.12);
        case TableStatus.fullyOccupied:
          // Subtle red tint for dark mode
          return AppTheme.redColor.withOpacity(0.12);
      }
    } else {
      switch (status) {
        case TableStatus.vacant:
          return colors.card;
        case TableStatus.partiallyOccupied:
          return AppTheme.greenTransLight.withOpacity(0.5);
        case TableStatus.fullyOccupied:
          return AppTheme.redColor.withOpacity(0.1);
      }
    }
  }

  Color _getBorderColor(TableStatus status, AppColors colors) {
    switch (status) {
      case TableStatus.vacant:
        return colors.border;
      case TableStatus.partiallyOccupied:
        return AppTheme.primaryGreen;
      case TableStatus.fullyOccupied:
        return AppTheme.redColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = 1.0.obs;
    final controller = Get.find<TablesController>();
    final colors = AppColors.of(context);

    return GestureDetector(
      onTapDown: (_) => scale.value = 0.96,
      onTapCancel: () => scale.value = 1.0,
      onTapUp: (_) {
        scale.value = 1.0;
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Obx(() {
        // Calculate status based on actual occupied count from API data
        final occupiedCount = controller.getOccupiedCountForTable(table);
        final status = table.getStatus(occupiedCount);

        return AnimatedScale(
          scale: scale.value,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: _getCardColor(status, colors),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: _getBorderColor(status, colors),
                width: 1.w,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(colors.isDark ? 0.3 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                if (status != TableStatus.vacant)
                  BoxShadow(
                    color: _getBorderColor(status, colors).withOpacity(colors.isDark ? 0.15 : 0.2),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      table.name,
                      style: AppTypography.cardTitle.copyWith(color: colors.text),
                    ),
                    Text(
                      '${table.chairCount} Chairs',
                      style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                    ),
                  ],
                ),
                Icon(
                  Icons.table_restaurant_rounded,
                  size: AppTypography.iconXL,
                  color: _getBorderColor(status, colors).withOpacity(colors.isDark ? 0.4 : 0.6),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _getBorderColor(status, colors).withOpacity(colors.isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    status == TableStatus.vacant
                        ? 'Vacant'
                        : status == TableStatus.fullyOccupied
                        ? 'Occupied'
                        : '$occupiedCount / ${table.chairCount} Seats',
                    style: AppTypography.cardInfo.copyWith(
                      color: _getBorderColor(status, colors),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
