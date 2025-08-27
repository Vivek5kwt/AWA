import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ONNX path if present, otherwise we use the heuristic fallback.
import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Simple WAV container for our parser (16-bit PCM).
class _Wav {
  _Wav(this.samples, this.sampleRate, this.numChannels);
  final Int16List samples; // interleaved if numChannels > 1
  final int sampleRate;
  final int numChannels;
  int get length => samples.length;
}

/// Offline speaker enrollment + identification with automatic fallback.
class SpeakerService {
  SpeakerService._internal();
  static final SpeakerService _instance = SpeakerService._internal();
  factory SpeakerService() => _instance;

  static const _assetModelPath =
      'assets/models/3dspeaker_speech_eres2netv2_sv_zh-cn_16k-common.onnx';

  SpeakerEmbeddingExtractor? _extractor; // non-null when ONNX available
  String? _modelLocalPath; // copied model path in app storage
  late String _storeKey; // per-mode bucket (onnx vs fallback)

  bool _initialized = false;

  bool get isReady => _extractor != null;
  bool get isFallback => _extractor == null;
  bool get initialized => _initialized;

  /// Initialize backend + decide per-mode storage key.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize sherpa_onnx FFI bindings (no-op if already done)
    try {
      initBindings();
    } catch (_) {}

    // Helpful diagnostics so asset issues are obvious
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      if (!manifest.contains(_assetModelPath)) {
        debugPrint('[SpeakerService] Asset NOT in bundle: $_assetModelPath');
      } else {
        debugPrint('[SpeakerService] Asset found in bundle: $_assetModelPath');
      }
    } catch (_) {}

    // Try prepare/copy model and build extractor
    _modelLocalPath = await _copyModelIfAny();
    if (_modelLocalPath != null) {
      try {
        final cfg = SpeakerEmbeddingExtractorConfig(
          model: _modelLocalPath!,
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        );
        _extractor = SpeakerEmbeddingExtractor(config: cfg);
        debugPrint('[SpeakerService] ONNX model loaded: $_modelLocalPath');
      } catch (e) {
        _extractor = null;
        debugPrint('[SpeakerService] Failed to init ONNX model, fallback: $e');
      }
    } else {
      debugPrint('[SpeakerService] No ONNX model in assets; using fallback heuristic.');
    }

    // Separate the stores so ONNX and fallback samples never mix
    _storeKey = _extractor != null
        ? '3dspeaker_speech_eres2netv2_sv_zh-cn_16k-common.onnx'
        : 'speaker_embeddings_v3_fallback';
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      _extractor?.free();
    } catch (_) {}
    _extractor = null;
    _initialized = false;
  }

  // ---------------- Public API ----------------

  Future<bool> hasEnrollments() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    return data.isNotEmpty;
  }

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

    await prefs.setString(_storeKey, jsonEncode(data));
    return n;
  }

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
    await prefs.setString(_storeKey, jsonEncode(data));
    return finalName;
  }

  /// Identify best match. Returns name or null if not confident.
  Future<String?> identify(
      String audioPath, {
        double threshold = 0.74,
        double secondBestMargin = 0.035,
        double displayThreshold = 0.40,
      }) async {
    // Use ranked scoring to decide the label
    final scores = await identifyScores(
      audioPath,
      topK: 2,
      includeBelowThreshold: true,
    );
    if (scores.isEmpty) return null;

    final best = scores[0];
    final bestScore = (best['score'] as num).toDouble();
    final bestId = best['name'] as String;
    final secondBest =
    scores.length > 1 ? (scores[1]['score'] as num).toDouble() : -1.0;

    final localThreshold = isFallback ? max(0.70, threshold - 0.04) : threshold;
    final localMargin =
    isFallback ? max(0.03, secondBestMargin - 0.01) : secondBestMargin;

    debugPrint('[Identify] top=$bestId '
        '${(bestScore * 100).toStringAsFixed(2)}% '
        'second=${(secondBest * 100).toStringAsFixed(2)}% '
        '(hardThr=${(localThreshold * 100).toStringAsFixed(0)}%, '
        'margin=${(localMargin * 100).toStringAsFixed(1)}%, '
        'displayThr=${(displayThreshold * 100).toStringAsFixed(0)}%)');

    String? result;
    if (bestScore >= localThreshold && (bestScore - secondBest) >= localMargin) {
      result = bestId;
    } else if (bestScore >= displayThreshold) {
      result = bestId;
    }

    if (result != null) {
      debugPrint('[Identify] Recognized ' 
          '$result @ ${(bestScore * 100).toStringAsFixed(1)}%');
    } else {
      debugPrint('[Identify] No confident match '
          '(top=$bestId @ ${(bestScore * 100).toStringAsFixed(1)}%)');
    }

    return result;
  }

  /// NEW: ranked candidates (name + score in 0..1). If [includeBelowThreshold] is
  /// false, prunes very low scores (< 0.20).
  Future<List<Map<String, dynamic>>> identifyScores(
      String audioPath, {
        int topK = 5,
        bool includeBelowThreshold = false,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    var data = _loadEmbeddings(prefs);
    if (data.isEmpty) {
      debugPrint('[SpeakerService] No enrollments in current mode ($_storeKey).');
      return [];
    }

    final probe = await _extractEmbeddingFromFile(audioPath);
    final probeDim = probe.length;

    // Keep only entries matching current embedding dimension
    data = _filterByDim(data, probeDim);
    if (data.isEmpty) {
      debugPrint(
          '[SpeakerService] Enrollment embeddings do not match dimension $probeDim. Re-enroll in this mode.');
      return [];
    }

    final List<Map<String, dynamic>> results = [];
    for (final entry in data.entries) {
      final name = entry.key;
      final list = (entry.value as List)
          .map<List<double>>((e) => List<double>.from(e as List))
          .toList();
      if (list.isEmpty) continue;

      final centroid = _meanVector(list);
      final centroidScore = _cosine(centroid, probe);

      double bestSample = -1.0;
      for (final s in list) {
        final sc = _cosine(s, probe);
        if (sc > bestSample) bestSample = sc;
      }

      final score = 0.6 * centroidScore + 0.4 * bestSample;
      results.add({'name': name, 'score': score});
    }

    results.sort((a, b) =>
        (b['score'] as double).compareTo(a['score'] as double));

    // Pretty console readout
    debugPrint('--- Speaker candidates ---');
    for (final c in results) {
      final n = c['name'];
      final sc = (c['score'] as double).clamp(0.0, 1.0);
      debugPrint('  $n : ${(sc * 100).toStringAsFixed(1)}%');
    }

    if (!includeBelowThreshold) {
      return results.where((e) => (e['score'] as double) >= 0.20).take(topK).toList();
    }
    return results.take(topK).toList();
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
    await prefs.remove(_storeKey);
  }

  /// Delete one enrolled speaker by name. Returns true if removed.
  Future<bool> deleteByName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _loadEmbeddings(prefs);
    if (!data.containsKey(name)) return false;
    data.remove(name);
    await prefs.setString(_storeKey, jsonEncode(data));
    return true;
  }

  // ---------------- Internals ----------------

  Map<String, dynamic> _loadEmbeddings(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_storeKey);
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

  Map<String, dynamic> _filterByDim(Map<String, dynamic> data, int dim) {
    final out = <String, dynamic>{};
    data.forEach((name, listDynamic) {
      final list = (listDynamic as List)
          .map<List<double>>((e) => List<double>.from(e as List))
          .where((e) => e.length == dim)
          .toList();
      if (list.isNotEmpty) out[name] = list;
    });
    return out;
  }

  Future<String?> _copyModelIfAny() async {
    try {
      final bytes = await rootBundle.load(_assetModelPath);
      final dir = await getApplicationSupportDirectory();
      final dst = File('${dir.path}/3dspeaker_speech_eres2netv2_sv_zh-cn_16k-common.onnx');
      if (!await dst.exists() || (await dst.length()) != bytes.lengthInBytes) {
        await dst.create(recursive: true);
        await dst.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      return dst.path;
    } catch (e) {
      debugPrint('[SpeakerService] rootBundle.load failed for $_assetModelPath: $e');
      return null;
    }
  }

  // -------- Embedding extraction (with quality gate) --------

  Future<List<double>> _extractEmbeddingFromFile(String wavPath) async {
    final wav = await _parseWav(wavPath);
    if (wav == null || wav.length < wav.sampleRate ~/ 2) {
      throw StateError('Recording too short or invalid.');
    }

    // Downmix to mono (if device ignored mono request)
    final mono = _downmixToMono(wav.samples, wav.numChannels);

    // Trim silence + normalize
    var processed = _trimSilenceAndNormalize(mono, wav.sampleRate);

    // Resample to 16 kHz if needed for model accuracy/speed
    const targetSr = 16000;
    if (wav.sampleRate != targetSr) {
      processed = _resampleLinear(processed, wav.sampleRate, targetSr);
    }

    // Enforce minimum speech duration
    final speechSec = processed.length / targetSr;
    if (speechSec < 1.2) {
      throw StateError('Please speak clearly for at least 1.2 seconds.');
    }

    if (_extractor != null) {
      final f32 = Float32List.fromList(processed);
      final stream = _extractor!.createStream();
      try {
        stream.acceptWaveform(samples: f32, sampleRate: targetSr);
        stream.inputFinished();
        while (!_extractor!.isReady(stream)) {
          await Future.delayed(const Duration(milliseconds: 2));
        }
        final emb = _extractor!.compute(stream); // Float32List
        return _l2norm(List<double>.from(emb));
      } finally {
        try {
          stream.free();
        } catch (_) {}
      }
    } else {
      // Fallback handcrafted embedding (compact, robust-ish)
      final wav2 = _Wav(
        Int16List.fromList(
          processed
              .map((v) => (v * 32768.0).clamp(-32768.0, 32767.0).toInt())
              .toList(),
        ),
        targetSr,
        1,
      );
      return _extractEmbeddingHeuristicFromWav(wav2);
    }
  }

  // ---------------- WAV parsing ----------------

  Future<_Wav?> _parseWav(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) return null;

    String _s(int o, int n) => String.fromCharCodes(bytes.sublist(o, o + n));
    if (_s(0, 4) != 'RIFF' || _s(8, 4) != 'WAVE') return null;

    final bd = ByteData.sublistView(bytes);
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;
    int? numChannels;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = _s(offset, 4);
      final size = bd.getUint32(offset + 4, Endian.little);
      final next = offset + 8 + size + (size.isOdd ? 1 : 0);
      if (id == 'fmt ') {
        final audioFormat = bd.getUint16(offset + 8, Endian.little);
        numChannels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
        if (audioFormat != 1 || bitsPerSample != 16 || (numChannels ?? 0) < 1) {
          return null; // expect PCM 16-bit mono/stereo
        }
      } else if (id == 'data') {
        dataOffset = offset + 8;
        dataSize = size;
        break;
      }
      offset = next;
    }

    if (sampleRate == null || bitsPerSample != 16 || dataOffset == null || dataSize == null) {
      return null;
    }
    if (dataOffset + dataSize > bytes.length) {
      return null;
    }

    final samples = Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes + dataOffset,
      dataSize ~/ 2,
    );
    return _Wav(samples, sampleRate, numChannels ?? 1);
  }

  // ---------------- Pre-processing helpers ----------------

  List<double> _downmixToMono(Int16List s, int channels) {
    if (channels <= 1) {
      return List<double>.generate(s.length, (i) => s[i] / 32768.0);
    }
    final frames = s.length ~/ channels;
    final out = List<double>.filled(frames, 0.0);
    var idx = 0;
    for (int f = 0; f < frames; f++) {
      double acc = 0.0;
      for (int c = 0; c < channels; c++) {
        acc += s[idx++] / 32768.0;
      }
      out[f] = acc / channels;
    }
    return out;
  }

  /// Trim leading/trailing silence and normalize peak amplitude.
  List<double> _trimSilenceAndNormalize(List<double> x, int sr) {
    final int frame = max(1, (sr * 0.025).round()); // 25 ms
    final int hop = max(1, (sr * 0.010).round()); // 10 ms
    final n = x.length;

    // Frame RMS
    final rms = <double>[];
    for (int start = 0; start + frame <= n; start += hop) {
      double sumSq = 0.0;
      for (int i = start; i < start + frame; i++) {
        final v = x[i];
        sumSq += v * v;
      }
      rms.add(sqrt(sumSq / frame));
    }
    if (rms.isEmpty) return x;

    final sorted = List<double>.from(rms)..sort();
    final median = sorted[(sorted.length - 1) ~/ 2];
    final thresh = max(0.008, median * 0.6);

    int first = -1, last = -1;
    for (int i = 0; i < rms.length; i++) {
      if (rms[i] >= thresh) {
        first = i;
        break;
      }
    }
    for (int i = rms.length - 1; i >= 0; i--) {
      if (rms[i] >= thresh) {
        last = i;
        break;
      }
    }
    if (first == -1 || last == -1 || last < first) {
      return _normalizePeak(x);
    }

    final startSamp = (first * hop).clamp(0, n - 1);
    final endSamp = min(n, last * hop + frame);
    final cut = x.sublist(startSamp, endSamp);

    final minKeep = max(1, (sr * 0.5).round());
    if (cut.length < minKeep) return _normalizePeak(x);

    return _normalizePeak(cut);
  }

  List<double> _normalizePeak(List<double> x) {
    double peak = 0.0;
    for (final v in x) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak < 1e-6) return x;
    final scale = 0.98 / peak;
    return [for (final v in x) v * scale];
  }

  /// Linear resample from [srcSr] to [dstSr].
  List<double> _resampleLinear(List<double> x, int srcSr, int dstSr) {
    if (srcSr == dstSr || x.isEmpty) return x;
    final ratio = dstSr / srcSr;
    final m = max(1, (x.length * ratio).round());
    final out = List<double>.filled(m, 0.0);
    for (int i = 0; i < m; i++) {
      final t = i / ratio;
      final idx = t.floor();
      final frac = t - idx;
      final a = x[idx];
      final b = idx + 1 < x.length ? x[idx + 1] : a;
      out[i] = a + (b - a) * frac;
    }
    return out;
  }

  // ---------------- Fallback heuristic embedding ----------------

  Future<List<double>> _extractEmbeddingHeuristicFromWav(_Wav wav) async {
    final n = wav.samples.length;
    final x = List<double>.filled(n, 0.0);
    double mean = 0.0;
    for (int i = 0; i < n; i++) {
      final v = wav.samples[i] / 32768.0;
      x[i] = v;
      mean += v;
    }
    mean /= max(1, n);

    // pre-emphasis
    const a = 0.97;
    double prev = 0.0;
    for (int i = 0; i < n; i++) {
      final v = x[i] - mean;
      final y = v - a * prev;
      x[i] = y;
      prev = v;
    }

    final int sr = wav.sampleRate;
    final int frame = max(1, (sr * 0.025).round());
    final int hop = max(1, (sr * 0.010).round());

    final rmsAll = <double>[];
    final zcrAll = <double>[];
    final freqs = <double>[200, 400, 800, 1600, 3200, 6000];
    final bandLogsAll =
    List<List<double>>.generate(freqs.length, (_) => <double>[]);

    for (int start = 0; start + frame <= n; start += hop) {
      double sumSq = 0.0;
      int zeroX = 0;

      double sPrev = x[start];
      for (int i = start; i < start + frame; i++) {
        final s = x[i];
        sumSq += s * s;
        if ((sPrev >= 0 && s < 0) || (sPrev < 0 && s >= 0)) zeroX++;
        sPrev = s;
      }
      final r = sqrt(sumSq / frame);
      final z = zeroX / frame;
      rmsAll.add(r);
      zcrAll.add(z);

      for (int fIdx = 0; fIdx < freqs.length; fIdx++) {
        final pw = _goertzelPower(x, start, frame, freqs[fIdx], sr);
        final lp = log(pw + 1e-12);
        bandLogsAll[fIdx].add(lp);
      }
    }

    // pick speechy frames
    List<int> keep = [];
    if (rmsAll.isNotEmpty) {
      final sorted = List<double>.from(rmsAll)..sort();
      final median = sorted[(sorted.length - 1) ~/ 2];
      final thresh = max(0.010, median * 0.6);
      for (int i = 0; i < rmsAll.length; i++) {
        if (rmsAll[i] >= thresh) keep.add(i);
      }
      if (keep.length < 8) {
        final idxs = List<int>.generate(rmsAll.length, (i) => i);
        idxs.sort((a, b) => rmsAll[b].compareTo(rmsAll[a]));
        final k = max(8, (rmsAll.length * 0.2).round());
        keep = idxs.take(k).toList();
      }
    }

    List<double> _pick(List<double> xs) => [for (final i in keep) xs[i]];
    final rms = _pick(rmsAll);
    final zcr = _pick(zcrAll);
    final bandLogs =
    List<List<double>>.generate(freqs.length, (j) => _pick(bandLogsAll[j]));

    List<double> _stats(List<double> v) {
      if (v.isEmpty) return [0, 0, 0, 0, 0, 0];
      final sorted = List<double>.from(v)..sort();
      final mean = v.reduce((a, b) => a + b) / v.length;
      double varSum = 0.0;
      for (final x in v) {
        final d = x - mean;
        varSum += d * d;
      }
      final std = sqrt(varSum / max(1, v.length - 1));
      double q(double p) => sorted[
      (p * (sorted.length - 1)).clamp(0, (sorted.length - 1).toDouble()).round()];
      final p25 = q(0.25), p50 = q(0.50), p75 = q(0.75);
      final p05 = q(0.05), p95 = q(0.95);
      final range = p95 - p05;
      return [mean, std, p25, p50, p75, range];
    }

    final f = <double>[];
    f.addAll(_stats(rms)); // 6
    f.addAll(_stats(zcr)); // +6 = 12
    for (final band in bandLogs) {
      final s = _stats(band);
      f.add(s[0]); // mean
      f.add(s[1]); // std
    } // +12 = 24 total dims

    return _l2norm(f);
  }

  double _goertzelPower(
      List<double> x, int start, int len, double freq, int sr) {
    if (len <= 0) return 0.0;
    final k = (0.5 + len * freq / sr).floor();
    final omega = 2.0 * pi * k / len;
    final coeff = 2.0 * cos(omega);

    double s0 = 0.0, s1 = 0.0, s2 = 0.0;
    final end = start + len;
    for (int i = start; i < end; i++) {
      s0 = x[i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return max(power, 0.0);
  }

  // ---------------- Vector math ----------------

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
