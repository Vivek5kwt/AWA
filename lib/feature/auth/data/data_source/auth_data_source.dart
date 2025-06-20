import '../../../../core/helpers/all_getter.dart';
import '../../../../core/network/http_service.dart';
import '../../../../core/response_wrapper/data_response.dart';
import '../models/user_model.dart';

abstract class AuthDataSource {
  Future<ResponseWrapper?> logInUser({required Map<String,dynamic> body});
}
class AuthDataSourceImpl extends AuthDataSource{

  @override
  Future<ResponseWrapper<UserModel>?> logInUser({required Map<String,dynamic> body}) async{
    try {
      final dataResponse = await Getters.getHttpService.request<UserModel>(
        body: body,
        url: ApiConstants.registerUser,
        fromJson: (json) => UserModel.fromJson(json),
      );
      if (dataResponse.response == 1 && dataResponse.data != null) {
          UserModel model = dataResponse.data!;
         // Getters.getLocalStorage.saveLoginUser(model);
         // Getters.getLocalStorage.saveToken(dataResponse.token??"");
         // Getters.getLocalStorage.saveIsProfileComplete(model.isComplete??0);
        return getSuccessResponseWrapper(dataResponse);
      } else {
        return getFailedResponseWrapper(dataResponse.errorMessage, response:dataResponse.data);
      }
    } catch (e) {
      return getFailedResponseWrapper(exceptionHandler(
        e: e,
        functionName: "userLogin",
      ));
    }
  }
}