import 'package:dio/dio.dart';
import '../../config/helper.dart';

class Injector {
  static final Injector _singleton = Injector._internal();
  static final _dio = Dio();

  factory Injector() {
    return _singleton;
  }

  Injector._internal();

  Dio getDio() {
    BaseOptions options = BaseOptions(
        receiveTimeout: const Duration(seconds: 90),
        connectTimeout: const Duration(seconds: 90));
    _dio.options = options;
    _dio.options.followRedirects = false;
    _dio.options.headers["Content-Type"] = "application/json";
    _dio.interceptors.clear();
/*    _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          compact: true,
          error: true,
          request: true,
        ));*/
    _dio.interceptors.add(LoggingInterceptors());
    return _dio;
  }

  static Options? getHeaderToken() {
    String? token = /*Getters.authToken*/ 'sdsds';
    //int? userId = Getters.getLoginUser?.id;
    if (token != null) {
      //  printLog("Logged in user Id==>>$userId");
      printLog("AuthToken==>> Bearer $token");
      var headerOptions = Options(headers: {
        'Authorization': 'Bearer $token',
        // options.headers['Authorization'] = 'Bearer ' +usertoken!;
      });
      return headerOptions;
    }
    return null;
  }
}

class LoggingInterceptors extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    blocLog(
        msg:
            "<-- ${err.message} ${(err.response?.requestOptions != null ? (err.response!.requestOptions.baseUrl + err.response!.requestOptions.path) : 'URL')}",
        bloc: 'DioException');
    blocLog(
        msg: "${err.response != null ? err.response!.data : 'Unknown Error'}",
        bloc: 'DioException');
    if (err.response?.statusMessage == "Internal Server Error") {
      throw Exception("Internal Server Error");
    }
    return super.onError(err, handler);
  }
}
