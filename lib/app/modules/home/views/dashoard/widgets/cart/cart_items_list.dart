import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../../cart/controller/cart_controller.dart';
import '../../../../../cart/views/widgets/quantity_dialog.dart';
import '../../../../controller/dashboard_controller.dart';

class CartItemList extends StatelessWidget {
  final CartController controller;

  const CartItemList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final visibleItems = controller.cartItems.where((item) => !item.isDeleted.value).toList();

      return ListView.builder(
        padding: EdgeInsets.all(2.w),
        itemCount: visibleItems.length,
        itemBuilder: (context, index) {
          final cartItem = visibleItems[index];
          return _AnimatedCartItem(
            key: ValueKey("${cartItem.product.id}_${cartItem.unit.unitId}_${cartItem.subId ?? index}"),
            cartItem: cartItem,
            onDelete: () => controller.removeItem(cartItem),
            controller: controller,
          );
        },
      );
    });
  }
}

class _AnimatedCartItem extends StatefulWidget {
  final CartItem cartItem;
  final VoidCallback onDelete;
  final CartController controller;

  const _AnimatedCartItem({
    required Key key,
    required this.cartItem,
    required this.onDelete,
    required this.controller,
  }) : super(key: key);

  @override
  State<_AnimatedCartItem> createState() => _AnimatedCartItemState();
}

class _AnimatedCartItemState extends State<_AnimatedCartItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _slideAnimation = Tween<double>(begin: 0.0, end: 100.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    await _animationController.forward();
    widget.onDelete();
    if (mounted) {
      _animationController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(_slideAnimation.value, 0),
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          ),
        );
      },
      child: cartItemWidget(),
    );
  }

  Widget cartItemWidget() {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () {
        final dashboardController = Get.find<DashboardController>();
        dashboardController.onProductTapped(widget.cartItem.product, existingItem: widget.cartItem);
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 1.h),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8.r),
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
            Row(
              children: [
                productImage(),
                SizedBox(width: 2.w),
                productDetails(),
                quantityControls(),
                SizedBox(width: 2.w),
                deleteButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget productImage() {
    final colors = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: widget.cartItem.product.image.isNotEmpty
          ? CachedNetworkImage(
        imageUrl: widget.cartItem.product.image,
        width: 12.w,
        height: 12.w,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: colors.textField,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 1)),
        ),
        errorWidget: (context, url, error) => paceHolder(),
      )
          : paceHolder(),
    );
  }

  Widget productDetails() {
    final colors = AppColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.cartItem.product.name,
            style: AppTypography.cardTitle.copyWith(
              fontSize: 4.sp,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 0.5.h),
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  widget.cartItem.unit.unitDisplay,
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 2.5.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 2.w),
              Obx(() => Text(
                '${widget.cartItem.subtotalWithTax.toStringAsFixed(2)}',
                style: AppTypography.cardSubtitle.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 3.sp,
                ),
              )),
            ],
          ),
          if (widget.cartItem.selectedAddons.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Obx(() {
                final addons = widget.cartItem.selectedAddons
                    .where((a) => a.quantity.value > 0)
                    .map((a) => "${a.name} x${a.quantity.value}")
                    .toList();

                if (addons.isEmpty) return const SizedBox.shrink();

                return Text(
                  addons.join(", "),
                  style: TextStyle(
                    fontSize: 2.5.sp,
                    color: colors.subtext,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget quantityControls() {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.textField,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          quantityButton(
            icon: Icons.remove,
            onPressed: () =>
                widget.controller.decreaseQuantity(widget.cartItem),
            color: colors.subtext,
          ),
          InkWell(
            onTap: () => QuantityDialog.show(widget.cartItem, widget.controller),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: Obx(() => Text(
                '${widget.cartItem.quantity.value}',
                style: AppTypography.cardSubtitle.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 4.sp,
                    color: colors.text),
              )),
            ),
          ),
          quantityButton(
            icon: Icons.add,
            onPressed: () =>
                widget.controller.updateQuantity(widget.cartItem, widget.cartItem.quantity.value + 1),
            color: AppTheme.primaryGreen,
          ),
        ],
      ),
    );
  }

  Widget deleteButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Colors.red.shade400,
          size: 6.sp,
        ),
        onPressed: _handleDelete,
        constraints: const BoxConstraints(),
        padding: EdgeInsets.all(2.w),
      ),
    );
  }

  Widget quantityButton({
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
          padding: EdgeInsets.all(3.w),
          child: Icon(
            icon,
            size: 4.sp,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget paceHolder() {
    final colors = AppColors.of(context);
    return Container(
      width: 12.w,
      height: 12.w,
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
        size: 10.sp,
      ),
    );
  }
}
