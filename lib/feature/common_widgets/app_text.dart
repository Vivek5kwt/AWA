import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_strings.dart';
import '../../config/helper.dart';


enum AppTextStyle { title, medium, regular, small }

class AppText extends StatelessWidget {
  final String text;
  final dynamic color;
  final dynamic underlineColor;
  final AppTextStyle? style;
  final bool? underline;
  final bool? strikeThrough;
  final double? textSize;
  final bool? capitalise;
  final int? maxlines;
  final TextAlign? textAlign;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final double? lineHeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final TextOverflow? overflow;

  const AppText(
      {super.key,
        required this.text,
      this.color,
      this.style,
      this.maxlines,
      this.textAlign,
      this.underline,
      this.textSize,
      this.fontFamily,
      this.fontWeight,
      this.lineHeight,
      this.fontStyle,
      this.underlineColor,
      this.strikeThrough,
      this.capitalise,
      this.letterSpacing,
      this.overflow});

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;

    return Text(
      capitalise != null && capitalise!
          ? text.toString().toUpperCase()
          : text.toString(),
      maxLines: maxlines,
      overflow: maxlines != null ? TextOverflow.ellipsis : null,
      textAlign: textAlign,

      style: getStyle(
          color ?? AppColors.black, textSize ?? 16.sp),
    );
  }

  TextStyle getStyle(
    Color color,
    double textSize,
  ) {
    return TextStyle(
        overflow: overflow,
        color: color,
        letterSpacing: letterSpacing,
        fontWeight: fontWeight ?? FontWeight.w500,
        fontSize: textSize,
        fontStyle: fontStyle ?? FontStyle.normal,
        height: lineHeight ?? 1.0,
        fontFamily: fontFamily ?? AppStrings.fontFamily,
        decorationColor: underlineColor ?? AppColors.black,
        decorationThickness: 1,
        decoration: strikeThrough != null && strikeThrough!
            ? TextDecoration.lineThrough
            : underline != null
                ? TextDecoration.underline
                : null);
  }
  FontWeight getWeight() {
    switch (style) {
      case AppTextStyle.title:
        return FontWeight.w600;
      case AppTextStyle.medium:
        return FontWeight.w500;
      case AppTextStyle.regular:
        return FontWeight.w400;
      case AppTextStyle.small:
        return FontWeight.w300;
      default:
        return FontWeight.w400;
    }
  }
}
