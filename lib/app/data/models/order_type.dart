enum OrderType {
  dineIn,
  delivery,
  pickUp;

  String get displayName {
    switch (this) {
      case OrderType.dineIn:
        return 'Dine In';
      case OrderType.delivery:
        return 'Delivery';
      case OrderType.pickUp:
        return 'Pick Up';
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
