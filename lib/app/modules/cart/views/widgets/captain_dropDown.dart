import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/cart_controller.dart';

class CaptainDropdown extends StatelessWidget {
  final CartController controller;

  const CaptainDropdown({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Obx(() {
      final captains = controller.captainsList;
      if (captains.isEmpty) return const SizedBox.shrink();

      return Theme(
        data: Theme.of(context).copyWith(
          canvasColor: colors.card,
          iconTheme: IconThemeData(color: colors.subtext),
        ),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: AppTypography.smallText),
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: colors.isDark
                  ? AppTheme.primaryGreen.withOpacity(0.4)
                  : AppTheme.primaryGreen.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                color: AppTheme.primaryGreen,
                size: AppTypography.cardTitle.fontSize,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(padding: EdgeInsets.zero,
                    value: controller.selectedCaptainId.value,
                    isExpanded: true,
                    dropdownColor: colors.card,
                    hint: Text(
                      "Select Captain",
                      style: AppTypography.cardSubtitle.copyWith(
                        color: colors.subtext,
                        fontSize: AppTypography.sizeText,
                      ),
                    ),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primaryGreen,
                      size: AppTypography.sizeText,
                    ),
                    // ✅ This style sets the SELECTED value text color
                    style: AppTypography.cardSubtitle.copyWith(
                      color: colors.text,
                      fontSize: AppTypography.sizeText,
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          "No Captain",
                          style: AppTypography.cardSubtitle.copyWith(
                            color: colors.subtext,
                            fontSize: AppTypography.sizeText,
                          ),
                        ),
                      ),
                      ...captains.map((captain) {
                        final int id = captain['ledger_id'] as int;
                        final String name =
                        (captain['ledg_name_only'] as String?)
                            ?.isNotEmpty ==
                            true
                            ? captain['ledg_name_only'] as String
                            : captain['ledger_name'] as String? ?? '';
                        return DropdownMenuItem<int?>(
                          value: id,
                          // ✅ Each item must set its own color explicitly —
                          //    the button-level `style` doesn't reach popup items
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.cardSubtitle.copyWith(
                              color: colors.text,
                              fontSize:AppTypography.smallText,
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        controller.clearCaptain();
                      } else {
                        final captain = captains.firstWhere(
                              (c) => c['ledger_id'] == value,
                        );
                        final String name =
                        (captain['ledg_name_only'] as String?)
                            ?.isNotEmpty ==
                            true
                            ? captain['ledg_name_only'] as String
                            : captain['ledger_name'] as String? ?? '';
                        controller.setCaption(value, name);
                      }
                    },
                  ),
                ),
              ),
              if (controller.selectedCaptainId.value != null)
                GestureDetector(
                  onTap: controller.clearCaptain,
                  child: Icon(
                    Icons.close,
                    size: AppTypography.sizeText,
                    color: colors.subtext,
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}