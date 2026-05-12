import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:restaurant_pos/app/modules/home/views/tables/widgets/table_card.dart';
import 'package:restaurant_pos/app/modules/home/views/tables/widgets/table_shimmer.dart';

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
        if (controller.isLoading.value) {
          return const TableShimmer();
        }

        if (controller.areas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_bar_outlined, size: AppTypography.foodIcon, color: colors.subtext),
                SizedBox(height: 10.h),
                Text('No tables found', style: AppTypography.cardSubtitle.copyWith(color: colors.subtext)),
                TextButton(
                  onPressed: () => controller.fetchTables(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              height: 60.h,
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                itemCount: controller.areas.length,
                itemBuilder: (context, index) {
                  final area = controller.areas[index];
                  final isSelected = controller.selectedArea.value?.id ==
                      area.id;

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    child: ChoiceChip(
                      label: Text(
                        area.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : colors.text,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight
                              .normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) controller.selectArea(area);
                      },
                      selectedColor: AppTheme.primaryGreen,
                      backgroundColor: colors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryGreen : colors.border,
                        ),
                      ),
                      showCheckmark: false,
                    ),
                  );
                },
              ),
            ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: GridView.builder(
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280.0,
                    mainAxisSpacing: 12.0,
                    crossAxisSpacing: 12.0,
                    childAspectRatio: 1,
                  ),
                  itemCount: controller.selectedArea.value?.tables.length ?? 0,
                  itemBuilder: (context, index) {
                    final table = controller.selectedArea.value!.tables[index];

                    return TweenAnimationBuilder(
                      key: ValueKey(table.id),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: Duration(milliseconds: 300 + (index * 30)),
                      curve: Curves.easeOut,
                      builder: (context, double value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: TableCard(
                        table: table,
                        onTap: () {
                          print(table.chairCount);
                          controller.selectTable(table);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}