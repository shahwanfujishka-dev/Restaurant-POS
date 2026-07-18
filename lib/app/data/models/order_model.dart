import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../../modules/home/views/dashoard/models/dashboard_models.dart';

enum OrderStatus { pending, preparing, ready, served, paid, cancelled, draft, billed }

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
  final double cgstRate; // ✅ Added for GST
  final double sgstRate; // ✅ Added for GST

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
    this.cgstRate = 0.0,
    this.sgstRate = 0.0,
  });

  double get subtotal => priceAtOrder * quantity;
}

class OrderModel {
  final String id;
  final String invNo;
  final String tableId;
  final String tableName;
  final String? customerName;
  final String? captainName;
  final int chairNumber;
  final int sales_odr_pos_status;
  final List<OrderItem> items;
  final Rx<OrderStatus> status;
  final DateTime createdAt;
  double subTotal;
  double totalAmount;
  double totalTax;
  double totalCgst;
  double totalSgst;
  double Taxpercentage;
  final List<Map<String, dynamic>>? gstList;
  double discount;
  double roundOff;
  int paymentType;
  String? qrLink;
  String? branchTin;
  String? branchName;
  String? branchPhone;
  String? branchMob;
  String? branchAddress;
  final int? areaId;
  final String? areaName;
  final int? priceGroupId;
  int sales_odr_order_type;
  bool isUnsynced; 

  OrderModel({
    required this.id,
    required this.invNo,
    required this.tableId,
    required this.tableName,
    this.customerName,
    this.captainName,
    required this.chairNumber,
    required this.sales_odr_pos_status,
    required this.items,
    required OrderStatus status,
    required this.createdAt,
    this.subTotal = 0.0, // ✅ Added
    required this.totalAmount,
    required this.totalTax,
    this.totalCgst = 0.0,
    this.totalSgst = 0.0,
    this.Taxpercentage = 0.0,
    this.gstList,
    this.discount = 0.0,
    this.roundOff = 0.0,
    this.paymentType = 2, // Default to Cash (2)
    this.qrLink,
    this.branchTin,
    this.branchName,
    this.branchPhone,
    this.branchMob,
    this.branchAddress,
    this.areaId,
    this.areaName,
    this.priceGroupId,
    this.sales_odr_order_type = 0,
    this.isUnsynced = false,
  }) : status = status.obs;

  /// Returns the final payable amount.
  /// For offline orders, totalAmount already includes roundOff.
  /// For online orders, we add roundOff to totalAmount.
  double get finalTotal => isUnsynced ? totalAmount : (totalAmount + roundOff);

  OrderModel copyWith({
    String? id,
    String? invNo,
    String? tableId,
    String? tableName,
    String? customerName,
    String? captainName,
    int? chairNumber,
    int? sales_odr_pos_status,
    List<OrderItem>? items,
    OrderStatus? status,
    DateTime? createdAt,
    double? subTotal, // ✅ Added
    double? totalAmount,
    double? totalTax,
    double? totalCgst,
    double? totalSgst,
    double? Taxpercentage,
    List<Map<String, dynamic>>? gstList,
    double? discount,
    double? roundOff,
    int? paymentType,
    String? qrLink,
    String? branchTin,
    String? branchName,
    String? branchPhone,
    String? branchMob,
    String? branchAddress,
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
      customerName: customerName ?? this.customerName,
      captainName: captainName ?? this.captainName,
      chairNumber: chairNumber ?? this.chairNumber,
      sales_odr_pos_status: sales_odr_pos_status ?? this.sales_odr_pos_status,
      items: items ?? this.items,
      status: status ?? this.status.value,
      createdAt: createdAt ?? this.createdAt,
      subTotal: subTotal ?? this.subTotal, // ✅ Added
      totalAmount: totalAmount ?? this.totalAmount,
      totalTax: totalTax ?? this.totalTax,
      totalCgst: totalCgst ?? this.totalCgst,
      totalSgst: totalSgst ?? this.totalSgst,
      Taxpercentage: Taxpercentage ?? this.Taxpercentage,
      gstList: gstList ?? this.gstList,
      discount: discount ?? this.discount,
      roundOff: roundOff ?? this.roundOff,
      paymentType: paymentType ?? this.paymentType,
      qrLink: qrLink ?? this.qrLink,
      branchTin: branchTin?? this.branchTin,
      branchName: branchName?? this.branchName,
      branchPhone: branchPhone?? this.branchPhone,
      branchMob: branchMob?? this.branchMob,
      branchAddress: branchAddress?? this.branchAddress,
      areaId: areaId ?? this.areaId,
      areaName: areaName ?? this.areaName,
      priceGroupId: priceGroupId ?? this.priceGroupId,
      sales_odr_order_type: sales_odr_order_type ?? this.sales_odr_order_type,
      isUnsynced: isUnsynced ?? this.isUnsynced,
    );
  }
}
