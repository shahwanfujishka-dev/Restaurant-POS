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
import '../../../../routes/app_pages.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/dashboard_controller.dart';
import '../../controller/order_controller.dart';
import '../../controller/printer_controller.dart';
import '../dashoard/widgets/dashboard_widgets/food_item_shimmer.dart';

class OrdersPage extends GetView<OrdersController> {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController dashboardController = Get.find<DashboardController>();
    final colors = AppColors.of(context);

    return DefaultTabController(
      length: 4,
      child: Builder( // ← Builder gives a context that has the TabController
        builder: (context) {
          final tabController = DefaultTabController.of(context); // ← get it here once
          return Scaffold(
            backgroundColor: colors.bg,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(60.h),
              child: Container(
                color: colors.card,
                padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 10.h),
                child: AnimatedTabBar(tabController: tabController), // ← pass directly
              ),
            ),
            body: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: FoodItemShimmer());
              }
              return TabBarView(
                controller: tabController, // ← same controller instance
                children: [
                  _buildOrderList(context, controller.dineInOrders, dashboardController),
                  _buildOrderList(context, controller.deliveryOrders, dashboardController),
                  _buildOrderList(context, controller.pickupOrders, dashboardController),
                  _buildOrderList(context, controller.paidOrders, dashboardController),
                ],
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<OrderModel> orders, DashboardController dashboardController) {
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

void _showOrderDetailsDialog(BuildContext context, OrderModel order, DashboardController dashboardController) {
  final controller = Get.find<OrdersController>();
  final colors = AppColors.of(context);
  final displayColor = order.status.value == OrderStatus.draft
      ? _getStatusColor(OrderStatus.draft)
      : _getOrderTypeColor(order.sales_odr_order_type);

  Get.dialog(
    Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Obx(() {
        final currentOrder = controller.orders.firstWhere(
              (o) => o.id == order.id,
          orElse: () => order,
        );

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
                      Text(
                        'Inv: #${currentOrder.invNo} • ${currentOrder.tableName} ${currentOrder.chairNumber > 0 ? "• ${currentOrder.chairNumber} chairs" : ""}',
                        style: AppTypography.cardSubtitle.copyWith(
                          color: colors.subtext,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      currentOrder.sales_odr_pos_status == 1 ?
                      IconButton(
                        onPressed: () {
                          final printerController =
                          Get.find<PrinterController>();
                          printerController.printKOT(currentOrder);
                        },
                        icon: const Icon(Icons.print, color: Colors.blue),
                        tooltip: 'print_order'.tr,
                      ):SizedBox.shrink(),
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
                padding: EdgeInsets.symmetric(horizontal : 4.w, vertical: 2 .h),
                decoration: BoxDecoration(
                  color: displayColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  children: [
                    if (dashboardController.vatType.value == 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'tax'.tr,
                            style: AppTypography.cardTitle.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.text,
                            ),
                          ),
                          Text(
                            '${currentOrder.totalTax.toStringAsFixed(2)}',
                            style: AppTypography.cardTitle.copyWith(
                              fontWeight: FontWeight.bold,
                              color: displayColor,
                            ),
                          ),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'total_amount'.tr,
                          style: AppTypography.cardTitle.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '${currentOrder.totalAmount.toStringAsFixed(2)}',
                          style: AppTypography.cardTitle.copyWith(
                            fontWeight: FontWeight.bold,
                            color: displayColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              if (currentOrder.status.value != OrderStatus.paid && currentOrder.status.value != OrderStatus.cancelled && currentOrder.status.value != OrderStatus.draft)
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    Get.toNamed(Routes.CASHIER, arguments: currentOrder);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: displayColor,
                    minimumSize: Size(double.infinity, 48.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: Text(
                    "Settle Order",
                    style: AppTypography.button,
                  ),
                ),
            ],
          ),
        );
      }),
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
    final displayColor = order.status.value == OrderStatus.draft
        ? _getStatusColor(OrderStatus.draft)
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
                              order.tableName,
                              style: AppTypography.cardTitle.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16.sp,
                                color: colors.text,
                              ),
                            ),
                            Row(
                              children: [
                                if (order.status.value != OrderStatus.paid && order.status.value != OrderStatus.cancelled)
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
                                if (order.status.value != OrderStatus.paid && order.status.value != OrderStatus.cancelled)
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
                              style: TextStyle(color: Colors.orange, fontSize: 10.sp, fontWeight: FontWeight.bold),
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
                              '${order.totalAmount.toStringAsFixed(2)}',
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
    final displayColor = order.status.value == OrderStatus.draft
        ? _getStatusColor(OrderStatus.draft)
        : _getOrderTypeColor(order.sales_odr_order_type);

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
                        order.tableName,
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
                        if (order.status.value != OrderStatus.paid && order.status.value != OrderStatus.cancelled)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onEdit,
                            icon: Icon(
                              Icons.edit_note,
                              size: 7.sp,
                              color: displayColor,
                            ),
                          ),
                        SizedBox(width: 4.w),
                        if (order.status.value != OrderStatus.paid && order.status.value != OrderStatus.cancelled)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onDelete,
                            icon: Icon(
                              Icons.delete_outline,
                              size: 7.sp,
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
                    padding: EdgeInsets.all(8.w),
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
                        // if (order.isUnsynced)
                        //   Text(
                        //     "OFFLINE",
                        //     style: TextStyle(color: Colors.orange, fontSize: 2.sp, fontWeight: FontWeight.bold),
                        //   ),
                        SizedBox(height: 4.h),
// In _MobileOrderCard build method
// After the existing Row with time and amount, add:

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  child: Obx(
                                        () => Text(
                                      controller.getElapsedTime(order.createdAt),
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 4.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                      '${order.totalAmount.toStringAsFixed(2)}',
                      style: AppTypography.cardSubtitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // ✅ ADD PAY BUTTON HERE
                    if (order.status.value != OrderStatus.paid &&
                        order.status.value != OrderStatus.cancelled)
                      GestureDetector(
                        onTap: () => Get.toNamed(Routes.CASHIER, arguments: order),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(6.r),
                            border: Border.all(color: Colors.white54),
                          ),
                          child: Text(
                            'PAY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 4.sp,
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
                          color: Colors.white,
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
    final displayColor = order.status.value == OrderStatus.draft
        ? _getStatusColor(OrderStatus.draft)
        : _getOrderTypeColor(order.sales_odr_order_type);

    return Container(
      width: isMobile ? double.infinity : 0.4.sw,
      padding: EdgeInsets.all(isMobile ? 24.w : 20.w),
      child: Obx(() {
        final controller = Get.find<OrdersController>();
        final currentOrder = controller.orders.firstWhere(
              (o) => o.id == order.id,
          orElse: () => order,
        );

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
                    Text(
                      'Inv: #${currentOrder.invNo} • ${currentOrder.tableName}',
                      style: AppTypography.cardSubtitle.copyWith(
                        color: colors.subtext,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (currentOrder.sales_odr_pos_status == 1)
                      IconButton(
                        onPressed: () {
                          final printerController = Get.find<PrinterController>();
                          printerController.printKOT(currentOrder);
                        },
                        icon: const Icon(Icons.print, color: Colors.blue),
                      ),
                    if (currentOrder.status.value != OrderStatus.paid && currentOrder.status.value != OrderStatus.cancelled)
                      IconButton(
                        onPressed: () {
                          Get.back();
                          onEdit();
                        },
                        icon: const Icon(Icons.edit, color: Colors.blue),
                      ),
                    if (currentOrder.status.value != OrderStatus.paid && currentOrder.status.value != OrderStatus.cancelled)
                      IconButton(
                        onPressed: () {
                          Get.back();
                          onDelete();
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
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
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: displayColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: [
                  if (dashboardController.vatType.value == 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'tax'.tr,
                          style: AppTypography.cardTitle.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 16.sp : 15.sp,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '${currentOrder.totalTax.toStringAsFixed(2)}',
                          style: AppTypography.cardTitle.copyWith(
                            fontWeight: FontWeight.bold,
                            color: displayColor,
                            fontSize: isMobile ? 18.sp : 16.sp,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'total_amount'.tr,
                        style: AppTypography.cardTitle.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 16.sp : 15.sp,
                          color: colors.text,
                        ),
                      ),
                      Text(
                        '${currentOrder.totalAmount.toStringAsFixed(2)}',
                        style: AppTypography.cardTitle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: displayColor,
                          fontSize: isMobile ? 18.sp : 16.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            if (currentOrder.status.value != OrderStatus.paid && currentOrder.status.value != OrderStatus.cancelled)
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  Get.toNamed(Routes.CASHIER, arguments: currentOrder);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: displayColor,
                  minimumSize: Size(double.infinity, 48.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text(
                  "Settle Order",
                  style: AppTypography.button,
                ),
              ),
            if (isMobile) SizedBox(height: 20.h),
          ],
        );
      }),
    );
  }
}
