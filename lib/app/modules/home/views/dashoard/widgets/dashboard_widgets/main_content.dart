import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';

import '../../../../../../../helper/screen_type.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../controller/dashboard_controller.dart';
import '../../../../controller/home_controller.dart';
import '../../models/dashboard_models.dart';
import 'category_chip.dart';
import 'category_shimmer.dart';
import 'food_items_grid.dart';

class MainContent extends GetView<DashboardController> {
  const MainContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          ScreenType.isMobile()
              ? _buildMobileLayout(context)
              : _buildTabletLayout(context),
          // 🔹 Loading Overlay
          Obx(() => controller.isLoadingDetails.value
              ? Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          )
              : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final cartController = Get.find<CartController>();
    final colors = AppColors.of(context);
    return Column(
      children: [
        Obx(() {
          return GestureDetector(
            onTap: () => Get.find<HomeController>().changeIndex(1),
            child: cartController.hasSelectedTable
                ? Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
              decoration: BoxDecoration(
                color: cartController.isEditing
                    ? Colors.blue.withOpacity(0.1)
                    : AppTheme.primaryGreen.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                      color: cartController.isEditing
                          ? Colors.blue.withOpacity(0.2)
                          : AppTheme.primaryGreen.withOpacity(0.2)
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                      Icons.table_restaurant,
                      color: cartController.isEditing ? Colors.blue : AppTheme.primaryGreen,
                      size: 22.sp
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (cartController.isEditing)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                margin: EdgeInsets.only(right: 8.w),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Text(
                                  "EDITING #${cartController.editingOrderId.value}",
                                  style: TextStyle(color: Colors.white, fontSize: 8.sp, fontWeight: FontWeight.bold),
                                ),
                              ),
                            Text(
                              "(${cartController.selectedAreaName.value})",
                              style: AppTypography.cardSubtitle.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cartController.isEditing ? Colors.blue : AppTheme.primaryGreen,
                                fontSize: 10.sp,
                              ),
                            ),
                            Text(
                              ' - ${cartController.selectedTableName.value}',
                              style: AppTypography.cardSubtitle.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cartController.isEditing ? Colors.blue : AppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Chair ${cartController.selectedChairCount.value}',
                          style: AppTypography.cardSubtitle.copyWith(
                            fontSize: 11.sp,
                            color: colors.subtext,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cartController.isEditing)
                    TextButton(
                      onPressed: () => cartController.stopEditing(),
                      child: const Text("Cancel", style: TextStyle(color: Colors.red)),
                    )
                  else ...[
                    Text(
                      'Change',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.primaryGreen, size: 18.sp),
                  ]
                ],
              ),
            )
                : const SizedBox.shrink(),
          );
        }),
        _buildSearchBar(context),
        _buildCategoryList(Axis.horizontal, context),
        const Expanded(child: FoodItemsGrid()),
      ],
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(context),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCategoryList(Axis.vertical, context),
              const Expanded(child: FoodItemsGrid()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: colors.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller.searchController,
              onChanged: (value) => controller.updateSearch(value),
              style: TextStyle(color: colors.text),
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: TextStyle(color: colors.subtext, fontSize: AppTypography.smallText),
                prefixIcon: Icon(Icons.search, color: AppTheme.primaryGreen, size: AppTypography.sizeTable),
                suffixIcon: Obx(() => controller.searchKeyword.value.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, color: colors.subtext),
                  onPressed: () {
                    controller.searchController.clear();
                    controller.updateSearch('');
                  },
                )
                    : const SizedBox.shrink()),
                filled: true,
                fillColor: colors.textField,
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16.w),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppTheme.primaryGreen, width: 1),
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          _buildFavoriteDropdown(context),
          SizedBox(width: 8.w),
          _buildRefreshButton(context),
        ],
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: 40.h,
      width: 40.w,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.1),
        ),
      ),
      child: IconButton(
        icon: Icon(Icons.refresh, color: AppTheme.primaryGreen, size: AppTypography.sizeTable),
        onPressed: () => controller.refreshDashboard(),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildFavoriteDropdown(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      if (controller.isLoadingFavorites.value) {
        return Container(
          width: 40.w,
          height: ScreenType.isMobile() ? 40.h : 12.h,
          padding: EdgeInsets.all(10.r),
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      }

      if (controller.favorites.isEmpty && !controller.isLoadingFavorites.value) {
        return const SizedBox.shrink();
      }

      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        height: 40.h,
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: controller.selectedFavoriteId.value != null
                ? AppTheme.primaryGreen
                : AppTheme.primaryGreen.withOpacity(0.1),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            dropdownColor: colors.card,
            value: controller.selectedFavoriteId.value,
            icon: Icon(
                Icons.favorite_rounded,
                color: controller.selectedFavoriteId.value != null ? AppTheme.primaryGreen : colors.subtext,
                size: AppTypography.sizeText
            ),
            hint: Text(
              "FAV",
              style: TextStyle(
                color: colors.subtext,
                fontSize: AppTypography.smallText,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: AppTypography.cardSubtitle.copyWith(
              color: AppTheme.primaryGreen,
              fontWeight: FontWeight.bold,
            ),
            onChanged: (int? newValue) {
              controller.setFavorite(newValue);
            },
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: Text("ALL", style: TextStyle(color: colors.text)),
                ),
              ),
              ...controller.favorites.map<DropdownMenuItem<int?>>((FavoriteModel fav) {
                return DropdownMenuItem<int?>(
                  value: fav.id,
                  child: Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: Text(fav.name.toUpperCase(), style: TextStyle(color: colors.text)),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCategoryList(Axis direction, BuildContext context) {
    bool isHorizontal = direction == Axis.horizontal;
    final colors = AppColors.of(context);

    return Obx(() {
      // Hide categories when a Favorite filter is active
      if (controller.selectedFavoriteId.value != null) {
        return const SizedBox.shrink();
      }

      if (controller.isLoadingCategories.value && controller.categories.isEmpty) {
        return CategoryShimmer(direction: direction);
      }

      if (controller.categories.isEmpty) {
        return Container(
          width: isHorizontal ? double.infinity : 40.w,
          height: isHorizontal ? 45.h : double.infinity,
          color: colors.bg,
          child: Center(child: Text("No categories", style: TextStyle(color: colors.subtext))),
        );
      }

      return Container(
        color: colors.bg,
        padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: isHorizontal ? 10.w : 1.w),
        width: isHorizontal ? null : 40.w,
        height: isHorizontal ? 45.h : null,
        child: ListView.separated(
          key: ValueKey(direction), // Add key to prevent layout issues
          controller: controller.categoryScrollController,
          scrollDirection: direction,
          itemCount: controller.categories.length + (controller.isMoreLoadingCategories.value ? 1 : 0),
          separatorBuilder: (_, __) => isHorizontal ? SizedBox(width: 5.w) : SizedBox(height: 5.h),
          itemBuilder: (context, index) {
            if (index == controller.categories.length) {
              return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final category = controller.categories[index];

            return Obx(() => CategoryChip(
              label: category.name,
              isSelected: controller.selectedCategoryId.value == category.id,
              onTap: () => controller.selectCategory(category.id),
            ));
          },
        ),
      );
    });
  }
}
