import 'package:get/get.dart';

import '../../../helper/network_helper.dart';
import '../../../helper/snackbar_helper.dart';
import '../../modules/cart/controller/cart_controller.dart';
import '../Device_Roles/device_roles.dart';
import 'local_hub_client.dart';

typedef SaveOrder =
    Future<Map<String, dynamic>?> Function({
      bool isDraft,
      int? payType,
      double? cashAmt,
      double? cardAmt,
      int? cashLedgerId,
      int? bankLedgerId,
      bool isCompliment,
      double discountAmount,
      double roundOffAmount,
      Map<String, dynamic>? customerData,
      String? customerName,
      String? customerMobile,
      String? customerAddress,
      bool? registerCustEnabled,
      String? customerVat,
      bool isSplit,
      int? splitCount,
      bool isBill,
      List<double> splitAmounts,
      bool printBill,
      Future<bool> Function(Map<String, dynamic>)? printPayment,
    });

class OrderSubmission {
  const OrderSubmission(this.cart);

  final CartController cart;

  bool tryBegin() {
    if (cart.isProcessing.value) return false;
    cart.isProcessing.value = true;
    return true;
  }

  void finish() => cart.isProcessing.value = false;

  SaveOrder get save => cart.isEditing ? cart.updateOrder : cart.placeOrder;

  Future<bool> checkReady({bool validateClient = false}) async {
    if (DeviceConfig.isOnline && !await NetworkHelper.hasInternetConnection()) {
      showSafeSnackbar('no_internet'.tr, 'check_network_msg'.tr);
      return false;
    }
    if (!validateClient || !cart.isLocalHubClient) return true;

    final ip = DeviceConfig.hostIp;
    if (ip == null || ip.trim().isEmpty) {
      showSafeSnackbar('main_cashier_not_set'.tr, 'main_cashier_ip_hint'.tr);
      return false;
    }

    if (!DeviceConfig.hasAuthToken) {
      showSafeSnackbar('device_not_registered'.tr, 'connect_to_hub_msg'.tr);
      return false;
    }

    try {
      await LocalHubClient.instance
          .testConnection(hostIp: ip, port: DeviceConfig.hostPort)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Warn but allow: placeOrder saves locally and SyncService retries later
      showSafeSnackbar('hub_unreachable'.tr, 'offline_save_msg'.tr);
    }
    return true;
  }
}
