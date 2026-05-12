import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import '../../../../../theme/app_theme.dart';
import '../../../../cart/controller/cart_controller.dart';
import 'cart/cart_header.dart';
import 'cart/cart_items_list.dart';
import 'cart/cart_summary.dart';
import 'cart/empty_cart_view.dart';

class CartPanel extends GetView<CartController> {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          CartHeader(controller: controller),
          Expanded(
            child: Obx(() {
              if (controller.cartItems.isEmpty) {
                return const EmptyCartView();
              }
              return CartItemList(controller: controller);
            }),
          ),
          CartSummary(controller: controller),
        ],
      ),
    );
  }
}