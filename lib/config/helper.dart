import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'extensions.dart';

void exit() {
  SystemNavigator.pop();
}

double screenWidth(BuildContext context) {
  return MediaQuery.of(context).size.width;
}

double screenHeight(BuildContext context) {
  return MediaQuery.of(context).size.height;
}

double safeAreaHeight(BuildContext context) {
  return (MediaQuery.of(context)
          .padding
          .top) /*+
          MediaQuery.of(context).padding.bottom)*/
      +
      15;
}

Widget dividerVirtical({
  double height = 25,
  double width = 1,
  Color color = const Color(0xff100301),
}) {
  return Container(
    height: height,
    width: width,
    color: color,
  );
}

void unFocus(BuildContext context) {
  FocusScope.of(context).unfocus();
}

SizedBox yHeight(double height) {
  return SizedBox(
    height: height,
  );
}

SizedBox xWidth(double width) {
  return SizedBox(
    width: width,
  );
}

void pushTo(BuildContext context, Widget widget) {
  Navigator.push(context, MaterialPageRoute(builder: (context) => widget));
}

void pushReplacement(BuildContext context, Widget widget) {
  Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (context) => widget));
}

void pushRemoveUtil(BuildContext context, Widget widget) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => widget),
    (route) {
      return false;
    },
  );
}

void offAllNamed(BuildContext context, String routesName) {
  Navigator.pushNamedAndRemoveUntil(
    context,
    routesName,
    (Route<dynamic> route) => false,
  );
}

void toNamed(BuildContext context, String routesName, {Object? args}) {
  Navigator.pushNamed(context, routesName, arguments: args);
}

void back(BuildContext context) {
  Navigator.pop(context);
}

void printLog(dynamic msg, {String fun = ""}) {
  _printLog(' $fun=> ${msg.toString()}');
}

void functionLog({required dynamic msg, required dynamic fun}) {
  _printLog("${fun.toString()} ::==> ${msg.toString()}");
}

void _printLog(dynamic msg, {String name = "Riverpod"}) {
  if (kDebugMode) {
    log(msg.toString(), name: name);
  }
}

void blocLog({required String msg, required String bloc}) {
  _printLog("${bloc.toString()} ::==> ${msg.toString()}");
}

bool emailValidation(String email) {
  Pattern pattern =
      r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
  RegExp regex = RegExp(pattern.toString());
  return regex.hasMatch(email);
}

Widget customLoader({
  double height = 55,
  double width = 100,
  Color color = Colors.black,
  double? value,
}) {
  return SizedBox(
      /*  child: Lottie.asset(Assets.buttonLoader,
      height: height,
      width: width,),*/
      );
}

checkPostLocked(int price) {
  return (price == 1);
}

bool isHtml(String input) {
  final RegExp htmlRegex = RegExp(r"<[^>]*>");
  return htmlRegex.hasMatch(input);
}
