import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:restaurant_pos/helper/screen_type.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../controller/table_controller.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;

  const TableCard({super.key, required this.table, required this.onTap});

  // ── Colors by status ───────────────────────────────────────────────────

  Color _accentColor(TableStatus status) {
    switch (status) {
      case TableStatus.vacant:
        return const Color(0xFF3B5BDB); // indigo
      case TableStatus.partiallyOccupied:
        return AppTheme.primaryGreen;
      case TableStatus.fullyOccupied:
        return AppTheme.redColor;
    }
  }

  Color _cardBg(TableStatus status, AppColors colors) {
    if (colors.isDark) {
      switch (status) {
        case TableStatus.vacant:
          return colors.card;
        case TableStatus.partiallyOccupied:
          return AppTheme.primaryGreen.withOpacity(.1);
        case TableStatus.fullyOccupied:
          return AppTheme.redColor.withOpacity(.1);
      }
    }
    switch (status) {
      case TableStatus.vacant:
        return colors.card;
      case TableStatus.partiallyOccupied:
        return AppTheme.greenTransLight.withOpacity(.35);
      case TableStatus.fullyOccupied:
        return AppTheme.redColor.withOpacity(.06);
    }
  }

  String _statusLabel(TableStatus status, int occupied, int total) {
    switch (status) {
      case TableStatus.vacant:
        return 'Vacant';
      case TableStatus.partiallyOccupied:
        return '$occupied / $total Seats';
      case TableStatus.fullyOccupied:
        return 'Full';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = 1.0.obs;
    final controller = Get.find<TablesController>();
    final colors = AppColors.of(context);

    return GestureDetector(
      onTapDown: (_) => scale.value = 0.95,
      onTapCancel: () => scale.value = 1.0,
      onTapUp: (_) {
        scale.value = 1.0;
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Obx(() {
        final occupied = controller.getOccupiedCountForTable(table);
        final status = table.getStatus(occupied);
        final accent = _accentColor(status);
        final fillPct =
        table.chairCount > 0 ? occupied / table.chairCount : 0.0;

        return AnimatedScale(
          scale: scale.value,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              color: _cardBg(status, colors),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color: status == TableStatus.vacant
                    ? colors.border
                    : accent.withOpacity(.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(colors.isDark ? .25 : .04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Top accent bar ──
                Container(
                  height: 3.5.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18.r),
                    ),
                    color: accent.withOpacity(
                        status == TableStatus.vacant ? .3 : .85),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(ScreenType.isMobile() ? 14.w : 10.w, 12.h, ScreenType.isMobile() ? 14.w : 10.w, 12.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ── Name + table number ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  table.name,
                                  style: AppTypography.cardTitle
                                      .copyWith(color: colors.text),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  '${table.chairCount} chairs',
                                  style: AppTypography.cardSubtitle
                                      .copyWith(color: colors.subtext),
                                ),
                              ],
                            ),
                            // Subtle large table number
                            Text(
                              table.name.replaceAll(RegExp(r'[^0-9]'), '')
                                  .padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: AppTypography.sizeTable,
                                fontWeight: FontWeight.w800,
                                color: accent.withOpacity(
                                    status == TableStatus.vacant ? .15 : .25),
                                letterSpacing: -1,
                              ),
                            ),
                          ],
                        ),

                        // ── Table icon ──
                        Center(
                          child: Icon(
                            Icons.table_restaurant_rounded,
                            size: AppTypography.iconXL,
                            color: accent.withOpacity(
                                colors.isDark ? .35 : .55),
                          ),
                        ),

                        // ── Status badge + fill bar ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withOpacity(
                                        colors.isDark ? .2 : .1),
                                    borderRadius: BorderRadius.circular(20.r),
                                  ),
                                  child: Text(
                                    _statusLabel(
                                        status, occupied, table.chairCount),
                                    style: AppTypography.cardInfo.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (status != TableStatus.vacant)
                                  Text(
                                    '${(fillPct * 100).round()}%',
                                    style: AppTypography.cardSubtitle.copyWith(
                                      color: colors.subtext,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 6.h),
                            // Seat fill bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4.r),
                              child: LinearProgressIndicator(
                                value: fillPct,
                                minHeight: 3.5.h,
                                backgroundColor: colors.border,
                                valueColor:
                                AlwaysStoppedAnimation<Color>(accent),
                              ),
                            ),
                          ],
                        ),
                      ],
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