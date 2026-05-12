import 'package:flutter/material.dart';
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
      appBar: AppBar(
        title: Text("Settlement #${controller.order.invNo}"),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(AppTypography.sizeText),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ───────── TOTAL ─────────
            _totalSection(colors),

            const SizedBox(height: 20),

            /// ───────── PAYMENT TYPES ─────────
            _paymentSelector(colors),

            const SizedBox(height: 20),

            /// ───────── CASH INPUT ─────────
            _cashSection(colors),

            /// ───────── SPLIT SECTION ─────────
            _splitSection(colors),

            const Spacer(),

            /// ───────── BUTTON ─────────
            _settleButton(),
          ],
        ),
      ),
    );
  }

  /// ─────────────────────────────────────────────
  /// TOTAL SECTION
  /// ─────────────────────────────────────────────
  Widget _totalSection(dynamic colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Total"),
          Text(
            controller.totalToPay.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  /// ─────────────────────────────────────────────
  /// PAYMENT SELECTOR
  /// ─────────────────────────────────────────────
  Widget _paymentSelector(dynamic colors) {
    return Obx(() {
      return Wrap(
        spacing: 10,
        children: controller.paymentMethods.map((type) {
          final isSelected = controller.paymentMethod.value == type;

          return ChoiceChip(
            label: Text(type),
            selected: isSelected,
            onSelected: (_) => controller.setPaymentMethod(type),
          );
        }).toList(),
      );
    });
  }

  /// ─────────────────────────────────────────────
  /// CASH SECTION
  /// ─────────────────────────────────────────────
  Widget _cashSection(dynamic colors) {
    return Obx(() {
      if (controller.paymentMethod.value != 'Cash') {
        return const SizedBox();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Cash Received"),

          TextField(
            controller: controller.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: controller.updateReceivedAmount,
            decoration: const InputDecoration(
              hintText: "Enter amount",
            ),
          ),

          const SizedBox(height: 10),

          /// Change
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Change"),
              Obx(() => Text(
                controller.changeAmount.toStringAsFixed(2),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              )),
            ],
          ),
        ],
      );
    });
  }

  /// ─────────────────────────────────────────────
  /// SPLIT SECTION
  /// ─────────────────────────────────────────────
  Widget _splitSection(dynamic colors) {
    return Obx(() {
      if (controller.paymentMethod.value != 'Split') {
        return const SizedBox();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),

          const Text("Split Count"),

          TextField(
            controller: controller.splitCountController,
            keyboardType: TextInputType.number,
            onChanged: controller.updateSplitCount,
            decoration: const InputDecoration(
              hintText: "Enter number of people",
            ),
          ),

          const SizedBox(height: 10),

          /// Split List
          ...controller.splitAmounts.asMap().entries.map((entry) {
            int index = entry.key;
            double amount = entry.value;

            return ListTile(
              title: Text("Person ${index + 1}"),
              trailing: Text(amount.toStringAsFixed(2)),
            );
          }),
        ],
      );
    });
  }

  /// ─────────────────────────────────────────────
  /// SETTLE BUTTON
  /// ─────────────────────────────────────────────
  Widget _settleButton() {
    return Obx(() {
      return ElevatedButton(
        onPressed: controller.isProcessing.value
            ? null
            : controller.settleOrder,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
        ),
        child: controller.isProcessing.value
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text("Settle Order"),
      );
    });
  }
}