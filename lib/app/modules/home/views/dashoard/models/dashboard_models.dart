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
      tokenPrinterId: (json['cat_token_printer'] as num? ?? 0).toInt(),
    );
  }
}

class FavoriteModel {
  final int id;
  final String name;
  final String? description;
  final int branchId;

  FavoriteModel({
    required this.id,
    required this.name,
    this.description,
    required this.branchId,
  });

  factory FavoriteModel.fromJson(Map<String, dynamic> json) {
    return FavoriteModel(
      id: json['favp_id'] ?? 0,
      name: json['favp_name'] ?? '',
      description: json['favp_description'],
      branchId: json['branch_id'] ?? 0,
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
    String imgUrl = json['prd_img_url']?.toString() ?? '';
    if (imgUrl.isNotEmpty && baseUrl.isNotEmpty && !imgUrl.startsWith('http')) {
      imgUrl = baseUrl + imgUrl;
    }

    return FoodItemModel(
      id: (json['prd_id'] ?? json['id'] ?? '').toString(),
      name: json['prd_name']?.toString() ?? json['name']?.toString() ?? 'Unknown Item',
      categoryId: (json['prd_cat_id'] ?? json['category_id'] ?? '').toString(),
      price: (json['sale_rate'] as num? ?? json['price'] as num? ?? 0.0).toDouble(),
      prd_tax: (json['prd_tax'] as num? ?? 0.0).toDouble(),
      image: imgUrl,
      unitDisplay: json['unit_display']?.toString() ?? '',
      taxCatId: (json['prd_tax_cat_id'] as num? ?? json['tax_cat_id'] as num? ?? 0).toInt(),
      taxPer: (json['tax_per'] as num? ?? 0.0).toDouble(),
      tokenPrinterId: (json['cat_token_printer'] as num?)?.toInt(),
    );
  }
}
double parseDouble(dynamic value) {
  if (value == null) return 1.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 1.0;
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
    log("RAW unit_base_qty → ${json['unit_base_qty']}");
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
      unitId: (json['unit_id'] as num? ?? json['produnit_unit_id'] as num? ?? 0).toInt(),
      unitName: name,
      unitDisplay: display,
      rate: (json['sur_unit_rate'] as num? ??
            json['sale_rate'] as num? ??
            json['rate'] as num? ??
            0.0).toDouble(),
      unitBaseQty: parseDouble(json['unit_base_qty']),
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
    int q = (json['prdaddon_qty'] as num? ?? 0).toInt();

    return AddonModel(
      id: (json['prdaddon_id'] as num? ?? (json['prd_id'] as num? ?? 0)).toInt(),
      subId: (json['sales_ord_sub_id'] as num?)?.toInt() == 0
          ? null
          : (json['sales_ord_sub_id'] as num?)?.toInt(),
      prdId: (json['prdaddon_prd_id'] as num? ?? (json['prd_id'] as num? ?? 0)).toInt(),
      prdaddon_flags: (json['prdaddon_flags'] as num? ?? 0).toInt(),
      name: (json['prd_name'] ?? json['name'] ?? '').toString(),
      price: (json['sales_ord_sub_rate'] as num? ??
          json['bs_srate'] as num? ??
          (json['sale_rate'] as num? ?? 0.0)).toDouble(),
      unitDisplay: (json['unit_display'] ?? json['prd_unit_display'] ?? '').toString(),
      unitId: (json['unit_id'] as num? ?? 0).toInt(),
      taxCatId: (json['prd_tax_cat_id'] as num? ?? 0).toInt(),
      taxPer: (json['tax_per'] as num? ?? 0.0).toDouble(),
      unitBaseQty: double.tryParse(json['unit_base_qty']?.toString() ?? '') ?? 1.0,
      isDefault: (json['is_default'] as num? ?? 0).toInt(),
      initialQty: isCommon ? 0 : q,
      freeQty: isCommon ? 0 : q,
      flags: (json['sales_ord_sub_flags'] as num? ?? 0).toInt(), // Capture flags from response
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
