import 'app_strings.dart';
import 'helper.dart';


class Validator {
  static final Validator _singleton = Validator._internal();

  factory Validator() {
    return _singleton;
  }

  Validator._internal();

  static Validator get instance => _singleton;

  var error = "";

  bool signUpValidator({
    required String phoneNumber,
  }) {
    if (phoneNumber.isEmpty) {
      error = AppStrings.appName;
      return false;
    } else if (phoneNumber.length < 6 || phoneNumber.length > 12) {
      error = AppStrings.appName;
      return false;
    } else {
      return true;
    }
  }

  bool checkPassword(String password) {
    return ((password.trim().length < 8) ||
        (!RegExp(r'(?=.*?\d)').hasMatch(password.trim())) ||
        (!RegExp(r'(?=.*?[!@#\$&*~])').hasMatch(password.trim())));
  }
}
