import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

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
          style: AppTypography.appBarTitle.copyWith(color: colors.text, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: colors.card,
        elevation: 0.5,
        iconTheme: IconThemeData(color: colors.text, size: AppTypography.sizeText),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: Column(
          children: [
            /// ───────── HEADER (Payment Methods | Account Dropdowns + Summary) ─────────
            _minimalHeader(colors),

            const SizedBox(height: 16),
            Divider(height: 1, color: colors.border.withOpacity(0.5)),
            const SizedBox(height: 16),

            /// ───────── DYNAMIC INPUTS ─────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _customerSection(colors),
                    _cashSection(colors),
                    _splitSection(colors),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
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
              ...controller.paymentMethods
                  .map((method) => _paymentMethodItem(method, colors))
                  .toList(),
              _splitToggle(colors),
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
              // ── Account Dropdowns + Payment Fields (reactive) ──
              Obx(() {
                final method = controller.paymentMethod.value;
                final showCash = method == 'Cash' || method == 'Multiple';
                final showBank = method == 'Card' || method == 'Bank' || method == 'Multiple';
                final showDropdowns = showCash || showBank;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Account Dropdowns
                    if (showDropdowns) ...[
                      if (showCash)
                        _buildMinimalDropdown(
                          "Cash Account",
                          controller.cashAccounts,
                          controller.selectedCashLedgerId.value,
                              (val) => controller.selectedCashLedgerId.value = val!,
                          colors,
                        ),
                      if (showCash && showBank) SizedBox(height: 8.h),
                      if (showBank)
                        _buildMinimalDropdown(
                          method == 'Multiple' ? "Bank Account" : "Select $method Account",
                          controller.bankAccounts,
                          controller.selectedBankLedgerId.value,
                              (val) => controller.selectedBankLedgerId.value = val!,
                          colors,
                        ),
                      SizedBox(height: 10.h),
                    ],

                    // ── Payment Fields directly below dropdowns ──
                    if (method == 'Cash') ...[
                      _inlineAmountField(
                        "Cash Received",
                        controller.amountController,
                        controller.updateReceivedAmount,
                        colors,
                        highlightColor: AppTheme.primaryGreen,
                        readOnly: true,
                      ),
                      SizedBox(height: 10.h),
                    ],

                    if (method == 'Card' || method == 'Bank') ...[
                      _inlineAmountField(
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
                      _inlineAmountField(
                        "Cash Amount",
                        controller.multiCashController,
                        controller.updateMultiCashAmount,
                        colors,
                        highlightColor: AppTheme.primaryGreen,
                        readOnly: false,
                      ),
                      SizedBox(height: 8.h),
                      _inlineAmountField(
                        "Bank Amount",
                        controller.multiBankController,
                        controller.updateMultiBankAmount,
                        colors,
                        highlightColor: Colors.blue,
                        readOnly: false,
                      ),
                      SizedBox(height: 8.h),
                      _multiTotalRow(colors),
                      SizedBox(height: 10.h),
                    ],

                    // ── Divider before summary ──
                    if (showDropdowns || method != 'Credit')
                      Divider(height: 1, color: colors.border.withOpacity(0.5)),
                    SizedBox(height: 10.h),
                  ],
                );
              }),

              // ── Summary Rows ──
              Obx(() => Column(
                children: [
                  _summaryRow("Subtotal", controller.subtotal.toStringAsFixed(2), colors),
                  SizedBox(height: 8.h),
                  _summaryRow("Tax", controller.tax.toStringAsFixed(2), colors),
                  SizedBox(height: 8.h),
                  _minimalDiscountInput(colors),
                  SizedBox(height: 8.h),
                  _minimalRoundOffInput(colors),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Divider(height: 1, color: colors.border),
                  ),
                  _summaryRow(
                    "Grand Total",
                    controller.totalToPay.toStringAsFixed(2),
                    colors,
                    isTotal: true,
                  ),
                ],
              )),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  PAYMENT METHOD ITEMS
  // ─────────────────────────────────────────────

  Widget _paymentMethodItem(String method, dynamic colors) {
    return Obx(() {
      final isSelected = controller.paymentMethod.value == method;
      return GestureDetector(
        onTap: () => controller.setPaymentMethod(method),
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 6.h),
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
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
            ),
          ),
        ),
      );
    });
  }

  Widget _splitToggle(dynamic colors) {
    return Obx(() => GestureDetector(
      onTap: () => controller.toggleSplit(!controller.isSplit.value),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(top: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: controller.isSplit.value
              ? Colors.orange.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: controller.isSplit.value ? Colors.orange : colors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.call_split,
              size: 16.sp,
              color: controller.isSplit.value ? Colors.orange : colors.text,
            ),
            SizedBox(width: 8.w),
            Text(
              "Split Amount",
              style: AppTypography.cardSubtitle.copyWith(
                color: controller.isSplit.value ? Colors.orange : colors.text,
                fontWeight: controller.isSplit.value
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // ─────────────────────────────────────────────
  //  CUSTOMER SECTION
  // ─────────────────────────────────────────────

  Widget _customerSection(dynamic colors) {
    return Obx(() {
      if (controller.paymentMethod.value != 'Credit') return const SizedBox.shrink();

      return Container(
        margin: EdgeInsets.only(bottom: 20.h),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header with toggle
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              color: AppTheme.primaryGreen,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "CUSTOMER",
                    style: AppTypography.cardTitle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Obx(() => CupertinoSwitch(
                    value: controller.isCustomerSelectEnabled.value,
                    onChanged: (val) => controller.isCustomerSelectEnabled.value = val,
                    activeColor: Colors.white.withOpacity(0.3),
                    trackColor: Colors.black26,
                  )),
                ],
              ),
            ),

            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  Obx(() {
                    if (controller.isCustomerSelectEnabled.value) {
                      return _buildCustomerSelector(colors);
                    } else {
                      return _buildReadOnlyTextField(
                        "Customer Name",
                        controller.customerNameController,
                        colors,
                      );
                    }
                  }),
                  SizedBox(height: 12.h),
                  _buildCustomerInput(
                    "Mobile",
                    controller.customerMobileController,
                    colors,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(height: 12.h),
                  _buildCustomerInput(
                    "VAT",
                    controller.customerVatController,
                    colors,
                  ),
                  SizedBox(height: 12.h),
                  _buildCustomerInput(
                    "Address",
                    controller.customerAddressController,
                    colors,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCustomerSelector(dynamic colors) {
    return GestureDetector(
      onTap: () => _showCustomerSearch(colors),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Obx(() => Text(
                controller.selectedCustomer.value?['name'] ?? "Select Customer",
                style: AppTypography.cardSubtitle.copyWith(
                  color: controller.selectedCustomer.value != null ? colors.text : colors.subtext,
                  fontWeight: FontWeight.w500,
                ),
           )),
            ),
            Icon(Icons.arrow_drop_down, color: colors.subtext),
          ],
        ),
      ),
    );
  }

  void _showCustomerSearch(dynamic colors) {
    final searchController = TextEditingController();
    final filteredCustomers = <Map<String, dynamic>>[].obs;
    filteredCustomers.assignAll(controller.customers);

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
                  hintText: "Search customer by name or mobile...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
                onChanged: (val) {
                  if (val.isEmpty) {
                    filteredCustomers.assignAll(controller.customers);
                  } else {
                    filteredCustomers.assignAll(
                      controller.customers.where((c) =>
                        (c['name']?.toString().toLowerCase().contains(val.toLowerCase()) ?? false) ||
                        (c['mobile']?.toString().contains(val) ?? false)
                      ).toList(),
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
                    title: Text(customer['name'] ?? "", style: AppTypography.cardSubtitle.copyWith(color: colors.text)),
                    subtitle: Text(customer['mobile'] ?? "No Mobile", style: AppTypography.cardInfo.copyWith(color: colors.subtext)),
                    onTap: () {
                      controller.onCustomerSelected(customer);
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

  Widget _buildCustomerInput(
      String label,
      TextEditingController ctrl,
      dynamic colors, {
        TextInputType keyboardType = TextInputType.text,
        int maxLines = 1,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.cardInfo.copyWith(color: colors.subtext),
        ),
        SizedBox(height: 4.h),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: AppTypography.cardSubtitle.copyWith(color: colors.text),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            filled: true,
            fillColor: colors.bg,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(color: AppTheme.primaryGreen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyTextField(String label, TextEditingController ctrl, dynamic colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.cardInfo.copyWith(color: colors.subtext)),
        SizedBox(height: 4.h),
        TextField(
          controller: ctrl,
          readOnly: true,
          style: AppTypography.cardSubtitle.copyWith(color: colors.text, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            filled: true,
            fillColor: colors.bg.withOpacity(0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: colors.border)),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, dynamic colors, {bool isTotal = false}) {
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

  Widget _minimalDiscountInput(dynamic colors) {
    return Row(
      children: [
        Text(
          "Discount",
          style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: SizedBox(
            height: 32.h,
            child: TextField(
              controller: controller.discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: controller.updateDiscountAmount,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
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

  Widget _minimalRoundOffInput(dynamic colors) {
    return Row(
      children: [
        Text(
          "Round Off",
          style: AppTypography.cardSubtitle.copyWith(color: colors.subtext),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: SizedBox(
            height: 32.h,
            child: TextField(
              controller: controller.roundOffController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: controller.updateRoundOffAmount,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: "0.00",
                contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
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

  Widget _cashSection(dynamic colors) {
    return Obx(() {
      final method = controller.paymentMethod.value;
      if (method != 'Cash') return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputFieldRow(
            "Cash Received",
            controller.amountController,
            controller.updateReceivedAmount,
            colors,
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Change",
                  style: AppTypography.cardSubtitle.copyWith(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Obx(() => Text(
                  controller.changeAmount.toStringAsFixed(2),
                  style: AppTypography.cardTitle.copyWith(
                    color: Colors.orange.shade900,
                    fontSize: AppTypography.sizeText,
                  ),
                )),
              ],
            ),
          ),
          SizedBox(height: 16.h),
        ],
      );
    });
  }

  Widget _splitSection(dynamic colors) {
    return Obx(() {
      if (!controller.isSplit.value) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputFieldRow(
            "Split Count",
            controller.splitCountController,
            controller.updateSplitCount,
            colors,
            isNumber: true,
          ),
          SizedBox(height: 12.h),
          ...controller.splitAmounts.asMap().entries.map((entry) {
            return Container(
              margin: EdgeInsets.only(bottom: 8.h),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: colors.border.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Person ${entry.key + 1}",
                    style: AppTypography.cardSubtitle.copyWith(color: colors.text),
                  ),
                  Text(
                    entry.value.toStringAsFixed(2),
                    style: AppTypography.cardTitle.copyWith(
                      color: AppTheme.primaryGreen,
                      fontSize: AppTypography.sizeText,
                    ),
                  ),
                ],
              ),
            );
          }),
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
                  style: AppTypography.button.copyWith(fontWeight: FontWeight.w900, fontSize: AppTypography.sizeCategory),
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

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  Widget _inputFieldRow(
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
              keyboardType: TextInputType.numberWithOptions(decimal: !isNumber),
              onChanged: onChg,
              textAlign: TextAlign.right,
              style: AppTypography.cardTitle.copyWith(color: colors.text),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
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
                  borderSide: BorderSide(color: AppTheme.primaryGreen),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalDropdown(
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

  /// Compact inline amount field used inside the header
  Widget _inlineAmountField(
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: readOnly ? null : onChg,
              textAlign: TextAlign.right,
              style: AppTypography.cardSubtitle.copyWith(
                color: readOnly ? colors.subtext : highlightColor,
                fontWeight: FontWeight.bold,
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

  /// Running total summary row for Multiple mode
  Widget _multiTotalRow(dynamic colors) {
    return Obx(() {
      final entered = controller.multiCashAmount.value + controller.multiBankAmount.value;
      final total = controller.totalToPay;
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
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isValid
                  ? (entered - total).toStringAsFixed(2)
                  : remaining.toStringAsFixed(2),
              style: AppTypography.cardSubtitle.copyWith(
                color: isValid ? AppTheme.primaryGreen : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    });
  }
}
