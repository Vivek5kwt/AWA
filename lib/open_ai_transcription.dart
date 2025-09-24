import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class OpenAIRealtimeTranscriptionService {
  final String url;
  final String languageCode;
  late WebSocketChannel _channel;

  OpenAIRealtimeTranscriptionService(this.url, this.languageCode);

  Future<void> connect({
    required void Function(String speaker, String text) onTranscription,
    void Function(Object error)? onError,
  }) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    print('sbndshh ${url}');
    //
    _channel.stream.listen((message) {
      try {
        final data = jsonDecode(message);
        if (data['type'] == 'transcription') {
          final speaker = data['speaker'] ?? 'Unknown';
          final text = data['text'] ?? '';
          onTranscription(speaker, text);
        }
      } catch (e) {
        // fallback for non-JSON messages
        onTranscription('Unknown', message.toString());
      }
    }, onError: onError, onDone: () {
      print("WebSocket closed.");
    });

    print("Connected to OpenAI Realtime API");
  }

  void sendLanguage(String languagePayload) {
    try {
      _channel.sink.add(languagePayload);
    } catch (e) {
      debugPrint("❌ Failed to send language: $e");
    }
  }

  void sendAudio(Uint8List audioBytes) {
    _channel.sink.add(audioBytes);
  }

  Future<void> close() async {
    try {
      await _channel.sink.close();
    } catch (e) {
      debugPrint("Error closing WebSocket: $e");
    }
  }
}
