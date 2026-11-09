import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart'hide ScreenType;
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
                  'no_tables_found'.tr,
                  style: AppTypography.cardTitle.copyWith(color: colors.text),
                ),
                SizedBox(height: 6.h),
                Text(
                  'pull_to_refresh_or_retry'.tr,
                  style: AppTypography.cardSubtitle.copyWith(
                    color: colors.subtext,
                  ),
                ),
                SizedBox(height: 20.h),
                GestureDetector(
                  onTap: controller.fetchTables,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 12.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(50.r),
                    ),
                    child: Text(
                      'retry'.tr,
                      style: AppTypography.button.copyWith(
                        fontSize: AppTypography.sizeCategory,
                      ),
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
                if (tables.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.table_restaurant_rounded,
                          size: AppTypography.iconLarge,
                          color: colors.subtext,
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'no_tables_found'.tr,
                          style: AppTypography.cardTitle.copyWith(
                            color: colors.subtext,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: ScreenType.isMobile() ? 200.w : 70.w,
                    mainAxisSpacing: 12.h,
                    crossAxisSpacing: ScreenType.isMobile() ? 12.w : 10.h,
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

class _AreaHeader extends GetView<TablesController> {
  const _AreaHeader();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.border, width: .5)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 52.h,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
              itemCount: controller.areas.length,
              itemBuilder: (context, index) {
                final area = controller.areas[index];

                return Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: Obx(() {
                    final isSelected =
                        controller.selectedArea.value?.id == area.id;

                    return GestureDetector(
                      onTap: () => controller.selectArea(area),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryGreen : colors.bg,
                          borderRadius: BorderRadius.circular(50.r),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : colors.border,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: _AreaNameDisplay(
                          name: area.name.tr,
                          isSelected: isSelected,
                          textColor: isSelected ? Colors.white : colors.subtext,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          ),
          // ── Stats summary row ──
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
                    label: '$vacant ${'vacant'.tr}',
                    dot: const Color(0xFF3B5BDB),
                    bg: const Color(0xFF3B5BDB).withOpacity(.1),
                  ),
                  SizedBox(width: 8.w),
                  _StatPill(
                    label: '$partial ${'partial'.tr}',
                    dot: AppTheme.primaryGreen,
                    bg: AppTheme.primaryGreen.withOpacity(.1),
                  ),
                  SizedBox(width: 8.w),
                  _StatPill(
                    label: '$full ${'occupied'.tr}',
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

class _AreaNameDisplay extends StatefulWidget {
  const _AreaNameDisplay({
    required this.name,
    required this.isSelected,
    required this.textColor,
  });

  final String name;
  final bool isSelected;
  final Color textColor;

  @override
  State<_AreaNameDisplay> createState() => _AreaNameDisplayState();
}

class _AreaNameDisplayState extends State<_AreaNameDisplay> {
  final ScrollController _scrollController = ScrollController();
  bool _isActive = true;

  bool get _isLongName => widget.name.length > 25;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollName());
  }

  @override
  void didUpdateWidget(covariant _AreaNameDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isActive && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  Future<void> _scrollName() async {
    while (_isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!_isActive || !_isLongName || !_scrollController.hasClients) {
        continue;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) continue;

      await _scrollController.animateTo(
        maxExtent,
        duration: Duration(
          milliseconds: (maxExtent * 90).round().clamp(1500, 10000).toInt(),
        ),
        curve: Curves.linear,
      );
      if (!_isActive || !_scrollController.hasClients) continue;

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (_isActive && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _isActive = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTypography.cardSubtitle.copyWith(
      color: _isLongName ? AppTheme.primaryGreen : widget.textColor,
      fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
      fontFamily: _isLongName ? 'monospace' : null,
      letterSpacing: _isLongName ? 0.8 : null,
    );

    if (!_isLongName) {
      return Text(widget.name, style: textStyle);
    }

    return Container(
      width: 90.w,
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.88),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(0.12),
            blurRadius: 5,
          ),
        ],
      ),
      child: IgnorePointer(
        child: ClipRect(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(
              widget.name,
              maxLines: 1,
              softWrap: false,
              style: textStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color dot;
  final Color bg;

  const _StatPill({required this.label, required this.dot, required this.bg});

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
