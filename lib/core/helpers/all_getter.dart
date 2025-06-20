import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../feature/auth/domain/usecases/get_auth.dart';
import '../network/http_service.dart';
import '../network/network_info.dart';
import '../local_storage/local_storage.dart';


class Getters {
  Getters._();

  static GlobalKey<NavigatorState> get navKey => GetIt.I.get<GlobalKey<NavigatorState>>();

  static DateTime get now => DateTime.now();



  static HttpService get getHttpService => GetIt.I.get<HttpService>();

  static AuthUseCase get getAuthRepo => GetIt.I.get<AuthUseCase>();

  static NetworkInfo get networkInfo => GetIt.I.get<NetworkInfo>();


  static BuildContext? get getContext => navKey.currentContext;

 // static UserModel? get getLoginUser => GetIt.I.get<LocalStorage>().getLoginUser();

//  static String? get authToken => GetIt.I.get<LocalStorage>().getToken();

 //static bool get isLoggedIn => GetIt.I.get<LocalStorage>().getIsProfileComplete() == 1;

  //static bool get hasProfileDate => GetIt.I.get<LocalStorage>().getLoginUser()?.firstName != null;
}
