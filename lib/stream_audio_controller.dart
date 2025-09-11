import 'package:flutter/services.dart';

class SystemAudioControl {
  static const _channel = MethodChannel("com.example.awa/audio");

  static Future<void> muteVoiceFeedback() async {
    try {
      await _channel.invokeMethod("muteVoiceFeedback");
    } catch (e) {
      print("Error muting feedback: $e");
    }
  }

  static Future<void> unmuteVoiceFeedback() async {
    try {
      await _channel.invokeMethod("unmuteVoiceFeedback");
    } catch (e) {
      print("Error unmuting feedback: $e");
    }
  }
}
