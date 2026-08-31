import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/models/order_type.dart';
import '../../../data/utils/AppState.dart';
import '../../../routes/app_pages.dart';
import '../../cart/controller/cart_controller.dart';
import '../../home/controller/home_controller.dart';

class OrderTypeController extends GetxController {
  // Global order type state
  final selectedType = Rxn<OrderType>();
  final isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    selectedType.value = AppState.orderType;
    isLoading.value = false;
  }

  @override
  void onReady() {
    super.onReady();
    // Ensure loading is false when the controller is ready to avoid stale shimmer
    isLoading.value = false;
  }

  Future<void> selectOrderType(OrderType type, {bool navigate = true}) async {
    if (isLoading.value) return;

    selectedType.value = type;
    AppState.orderType = type; 

    if (!navigate) {
       _handleHomeNavigation(type);
       return;
    }

    isLoading.value = true;

    // ✅ Crucial: Small delay to allow the UI to render the shimmer
    // BEFORE the main thread blocks while building the Home screen.
    await Future.delayed(const Duration(milliseconds: 150));

    if (Navigator.canPop(Get.context!)) {
      _handleHomeNavigation(type);
      Get.back();
    } else {
      Get.offAllNamed(Routes.HOME);
      _applyIndexWhenReady(type);
    }
    
    // Reset isLoading after navigation to ensure it's ready for the next time
    // the user opens the Order Type screen. We use a delay to ensure the
    // navigation transition is visually completed.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (Get.isRegistered<OrderTypeController>()) {
        isLoading.value = false;
      }
    });
  }

  void _applyIndexWhenReady(OrderType type) {
    if (Get.isRegistered<HomeController>()) {
      _handleHomeNavigation(type);
    } else {
      // Use a 100ms delay instead of zero to prevent event loop saturation
      Future.delayed(const Duration(milliseconds: 100), () => _applyIndexWhenReady(type));
    }
  }

  void _handleHomeNavigation(OrderType type) {
    try {
      if (Get.isRegistered<HomeController>() && Get.isRegistered<CartController>()) {
        final homeController = Get.find<HomeController>();
        final cart = Get.find<CartController>();
        
        // Treat empty or "0" as no table selected
        bool noTableSelected = cart.selectedTableId.isEmpty || cart.selectedTableId.value == "0";
        
        if (type == OrderType.dineIn && noTableSelected) {
          // Force navigate to Tables page (index 1) to pick a table
          homeController.changeIndex(1);
        } else {
          homeController.changeIndex(0);
        }
      }
    } catch (e) {
      debugPrint("Navigation adjustment error: $e");
    }
  }
}
