import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:restaurant_pos/app/modules/home/views/tables/widgets/table_card.dart';
import 'package:restaurant_pos/app/modules/home/views/tables/widgets/table_shimmer.dart';
import 'package:restaurant_pos/helper/screen_type.dart';

import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/table_controller.dart';

class TablesPage extends GetView<TablesController> {
  const TablesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: Obx(() {
        if (controller.isLoading.value) return const TableShimmer();

        if (controller.areas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72.w,
                  height: 72.w,
                  decoration: BoxDecoration(
                    color: colors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.table_restaurant_rounded,
                    size: AppTypography.iconLarge,
                    color: colors.subtext,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'No tables found',
                  style: AppTypography.cardTitle.copyWith(color: colors.text),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Pull down to refresh or tap retry',
                  style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                ),
                SizedBox(height: 20.h),
                GestureDetector(
                  onTap: controller.fetchTables,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(50.r),
                    ),
                    child: Text(
                      'Retry',
                      style: AppTypography.button.copyWith(fontSize: AppTypography.sizeCategory),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // ── Header: area chips + stats summary ──
            const _AreaHeader(),

            // ── Table grid ──
            Expanded(
              child: Obx(() {
                final tables = controller.selectedArea.value?.tables ?? [];
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: ScreenType.isMobile() ? 200.w : 70.w,
                    mainAxisSpacing: 12.h,
                    crossAxisSpacing: ScreenType.isMobile() ?12.w : 10.h,
                    childAspectRatio: .92,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(table.id),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 280 + index * 40),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - v)),
                          child: child,
                        ),
                      ),
                      child: TableCard(
                        table: table,
                        onTap: () => controller.selectTable(table),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        );
      }),
    );
  }
}

// ── Area header with chips and live stats row ──────────────────────────────
// NOTE: colors is resolved inside build() — NOT passed from the parent —
// so dark-mode rebuilds and reactive Obx updates always see fresh values.

class _AreaHeader extends GetView<TablesController> {
  const _AreaHeader();

  @override
  Widget build(BuildContext context) {
    // Resolve colors here so every rebuild (theme change, Obx tick) is fresh.
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.border, width: .5)),
      ),
      child: Column(
        children: [
          // ── Area chips ──
          // Each chip wraps its own Obx so it independently subscribes to
          // selectedArea. The outer ListView has NO Obx — it only rebuilds
          // when the areas list itself changes. This is the correct pattern:
          // one reactive scope per chip, not one scope for the whole list.
          SizedBox(
            height: 52.h,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              itemCount: controller.areas.length,
              itemBuilder: (context, index) {
                final area = controller.areas[index];

                return Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  // Per-chip Obx: this chip rebuilds whenever selectedArea
                  // changes, regardless of ListView item-caching behaviour.
                  child: Obx(() {
                    final isSelected =
                        controller.selectedArea.value?.id == area.id;

                    return GestureDetector(
                      onTap: () => controller.selectArea(area),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : colors.bg,
                          borderRadius: BorderRadius.circular(50.r),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : colors.border,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          area.name,
                          style: AppTypography.cardSubtitle.copyWith(
                            color:
                            isSelected ? Colors.white : colors.subtext,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          // ── Stats summary row ──
          // Single Obx reads selectedArea so it rebuilds on every area switch.
          Obx(() {
            final tables = controller.selectedArea.value?.tables ?? [];
            int vacant = 0, partial = 0, full = 0;
            for (final t in tables) {
              final occ = controller.getOccupiedCountForTable(t);
              switch (t.getStatus(occ)) {
                case TableStatus.vacant:
                  vacant++;
                case TableStatus.partiallyOccupied:
                  partial++;
                case TableStatus.fullyOccupied:
                  full++;
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: Row(
                children: [
                  _StatPill(
                    label: '$vacant Vacant',
                    dot: const Color(0xFF3B5BDB),
                    bg: const Color(0xFF3B5BDB).withOpacity(.1),
                  ),
                  SizedBox(width: 8.w),
                  _StatPill(
                    label: '$partial Partial',
                    dot: AppTheme.primaryGreen,
                    bg: AppTheme.primaryGreen.withOpacity(.1),
                  ),
                  SizedBox(width: 8.w),
                  _StatPill(
                    label: '$full Occupied',
                    dot: AppTheme.redColor,
                    bg: AppTheme.redColor.withOpacity(.1),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color dot;
  final Color bg;

  const _StatPill({
    required this.label,
    required this.dot,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7.r,
            height: 7.r,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: 6.w),
          Text(
            label,
            style: AppTypography.cardSubtitle.copyWith(
              color: dot,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}