import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';
import '../../../../controller/dashboard_controller.dart';
import '../../models/dashboard_models.dart';

class FoodItemCard extends StatefulWidget {
  final FoodItemModel item;
  final VoidCallback? onTap;

  const FoodItemCard({
    super.key,
    required this.item,
    this.onTap,
  });

  @override
  State<FoodItemCard> createState() => _FoodItemCardState();
}

class _FoodItemCardState extends State<FoodItemCard>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _checkController;
  bool _showCheck = false;
  late DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<DashboardController>();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1,
      value: 1,
    );
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  void _onTap() {
    _scaleController.forward();
    HapticFeedback.lightImpact();
    widget.onTap?.call();

    setState(() {
      _showCheck = true;
    });
    _checkController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _showCheck = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTapDown: (_) => _scaleController.reverse(),
      onTapCancel: () => _scaleController.forward(),
      onTapUp: (_) => _onTap(),
      child: ScaleTransition(
        scale: _scaleController,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            child: Stack(
              children: [
                /// 🍔 IMAGE
                Positioned.fill(
                  child: widget.item.image.isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: widget.item.image,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    memCacheHeight: 300,
                    placeholder: (context, url) => Container(
                      color: colors.textField,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildPlaceholder(context),
                  )
                      : _buildPlaceholder(context),
                ),

                /// 🌑 GRADIENT OVERLAY
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                ),

                /// 💲 PRICE BADGE (Modern)
                Positioned(
                  top: 10.h,
                  right: 10.w,
                  child: Container(
                    padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Obx(() {
                      double displayPrice = widget.item.price;
                      if (_controller.vatType.value == 0) {
                        displayPrice = widget.item.price + (widget.item.price * widget.item.prd_tax / 100);
                      }
                      return Text(
                        displayPrice.toStringAsFixed(2),
                        style: AppTypography.cardSubtitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }),
                  ),
                ),

                /// 📝 FOOD NAME (ON IMAGE)
                Positioned(
                  left: 6.w,
                  right: 6.w,
                  bottom: 12.h,
                  child: Text(
                    widget.item.name,
                    style: AppTypography.cardSubtitle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),


                Positioned(
                  bottom: 10.h,
                  right: 2.w,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(1.w),
                    child:  Icon(
                      Icons.add,
                      color: Colors.white,
                      size: AppTypography.sizeTable,
                    ),
                  ),
                ),

                /// ✅ CHECK ANIMATION
                if (_showCheck)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _checkController,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen
                                .withOpacity(0.4 * (1 - _checkController.value)),
                          ),
                          child: Center(
                            child: Transform.scale(
                              scale: 1.0 + _checkController.value,
                              child: Opacity(
                                opacity: 1 - _checkController.value,
                                child: Container(
                                  padding: EdgeInsets.all(6.w),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: AppTypography.sizeTable,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
        color: colors.textField,
        child: Icon(Icons.fastfood,
            color: colors.subtext.withOpacity(0.3), size: AppTypography.foodIcon));
  }
}