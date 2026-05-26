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
  final int sales_odr_order_type;
  bool isUnsynced; // ✅ Removed final to allow updating sync status in UI

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

  // ✅ Add copyWith method
  OrderModel copyWith({
    String? id,
    String? invNo,
    String? tableId,
    String? tableName,
    int? chairNumber,
    int? sales_odr_pos_status,
    List<OrderItem>? items,
    OrderStatus? status,
    DateTime? createdAt,
    double? totalAmount,
    double? totalTax,
    int? areaId,
    String? areaName,
    int? priceGroupId,
    int? sales_odr_order_type,
    bool? isUnsynced,
  }) {
    return OrderModel(
      id: id ?? this.id,
      invNo: invNo ?? this.invNo,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      chairNumber: chairNumber ?? this.chairNumber,
      sales_odr_pos_status: sales_odr_pos_status ?? this.sales_odr_pos_status,
      items: items ?? this.items,
      status: status ?? this.status.value,
      createdAt: createdAt ?? this.createdAt,
      totalAmount: totalAmount ?? this.totalAmount,
      totalTax: totalTax ?? this.totalTax,
      areaId: areaId ?? this.areaId,
      areaName: areaName ?? this.areaName,
      priceGroupId: priceGroupId ?? this.priceGroupId,
      sales_odr_order_type: sales_odr_order_type ?? this.sales_odr_order_type,
      isUnsynced: isUnsynced ?? this.isUnsynced,
    );
  }
}