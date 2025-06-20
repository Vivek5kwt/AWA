// To parse this JSON data, do
//
//     final userModel = userModelFromJson(jsonString);

import 'dart:convert';

UserModel userModelFromJson(String str) => UserModel.fromJson(json.decode(str));

String userModelToJson(UserModel data) => json.encode(data.toJson());

class UserModel {
  int? id;
  dynamic otp;
  bool? isAlreadyExist;
  int? isComplete;
  int? userId;
  String? profilePic;
  String? firstName;
  String? lastName;
  String? email;
  String? phoneNumber;
  String? countryCode;
  int? age;

  UserModel(
      {this.isAlreadyExist,
      this.otp,
      this.id,
      this.isComplete,
      this.age,
      this.email,
      this.firstName,
      this.lastName,
      this.phoneNumber,
      this.profilePic,
      this.countryCode,
      this.userId});

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        isAlreadyExist: json["isAlreadyExist"],
        otp: json["otp"],
        id: json["id"],
        isComplete: json["isComplete"],
        age: json["age"],
        email: json["email"],
        firstName: json["firstName"],
        lastName: json["lastName"],
        phoneNumber: json["phoneNumber"],
        profilePic: json["profilePic"],
        countryCode: json["countryCode"],
        userId: json["userId"],
      );

  Map<String, dynamic> toJson() => {
        "isAlreadyExist": isAlreadyExist,
        "otp": otp,
        "id": id,
        "isComplete": isComplete,
        "countryCode": countryCode,
        "userId": userId,
        "profilePic": profilePic,
        "phoneNumber": phoneNumber,
        "lastName": lastName,
        "firstName": firstName,
        "email": email,
        "age": age,
      };
}
