part of '../core/network/http_service.dart';
abstract final class ApiConstants {
  //live
  static const String baseUrl = "http://172.232.104.30:5000";
  static const String streamUrl = "ws://192.168.1.31:8001/ws/transcribe?email=vivek5kwt@gmail.com";
  //local
  //static const String baseUrl = "http://192.168.1.31:8001";
  static const String googleApiKey = 'AIzaSyBtUTh-qBSF35PlyBIJVJz9SU8mj2Jn1Hw';
  static const String googleProjectId = 'awa-dev-501dc';
  static const String _apiBaseUrl = "${baseUrl}/";
  static const String registerUser = "${_apiBaseUrl}register_user";
  static const String loginUser = "${_apiBaseUrl}login_user";
  static const String socialLogin = "${_apiBaseUrl}login_user";
  //static const String registerSpeaker = "${_apiBaseUrl}register_speaker";
  static const String listSpeaker = "${_apiBaseUrl}list_speakers?email=";
  static const String listUsers = "${_apiBaseUrl}list_users";
  static const String listFriends = "${_apiBaseUrl}list_friends";
  static const String deleteUser = "${_apiBaseUrl}delete_account";
  static const String logoutUser = "${_apiBaseUrl}logout_user";
  static const String addFriend = "${_apiBaseUrl}add_friend";
  static const String deleteFriends = "${_apiBaseUrl}delete_friend";
  //static const String deleteSpeaker = "${_apiBaseUrl}delete_speaker";
  static const String deleteSpeaker = "${_apiBaseUrl}api/speakers/";
  static const String identifySpeaker = "${_apiBaseUrl}identify_speaker";
  static const String identifySpeakerNative =
      "${_apiBaseUrl}identify_speaker_native";
  static const String streamIdentify = "${_apiBaseUrl}stream_identify";
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
  static const String getRegistration = "${_apiBaseUrl}api/registration-text";
  static const String registerSpeaker = "${_apiBaseUrl}api";

// ElevenLabs endpoints
  static const String elevenLabsApiKey = 'sk_01a87d73ba133e530ecab10f160cb0f4a98bdaad75449fc5';
  static const String _elevenLabsBaseUrl = 'https://api.elevenlabs.io/v1';
// Base path for ElevenLabs voices collection
  static const String elevenLabsVoices = "${_elevenLabsBaseUrl}/voices";
// List voices endpoint (same as [elevenLabsVoices])
  static const String listElevenLabsVoices = elevenLabsVoices;
  static const String elevenLabsSpeechToText =
      "${_elevenLabsBaseUrl}/speech-to-text";
  static const String elevenLabsModelId = 'scribe_v1';
  static const String elevenLabsLanguage = 'en';

  static Uri get streamSpeakerTranscribeUri {
    final baseUri = Uri.parse(baseUrl);
    final isSecure = baseUri.scheme == 'https';
    return Uri(
      scheme: isSecure ? 'wss' : 'ws',
      host: baseUri.host,
      port: 5000,
      path: 'stream_speaker_transcribe',
    );
  }
}
