import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import 'package:restaurant_pos/helper/screen_type.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';

class CashierWidgets {
  CashierWidgets._(); // private constructor (prevents instantiation)

  // ─────────────────────────────────────────────
  // PAYMENT METHOD ITEM
  // ─────────────────────────────────────────────
  static Widget paymentMethodItem(
      String method,
      RxString paymentMethod,
      dynamic colors,
      VoidCallback onTap,
      ) {
    return Obx(() {
      final isSelected = paymentMethod.value == method;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 6.h),
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryGreen.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isSelected ? AppTheme.primaryGreen : colors.border,
              width: 1,
            ),
          ),
          child: Text(
            method,
            style: AppTypography.cardSubtitle.copyWith(
              color: isSelected ? AppTheme.primaryGreen : colors.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 7.sp
            ),
          ),
        ),
      );
    });
  }

  // ─────────────────────────────────────────────
  // SPLIT TOGGLE
  // ─────────────────────────────────────────────
  static Widget splitToggle(
      RxBool isSplit,
      dynamic colors,
      VoidCallback onTap,
      ) {
    return Obx(() => GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(top: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSplit.value
              ? Colors.orange.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: isSplit.value ? Colors.orange : colors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.call_split,
              size: 16.sp,
              color: isSplit.value ? Colors.orange : colors.text,
            ),
            SizedBox(width: 8.w),
            Text(
              "Split Amount",
              style: AppTypography.cardSubtitle.copyWith(
                color: isSplit.value ? Colors.orange : colors.text,
                fontWeight: isSplit.value ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // ─────────────────────────────────────────────
  // CUSTOMER SECTION
  // ─────────────────────────────────────────────
  static Widget customerSection(
      RxString paymentMethod,
      RxBool isCustomerSelectEnabled,
      Rx<Map<String, dynamic>?> selectedCustomer,
      TextEditingController customerNameController,
      TextEditingController customerMobileController,
      TextEditingController customerAddressController,
      TextEditingController customerVatController,
      List<Map<String, dynamic>> customers,
      Function(Map<String, dynamic>?) onCustomerSelected,
      dynamic colors,
      ) {
    return Obx(() {
      final isCard = paymentMethod.value == 'Card';
      final isCredit = paymentMethod.value == 'Credit';
      final isSelectEnabled = isCustomerSelectEnabled.value;

      return Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: colors.border.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: AppTypography.sizeText, color: colors.subtext),
                      SizedBox(width: 6.w),
                      Text(
                        "Customer Info",
                        style: AppTypography.cardInfo.copyWith(
                          color: colors.subtext,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          fontSize: AppTypography.sizeText
                        ),
                      ),
                    ],
                  ),
                  if (isCard || isCredit)
                    CupertinoSwitch(
                      value: isSelectEnabled,
                      onChanged: (val) => isCustomerSelectEnabled.value = val,
                      activeColor: AppTheme.primaryGreen,
                      trackColor: colors.border,
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border.withOpacity(0.3)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
              child: ( isSelectEnabled)
                  ? Column(
                children: [
                  minimalCustomerField("Mobile", customerMobileController, colors,Keyboard: TextInputType.number),
                  SizedBox(height: 8.h),
                  minimalCustomerSelector(
                    selectedCustomer,
                    customers,
                    onCustomerSelected,
                    colors,
                  ),
                  SizedBox(height: 10.h),
                  minimalCustomerField("VAT", customerVatController, colors,Keyboard: TextInputType.phone),
                  SizedBox(height: 8.h),
                  minimalCustomerField("Address", customerAddressController, colors, maxLines: 1,Keyboard: TextInputType.text),
                ],
              )
                  : Column(
                children: [
                  minimalCustomerField("Mobile", customerMobileController, colors,Keyboard: TextInputType.number),
                  SizedBox(height: 8.h),
                  minimalCustomerField(
                    "Customer",
                    customerNameController,
                    colors,
                    isReadOnly: false,Keyboard: TextInputType.text
                  ),
                  SizedBox(height: 10.h),

                  minimalCustomerField("Address", customerAddressController, colors, maxLines: 1,Keyboard: TextInputType.text),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ─────────────────────────────────────────────
  // MINIMAL CUSTOMER SELECTOR
  // ─────────────────────────────────────────────
  static Widget minimalCustomerSelector(
      Rx<Map<String, dynamic>?> selectedCustomer,
      List<Map<String, dynamic>> customers,
      Function(Map<String, dynamic>?) onCustomerSelected,
      dynamic colors,
      ) {
    return GestureDetector(
      onTap: () => _showCustomerSearch(selectedCustomer, customers, onCustomerSelected, colors),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: colors.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: AppTypography.sizeText, color: colors.subtext),
            SizedBox(width: 8.w),
            Expanded(
              child: Obx(() => Text(
                selectedCustomer.value?['name'] ?? "Select Customer",
                style: AppTypography.cardSubtitle.copyWith(
                  color: selectedCustomer.value != null ? colors.text : colors.subtext,
                  fontWeight: FontWeight.w500,fontSize: AppTypography.sizeText
                ),
              )),
            ),
            Icon(Icons.arrow_drop_down, size: AppTypography.sizeText, color: colors.subtext),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MINIMAL CUSTOMER FIELD
  // ─────────────────────────────────────────────
  static Widget minimalCustomerField(
      String label,
      TextEditingController ctrl,
      dynamic colors, {
        int maxLines = 1,
        bool isReadOnly = false, required TextInputType Keyboard,
      }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: colors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: ScreenType.isMobile()?80.w:30.w,
            child: Text(
              label,
              style: AppTypography.cardInfo.copyWith(
                color: colors.subtext,
                  fontSize: AppTypography.sizeText
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              readOnly: isReadOnly,
              maxLines: maxLines,
              keyboardType: Keyboard,
              style: AppTypography.cardSubtitle.copyWith(
                color: colors.text,
                  fontSize: AppTypography.sizeText
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                border: InputBorder.none,
                hintText: isReadOnly ? "Cash Customer" : "Enter $label",
                hintStyle: AppTypography.cardInfo.copyWith(color: colors.subtext.withOpacity(0.5),fontSize: AppTypography.sizeText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SUMMARY ROW
  // ─────────────────────────────────────────────
  static Widget summaryRow(
      String label,
      String value,
      dynamic colors, {
        bool isTotal = false,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTypography.cardTitle.copyWith(color: colors.text,fontSize: AppTypography.sizeText)
              : AppTypography.cardSubtitle.copyWith(color: colors.subtext,fontSize: AppTypography.sizeText),
        ),
        Text(
          value,
          style: isTotal
              ? AppTypography.headline2.copyWith(
            color: AppTheme.primaryGreen,
            fontSize: AppTypography.sizeText,
          )
              : AppTypography.cardSubtitle.copyWith(
            color: colors.text,
            fontWeight: FontWeight.w600,fontSize: AppTypography.sizeText
          ),
        ),
      ],
    );
  }


  // ─────────────────────────────────────────────
  // MINIMAL DISCOUNT INPUT
  // ─────────────────────────────────────────────
  static Widget minimalDiscountInput(
      TextEditingController discountController,
      Function(String) onChanged,
      dynamic colors,
      ) {
    return Row(
      children: [
        Text(
          "Discount",
          style: AppTypography.cardSubtitle.copyWith(color: colors.subtext,fontSize: AppTypography.sizeText),
        ),
        SizedBox(width: ScreenType.isMobile() ? 8.w: 120.w),
        Expanded(
          child: SizedBox(
            height: 30.h,
            child: TextField(
              controller: discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onChanged,
              onTap: () {
                if (discountController.text == "0.00") {
                  discountController.clear();
                }
              },
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: colors.text,
                fontWeight: FontWeight.bold,fontSize: AppTypography.sizeText
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                contentPadding: EdgeInsets.symmetric(horizontal: 0.w),
                filled: true,
                fillColor: colors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(color: AppTheme.primaryGreen),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // MINIMAL ROUND OFF INPUT
  // ─────────────────────────────────────────────
  static Widget minimalRoundOffInput(
      TextEditingController roundOffController,
      Function(String) onChanged,
      VoidCallback onIncrement,
      VoidCallback onDecrement,
      dynamic colors,
      ) {
    return Row(
      children: [
        Text(
          "Round Off",
          style: AppTypography.cardSubtitle.copyWith(color: colors.subtext,fontSize: AppTypography.sizeText),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Row(
            children: [
              roundOffBtn(Icons.remove, onDecrement, colors),
              Expanded(
                child: SizedBox(
                  height: 32.h,
                  child: TextField(
                    controller: roundOffController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onChanged: onChanged,
                    onTap: () {
                      if (roundOffController.text == "0.00") {
                        roundOffController.clear();
                      }
                    },
                    textAlign: TextAlign.center,
                    style: AppTypography.cardSubtitle.copyWith(
                      color: colors.text,
                      fontWeight: FontWeight.bold,fontSize: AppTypography.sizeText
                    ),
                    decoration: InputDecoration(
                      hintText: "0.00",
                      contentPadding: EdgeInsets.symmetric(horizontal: 4.w),
                      filled: true,
                      fillColor: colors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6.r),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6.r),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6.r),
                        borderSide: BorderSide(color: AppTheme.primaryGreen),
                      ),
                    ),
                  ),
                ),
              ),
              roundOffBtn(Icons.add, onIncrement, colors),
            ],
          ),
        ),
      ],
    );
  }

  static Widget roundOffBtn(IconData icon, VoidCallback onTap, dynamic colors) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: ScreenType.isMobile() ? 25.h : 32.h,
        width: ScreenType.isMobile() ? 25.h : 32.h,
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, size: AppTypography.sizeText, color: colors.text),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // INPUT FIELD ROW
  // ─────────────────────────────────────────────
  // ─────────────────────────────────────────────
// CASH RECEIVED ROW (styled like splitSummaryRow)
// ─────────────────────────────────────────────
  static Widget cashReceivedRow(
      TextEditingController ctrl,
      Function(String) onChg,
      RxDouble receivedAmount,
      double totalToPay,
      dynamic colors, {
        bool readOnly = false,
      }) {
    return Obx(() {
      final bool sufficient = receivedAmount.value >= totalToPay;
      final double change = (receivedAmount.value - totalToPay).clamp(0, double.infinity);

      return Container(
        padding: EdgeInsets.symmetric(horizontal: 6.w),
        decoration: BoxDecoration(
          color: sufficient
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: sufficient ? AppTheme.primaryGreen : Colors.red,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Cash Received",
                  style: AppTypography.cardSubtitle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                    fontSize: AppTypography.sizeText
                  ),
                ),
                SizedBox(
                  width: 120.w,
                  height: 28.h,
                  child: TextField(
                    controller: ctrl,
                    readOnly: readOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: readOnly ? null : onChg,
                    textAlign: TextAlign.right,
                    style: AppTypography.cardSubtitle.copyWith(
                      color: sufficient ? AppTheme.primaryGreen : Colors.red,
                      fontWeight: FontWeight.bold,fontSize: AppTypography.sizeText
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: "0.00",
                    ),
                  ),
                ),
              ],
            ),
            if (change > 0) ...[
              Divider(height: 1, color: colors.border.withOpacity(0.3)),
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Change",
                    style: AppTypography.cardSubtitle.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,fontSize: AppTypography.sizeText
                    ),
                  ),
                  Text(
                    change.toStringAsFixed(2),
                    style: AppTypography.cardSubtitle.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,fontSize: AppTypography.sizeText
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    });
  }

  static Widget inputFieldRow(
      String label,
      TextEditingController ctrl,
      Function(String) onChg,
      dynamic colors, {
        bool isNumber = false,
        bool readOnly = false,
      }) {
    return SizedBox(
      height: 40.h,
      child: TextField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !isNumber,
        ),
        onChanged: readOnly ? null : onChg,
        textAlign: TextAlign.right,
        style: AppTypography.cardTitle.copyWith(
          color: readOnly ? colors.subtext : colors.text,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTypography.cardSubtitle.copyWith(
            color: readOnly ? colors.subtext : colors.text,
          ),
          floatingLabelStyle: TextStyle(
            color: readOnly
                ? colors.subtext
                : AppTheme.primaryGreen,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12.w,
          ),
          filled: true,
          fillColor: colors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: BorderSide(
              color: colors.border,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: BorderSide(
              color: colors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: const BorderSide(
              color: AppTheme.primaryGreen,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DROPDOWN
  // ─────────────────────────────────────────────
  static Widget minimalDropdown(
      String label,
      List<Map<String, dynamic>> items,
      int selected,
      ValueChanged<int?> onChg,
      dynamic colors,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.cardSubtitle.copyWith(
            color: colors.subtext,
            fontWeight: FontWeight.w500,fontSize: AppTypography.sizeText
          ),
        ),
        SizedBox(height: 6.h),
        Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: items.any((e) => (e['ledger_id'] as num).toInt() == selected)
                  ? selected
                  : null,
              dropdownColor: colors.card,
              icon: Icon(
                Icons.expand_more,
                size: AppTypography.sizeText,
                color: colors.subtext,
              ),
              items: items
                  .map((acc) => DropdownMenuItem<int>(
                value: (acc['ledger_id'] as num).toInt(),
                child: Text(
                  acc['ledger_name'] ?? "",
                  style: AppTypography.cardSubtitle.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w500,fontSize: AppTypography.sizeText
                  ),
                ),
              ))
                  .toList(),
              onChanged: onChg,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // INLINE AMOUNT FIELD
  // ─────────────────────────────────────────────
  static Widget inlineAmountField(
      String label,
      TextEditingController ctrl,
      Function(String) onChg,
      dynamic colors, {
        required Color highlightColor,
        required bool readOnly,
      }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: AppTypography.cardSubtitle.copyWith(
              color: readOnly ? colors.subtext : colors.text,
              fontWeight: FontWeight.w600,fontSize: AppTypography.sizeText
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: SizedBox(
            height: 34.h,
            child: TextField(
              controller: ctrl,
              readOnly: readOnly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: readOnly ? null : onChg,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: readOnly ? colors.subtext : highlightColor,
                fontWeight: FontWeight.bold,fontSize: AppTypography.sizeText
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
                filled: true,
                fillColor: readOnly
                    ? colors.card
                    : highlightColor.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(
                    color: readOnly
                        ? colors.border
                        : highlightColor.withOpacity(0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(
                    color: readOnly
                        ? colors.border
                        : highlightColor.withOpacity(0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(
                    color: readOnly ? colors.border : highlightColor,
                    width: readOnly ? 1 : 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // MULTI TOTAL ROW
  // ─────────────────────────────────────────────
  static Widget multiTotalRow(
      RxDouble multiCashAmount,
      RxDouble multiBankAmount,
      double totalToPay,
      dynamic colors,
      ) {
    return Obx(() {
      final entered = multiCashAmount.value + multiBankAmount.value;
      final total = totalToPay;
      final remaining = total - entered;
      final isValid = remaining <= 0;

      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isValid
              ? AppTheme.primaryGreen.withOpacity(0.08)
              : Colors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: isValid
                ? AppTheme.primaryGreen.withOpacity(0.4)
                : Colors.orange.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isValid ? "Change" : "Remaining",
              style: AppTypography.cardSubtitle.copyWith(
                color: isValid ? AppTheme.primaryGreen : Colors.orange.shade800,
                fontWeight: FontWeight.w600,fontSize: AppTypography.sizeText
              ),
            ),
            Text(
              isValid
                  ? (entered - total).toStringAsFixed(2)
                  : remaining.toStringAsFixed(2),
              style: AppTypography.cardSubtitle.copyWith(
                color: isValid ? AppTheme.primaryGreen : Colors.orange.shade800,
                fontWeight: FontWeight.bold,fontSize: AppTypography.sizeText
              ),
            ),
          ],
        ),
      );
    });
  }

  // ─────────────────────────────────────────────
  // SPLIT AMOUNT EDIT ROW
  // ─────────────────────────────────────────────
  // ─────────────────────────────────────────────
// SPLIT AMOUNT EDIT ROW (aligned to match inputFieldRow / Grand Total)
// ─────────────────────────────────────────────
  static Widget splitAmountEditRow(
      int index,
      TextEditingController ctrl,
      Function(String) onChg,
      dynamic colors,
      ) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Person ${index + 1}",
            style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
          ),
          SizedBox(
            width: 120.w,
            height: 32.h,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onChg,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                filled: true,
                fillColor: colors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ─────────────────────────────────────────────
  // SPLIT SUMMARY ROW
  // ─────────────────────────────────────────────
  static Widget splitSummaryRow(
      double currentTotal,
      double diff,
      dynamic colors,
      ) {
    final bool balanced = diff.abs() < 0.01;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: balanced ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: balanced ? AppTheme.primaryGreen : Colors.red),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Split", style: AppTypography.cardSubtitle.copyWith(fontWeight: FontWeight.bold)),
              Text(currentTotal.toStringAsFixed(2), style: AppTypography.cardSubtitle.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          if (!balanced) ...[
            SizedBox(height: 4.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(diff > 0 ? "Under by" : "Over by",
                    style: AppTypography.cardInfo.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
                Text(diff.abs().toStringAsFixed(2),
                    style: AppTypography.cardInfo.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PRIVATE HELPER: SHOW CUSTOMER SEARCH
  // ─────────────────────────────────────────────
  static void _showCustomerSearch(
      Rx<Map<String, dynamic>?> selectedCustomer,
      List<Map<String, dynamic>> customers,
      Function(Map<String, dynamic>?) onCustomerSelected,
      dynamic colors,
      ) {
    final searchController = TextEditingController();
    final filteredCustomers = <Map<String, dynamic>>[].obs;
    filteredCustomers.assignAll(customers);

    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Search customer...",
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: colors.card,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  if (val.isEmpty) {
                    filteredCustomers.assignAll(customers);
                  } else {
                    filteredCustomers.assignAll(
                      customers.where((c) =>
                      (c['name']?.toString().toLowerCase().contains(val.toLowerCase()) ?? false) ||
                          (c['mobile']?.toString().contains(val) ?? false)).toList(),
                    );
                  }
                },
              ),
            ),
            Expanded(
              child: Obx(() => ListView.separated(
                itemCount: filteredCustomers.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                itemBuilder: (context, index) {
                  final customer = filteredCustomers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                      child: Icon(Icons.person, size: AppTypography.sizeText, color: AppTheme.primaryGreen),
                    ),
                    title: Text(
                      customer['name'] ?? "",
                      style: AppTypography.cardSubtitle.copyWith(color: colors.text),
                    ),
                    subtitle: Text(
                      customer['mobile'] ?? "No Mobile",
                      style: AppTypography.cardInfo.copyWith(color: colors.subtext),
                    ),
                    onTap: () {
                      onCustomerSelected(customer);
                      Get.back();
                    },
                  );
                },
              )),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}
