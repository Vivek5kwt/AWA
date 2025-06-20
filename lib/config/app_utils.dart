import 'package:bot_toast/bot_toast.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mime/mime.dart';
import '../feature/common_widgets/custom_toast.dart';

class Utils {
  Utils._();

  static Future<bool> hasNetwork({bool? showToast}) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      toast(msg: "Please check your Internet Connection", isError: true);
      return false;
    } else {
      return true;
    }
  }

  static bool emailValidation(String email) {
    Pattern pattern =
        r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
    RegExp regex = RegExp(pattern.toString());
    return regex.hasMatch(email);
  }

  static String? getFileType(String path) {
    final mimeType = lookupMimeType(path);
    String? result = mimeType?.substring(0, mimeType.indexOf('/'));
    return result;
  }

  static Future<void> showLoader() async {
    BotToast.cleanAll();
    BotToast.showCustomLoading(
        useSafeArea: true,
        allowClick: false,
        clickClose: false,
        ignoreContentClick: true,
        align: Alignment.center,
        toastBuilder: (void Function() cancelFunc) {
          return SizedBox();
          //Lottie.asset(Assets.appLoading,height: 180.h);
        });
  }

  static void hideLoader() {
    BotToast.closeAllLoading();
  }

  static void hideKeyboard(context) {
    FocusScope.of(context).requestFocus(FocusNode());
  }

  static Widget svgImage({
    required String assetPath,
    double size = 40.0,
    Color? color,
  }) {
    return SvgPicture.asset(
      'assets/images/$assetPath',
      fit: BoxFit.contain,
      semanticsLabel: assetPath,
      width: size,
      height: size,
      color: color,
    );
  }
}
