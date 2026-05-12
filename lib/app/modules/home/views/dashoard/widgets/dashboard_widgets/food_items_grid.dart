import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';

import '../../../../controller/dashboard_controller.dart';
import 'food_item_card.dart';
import 'food_item_shimmer.dart';

class FoodItemsGrid extends GetView<DashboardController> {
  const FoodItemsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DashboardController());
    return Obx(() {
      // Show initial shimmer if loading first batch
      if (controller.isLoadingProducts.value && controller.filteredFoodItems.isEmpty) {
        return const FoodItemShimmer();
      }

      if (controller.filteredFoodItems.isEmpty && !controller.isLoadingProducts.value) {
        return const Center(child: Text('No items in this category.'));
      }

      return Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(4.w),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180.0,
                mainAxisSpacing: 16,
                crossAxisSpacing: 4,
                childAspectRatio: 0.9,
              ),
              itemCount: controller.filteredFoodItems.length,
              itemBuilder: (context, index) {
                final item = controller.filteredFoodItems[index];

                return TweenAnimationBuilder(
                  duration: Duration(milliseconds: 300 + (index % 20 * 60)), // Reset delay for each batch
                  tween: Tween<double>(begin: 0, end: 1),
                  curve: Curves.easeOut,
                  builder: (context, double value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.95 + (value * 0.05),
                        child: child,
                      ),
                    );
                  },
                  child: FoodItemCard(
                    item: item,
                    onTap: () {
                      print(item.id);
                      controller.onProductTapped(item);
                    } ,
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
