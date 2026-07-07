import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:intl/intl.dart';
import 'package:restaurant_pos/app/modules/home/views/orders/widgets/AnimatedTabBar.dart';

import '../../../../../helper/screen_type.dart';
import '../../../../data/models/order_model.dart';
import '../../../../data/services/database_helper.dart';
import '../../../../routes/app_pages.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../../cart/controller/cart_controller.dart';
import '../../controller/dashboard_controller.dart';
import '../../controller/order_controller.dart';
import '../../controller/printer_controller.dart';
import '../dashoard/widgets/dashboard_widgets/food_item_shimmer.dart';

class OrdersPage extends GetView<OrdersController> {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController dashboardController =
        Get.find<DashboardController>();
    final colors = AppColors.of(context);

    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return Scaffold(
            backgroundColor: colors.bg,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(60.h),
              child: Container(
                color: colors.card,
                padding: EdgeInsets.symmetric(horizontal: ScreenType.isMobile() ? 10.w : 55.w, vertical: 10.h),
                child: AnimatedTabBar(
                  tabController: tabController,
                ),
              ),
            ),
            body: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: FoodItemShimmer());
              }
              return TabBarView(
                controller: tabController,
                children: [
                  _buildOrderList(
                    context,
                    controller.dineInOrders,
                    dashboardController,
                  ),
                  _buildOrderList(
                    context,
                    controller.deliveryOrders,
                    dashboardController,
                  ),
                  _buildOrderList(
                    context,
                    controller.pickupOrders,
                    dashboardController,
                  ),
                  _buildPaidOrderList(
                    context,
                    dashboardController,
                  ),
                ],
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildPaidOrderList(
    BuildContext context,
    DashboardController dashboardController,
  ) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        // Date Selector Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),
          color: colors.card,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, size: AppTypography.sizeText, color: colors.subtext),
                  SizedBox(width: 8.w),
                  Obx(() => Text(
                        DateFormat('EEEE, MMM d, yyyy')
                            .format(controller.selectedSoldDate.value),
                        style: AppTypography.cardSubtitle.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                        ),
                      )),
                ],
              ),
              TextButton.icon(
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: controller.selectedSoldDate.value,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: colors.isDark 
                            ? ColorScheme.dark(
                                primary: AppTheme.primaryGreen,
                                onPrimary: Colors.white,
                                surface: colors.card,
                                onSurface: colors.text,
                              )
                            : ColorScheme.light(
                                primary: AppTheme.primaryGreen,
                                onPrimary: Colors.white,
                                surface: colors.card,
                                onSurface: colors.text,
                              ),
                          dialogBackgroundColor: colors.card,
                          textButtonTheme: TextButtonThemeData(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    controller.changeSoldDate(picked);
                  }
                },
                icon: Icon(Icons.edit_calendar, size:AppTypography.sizeText),
                label: Text('change_date'.tr),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() => _buildOrderList(
                context,
                controller.paidOrders,
                dashboardController,
              )),
        ),
      ],
    );
  }

  Widget _buildOrderList(
    BuildContext context,
    List<OrderModel> orders,
    DashboardController dashboardController,
  ) {
    final colors = AppColors.of(context);

    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.fetchOrders,
        child: Stack(
          children: [
            ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 0.2.sh),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 60.sp,
                        color: colors.subtext.withOpacity(0.5),
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        'no_orders'.tr,
                        style: AppTypography.subtitle.copyWith(
                          color: colors.subtext,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'pull_to_refresh'.tr,
                        style: AppTypography.cardInfo.copyWith(
                          color: colors.subtext.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (ScreenType.isMobile()) {
      return RefreshIndicator(
        onRefresh: controller.fetchOrders,
        child: ListView.builder(
          padding: EdgeInsets.all(12.w),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _MobileOrderCard(
              order: order,
              index: index,
              onEdit: () => controller.editOrder(order),
              onDelete: () => controller.cancelOrder(order),
              onTap: () {
                controller.fetchOrderDetails(order);
                _showMobileOrderDetails(
                  context,
                  order,
                  onEdit: () => controller.editOrder(order),
                  onDelete: () => controller.cancelOrder(order),
                );
              },
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.fetchOrders,
      child: GridView.builder(
        padding: EdgeInsets.all(8.w),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12.h,
          crossAxisSpacing: 12.w,
          mainAxisExtent: 180.h,
        ),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _OrderTicket(
            order: order,
            index: index,
            onEdit: () => controller.editOrder(order),
            onDelete: () => controller.cancelOrder(order),
            onTap: () {
              controller.fetchOrderDetails(order);
              _showOrderDetailsDialog(context, order, dashboardController);
            },
          );
        },
      ),
    );
  }
}

void _showOrderDetailsDialog(
  BuildContext context,
  OrderModel order,
  DashboardController dashboardController,
) {
  final controller = Get.find<OrdersController>();
  final colors = AppColors.of(context);
  final displayColor = (order.status.value == OrderStatus.draft || order.status.value == OrderStatus.billed)
      ? _getStatusColor(order.status.value)
      : _getOrderTypeColor(order.sales_odr_order_type);

  Get.dialog(
    Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Obx(() {
        final currentOrder = controller.orders.firstWhereOrNull(
          (o) => o.id == order.id,
        ) ?? controller.soldOrders.firstWhereOrNull(
          (o) => o.id == order.id,
        ) ?? order;

        final String displayIdentifier = currentOrder.status.value == OrderStatus.paid
            ? _getOrderTypeName(currentOrder.sales_odr_order_type)
            : currentOrder.tableName;

        // Calculate subtotal from items to ensure accuracy
        double calculatedSubtotal = 0;
        for (var item in currentOrder.items) {
          calculatedSubtotal += item.priceAtOrder * item.quantity;
        }
        final totAmt = currentOrder.finalTotal;

        return Container(
          width: 0.4.sw,
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'order_details'.tr,
                        style: AppTypography.cardTitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                      RichText(
                        text: TextSpan(
                          style: AppTypography.cardSubtitle.copyWith(
                            color: colors.subtext,
                          ),
                          children: [
                            TextSpan(text: 'Inv: #${currentOrder.invNo} • '),
                            TextSpan(
                              text: displayIdentifier,
                              style: TextStyle(
                                color: displayColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (currentOrder.chairNumber > 0)
                              TextSpan(text: " • ${currentOrder.chairNumber} chairs"),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (currentOrder.sales_odr_pos_status == 1 || currentOrder.sales_odr_pos_status == 2 || currentOrder.status.value == OrderStatus.paid)
                        IconButton(
                          onPressed: () {
                            final printerController =
                                Get.find<PrinterController>();
                            if (currentOrder.status.value == OrderStatus.paid) {
                              printerController.printReceipt(
                                currentOrder,
                                currentOrder.totalAmount,
                                0, // change
                                roundOff: currentOrder.roundOff,    // ← add this
                                discount: currentOrder.discount,    // ← add this
                              );                            } else {
                              printerController.printKOT(currentOrder);
                            }
                          },
                          icon: const Icon(Icons.print, color: Colors.blue),
                          tooltip: 'print_kot'.tr,
                        ),
                      if (currentOrder.sales_odr_pos_status == 1 || currentOrder.sales_odr_pos_status == 2 && currentOrder.status.value != OrderStatus.paid)
                        IconButton(
                          onPressed: () {
                            final printerController = Get.find<PrinterController>();
                            printerController.printReceipt(currentOrder, 0, 0, isBill: true);
                          },
                          icon: const Icon(Icons.receipt_long, color: Colors.orange),
                          tooltip: 'Print Bill',
                        ),
                      if (currentOrder.status.value != OrderStatus.paid)
                      IconButton(
                        onPressed: () {
                          Get.back();
                          controller.cancelOrder(currentOrder);
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        tooltip: 'cancel_order'.tr,
                      ),
                      IconButton(
                        onPressed: () => Get.back(),
                        icon: Icon(Icons.close, color: colors.text),
                      ),
                    ],
                  ),
                ],
              ),
              Divider(color: colors.border),
              SizedBox(height: 5.h),
              if(currentOrder.status.value != OrderStatus.paid)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: Colors.orange,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    controller.getElapsedTime(currentOrder.createdAt),
                    style: AppTypography.cardTitle.copyWith(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (currentOrder.items.isEmpty)
                Padding(
                  padding: EdgeInsets.all(20.w),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 0.4.sh),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: currentOrder.items.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: colors.border.withOpacity(0.5)),
                    itemBuilder: (context, index) {
                      final item = currentOrder.items[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: colors.textField,
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                '${item.quantity}x',
                                style: AppTypography.cardSubtitle.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: displayColor,
                                ),
                              ),
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: AppTypography.cardSubtitle.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.text,
                                    ),
                                  ),
                                  Text(
                                    '${item.priceAtOrder.toStringAsFixed(2)} each',
                                    style: AppTypography.cardSubtitle.copyWith(
                                      color: colors.subtext,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${(item.priceAtOrder * item.quantity).toStringAsFixed(2)}',
                              style: AppTypography.cardSubtitle.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.text,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: displayColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(context, 'Subtotal', calculatedSubtotal, colors.text, bold: false),
                    if (currentOrder.discount > 0)
                      _buildDetailRow(context, 'Discount', -currentOrder.discount, Colors.red, bold: false),
                    if (dashboardController.vatType.value == 0 || currentOrder.totalTax > 0)
                      _buildDetailRow(context, 'Tax', currentOrder.totalTax, colors.text, bold: false),
                    if (currentOrder.roundOff != 0)
                      _buildDetailRow(context, 'Round Off', currentOrder.roundOff, colors.text, bold: false),
                    const Divider(),
                    _buildDetailRow(context, 'Total Amount', totAmt, displayColor, bold: true),
                  ],
                ),
              ),
              // SizedBox(height: 16.h),
              // if (currentOrder.status.value != OrderStatus.paid &&
              //     currentOrder.status.value != OrderStatus.cancelled &&
              //     currentOrder.status.value != OrderStatus.draft)
              //   ElevatedButton(
              //     onPressed: () {
              //       Get.back();
              //       controller.goToCashier(currentOrder);
              //     },
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: displayColor,
              //       minimumSize: Size(double.infinity, 48.h),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12.r),
              //       ),
              //     ),
              //     child: Text("Settle Order", style: AppTypography.button),
              //   ),
            ],
          ),
        );
      }),
    ),
  );
}

Widget _buildDetailRow(BuildContext context, String label, double amount, Color color, {bool bold = false, double? fontSize}) {
  final colors = AppColors.of(context);
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 2.h),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.tr,
          style: AppTypography.cardTitle.copyWith(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: colors.text,
            fontSize: fontSize,
          ),
        ),
        Text(
          amount.toStringAsFixed(2),
          style: AppTypography.cardTitle.copyWith(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
            fontSize: fontSize,
          ),
        ),
      ],
    ),
  );
}

class _MobileOrderCard extends StatelessWidget {
  final OrderModel order;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _MobileOrderCard({
    required this.order,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OrdersController>();
    final colors = AppColors.of(context);
    final displayColor = (order.status.value == OrderStatus.draft || order.status.value == OrderStatus.billed)
        ? _getStatusColor(order.status.value)
        : _getOrderTypeColor(order.sales_odr_order_type);

    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 100)),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6.w,
                  decoration: BoxDecoration(
                    color: displayColor,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(16.r),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              order.status.value == OrderStatus.paid
                                  ? _getOrderTypeName(order.sales_odr_order_type)
                                  : order.tableName,
                              style: AppTypography.cardTitle.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16.sp,
                                color: order.status.value == OrderStatus.paid ? displayColor : colors.text,
                              ),
                            ),
                            Row(
                              children: [
                                if (order.status.value != OrderStatus.paid &&
                                    order.status.value != OrderStatus.cancelled)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: onEdit,
                                    icon: const Icon(
                                      Icons.edit_note,
                                      color: Colors.blue,
                                    ),
                                  ),
                                SizedBox(width: 4.w),
                                if (order.status.value != OrderStatus.paid &&
                                    order.status.value != OrderStatus.cancelled)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: onDelete,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                  ),
                                SizedBox(width: 8.w),
                                _StatusBadge(status: order.status.value),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Inv: #${order.invNo}${order.chairNumber > 0 ? " • Chair ${order.chairNumber}" : ""}',
                          style: AppTypography.cardSubtitle.copyWith(
                            color: colors.subtext,
                          ),
                        ),
                        if (order.isUnsynced)
                          Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: Text(
                              "PENDING SYNC",
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        SizedBox(height: 12.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${DateFormat('hh:mm a').format(order.createdAt)}',
                                  style: AppTypography.cardSubtitle.copyWith(
                                    fontSize: 12.sp,
                                    color: colors.subtext,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                if(order.status.value != OrderStatus.paid)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  child: Obx(
                                    () => Text(
                                      controller.getElapsedTime(
                                        order.createdAt,
                                      ),
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${order.finalTotal.toStringAsFixed(2)}',
                              style: AppTypography.cardTitle.copyWith(
                                color: displayColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16.sp,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderTicket extends StatelessWidget {
  final OrderModel order;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _OrderTicket({
    required this.order,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OrdersController>();
    final colors = AppColors.of(context);
    final displayColor = (order.status.value == OrderStatus.draft || order.status.value == OrderStatus.billed)
        ? _getStatusColor(order.status.value)
        : _getOrderTypeColor(order.sales_odr_order_type);
    final totalAmt = order.finalTotal;
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 100)),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.8 + (0.2 * value), child: child),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Column(
            children: [
              Container(
                height: 40.h,
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                color: displayColor.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        order.status.value == OrderStatus.paid
                            ? _getOrderTypeName(order.sales_odr_order_type)
                            : order.tableName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardSubtitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: displayColor,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (order.status.value != OrderStatus.paid &&
                            order.status.value != OrderStatus.cancelled)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onEdit,
                            icon: Icon(
                              Icons.edit_note,
                              size: AppTypography.sizeCategory,
                              color: displayColor,
                            ),
                          ),
                        // SizedBox(width: 2.w),
                        if (order.status.value != OrderStatus.paid &&
                            order.status.value != OrderStatus.cancelled)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onDelete,
                            icon: Icon(
                              Icons.delete_outline,
                              size: AppTypography.sizeCategory,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(2.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Inv: #${order.invNo}',
                          style: AppTypography.cardSubtitle.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if(order.status.value != OrderStatus.paid)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4.w,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Obx(
                                () => Text(
                                  controller.getElapsedTime(
                                    order.createdAt,
                                  ),
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: AppTypography.smallText,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateFormat('hh:mm a').format(order.createdAt),
                          style: AppTypography.cardInfo.copyWith(
                            fontSize: AppTypography.smallText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                height: 40.h,
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                decoration: BoxDecoration(
                  color: displayColor,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12.r),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      totalAmt.toStringAsFixed(2),
                      style: AppTypography.cardSubtitle.copyWith(
                        color: displayColor == Colors.lightGreen ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (order.status.value != OrderStatus.paid &&
                        order.status.value != OrderStatus.cancelled && order.status.value != OrderStatus.draft)
                      GestureDetector(
                        onTap: () {
                          controller.goToCashier(order);
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: (displayColor == Colors.lightGreen ? Colors.black : Colors.white).withOpacity(0.25),
                            borderRadius: BorderRadius.circular(6.r),
                            border: Border.all(color: (displayColor == Colors.lightGreen ? Colors.black54 : Colors.white54)),
                          ),
                          child: Text(
                            'PAY',
                            style: TextStyle(
                              color: displayColor == Colors.lightGreen ? Colors.black : Colors.white,
                              fontSize: AppTypography.sizeText,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        order.status.value.name.toUpperCase(),
                        style: AppTypography.cardSubtitle.copyWith(
                          color: displayColor == Colors.lightGreen ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

Color _getOrderTypeColor(int type) {
  switch (type) {
    case 0: // Dine In
      return Colors.orange;
    case 1: // Delivery
      return Colors.blue;
    case 2: // Pickup
      return AppTheme.primaryGreen;
      case 3: // Paid
      return Colors.teal;
    default:
      return AppTheme.primaryGreen;
  }
}

Color _getStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Colors.orange;
    case OrderStatus.preparing:
      return Colors.blue;
    case OrderStatus.ready:
      return Colors.purple;
    case OrderStatus.served:
      return AppTheme.primaryGreen;
    case OrderStatus.paid:
      return Colors.teal;
    case OrderStatus.cancelled:
      return Colors.red;
    case OrderStatus.draft:
      return Colors.grey;
    case OrderStatus.billed:
      return Colors.lightGreen;
    default:
      return Colors.yellow;
  }
}

void _showMobileOrderDetails(
  BuildContext context,
  OrderModel order, {
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final colors = AppColors.of(context);
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: _OrderDetailsContent(
        order: order,
        isMobile: true,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    ),
    isScrollControlled: true,
  );
}

class _OrderDetailsContent extends StatelessWidget {
  final OrderModel order;
  final bool isMobile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OrderDetailsContent({
    required this.order,
    required this.isMobile,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final DashboardController dashboardController =
        Get.find<DashboardController>();
    final colors = AppColors.of(context);
    final displayColor = (order.status.value == OrderStatus.draft || order.status.value == OrderStatus.billed)
        ? _getStatusColor(order.status.value)
        : _getOrderTypeColor(order.sales_odr_order_type);
    final DatabaseHelper _dbHelper = DatabaseHelper.instance;
    return Container(
      width: isMobile ? double.infinity : 0.4.sw,
      padding: EdgeInsets.all(isMobile ? 24.w : 20.w),
      child: Obx(() {
        final controller = Get.find<OrdersController>();
        final currentOrder = controller.orders.firstWhereOrNull(
          (o) => o.id == order.id,
        ) ?? controller.soldOrders.firstWhereOrNull(
          (o) => o.id == order.id,
        ) ?? order;

        final String displayIdentifier = currentOrder.status.value == OrderStatus.paid
            ? _getOrderTypeName(currentOrder.sales_odr_order_type)
            : currentOrder.tableName;

        // Calculate subtotal from items to ensure accuracy
        double calculatedSubtotal = 0;
        for (var item in currentOrder.items) {
          calculatedSubtotal += item.priceAtOrder * item.quantity;
        }
        final totAmt = currentOrder.finalTotal;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile)
              Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 20.h),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'order_details'.tr,
                      style: AppTypography.cardTitle.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 18.sp : 16.sp,
                        color: colors.text,
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        style: AppTypography.cardSubtitle.copyWith(
                          color: colors.subtext,
                        ),
                        children: [
                          TextSpan(text: 'Inv: #${currentOrder.invNo} • '),
                          TextSpan(
                            text: displayIdentifier,
                            style: TextStyle(
                              color: displayColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (currentOrder.sales_odr_pos_status == 1 || currentOrder.sales_odr_pos_status == 2 || currentOrder.status.value == OrderStatus.paid)
                      IconButton(
                        onPressed: () {
                          final printerController =
                              Get.find<PrinterController>();
                          if (currentOrder.status.value == OrderStatus.paid) {
                            printerController.printReceipt(
                              currentOrder,
                              currentOrder.totalAmount,
                              0, // change
                              roundOff: currentOrder.roundOff,    // ← add this
                              discount: currentOrder.discount,    // ← add this
                            );                          } else {
                            printerController.printKOT(currentOrder);
                          }
                        },
                        icon: const Icon(Icons.print, color: Colors.blue),
                        tooltip: 'print_kot'.tr,
                      ),
                    if (currentOrder.sales_odr_pos_status == 1 || currentOrder.sales_odr_pos_status == 2 && currentOrder.status.value != OrderStatus.paid)
                      IconButton(
                        onPressed: () {
                          final printerController = Get.find<PrinterController>();
                          printerController.printReceipt(currentOrder, 0, 0, isBill: true);
                        },
                        icon: const Icon(Icons.receipt_long, color: Colors.orange),
                        tooltip: 'Print Bill',
                      ),
                    if (currentOrder.status.value != OrderStatus.paid &&
                        currentOrder.status.value != OrderStatus.cancelled)
                      IconButton(
                        onPressed: () {
                          Get.back();
                          onEdit();
                        },
                        icon: const Icon(Icons.edit, color: Colors.blue),
                      ),
                    if (currentOrder.status.value != OrderStatus.paid &&
                        currentOrder.status.value != OrderStatus.cancelled)
                      IconButton(
                        onPressed: () {
                          Get.back();
                          onDelete();
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: Icon(Icons.close, color: colors.text),
                    ),
                  ],
                ),
              ],
            ),
            Divider(color: colors.border),
            SizedBox(height: 5.h),
            if(currentOrder.status.value != OrderStatus.paid)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Colors.orange,
                ),
                SizedBox(width: 4.w),
                Text(
                  controller.getElapsedTime(currentOrder.createdAt),
                  style: AppTypography.cardTitle.copyWith(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (currentOrder.items.isEmpty)
              Padding(
                padding: EdgeInsets.all(20.w),
                child: const Center(child: CircularProgressIndicator()),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: isMobile ? 0.5.sh : 0.4.sh,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: currentOrder.items.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: colors.border.withOpacity(0.5)),
                  itemBuilder: (context, index) {
                    final item = currentOrder.items[index];
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: colors.textField,
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              '${item.quantity}x',
                              style: AppTypography.cardSubtitle.copyWith(
                                fontWeight: FontWeight.bold,
                                color: displayColor,
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.name,
                                  style: AppTypography.cardSubtitle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isMobile ? 14.sp : 13.sp,
                                    color: colors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(item.priceAtOrder * item.quantity).toStringAsFixed(2)}',
                            style: AppTypography.cardSubtitle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 14.sp : 13.sp,
                              color: colors.text,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            SizedBox(height: 20.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: displayColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: [
                  _buildDetailRow(context, 'Subtotal', calculatedSubtotal, colors.text, bold: false, fontSize: isMobile ? 14.sp : 10.sp),
                  if (currentOrder.discount > 0)
                    _buildDetailRow(context, 'Discount', -currentOrder.discount, Colors.red, bold: false, fontSize: isMobile ? 14.sp : 10.sp),
                  if (dashboardController.vatType.value == 0 || currentOrder.totalTax > 0)
                    _buildDetailRow(context, 'Tax', currentOrder.totalTax, colors.text, bold: false, fontSize: isMobile ? 14.sp : 10.sp),
                  if (currentOrder.roundOff != 0)
                    _buildDetailRow(context, 'Round Off', currentOrder.roundOff, colors.text, bold: false, fontSize: isMobile ? 14.sp : 10.sp),
                  const Divider(),
                  _buildDetailRow(context, 'Total Amount', totAmt, displayColor, bold: true, fontSize: isMobile ? 18.sp : 12.sp),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            if (currentOrder.status.value != OrderStatus.paid &&
                currentOrder.status.value != OrderStatus.cancelled)
              ElevatedButton(
                onPressed: () async {
                  Get.back();
                  await _dbHelper.getCaptains();
                  controller.goToCashier(order);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: displayColor,
                  minimumSize: Size(double.infinity, 48.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text("Settle Order", style: AppTypography.button),
              ),
            if (isMobile) SizedBox(height: 20.h),
          ],
        );
      }),
    );
  }
}

String _getOrderTypeName(int type) {
  switch (type) {
    case 0:
      return 'Dine In';
    case 1:
      return 'Delivery';
    case 2:
      return 'Pickup';
    default:
      return 'Other';
  }
}