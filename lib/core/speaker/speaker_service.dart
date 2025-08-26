import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Offline speaker enrollment + identification with real embeddings
/// from sherpa_onnx SpeakerEmbeddingExtractor.
/// - Stores multiple samples per user and matches against the per-user average.
/// - Uses cosine similarity with a second-best margin to avoid false positives.
class SpeakerService {
  static const _storageKey = 'speaker_embeddings_v3';

  SpeakerEmbeddingExtractor? _extractor;
  String? _modelLocalPath;

  bool get isReady => _extractor != null;

  /// Initialize sherpa-onnx and load the ONNX embedding model from assets.
  /// Make sure you include the file in pubspec:
  ///   assets:
  ///     - assets/models/speaker_embedding.onnx
  Future<void> init() async {
    if (_extractor != null) return;

    // Initialize native bindings.
    initBindings(); // required before readWave()/extractor usage. :contentReference[oaicite:0]{index=0}

    // Copy the ONNX model from assets to an accessible file path.
    _modelLocalPath = await _ensureModelIsReady();

    final cfg = SpeakerEmbeddingExtractorConfig(
      model: _modelLocalPath!,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    _extractor = SpeakerEmbeddingExtractor(config: cfg); // :contentReference[oaicite:1]{index=1}
  }

  /// Free extractor resources (call from your widget's dispose()).
  Future<void> dispose() async {
    try {
      _extractor?.free();
    } catch (_) {}
    _extractor = null;
  }

  // ---------- Public API ----------

  /// Append one recording sample to [name]. Creates the entry if absent.
  Future<String> enrollAppend(String name, String audioPath) async {
    final n = name.trim();
    if (n.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    final emb = await _extractEmbeddingFromFile(audioPath);

    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);

    final list = (data[n] ?? <List<double>>[]) as List<dynamic>;
    final updated = <List<double>>[];
    for (final e in list) {
      updated.add(List<double>.from(e as List));
    }
    updated.add(emb);
    data[n] = updated;

    await prefs.setString(_storageKey, jsonEncode(data));
    return n;
  }

  /// One-shot enroll to a unique name (kept for compatibility).
  Future<String> enrollName(String name, String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);

    var finalName = name.trim();
    if (finalName.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    if (data.containsKey(finalName)) {
      var i = 2;
      while (data.containsKey('$finalName-$i')) i++;
      finalName = '$finalName-$i';
    }

    final emb = await _extractEmbeddingFromFile(audioPath);
    data[finalName] = <List<double>>[emb];
    await prefs.setString(_storageKey, jsonEncode(data));
    return finalName;
  }

  /// Identify best match; returns user name or null if not confident.
  Future<String?> identify(
      String audioPath, {
        double threshold = 0.80,
        double secondBestMargin = 0.04,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    if (data.isEmpty) return null;

    final probe = await _extractEmbeddingFromFile(audioPath);

    String? bestId;
    double best = -1.0, secondBest = -1.0;

    data.forEach((name, listDynamic) {
      final list = (listDynamic as List)
          .map<List<double>>((e) => List<double>.from(e as List))
          .toList();
      if (list.isEmpty) return;

      final avg = _meanVector(list);
      final s = _cosine(avg, probe);
      if (s > best) {
        secondBest = best;
        best = s;
        bestId = name;
      } else if (s > secondBest) {
        secondBest = s;
      }
    });

    if (best >= threshold && (best - secondBest) >= secondBestMargin) {
      return bestId;
    }
    return null;
  }

  Future<List<String>> listRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    final list = data.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<Map<String, int>> listRegisteredWithCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    final out = <String, int>{};
    for (final e in data.entries) {
      final samples = (e.value as List?) ?? const [];
      out[e.key] = samples.length;
    }
    return Map.fromEntries(out.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ---------- Internals ----------

  Map<String, dynamic> _loadEmbeddings(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    final raw = jsonDecode(jsonStr);

    // Back-compat: if value is List<double>, wrap as [value]
    final out = <String, dynamic>{};
    (raw as Map<String, dynamic>).forEach((k, v) {
      if (v is List && v.isNotEmpty && v.first is num) {
        out[k] = <List<double>>[
          List<double>.from(v.map((e) => (e as num).toDouble()))
        ];
      } else if (v is List) {
        out[k] = v;
      } else {
        out[k] = <List<double>>[];
      }
    });
    return out;
  }

  Future<String> _ensureModelIsReady() async {
    // Support one expected asset path. Change if you prefer a different name.
    const assetPath = 'assets/models/speaker_embedding.onnx';

    final bytes = await rootBundle.load(assetPath).catchError((_) {
      throw StateError(
        'Model not found in assets: $assetPath\n'
            'Add it to pubspec.yaml and include the file.',
      );
    });

    final dir = await getApplicationSupportDirectory();
    final dst = File('${dir.path}/speaker_embedding.onnx');
    if (!await dst.exists() || (await dst.length()) != bytes.lengthInBytes) {
      await dst.create(recursive: true);
      await dst.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    return dst.path;
  }

  /// Extract a normalized speaker embedding from a WAV file using
  /// SpeakerEmbeddingExtractor. We read the wave, push to an OnlineStream,
  /// mark input finished, wait until ready, then compute. :contentReference[oaicite:2]{index=2}
  Future<List<double>> _extractEmbeddingFromFile(String wavPath) async {
    final ext = _extractor;
    if (ext == null) {
      throw StateError('SpeakerService not initialized');
    }

    final wave = readWave(wavPath); // -> WaveData {samples, sampleRate} :contentReference[oaicite:3]{index=3}
    if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
      throw StateError('Invalid/empty WAV: $wavPath');
    }

    final stream = ext.createStream(); // :contentReference[oaicite:4]{index=4}
    try {
      // Feed all samples and finalize input
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate); // :contentReference[oaicite:5]{index=5}
      stream.inputFinished(); // :contentReference[oaicite:6]{index=6}

      // Wait until extractor is ready, then compute embedding
      while (!ext.isReady(stream)) {
        await Future.delayed(const Duration(milliseconds: 2));
      }
      final emb = ext.compute(stream); // Float32List embedding :contentReference[oaicite:7]{index=7}
      return _l2norm(List<double>.from(emb));
    } finally {
      try {
        stream.free();
      } catch (_) {}
    }
  }

  // ---------- Vector math ----------

  List<double> _l2norm(List<double> v) {
    double nrm = 0.0;
    for (final x in v) nrm += x * x;
    if (nrm == 0) return v;
    nrm = sqrt(nrm);
    return v.map((x) => x / nrm).toList();
  }

  List<double> _meanVector(List<List<double>> xs) {
    if (xs.isEmpty) return const <double>[];
    final m = xs.first.length;
    final out = List<double>.filled(m, 0.0);
    for (final v in xs) {
      for (int i = 0; i < m; i++) out[i] += v[i];
    }
    for (int i = 0; i < m; i++) out[i] /= xs.length;
    return _l2norm(out);
  }

  double _cosine(List<double> a, List<double> b) {
    final m = min(a.length, b.length);
    if (m == 0) return 0.0;
    double dot = 0.0, na = 0.0, nb = 0.0;
    for (int i = 0; i < m; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (sqrt(na) * sqrt(nb));
  }
}
