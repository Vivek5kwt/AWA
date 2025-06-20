part 'data_response.g.dart';

class ResponseWrapper<TModel>{
  String? token;
  int? response;
  String? errorMessage;
  TModel? data;


  ResponseWrapper({this.response, this.token, this.errorMessage, this.data});

  factory ResponseWrapper.fromJson(Map<String, dynamic> json, TModel Function(Object? json) fromJsonT,) => _$ResponseWrapperFromJson(json, fromJsonT);
  Map<String, dynamic> toJson(Object Function(TModel value) toJsonT) => _$ResponseWrapperToJson(this, toJsonT);

}
