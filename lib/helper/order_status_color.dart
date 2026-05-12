import 'package:flutter/material.dart';
import '../app/data/models/order_model.dart';
import '../app/theme/app_theme.dart';

Color getStatusColor(OrderStatus status) {
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
    default:
      return Colors.grey;
  }
}