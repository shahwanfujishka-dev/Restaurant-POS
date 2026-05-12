import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';

import '../../../../../helper/screen_type.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/cart_controller.dart';

class QuantityDialog extends StatefulWidget {
  final CartItem item;
  final CartController controller;

  const QuantityDialog({super.key, required this.item, required this.controller});

  static void show(CartItem item, CartController controller) {
    Get.dialog(
      QuantityDialog(item: item, controller: controller),
      barrierDismissible: true,
    );
  }

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late TextEditingController _textController;
  final List<int> presets = [5, 10, 20, 50];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.item.quantity.value.toString());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _updateQty(int val) {
    if (val > 0) {
      widget.controller.updateQuantity(widget.item, val);
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = ScreenType.isMobile();
    final colors = AppColors.of(context);

    return Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: Container(
        padding: EdgeInsets.all(10.w),
        width: isMobile ? 300.w : 100.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Update Quantity",
              style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: colors.text),
            ),
            SizedBox(height: 8.h),
            Text(
              widget.item.product.name,
              style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: _textController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              style: AppTypography.appBarTitle.copyWith(color: colors.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.textField,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 10.h),
              ),
              onSubmitted: (value) {
                final val = int.tryParse(value);
                if (val != null) _updateQty(val);
              },
            ),
            SizedBox(height: 10.h),
            Text(
              "Quick Presets",
              style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
            ),
            SizedBox(height: 6.h),
            Wrap(
              spacing: 5.w,
              runSpacing: 5.h,
              alignment: WrapAlignment.center,
              children: presets.map((preset) {
                return InkWell(
                  onTap: () => _updateQty(preset),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: AppTypography.sizeText, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
                    ),
                    child: Text(
                      "$preset",
                      style: AppTypography.cardTitle.copyWith(
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Get.back(),
                    child: Text("Cancel", style:AppTypography.button.copyWith(color: colors.subtext)),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final val = int.tryParse(_textController.text);
                      if (val != null) _updateQty(val);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    child: Text("Set", style:AppTypography.button),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}