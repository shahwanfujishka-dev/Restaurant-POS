import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:restaurant_pos/app/modules/cart/views/widgets/mobile_cart_header.dart';
import 'package:restaurant_pos/app/modules/cart/views/widgets/mobile_cart_item_list.dart';
import 'package:restaurant_pos/app/modules/cart/views/widgets/mobile_cart_summary.dart';
import 'package:restaurant_pos/app/modules/cart/views/widgets/mobile_empty_cart_view.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../controller/cart_controller.dart';

class CartView extends GetView<CartController> {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          'my_cart'.tr,
          style: AppTypography.appBarTitle.copyWith(
            color: colors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colors.card,
        elevation: 0.5,
        leading: Container(
          margin: EdgeInsets.only(left: 8.w),
          decoration: BoxDecoration(
            color: colors.textField,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: colors.text),
            onPressed: () => Get.back(),
          ),
        ),
        actions: [
          Obx(() => controller.cartItems.isNotEmpty
              ? Container(
            margin: EdgeInsets.only(right: 8.w),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () {
                Get.defaultDialog(
                  backgroundColor: colors.card,
                  title: "Clear Cart",
                  titleStyle: AppTypography.cardTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16.sp,
                    color: colors.text,
                  ),
                  middleText: "Remove all items from your cart?",
                  middleTextStyle: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
                  radius: 16.r,
                  textConfirm: "Clear All",
                  textCancel: "Cancel",
                  confirmTextColor: Colors.white,
                  buttonColor: Colors.red,
                  cancelTextColor: colors.subtext,
                  onConfirm: () {
                    controller.clearCart();
                    Get.back();
                  },
                );
              },
            ),
          )
              : const SizedBox.shrink()),
        ],
      ),
      body: Column(
        children: [
          MobileCartHeader(controller: controller),
          Expanded(
            child: Obx(() {
              if (controller.cartItems.isEmpty) {
                return const MobileEmptyCartView();
              }
              return MobileCartItemList(controller: controller);
            }),
          ),
          SizedBox(height: MediaQuery.of(context).size.height*0.38,)
        ],
      ),
      bottomSheet: MobileCartSummary(controller: controller),
    );
  }
}
