import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class AsrService {
  AsrService._internal();
  static final AsrService _instance = AsrService._internal();
  factory AsrService() => _instance;

  OfflineRecognizer? _asr;
  bool _initialized = false;

  OfflineRecognizer? get asr => _asr;
  bool get isReady => _asr != null;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final asrDir = Directory('${dir.path}/asr');
      if (!await asrDir.exists()) {
        await asrDir.create(recursive: true);
      }

      Future<String> copy(String asset, String fileName) async {
        final bytes = await rootBundle.load(asset);
        final dst = File('${asrDir.path}/$fileName');
        if (!await dst.exists() || (await dst.length()) != bytes.lengthInBytes) {
          await dst.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        }
        return dst.path;
      }

      final encoder = await copy('assets/asr/encoder-epoch-99-avg-1.onnx', 'encoder-epoch-99-avg-1.onnx');
      final decoder = await copy('assets/asr/decoder-epoch-99-avg-1.onnx', 'decoder-epoch-99-avg-1.onnx');
      final joiner = await copy('assets/asr/joiner-epoch-99-avg-1.onnx', 'joiner-epoch-99-avg-1.onnx');
      final tokens = await copy('assets/asr/tokens.txt', 'tokens.txt');

      final cfg = OfflineRecognizerConfig(
        feat: FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: OfflineModelConfig(
          transducer: OfflineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: tokens,
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 4,
      );

      _asr = OfflineRecognizer(cfg);
      debugPrint('[AsrService] Ready with Conformer EN model.');
    } catch (e) {
      debugPrint('[AsrService] init failed: $e');
      _asr = null;
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      _asr?.free();
    } catch (_) {}
    _asr = null;
    _initialized = false;
  }
}

