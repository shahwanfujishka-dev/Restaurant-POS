import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:restaurant_pos/app/modules/cart/views/widgets/quantity_dialog.dart';

import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../../home/controller/dashboard_controller.dart';
import '../../controller/cart_controller.dart';

class MobileCartItemList extends StatelessWidget {
  final CartController controller;

  const MobileCartItemList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      final visibleItems = controller.cartItems.where((item) => !item.isDeleted.value).toList();

      if (visibleItems.isEmpty) {
        return Center(
          child: Text(
            "Cart is empty",
            style: TextStyle(color: colors.subtext),
          ),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.all(10.w),
        itemCount: visibleItems.length,
        itemBuilder: (context, index) {
          final cartItem = visibleItems[index];
          return _buildCartItem(context, cartItem);
        },
      );
    });
  }

  Widget _buildCartItem(BuildContext context, CartItem cartItem) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () {
        final dashboardController = Get.find<DashboardController>();
        dashboardController.onProductTapped(cartItem.product, existingItem: cartItem);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 4.h),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(8.w),
              child: Row(
                children: [
                  // Product Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: cartItem.product.image.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: cartItem.product.image,
                      width: 60.w,
                      height: 60.w,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: colors.textField,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: (context, url, error) => _buildPlaceholder(context),
                    )
                        : _buildPlaceholder(context),
                  ),
                  SizedBox(width: 12.w),

                  // Product Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cartItem.product.name,
                          style: AppTypography.cardTitle.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.sp,
                            color: colors.text,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Display Unit
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            cartItem.unit.unitDisplay,
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Obx(() => Text(
                          '${cartItem.subtotalWithTax.toStringAsFixed(2)}',
                          style: AppTypography.cardSubtitle.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.sp,
                          ),
                        )),
                        if (cartItem.selectedAddons.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2.h),
                            child: Obx(() {
                              final addons = cartItem.selectedAddons
                                  .where((a) => a.quantity.value > 0)
                                  .map((a) => "${a.name} x${a.quantity.value}")
                                  .toList();

                              if (addons.isEmpty) return const SizedBox.shrink();

                              return Text(
                                addons.join(", "),
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: colors.subtext,
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            }),
                          ),
                      ],
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color: colors.textField,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: colors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildQuantityButton(
                          context,
                          icon: Icons.remove,
                          onPressed: () => controller.decreaseQuantity(cartItem),
                          color: colors.subtext,
                        ),
                        InkWell(
                          onTap: () => QuantityDialog.show(cartItem, controller),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            child: Obx(() => Text(
                              '${cartItem.quantity.value}',
                              style: AppTypography.cardTitle.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.sp,
                                color: colors.text,
                              ),
                            )),
                          ),
                        ),
                        _buildQuantityButton(
                          context,
                          icon: Icons.add,
                          onPressed: () {
                            controller.updateQuantity(cartItem, cartItem.quantity.value + 1);
                          },
                          color: AppTheme.primaryGreen,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),

                  // Delete Button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                        size: 20.sp,
                      ),
                      onPressed: () => controller.removeItem(cartItem),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.all(6.w),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          child: Icon(
            icon,
            size: 16.sp,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 60.w,
      height: 60.w,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.textField,
            colors.border,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Icon(
        Icons.restaurant_menu,
        color: colors.subtext,
        size: 24.sp,
      ),
    );
  }
}
