import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

class CategoryShimmer extends StatelessWidget {
  final Axis direction;
  const CategoryShimmer({super.key, this.direction = Axis.horizontal});

  @override
  Widget build(BuildContext context) {
    bool isHorizontal = direction == Axis.horizontal;
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: isHorizontal ? 45.h : null,
        width: isHorizontal ? double.infinity : 40.w,
        padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: isHorizontal ? 10.w : 1.w),
        child: ListView.separated(
          scrollDirection: direction,
          itemCount: 8,
          separatorBuilder: (_, __) => isHorizontal ? SizedBox(width: 5.w) : SizedBox(height: 5.h),
          itemBuilder: (context, index) {
            return Container(
              width: isHorizontal ? 80.w : double.infinity,
              height: isHorizontal ? double.infinity : 30.h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
              ),
            );
          },
        ),
      ),
    );
  }
}
