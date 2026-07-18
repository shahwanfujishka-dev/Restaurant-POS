import 'dart:convert';
import 'dart:developer';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

class CategoryModel {
  final String id;
  final String cat_pos;
  final String name;
  final int tokenPrinterId;
  final RxString printerAddress = "".obs;

  CategoryModel({
    required this.id,
    required this.cat_pos,
    required this.name,
    required this.tokenPrinterId,
    String? initialPrinter
  }) {
    if (initialPrinter != null) printerAddress.value = initialPrinter;
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: (json['cat_id'] ?? '').toString(),
      cat_pos: (json['cat_pos'] ?? '').toString(),
      name: json['cat_name']?.toString() ?? '',
      tokenPrinterId: parseInt(json['cat_token_printer']),
    );
  }
}

class FavoriteModel {
  final int id;
  final String name;
  final String? description;
  final String? image;
  final int branchId;

  FavoriteModel({
    required this.id,
    required this.name,
    this.description,
    this.image,
    required this.branchId,
  });

  factory FavoriteModel.fromJson(Map<String, dynamic> json) {
    return FavoriteModel(
      id: parseInt(json['fav_id'] ?? json['favp_id'] ?? json['id']),
      name: (json['fav_name'] ?? json['favp_name'] ?? json['name'] ?? '').toString(),
      description: (json['favp_description'] ?? json['description'])?.toString(),
      image: (json['fav_img_url'] ?? json['favp_img_url'] ?? json['image'])?.toString(),
      branchId: parseInt(json['branch_id']),
    );
  }
}

class FoodItemModel {
  final String id;
  final String name;
  final String categoryId;
  final double price;
  final double prd_tax;
  final String image;
  final String unitDisplay;
  final int taxCatId;
  final double taxPer;
  final int? tokenPrinterId; // Added for offline routing

  FoodItemModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    required this.prd_tax,
    required this.image,
    required this.unitDisplay,
    this.taxCatId = 0,
    this.taxPer = 0.0,
    this.tokenPrinterId,
  });

  factory FoodItemModel.fromJson(Map<String, dynamic> json, {String baseUrl = ""}) {
    String imgUrl = (json['prd_img_url'] ?? json['image'])?.toString() ?? '';
    if (imgUrl.isNotEmpty && baseUrl.isNotEmpty && !imgUrl.startsWith('http')) {
      imgUrl = baseUrl + imgUrl;
    }

    return FoodItemModel(
      id: (json['prd_id'] ?? json['id'] ?? '').toString(),
      name: json['prd_name']?.toString() ?? json['name']?.toString() ?? 'Unknown Item',
      categoryId: (json['prd_cat_id'] ?? json['category_id'] ?? '').toString(),
      price: parseDouble(json['sale_rate'] ?? json['price'], defaultValue: 0.0),
      prd_tax: parseDouble(json['prd_tax'], defaultValue: 0.0),
      image: imgUrl,
      unitDisplay: json['unit_display']?.toString() ?? '',
      taxCatId: parseInt(json['prd_tax_cat_id'] ?? json['tax_cat_id']),
      taxPer: parseDouble(json['tax_per'], defaultValue: 0.0),
      tokenPrinterId: parseInt(json['cat_token_printer']) == 0 ? null : parseInt(json['cat_token_printer']),
    );
  }
}

double parseDouble(dynamic value, {double defaultValue = 1.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? defaultValue;
}

class ProductUnit {
  final int unitId;
  final String unitName;
  final String unitDisplay;
  final double rate;
  final double unitBaseQty;
  final List<AddonModel> existAddOns;

  ProductUnit({
    required this.unitId,
    required this.unitName,
    required this.unitDisplay,
    required this.rate,
    required this.unitBaseQty,
    required this.existAddOns,
  });

  ProductUnit copyWith({
    int? unitId,
    String? unitName,
    String? unitDisplay,
    double? rate,
    double? unitBaseQty,
    List<AddonModel>? existAddOns,
  }) {
    return ProductUnit(
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      unitDisplay: unitDisplay ?? this.unitDisplay,
      rate: rate ?? this.rate,
      unitBaseQty: unitBaseQty ?? this.unitBaseQty,
      existAddOns: existAddOns ?? this.existAddOns,
    );
  }

  factory ProductUnit.fromJson(Map<String, dynamic> json) {
    // Extensive fallback for unit name fields commonly used in APIs and Local DB
    String name = (json['unit_name'] ??
                  json['prd_unit_name'] ??
                  json['unit_display'] ??
                  json['prd_unit_display'] ??
                  '').toString();

    String display = (json['unit_display'] ??
                     json['prd_unit_display'] ??
                     json['unit_name'] ??
                     json['prd_unit_name'] ??
                     '').toString();

    // Handle nested addons which could be a List or a JSON String (from Local DB)
    dynamic rawExistAddons = json['existAddOn'] ?? json['exist_addons'] ?? [];
    List<dynamic> existAddonsList = [];
    if (rawExistAddons is String && rawExistAddons.isNotEmpty) {
      try {
        existAddonsList = jsonDecode(rawExistAddons);
      } catch (_) {}
    } else if (rawExistAddons is List) {
      existAddonsList = rawExistAddons;
    }

    return ProductUnit(
      unitId: parseInt(json['unit_id'] ?? json['produnit_unit_id']),
      unitName: name,
      unitDisplay: display,
      rate: parseDouble(json['sur_unit_rate'] ??
            json['sale_rate'] ??
            json['prd_unit_rate'] ??
            json['rate'], defaultValue: 0.0),
      unitBaseQty: parseDouble(json['unit_base_qty'], defaultValue: 1.0),
      existAddOns: existAddonsList
          .map((e) => AddonModel.fromJson(e))
          .toList(),
    );
  }
}

class AddonModel {
  final int id;
  final int? subId;
  final int prdId;
  final int prdaddon_flags;
  final String name;
  final double price;
  final String unitDisplay;
  final int unitId;
  final int taxCatId;
  final double taxPer;
  final double unitBaseQty;
  final int initialQty;
  final int? isDefault;
  final int freeQty; // Threshold for free items
  final int flags; // 0 = unchanged, 1 = new/modified (from sales_ord_sub_flags)
  RxInt quantity = 0.obs;

  AddonModel({
    required this.id,
    this.subId,
    required this.prdId,
    required this.prdaddon_flags,
    required this.name,
    required this.price,
    required this.unitDisplay,
    this.unitId = 0,
    this.taxCatId = 0,
    this.taxPer = 0.0,
    this.unitBaseQty = 1.0,
    int initialQty = 0,
    this.isDefault = 0,
    this.freeQty = 0,
    this.flags = 0, // Default to 0 (unchanged)
  }) : initialQty = initialQty {
    quantity.value = initialQty;
  }

  factory AddonModel.fromJson(Map<String, dynamic> json) {
    bool isCommon = json['commonAddon'] == true;
    int q = parseInt(json['prdaddon_qty']);

    return AddonModel(
      id: parseInt(json['prdaddon_id'] ?? json['prd_id']),
      subId: parseInt(json['sales_ord_sub_id']) == 0
          ? null
          : parseInt(json['sales_ord_sub_id']),
      prdId: parseInt(json['prdaddon_prd_id'] ?? json['prd_id']),
      prdaddon_flags: parseInt(json['prdaddon_flags']),
      name: (json['prd_name'] ?? json['name'] ?? '').toString(),
      price: parseDouble(json['sales_ord_sub_rate'] ??
          json['bs_srate'] ??
          json['sale_rate'], defaultValue: 0.0),
      unitDisplay: (json['unit_display'] ?? json['prd_unit_display'] ?? '').toString(),
      unitId: parseInt(json['unit_id']),
      taxCatId: parseInt(json['prd_tax_cat_id']),
      taxPer: parseDouble(json['tax_per'], defaultValue: 0.0),
      unitBaseQty: parseDouble(json['unit_base_qty'], defaultValue: 1.0),
      isDefault: parseInt(json['is_default']),
      initialQty: isCommon ? 0 : q,
      freeQty: isCommon ? 0 : q,
      flags: parseInt(json['sales_ord_sub_flags']),
    );
  }

  bool get isSelectedValue => quantity.value > 0;

  AddonModel copyWith({
    int? id,
    int? subId,
    int? prdId,
    int? prdaddon_flags,
    String? name,
    double? price,
    String? unitDisplay,
    int? unitId,
    int? taxCatId,
    double? taxPer,
    double? unitBaseQty,
    int? initialQty,
    int? isDefault,
    int? quantityValue,
    int? freeQty,
    int? flags,
  }) {
    final newAddon = AddonModel(
      id: id ?? this.id,
      subId: subId ?? this.subId,
      prdId: prdId ?? this.prdId,
      prdaddon_flags: prdaddon_flags ?? this.prdaddon_flags,
      name: name ?? this.name,
      price: price ?? this.price,
      unitDisplay: unitDisplay ?? this.unitDisplay,
      unitId: unitId ?? this.unitId,
      taxCatId: taxCatId ?? this.taxCatId,
      taxPer: taxPer ?? this.taxPer,
      unitBaseQty: unitBaseQty ?? this.unitBaseQty,
      initialQty: initialQty ?? this.initialQty,
      isDefault: isDefault ?? this.isDefault,
      freeQty: freeQty ?? this.freeQty,
      flags: flags ?? this.flags,
    );
    newAddon.quantity.value = quantityValue ?? this.quantity.value;
    return newAddon;
  }
}
