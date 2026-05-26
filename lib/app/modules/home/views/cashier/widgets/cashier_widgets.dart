import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';

class CashierWidgets {
  CashierWidgets._(); // private constructor (prevents instantiation)

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
              ? AppTypography.cardTitle.copyWith(color: colors.text)
              : AppTypography.cardSubtitle.copyWith(color: colors.subtext),
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // INPUT FIELD ROW
  // ─────────────────────────────────────────────
  static Widget inputFieldRow(
      String label,
      TextEditingController ctrl,
      Function(String) onChg,
      dynamic colors, {
        bool isNumber = false,
      }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: AppTypography.cardSubtitle.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: SizedBox(
            height: 40.h,
            child: TextField(
              controller: ctrl,
              keyboardType:
              TextInputType.numberWithOptions(decimal: !isNumber),
              onChanged: onChg,
              textAlign: TextAlign.right,
              style:
              AppTypography.cardTitle.copyWith(color: colors.text),
              decoration: InputDecoration(
                contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide:
                  BorderSide(color: AppTheme.primaryGreen),
                ),
              ),
            ),
          ),
        ),
      ],
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
            fontWeight: FontWeight.w500,
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
              value: items.any((e) =>
              (e['ledger_id'] as num).toInt() == selected)
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
                value:
                (acc['ledger_id'] as num).toInt(),
                child: Text(
                  acc['ledger_name'] ?? "",
                  style: AppTypography.cardSubtitle
                      .copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w500,
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
              fontWeight: FontWeight.w600,
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
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: readOnly ? null : onChg,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: readOnly ? colors.subtext : highlightColor,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                contentPadding:
                EdgeInsets.symmetric(horizontal: 8.w),
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}