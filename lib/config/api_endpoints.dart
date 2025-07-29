part of '../core/network/http_service.dart';
abstract final class ApiConstants {
  //live
 // static const String baseUrl = "http://172.232.104.30:8000";
  //local
  static const String baseUrl = "http://192.168.1.12:5000";
  static const String _apiBaseUrl = "${baseUrl}/";
  static const String registerUser = "${_apiBaseUrl}register _user";
  static const String loginUser = "${_apiBaseUrl}login_use  r";
  static const String socialLogin =  "${_apiBaseUrl}login_user";
  static const String registerSpeaker = "${_apiBaseUrl}register_speaker";
  static const String listSpeaker = "${_apiBaseUrl}list_speakers?email=";
  static const String listUsers = "${_apiBaseUrl}list_users";
  static const String listFriends = "${_apiBaseUrl}list_friends";
  static const String deleteUser = "${_apiBaseUrl}delete_account";
  static const String logoutUser = "${_apiBaseUrl}logout_user";
  static const String addFriend = "${_apiBaseUrl}add_friend";
  static const String deleteFriends = "${_apiBaseUrl}delete_friend";
  static const String deleteSpeaker = "${_apiBaseUrl}delete_speaker";
  static const String identifySpeaker = "${_apiBaseUrl}identify_speaker";
  static const String updateUserProfile =  "${_apiBaseUrl}update_user_profile";
  static const String getNotification = "${_apiBaseUrl}get_notifications";
  static const String sendNotification = "${_apiBaseUrl}send_notification";
  static const String sendFriendNotification =
      "${_apiBaseUrl}send_friend_notification";
  static const String deleteNotification = "${_apiBaseUrl}delete_notification";
  static const String getNotificationCount =
      "${_apiBaseUrl}get_notification_count";
  static const String notificationReaded =
      "${_apiBaseUrl}notification_readed";
  static const String getSubPlan = "${_apiBaseUrl}get_subscription_plans";
  static const String getTransaction = "${_apiBaseUrl}get_transactions_by_email";
}
