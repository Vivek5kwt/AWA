import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Provides simple offline speaker enrollment and identification using
/// locally stored embeddings.
class SpeakerService {
  static const _storageKey = 'speaker_embeddings';

  /// Underlying model from `sherpa_onnx`.
  ///
  /// The actual type depends on the package implementation. It is kept as
  /// `dynamic` here to avoid compilation issues if the API changes.
  late final dynamic _model;

  /// Initialize the speaker model. Replace the body with actual
  /// initialization logic from `sherpa_onnx`.
  Future<void> init() async {
    // TODO: Initialize `_model` with sherpa_onnx APIs.
    _model = null;
  }

  /// Enroll [id] using the audio stored at [audioPath]. The computed embedding
  /// is persisted locally using [SharedPreferences].
  Future<void> enroll(String id, String audioPath) async {
    final embedding = await _extractEmbedding(audioPath);
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    data[id] = embedding;
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  /// Identify which enrolled speaker most closely matches the voice in
  /// [audioPath]. Returns the speaker id on success or `null` if no match
  /// passes the [threshold].
  Future<String?> identify(String audioPath, {double threshold = 0.8}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    if (data.isEmpty) return null;

    final testEmbedding = await _extractEmbedding(audioPath);
    double bestScore = 0.0;
    String? bestId;
    data.forEach((id, emb) {
      final score = _cosine(List<double>.from(emb), testEmbedding);
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    });
    return bestScore >= threshold ? bestId : null;
  }

  Map<String, dynamic> _loadEmbeddings(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// Extract an embedding for the audio at [path].
  ///
  /// This currently returns a very small placeholder embedding based on the
  /// average byte value of the file. Replace with real calls into the
  /// `sherpa_onnx` package.
  Future<List<double>> _extractEmbedding(String path) async {
    final bytes = await File(path).readAsBytes();
    final avg = bytes.isEmpty
        ? 0.0
        : bytes.reduce((a, b) => a + b) / bytes.length;
    return [avg.toDouble()];
  }

  double _cosine(List<double> a, List<double> b) {
    final length = min(a.length, b.length);
    double dot = 0, magA = 0, magB = 0;
    for (var i = 0; i < length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA == 0 || magB == 0) return 0.0;
    return dot / (sqrt(magA) * sqrt(magB));
  }
}
