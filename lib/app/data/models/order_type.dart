import 'package:get/get.dart';

enum OrderType {
  dineIn,
  delivery,
  pickUp;

  String get displayName {
    switch (this) {
      case OrderType.dineIn:
        return 'dine_in'.tr;
      case OrderType.delivery:
        return 'delivery'.tr;
      case OrderType.pickUp:
        return 'pickup'.tr;
    }
  }

  int get id {
    switch (this) {
      case OrderType.dineIn:
        return 0;
      case OrderType.delivery:
        return 1;
      case OrderType.pickUp:
        return 2;
    }
  }
}
