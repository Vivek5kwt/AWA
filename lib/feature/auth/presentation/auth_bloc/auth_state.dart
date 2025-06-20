part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
}

final class AuthInitial extends AuthState {
  @override
  List<Object> get props => [];
}

final class LoginLoading extends AuthState {
  @override
  List<Object> get props => [];
}
final class LoginSuccess extends AuthState {
  final String message;
  const LoginSuccess({required this.message});
  @override
  List<Object> get props => [message];
}

final class LoginFailed extends AuthState {
  final String error;
  const LoginFailed({required this.error});
  @override
  List<Object> get props => [error];
}
