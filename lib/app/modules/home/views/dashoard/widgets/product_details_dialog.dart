import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_navigation/src/snackbar/snackbar.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../../../widgets/reusable_button.dart';
import '../../../../cart/controller/cart_controller.dart';
import '../../../controller/dashboard_controller.dart';
import '../models/dashboard_models.dart';

class ProductDetailsDialog extends GetView<DashboardController> {
  final FoodItemModel product;
  final CartItem? existingItem;

  const ProductDetailsDialog({super.key, required this.product, this.existingItem});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AlertDialog(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withOpacity(0.1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                existingItem != null ? "Edit ${product.name}" : product.name,
                style: AppTypography.cardTitle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: colors.text),
              onPressed: () => Get.back(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: AppTypography.sizeDialogue,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Units Selection
              Text(
                'Select Unit',
                style: AppTypography.cardSubtitle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
              SizedBox(height: 5.h),
              Obx(() => Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: controller.productUnits.map((unit) {
                  final isSelected = controller.selectedUnit.value?.unitId == unit.unitId;

                  // Calculate display price based on vatType
                  double displayPrice = unit.rate;
                  if (controller.vatType.value == 1) {
                    displayPrice = unit.rate + (unit.rate * product.prd_tax / 100);
                  }

                  return ChoiceChip(
                    label: Text(unit.unitName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        controller.selectedUnit.value = unit;
                        debugPrint("Selected Unit: ${unit.unitName}");
                        debugPrint("Base Qty: ${unit.unitBaseQty}");
                      }
                    },
                    selectedColor: AppTheme.primaryGreen,
                    backgroundColor: colors.textField,
                    checkmarkColor: Colors.white,
                    labelStyle: AppTypography.cardTitle.copyWith(
                      color: isSelected ? Colors.white : colors.text,
                      fontSize: AppTypography.smallText,
                    ),
                  );
                }).toList(),
              )),
              Divider(height: 16, color: colors.border),
              Obx(() {
                final addons = (controller.selectedUnit.value?.existAddOns ?? [])
                    .where((addon) => addon.prdaddon_flags == 1)
                    .toList();

                final common = controller.commonAddons
                    .where((addon) => addon.prdaddon_flags == 1)
                    .toList();

                if (addons.isEmpty && common.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add-ons',
                        style: AppTypography.cardSubtitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        'No add-ons available',
                        style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (addons.isNotEmpty) ...[
                      Text(
                        'Add-ons',
                        style: AppTypography.cardSubtitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      ...addons.map((addon) => _buildAddonQuantityItem(addon, colors)),
                    ],
                    if (common.isNotEmpty) ...[
                      if (addons.isNotEmpty) Divider(height: 12, color: colors.border),
                      Text(
                        'Paid add ons',
                        style: AppTypography.cardSubtitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      ...common.map((addon) => _buildAddonQuantityItem(addon, colors)),
                    ],
                  ],
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        PrimaryButton(
            text: existingItem != null ? 'Update Cart' : 'Add to Cart',
            onPressed: () {
              try {
                final selectedUnit = controller.selectedUnit.value;

                if (selectedUnit == null) {
                  Get.snackbar("Error", "Please select a unit", snackPosition: SnackPosition.BOTTOM);
                  return;
                }

                final selectedAddons = <AddonModel>[];
                final currentUnitAddons = controller.selectedUnit.value?.existAddOns ?? [];

                for (var a in currentUnitAddons) {
                  if (a.prdaddon_flags == 1 && a.quantity.value > 0) {
                    selectedAddons.add(
                      a.copyWith(quantityValue: a.quantity.value),
                    );
                  }
                }

                for (var a in controller.commonAddons) {
                  if (a.prdaddon_flags == 1 && a.quantity.value > 0) {
                    selectedAddons.add(
                      a.copyWith(quantityValue: a.quantity.value),
                    );
                  }
                }

                final cartController = controller.cartController;

                if (Get.isDialogOpen ?? false) {
                  Get.back();
                }

                if (existingItem != null) {
                  cartController.updateItemDetails(existingItem!, selectedUnit, selectedAddons);
                } else {
                  cartController.addItemWithDetails(product, selectedUnit, selectedAddons);
                }

              } catch (e) {
                debugPrint("Add to cart error: $e");
                Get.snackbar("Error", "Something went wrong", snackPosition: SnackPosition.BOTTOM);
              }
            }
        ),
      ],
    );
  }

  Widget _buildAddonQuantityItem(AddonModel addon, AppColors colors) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addon.name,
                  style: AppTypography.cardSubtitle.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text,
                  ),
                ),
                Obx(() {
                  double displayAddonPrice = addon.price;
                  if (controller.vatType.value == 1) {
                    displayAddonPrice = addon.price + (addon.price * addon.taxPer / 100);
                  }
                  return Text(
                    "+ ${displayAddonPrice.toStringAsFixed(2)} / ${addon.unitDisplay}",
                    style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                  );
                }),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.textField,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSmallQtyBtn(
                  icon: Icons.remove,
                  colors: colors,
                  onPressed: () {
                    if (addon.quantity.value > 0) addon.quantity.value--;
                  },
                ),
                Obx(() => Container(
                  width: 30.w, // Slightly wider for better centering
                  alignment: Alignment.center,
                  child: Text(
                    "${addon.quantity.value}",
                    style: AppTypography.cardTitle.copyWith(color: colors.text),
                  ),
                )),
                _buildSmallQtyBtn(
                  icon: Icons.add,
                  onPressed: () => addon.quantity.value++,
                  color: AppTheme.primaryGreen,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallQtyBtn({
    required IconData icon,
    required VoidCallback onPressed,
    required AppColors colors,
    Color? color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8.r),
      child: Padding(
        padding: EdgeInsets.all(8.r),
        child: Icon(
          icon,
          size: AppTypography.sizeCategory,
          color: color ?? colors.subtext,
        ),
      ),
    );
  }
}
