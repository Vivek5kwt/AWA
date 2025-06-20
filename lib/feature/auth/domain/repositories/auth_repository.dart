
import '../../../../core/error/failure.dart';
import '../../../../core/utils/dartz/either.dart';
import '../../data/models/user_model.dart';

abstract class AuthRepository {
  Future<Either<Failure, UserModel?>> doLogin({required Map<String, dynamic> body});
}