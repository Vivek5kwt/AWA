import '../../../../core/error/failure.dart';
import '../../../../core/utils/dartz/either.dart';
import '../../data/models/user_model.dart';
import '../repositories/auth_repository.dart';

abstract class AuthUseCase {
  Future<Either<Failure, UserModel?>> callLogin({required Map<String,dynamic> body});
}

class AuthUseCaseImpl implements AuthUseCase{
  final AuthRepository repository;

  AuthUseCaseImpl({required this.repository});

  @override
  Future<Either<Failure, UserModel?>> callLogin({required Map<String, dynamic> body}) async {
    final result = await repository.doLogin(body: body);
    return result.fold((l) => Left(l), (r) {
      return Right(r);
    });
  }
}
