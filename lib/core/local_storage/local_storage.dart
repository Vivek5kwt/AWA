import 'package:hive_flutter/adapters.dart';

import '../../config/helper.dart';

abstract class HiveConst {
  static const String userData = 'userData';
  static const String authToken = 'authToken';
  static const String isProfileComplete = 'isProfileComplete';
}

abstract class LocalStorage {
  //Future<bool> saveLoginUser(UserModel userModel);

  //UserModel? getLoginUser();

  Future<void> clearAllBox();

  String? getToken();

  Future<void> saveToken(String token);
  Future<void> saveIsProfileComplete(int isComplete);
  int? getIsProfileComplete();
}

class HiveStorageImp extends LocalStorage {
  final Box userBox;

  HiveStorageImp({
    required this.userBox,
  });

  @override
  Future<void> saveToken(String token) async {
    await userBox.put(HiveConst.authToken, token);
  }

  @override
  String? getToken() {
    final authToken = userBox.get(HiveConst.authToken);
    return authToken;
  }

  static Future<LocalStorage> init() async => HiveStorageImp(
        userBox: await Hive.openBox(HiveConst.userData),
      );

  /*  @override
  Future<bool> saveLoginUser(UserModel userModel) async {
    await userBox.put(HiveConst.userData, userModel.toJson());

    return true;
  }

  @override
  UserModel? getLoginUser() {
    final user = userBox.get(HiveConst.userData);
    if (user == null) return null;
    final data = UserModel.fromJson(jsonDecode(jsonEncode(user)));
    return data;
  }*/

  @override
  Future<void> clearAllBox() async {
    await userBox.clear();
  }

  @override
  Future<void> saveIsProfileComplete(int isComplete) async {
    await userBox.put(HiveConst.isProfileComplete, isComplete);
  }

  @override
  int? getIsProfileComplete() {
    final isComplete = userBox.get(HiveConst.isProfileComplete);
    return isComplete;
  }
}
