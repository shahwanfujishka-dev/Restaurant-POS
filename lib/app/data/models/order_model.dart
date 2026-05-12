import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../../modules/home/views/dashoard/models/dashboard_models.dart';

enum OrderStatus { pending, preparing, ready, served, paid, cancelled, draft }

class OrderItem {
  final int? subId;
  final FoodItemModel product;
  final ProductUnit unit;
  final List<AddonModel> selectedAddons;
  final int quantity;
  final double priceAtOrder;
  final int? addonParentPrdId;
  final int? addonParentUnitId;
  final int? unitId;
  final int? tokenPrinterId; // ✅ Added to track routing station
  final bool isRemoved; // ✅ Added to track if item was removed/decreased
  Map<int, int>? addonSubIdMap;
  final bool isKotModified;

  OrderItem({
    this.subId,
    required this.product,
    required this.unit,
    this.selectedAddons = const [],
    this.addonParentPrdId,
    this.addonParentUnitId,
    this.unitId,
    this.tokenPrinterId,
    this.isRemoved = false,
    this.addonSubIdMap,
    required this.quantity,
    required this.priceAtOrder,
    this.isKotModified = false,
  });

  double get subtotal => priceAtOrder * quantity;
}

class OrderModel {
  final String id;
  final String invNo;
  final String tableId;
  final String tableName;
  final int chairNumber;
  final int sales_odr_pos_status;
  final List<OrderItem> items;
  final Rx<OrderStatus> status;
  final DateTime createdAt;
  double totalAmount;
  double totalTax;

  final int? areaId;
  final String? areaName;
  final int? priceGroupId;
  final int sales_odr_order_type; // 0-dine in, 1-delivery, 2-pickup

  final bool isUnsynced; // ✅ Track if this order is stored only locally

  OrderModel({
    required this.id,
    required this.invNo,
    required this.tableId,
    required this.tableName,
    required this.chairNumber,
    required this.sales_odr_pos_status,
    required this.items,
    required OrderStatus status,
    required this.createdAt,
    required this.totalAmount,
    required this.totalTax,
    this.areaId,
    this.areaName,
    this.priceGroupId,
    this.sales_odr_order_type = 0,
    this.isUnsynced = false,
  }) : status = status.obs;
}
