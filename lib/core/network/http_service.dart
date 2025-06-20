import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../../config/helper.dart';
import '../response_wrapper/data_response.dart';
import 'interceptor.dart';

part '../../config/api_endpoints.dart';

part '../error/exceptions.dart';

enum RequestType {
  post,
  get,
  delete,
  put,
  multipart,
}

class HttpService {
  late Dio _dio;

  HttpService() {
    _dio = Injector().getDio();
  }

  ///  ---------------------------------Create a Network Request ---------------------------------------->

  Future<ResponseWrapper<T?>> request<T>({
    required String url,
    RequestType requestType = RequestType.post,
    Map<String, dynamic>? body,
    String? imagePath,
    String? paramName,
    required T Function(dynamic json) fromJson,
  }) async {

    try {
      Map<String, dynamic> map = body ?? {};
      Response response = await _checkRequest(
        fullUrl: url,
        imagePath: imagePath,
        paramName: paramName,
        requestType: requestType,
        body: map,
      );
      var parsedData =
          (response.data).containsKey('data') && response.data["data"] != null
              ? dataParser<T>(response.data["data"], fromJson)
              : null;
      var dataResponse = ResponseWrapper<T>(
        errorMessage: response.data["errorMessage"],
        token: response.data["token"],
        response: response.data["response"],
        data: parsedData,
      );
      return dataResponse;
    } catch (err, c) {
      functionLog(msg: "t>>>>>>>>$err", fun: "requestData");
      functionLog(msg: "t>>>>>>>>$c", fun: "requestData");
      if (err is DioException) {
        if (err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionTimeout) {
          return ResponseWrapper(
              response: 0, errorMessage: "Unable to reach the servers");
        } else if (err.type == DioExceptionType.connectionError) {
          return ResponseWrapper(
              response: 0,
              errorMessage: "Please check your internet connection");
        } else if (err.response != null && (err.response?.statusCode == 401)) {
          //  Utils.startFirstScreen();
          throw ResponseWrapper(
              response: 0, errorMessage: "Authentication Failed");
        }
      }
      final res = (err as dynamic).response;
      if (res != null && res?.data.runtimeType != String) {
        return ResponseWrapper.fromJson(
          res?.data,
          (data) => null,
        );
      }
      return ResponseWrapper(response: 0, errorMessage: err.toString());
    }
  }

  ///  ---------------------------------Get request Type ---------------------------------------->
  Future<Response> _checkRequest({
    required String fullUrl,
    required RequestType requestType,
    required String? imagePath,
    required String? paramName,
    required Map<String, dynamic> body,
  }) async {
    final headerToken = Injector.getHeaderToken();
    if (requestType == RequestType.get) {
      return _dio.get(
        fullUrl,
        options: headerToken,
        queryParameters: body,
      );
    } else if (requestType == RequestType.post) {
      return _dio.post(
        fullUrl,
        data: body,
        options: Injector.getHeaderToken(),
      );
    } else if (requestType == RequestType.multipart &&
        imagePath != null &&
        paramName != null) {
      Map<String, dynamic> map = HashMap();
      map.addAll(body);
      if (imagePath.isNotEmpty) {
        File file = File(imagePath);
        String fileType = imagePath.substring(imagePath.lastIndexOf(".") + 1);
        map[paramName] = await MultipartFile.fromFile(file.path,
            filename: imagePath.split("/").last,
            contentType: MediaType(getFileType(imagePath)!, fileType));
      }
      return _dio.post(
        fullUrl,
        data: FormData.fromMap(map),
        options: Injector.getHeaderToken(),
      );
    } else if (requestType == RequestType.delete) {
      return _dio.delete(
        fullUrl,
        data: body,
        options: headerToken,
      );
    } else if (requestType == RequestType.put) {
      return _dio.put(
        fullUrl,
        data: body,
        options: headerToken,
      );
    } else {
      return _dio.patch(
        fullUrl,
        data: body,
        options: headerToken,
      );
    }
  }

  String? getFileType(String path) {
    final mimeType = lookupMimeType(path);
    String? result = mimeType?.substring(0, mimeType.indexOf('/'));
    return result;
  }

  T dataParser<T>(dynamic json, T Function(dynamic) fromJson) {
    return fromJson(json);
  }
}
