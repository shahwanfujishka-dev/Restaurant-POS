import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import 'package:restaurant_pos/app/modules/home/views/cashier/widgets/cashier_widgets.dart';
import 'package:restaurant_pos/helper/screen_type.dart';

import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/cashier_controller.dart';

class CashierView extends GetView<CashierController> {
  const CashierView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          "Settlement #${controller.order.invNo}",
          style: AppTypography.appBarTitle.copyWith(
            color: colors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: colors.card,
        elevation: 0.5,
        iconTheme: IconThemeData(
          color: colors.text,
          size: AppTypography.sizeText,
        ),
      ),
      body: SingleChildScrollView(
        controller: controller.scrollController,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          child: Column(
            children: [
              _minimalHeader(colors),
              SizedBox(height: 10.h),

              ScreenType.isMobile()?
              /// Customer Section
              CashierWidgets.customerSection(
                controller.paymentMethod,
                controller.isCustomerSelectEnabled,
                controller.selectedCustomer,
                controller.customerNameController,
                controller.customerMobileController,
                controller.customerAddressController,
                controller.customerVatController,
                controller.customers,
                controller.onCustomerSelected,
                colors,
              ):SizedBox.shrink(),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.border.withOpacity(0.5)),
              const SizedBox(height: 16),
              Column(
                children: [
                  _cashSection(colors),
                  _splitSection(colors),
                  const SizedBox(height: 100),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _actionButtons(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.transparent,
        elevation: 0,
        height: 70.h,
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HEADER
  // ─────────────────────────────────────────────

  Widget _minimalHeader(dynamic colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// LEFT: Payment Methods & Split Toggle
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...controller.paymentMethods.map((method) =>
                  CashierWidgets.paymentMethodItem(
                    method,
                    controller.paymentMethod,
                    colors,
                        () => controller.setPaymentMethod(method),
                  ),
              ),
              CashierWidgets.splitToggle(
                controller.isSplit,
                colors,
                    () => controller.toggleSplit(!controller.isSplit.value),
              ),
            ],
          ),
        ),

        const SizedBox(width: 24),

        /// RIGHT: Account Dropdowns + Summary
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() {
                final method = controller.paymentMethod.value;
                final showCash = method == 'Cash' || method == 'Multiple';
                final showBank = method == 'Card' || method == 'Bank' || method == 'Multiple';
                final showDropdowns = showCash || showBank;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDropdowns) ...[
                      if (showCash)
                        CashierWidgets.minimalDropdown(
                          "Cash Account",
                          controller.cashAccounts,
                          controller.selectedCashLedgerId.value,
                              (val) => controller.selectedCashLedgerId.value = val!,
                          colors,
                        ),
                      if (showCash && showBank) SizedBox(height: 8.h),
                      if (showBank)
                        CashierWidgets.minimalDropdown(
                          method == 'Multiple' ? "Bank Account" : "Select $method Account",
                          controller.bankAccounts,
                          controller.selectedBankLedgerId.value,
                              (val) => controller.selectedBankLedgerId.value = val!,
                          colors,
                        ),
                      SizedBox(height: 10.h),
                    ],

                    if (method == 'Card' || method == 'Bank') ...[
                      CashierWidgets.inlineAmountField(
                        "$method Amount",
                        controller.bankAmountController,
                        controller.updateBankReceivedAmount,
                        colors,
                        highlightColor: Colors.blue,
                        readOnly: true,
                      ),
                      SizedBox(height: 10.h),
                    ],

                    if (method == 'Multiple') ...[
                      CashierWidgets.inlineAmountField(
                        "Cash Amount",
                        controller.multiCashController,
                        controller.updateMultiCashAmount,
                        colors,
                        highlightColor: AppTheme.primaryGreen,
                        readOnly: false,
                      ),
                      SizedBox(height: 8.h),
                      CashierWidgets.inlineAmountField(
                        "Bank Amount",
                        controller.multiBankController,
                        controller.updateMultiBankAmount,
                        colors,
                        highlightColor: Colors.blue,
                        readOnly: false,
                      ),
                      SizedBox(height: 8.h),
                      CashierWidgets.multiTotalRow(
                        controller.multiCashAmount,
                        controller.multiBankAmount,
                        controller.totalToPay,
                        colors,
                      ),
                      SizedBox(height: 10.h),
                    ],

                    if (showDropdowns || method != 'Credit')
                      Divider(height: 1, color: colors.border.withOpacity(0.5)),
                    SizedBox(height: 10.h),
                  ],
                );
              }),

              /// Summary Rows
              Obx(() => Column(
                children: [
                  CashierWidgets.summaryRow(
                    "Subtotal",
                    controller.subtotal.toStringAsFixed(2),
                    colors,
                  ),
                  SizedBox(height: 8.h),
                  CashierWidgets.summaryRow(
                    "Tax",
                    controller.tax.toStringAsFixed(2),
                    colors,
                  ),
                  SizedBox(height: 8.h),
                  CashierWidgets.minimalDiscountInput(
                    controller.discountController,
                    controller.updateDiscountAmount,
                    colors,
                  ),
                  SizedBox(height: 8.h),
                  CashierWidgets.minimalRoundOffInput(
                    controller.roundOffController,
                    controller.updateRoundOffAmount,
                    controller.incrementRoundOff,
                    controller.decrementRoundOff,
                    colors,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Divider(height: 1, color: colors.border),
                  ),
                  CashierWidgets.summaryRow(
                    "Grand Total",
                    controller.totalToPay.toStringAsFixed(2),
                    colors,
                    isTotal: true,
                  ),
                ],
              )),
              !ScreenType.isMobile()?
              CashierWidgets.customerSection(
                controller.paymentMethod,
                controller.isCustomerSelectEnabled,
                controller.selectedCustomer,
                controller.customerNameController,
                controller.customerMobileController,
                controller.customerAddressController,
                controller.customerVatController,
                controller.customers,
                controller.onCustomerSelected,
                colors,
              )
                  :SizedBox.shrink(),
            ],
          ),
        ),

      ],
    );
  }

  // ─────────────────────────────────────────────
  //  CASH SECTION
  // ─────────────────────────────────────────────

  Widget _cashSection(dynamic colors) {
    return Obx(() {
      final method = controller.paymentMethod.value;
      if (method != 'Cash') return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CashierWidgets.inputFieldRow(
            "Cash Received",
            controller.amountController,
            controller.updateReceivedAmount,
            colors,
            readOnly: true,
          ),
          SizedBox(height: 16.h),
        ],
      );
    });
  }

  // ─────────────────────────────────────────────
  //  SPLIT SECTION
  // ─────────────────────────────────────────────

  Widget _splitSection(dynamic colors) {
    return Obx(() {
      if (!controller.isSplit.value) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CashierWidgets.inputFieldRow(
            "Split Count",
            controller.splitCountController,
            controller.updateSplitCount,
            colors,
            isNumber: true,
          ),
          SizedBox(height: 16.h),
          Text(
            "Individual Amounts",
            style: AppTypography.cardSubtitle.copyWith(
              color: colors.subtext,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          ...controller.splitControllers.asMap().entries.map((entry) {
            return CashierWidgets.splitAmountEditRow(
              entry.key,
              entry.value,
              (val) => controller.updateSplitAmount(entry.key, val),
              colors,
            );
          }),
          SizedBox(height: 12.h),
          CashierWidgets.splitSummaryRow(
            controller.currentSplitTotal,
            controller.splitDifference,
            colors,
          ),
        ],
      );
    });
  }

  // ─────────────────────────────────────────────
  //  ACTION BUTTONS
  // ─────────────────────────────────────────────

  Widget _actionButtons(BuildContext context) {
    return Obx(() => Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52.h,
              child: ElevatedButton.icon(
                onPressed: controller.isProcessing.value ? null : controller.handleCompliment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.card_giftcard),
                label: Text(
                  "COMPLIMENT",
                  style: AppTypography.button.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: AppTypography.sizeCategory,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52.h,
              child: FloatingActionButton.extended(
                onPressed: controller.isProcessing.value ? null : controller.settleOrder,
                backgroundColor: AppTheme.primaryGreen,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                label: controller.isProcessing.value
                    ? SizedBox(
                  height: 24.h,
                  width: 24.h,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                    : Text(
                  "SETTLE ORDER",
                  style: AppTypography.button.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: AppTypography.sizeCategory,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
