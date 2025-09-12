import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:wave_blob/wave_blob.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web_socket_channel/io.dart';

import '../../../../core/utils/routing/routes.dart';

class GroupSpeechToTextScreen extends StatefulWidget {
  final bool isDarkMode;
  final String phoneNumber;

  const GroupSpeechToTextScreen({
    Key? key,
    this.isDarkMode = false,
    required this.phoneNumber,
  }) : super(key: key);

  @override
  State<GroupSpeechToTextScreen> createState() => _GroupSpeechToTextScreenState();
}

class _GroupSpeechToTextScreenState extends State<GroupSpeechToTextScreen> with TickerProviderStateMixin {
  bool _isRecording = false;
  double _amplitude = 0;
  Timer? _amplitudeTimer;
  late AnimationController _micGlowController;
  final AudioRecorder _recorder = AudioRecorder();
  IOWebSocketChannel? _assemblyChannel;
  StreamSubscription<Uint8List>? _audioStreamSub;

  final List<Map<String, dynamic>> _messages = [];
  int _speakerIndex = 0;
  final List<Color> _userColors = [
    const Color(0xFF50E3C2),
    const Color(0xFF8E54E9),
    const Color(0xFF4776E6),
    const Color(0xFFFFA726),
  ];
  final Map<String, String> _speakerNames = {};
  final Map<String, Color> _speakerColors = {};

  String? _currentFilePath;
  final TextEditingController _textController = TextEditingController();
  String _myName = '';
  Color _myColor = const Color(0xFF1E88E5);

  final FlutterTts _flutterTts = FlutterTts();

  String _appLanguageCode = 'en';

  bool _speakOnMeeting = true;
  bool _showTextMyLanguage = false;

  final List<_AudioQueueItem> _audioQueue = [];
  bool _isApiProcessing = false;
  int _audioLabel = 0;

  late final ScrollController _scrollController;
  bool _showScrollDownBtn = false;
  bool _shouldAutoscroll = true;

  late final FirebaseFirestore _firestore;
  late String _meetingDocId;
  bool _savingHistory = false;

  String _latestSentence = '';
  Timer? _latestSentenceTimer;
  Timer? _silenceTimer;
  final Duration _silenceDuration = const Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _micGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.97,
      upperBound: 1.13,
    )..repeat(reverse: true);
    _initUser();
    _initTTS();
    _loadSpeakOnMeeting();
    _loadShowTextMyLanguage();
    _loadAppLanguageCode();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);

    _firestore = FirebaseFirestore.instance;
    _meetingDocId = "meeting_${DateTime.now().millisecondsSinceEpoch}";
    _loadPreviousMessages();
  }

  Future<void> _loadPreviousMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final doc = await _firestore
        .collection('meeting_histories')
        .doc('user_$email')
        .collection('meetings')
        .doc(_meetingDocId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        _messages.clear();
        _messages.addAll(List<Map<String, dynamic>>.from(data['messages'] ?? []));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _handleScroll() {
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 50;
    if (atBottom && _showScrollDownBtn) {
      setState(() {
        _showScrollDownBtn = false;
        _shouldAutoscroll = true;
      });
    } else if (!atBottom && !_showScrollDownBtn) {
      setState(() {
        _showScrollDownBtn = true;
        _shouldAutoscroll = false;
      });
    }
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _latestSentenceTimer?.cancel();
    _silenceTimer?.cancel();
    _audioStreamSub?.cancel();
    _assemblyChannel?.sink.close();
    _recorder.dispose();
    _micGlowController.dispose();
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSpeakOnMeeting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speakOnMeeting = prefs.getBool('speakOnMeeting') ?? true;
    });
  }

  Future<void> _loadShowTextMyLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showTextMyLanguage = prefs.getBool('useNativeApi') ?? false;
    });
  }

  Future<void> _toggleShowTextMyLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_showTextMyLanguage;
    await prefs.setBool('useNativeApi', newVal);
    setState(() => _showTextMyLanguage = newVal);
  }

  Future<void> _loadAppLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language_code');
    setState(() {
      _appLanguageCode = code ?? Localizations.localeOf(context).languageCode;
    });
  }

  Future<void> _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'Me';
    final name = prefs.getString('name') ?? email.split('@')[0];
    setState(() {
      _myName = _capitalize(name);
      _myColor = const Color(0xFF1E88E5);
    });
  }

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage("en-IN");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.32);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setVoice({
      'name': 'en-in-x-end-network',
      'locale': 'en-IN',
    });
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _generateTempFilePath() {
    final tempDir = Directory.systemTemp;
    return '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  String _getSpeakerName(String speakerId) {
    return _speakerNames.putIfAbsent(
        speakerId, () => 'speaker${_speakerNames.length + 1}');
  }

  Color _getSpeakerColor(String speakerId) {
    return _speakerColors.putIfAbsent(speakerId, () {
      final color = _userColors[_speakerIndex % _userColors.length];
      _speakerIndex++;
      return color;
    });
  }

  Future<void> _sendTurnChunk({
    required String text,
    required int start,
    required int end,
    String speaker = 'unknown',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? '';
      final uri = Uri.parse(ApiConstants.streamIdentify);
      final body = jsonEncode({
        'email': email,
        'start': start,
        'end': end,
        'speaker': speaker,
        'text': text,
      });
      final res = await http.post(uri,
          headers: {'Content-Type': 'application/json'}, body: body);
      print('📡 Sent chunk to stream_identify: ${res.statusCode}');
    } catch (e) {
      print('❌ Failed to send chunk: $e');
    }
  }

  /// Ensures outgoing audio chunks are little-endian PCM16.
  /// Some platforms may provide PCM data in a different endianness, so we
  /// explicitly rewrite each 16-bit sample as little endian before sending it
  /// to AssemblyAI.
  Uint8List _toPCM16LE(Uint8List data) {
    final input = ByteData.sublistView(data);
    final out = Uint8List(data.length);
    final output = ByteData.sublistView(out);
    for (int i = 0; i < data.length ~/ 2; i++) {
      final sample = input.getInt16(i * 2, Endian.little);
      output.setInt16(i * 2, sample, Endian.little);
    }
    return out;
  }

  // 🔧 FIXED: use /v3/ws (not just /v3). Kept sample_rate & encoding. Added format_turns and a keep-alive ping.
  Future<void> _initAssemblyConnection() async {
    try {
      final url =
          'wss://streaming.assemblyai.com/v3/ws?sample_rate=16000&encoding=pcm_s16le&format_turns=true';

      print("🔌 Connecting to: $url");

      _assemblyChannel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: {
          // For production you should use an ephemeral token instead of your permanent key.
          'Authorization': '2e2658a6407841d195ab268060d19b7e',
        },
        pingInterval: const Duration(seconds: 15),
      );

      print("  Connected to AssemblyAI Universal Streaming. Waiting for messages...");

      _assemblyChannel!.stream.listen((message) async {
        print("📩 Message received: $message");
        try {
          final data = jsonDecode(message);
          final rawType = (data['message_type'] ?? data['type'] ?? '').toString();
          final msgType = rawType.toLowerCase();

          // Helper to safely parse ints from dynamic values
          int _parseTime(dynamic v) {
            if (v is int) return v;
            return int.tryParse(v?.toString() ?? '') ?? 0;
          }

          if (msgType == 'partialtranscript' || msgType == 'partial_transcript') {
            final text = data['text']?.toString() ?? '';
            final start = _parseTime(data['audio_start']);
            final end = _parseTime(data['audio_end']);
            final spId = data['speaker']?.toString() ?? 'unknown';
            final spName = _getSpeakerName(spId);
            print("✍️ Partial Transcript: $text [$start-$end] ($spName)");
            setState(() => _latestSentence = text);
            unawaited(_sendTurnChunk(
                text: text, start: start, end: end, speaker: spName));
          } else if (msgType == 'finaltranscript' ||
              msgType == 'final_transcript') {
            final text = data['text']?.toString() ?? '';
            print("✅ Final Transcript: $text");
            final words = data['words'] as List? ?? [];
            if (words.isNotEmpty) {
              final List<Map<String, dynamic>> segments = [];
              String? currentSpeaker;
              int? segStart;
              int? segEnd;
              final buffer = StringBuffer();
              for (final w in words) {
                final sp = w['speaker']?.toString() ?? 'unknown';
                final wStart = w['start'] is int
                    ? w['start'] as int
                    : int.tryParse(w['start'].toString()) ?? 0;
                final wEnd = w['end'] is int
                    ? w['end'] as int
                    : int.tryParse(w['end'].toString()) ?? 0;
                final wText = w['text']?.toString() ?? '';
                if (currentSpeaker == null) {
                  currentSpeaker = sp;
                  segStart = wStart;
                } else if (sp != currentSpeaker) {
                  segments.add({
                    'speaker': currentSpeaker,
                    'start': segStart ?? 0,
                    'end': segEnd ?? segStart ?? 0,
                    'text': buffer.toString().trim(),
                  });
                  buffer.clear();
                  currentSpeaker = sp;
                  segStart = wStart;
                }
                segEnd = wEnd;
                buffer.write('$wText ');
              }
              if (currentSpeaker != null) {
                segments.add({
                  'speaker': currentSpeaker,
                  'start': segStart ?? 0,
                  'end': segEnd ?? segStart ?? 0,
                  'text': buffer.toString().trim(),
                });
              }
              final newMessages = <Map<String, dynamic>>[];
              for (final seg in segments) {
                final spId = seg['speaker'] as String;
                final spName = _getSpeakerName(spId);
                final spColor = _getSpeakerColor(spId);
                final segText = seg['text'] as String;
                final segStart = seg['start'] as int;
                final segEnd = seg['end'] as int;
                print('🗣️ $spName [$segStart-$segEnd]: $segText');
                unawaited(_sendTurnChunk(
                    text: segText,
                    start: segStart,
                    end: segEnd,
                    speaker: spName));
                newMessages.add({
                  'user': spName,
                  'text': segText,
                  'time': TimeOfDay.now().format(context),
                  'isMe': false,
                  'color': spColor,
                });
              }
              if (newMessages.isNotEmpty) {
                setState(() {
                  _messages.addAll(newMessages);
                  _latestSentence = '';
                });
                if (_shouldAutoscroll) _scrollToBottom();
              }
            } else {
              final start = _parseTime(data['audio_start']);
              final end = _parseTime(data['audio_end']);
              unawaited(
                  _sendTurnChunk(text: text, start: start, end: end, speaker: _myName));
              setState(() {
                _messages.add({
                  'user': _myName,
                  'text': text,
                  'time': TimeOfDay.now().format(context),
                  'isMe': true,
                });
                _latestSentence = '';
              });
            if (_shouldAutoscroll) _scrollToBottom();
          }
          } else if (msgType == 'turndetected' ||
              msgType == 'turn' ||
              msgType == 'turn_detected') {
            final text = data['text']?.toString() ?? '';
            final start = _parseTime(data['audio_start']);
            final end = _parseTime(data['audio_end']);
            final spId = data['speaker']?.toString() ?? 'unknown';
            final spName = _getSpeakerName(spId);
            print("🔀 Turn detected for $spName: $text [$start-$end]");
            unawaited(
                _sendTurnChunk(text: text, start: start, end: end, speaker: spName));
          } else if (msgType == 'sessionbegins' ||
              msgType == 'session_begins') {
            print('🚀 Session begins');
          } else {
            print("ℹ️ Other message type: $rawType");
          }
        } catch (e) {
          print("❌ Failed to parse: $e");
        }
      }, onError: (error) {
        print('⚠️ WebSocket error: $error');
      }, onDone: () {
        print('🔚 WebSocket connection closed');
      });


    } catch (e, st) {
      print("❌ Connection failed: $e\n$st");
    }
  }

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;

    await _initAssemblyConnection();

    setState(() {
      _isRecording = true;
      _speakerIndex = 0;
    });
    _resetSilenceTimer();

    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!_isRecording) return;
      setState(() {
        _amplitude = 2200 + Random().nextInt(3400).toDouble();
      });
    });

    final config = const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );
    print('🎙️ Recorder config: 16kHz mono PCM16');
    final stream = await _recorder.startStream(config);

    _audioStreamSub = stream.listen((data) {
      if (_assemblyChannel != null) {
        final pcmBytes = _toPCM16LE(data);
        final base64Chunk = base64Encode(pcmBytes);
        print("🎤 Sending ${pcmBytes.length} bytes");
        _assemblyChannel!.sink.add(jsonEncode({
          "audio_data": base64Chunk,
        }));
      }
    });

  }

  Future<void> _continueRecordingCycle() async {
    while (_isRecording) {
      await Future.delayed(const Duration(seconds: 5));
      if (!_isRecording) break;

      final String? stoppedPath = await _recorder.stop();
      if (stoppedPath != null) {
        final File audioFile = File(stoppedPath);
        final label = _audioLabel++;
        bool shouldSend = await _isAudioSignificant(audioFile);
        if (shouldSend) {
          _resetSilenceTimer();
          _audioQueue.add(_AudioQueueItem(file: audioFile, label: label));
          _processAudioQueue();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("No voice detected, try again!"),
              backgroundColor: Colors.orange.shade400,
              duration: const Duration(milliseconds: 900),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      if (!_isRecording) break;

      _currentFilePath = _generateTempFilePath();
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 256000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentFilePath!,
      );
    }
  }

  Future<bool> _isAudioSignificant(File file) async {
    try {
      if (!(await file.exists())) return false;
      final bytes = await file.readAsBytes();
      if (bytes.length < 6000) return false;
      if (bytes.length > 44) {
        Uint8List pcm = bytes.sublist(44);
        int silentCount = 0;
        for (int i = 0; i < pcm.length; i += 2) {
          int val = pcm[i] | (pcm[i + 1] << 8);
          if (val.abs() < 300) silentCount++;
        }
        if (silentCount > (pcm.length ~/ 2 * 0.90)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopListening() async {
    setState(() {
      _isRecording = false;
      _amplitude = 0;
    });
    _silenceTimer?.cancel();
    _amplitudeTimer?.cancel();
    await _audioStreamSub?.cancel();
    await _recorder.stop();
    _assemblyChannel?.sink.close();
  }

  Future<int> _getWavDurationSeconds(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return 0;
      final byteRate = bytes.buffer.asByteData().getUint32(28, Endian.little);
      final dataLen = bytes.length - 44;
      if (byteRate > 0) return (dataLen ~/ byteRate).clamp(0, 1000);
    } catch (_) {}
    return 0;
  }

  // Allow English and major Indian scripts so that Hindi or other
  // Indian languages are not filtered out when app language is English.
  bool _isTextInLanguage(String text, String languageCode) {
    if (languageCode == 'en') {
      final englishLetters =
      text.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').replaceAll(' ', '');
      final hasIndianChars = RegExp(
          r'[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF'
          r'\u0B00-\u0B7F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF'
          r'\u0D00-\u0D7F\u0D80-\u0DFF]')
          .hasMatch(text);
      if (englishLetters.length > text.length * 0.6 || hasIndianChars) {
        return true;
      }
      return false;
    }
    return true;
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceDuration, _handleSilenceTimeout);
  }

  void _handleSilenceTimeout() {
    if (!_isRecording) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No voice detected'),
        content: const Text(
            'No voice detected for a while. Stop the conversation? You can start again when your meeting begins. Your meeting is saved.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _stopListening();
            },
            child: const Text('Stop'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetSilenceTimer();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _processAudioQueue() async {
    if (_isApiProcessing || _audioQueue.isEmpty) return;
    _isApiProcessing = true;
    while (_audioQueue.isNotEmpty) {
      final item = _audioQueue.removeAt(0);
      await _hitIdentifySpeaker(item.file, item.label);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _isApiProcessing = false;
  }

  Future<void> _hitIdentifySpeaker(File audioFile, int label) async {
    final prefs = await SharedPreferences.getInstance();
    final storedEmail = prefs.getString('email') ?? '';

    final base = _showTextMyLanguage
        ? ApiConstants.identifySpeakerNative
        : ApiConstants.identifySpeaker;
    Uri uri = Uri.parse('$base?email=$storedEmail&label=$label');
    void showAccountDeletedDialog() {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "accountDeleted",
        pageBuilder: (ctx, _, __) => WillPopScope(
          onWillPop: () async => false,
          child: Container(
            color: widget.isDarkMode ? Color(0xFF181A20) : Color(0xFFFCF6BA),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Material(
                  borderRadius: BorderRadius.circular(26),
                  color: widget.isDarkMode
                      ? Colors.blueGrey[900]!.withOpacity(0.98)
                      : Colors.white.withOpacity(0.97),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          color: widget.isDarkMode
                              ? Colors.cyanAccent
                              : Colors.deepPurpleAccent,
                          size: 55,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Your account has been blocked",
                          style: TextStyle(
                            color: widget.isDarkMode
                                ? Colors.cyanAccent
                                : Colors.deepPurpleAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            letterSpacing: 1.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "For security reasons, your account was blocked by admin. Please contact our support team for assistance.",
                          style: TextStyle(
                            color: widget.isDarkMode
                                ? Colors.white70
                                : Colors.blueGrey.shade700,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 26),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isDarkMode
                                ? Colors.cyanAccent.withOpacity(0.85)
                                : Colors.deepPurpleAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 38, vertical: 14),
                          ),
                          icon: Icon(
                            Icons.support_agent_rounded,
                            color: widget.isDarkMode ? Colors.black : Colors.white,
                            size: 26,
                          ),
                          label: Text(
                            "Contact Support",
                            style: TextStyle(
                                color: widget.isDarkMode
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17.3),
                          ),
                          onPressed: () {
                            context.go(Routes.login);
                          },
                        ),
                        const SizedBox(height: 15),
                        TextButton(
                            onPressed: () {
                              context.go(Routes.login);
                            },
                            child: Text(
                              "Exit App",
                              style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.cyanAccent
                                      : Colors.deepPurpleAccent,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold),
                            )
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    Future<http.StreamedResponse> sendRequest(Uri targetUri) {
      final request = http.MultipartRequest('POST', targetUri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio_file',
            audioFile.readAsBytesSync(),
            filename: audioFile.path.split('/').last,
            contentType: MediaType('audio', 'wav'),
          ),
        );
      return request.send();
    }

    try {
      http.StreamedResponse streamed = await sendRequest(uri);
      http.Response response = await http.Response.fromStream(streamed);

      if (response.statusCode == 307 || response.statusCode == 302) {
        final location = streamed.headers['location'];
        if (location != null) {
          uri = Uri.parse(location);
          streamed = await sendRequest(uri);
          response = await http.Response.fromStream(streamed);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Redirect without Location header'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }
      if (response.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        setState(() {
        });
        return;
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final speakers = body['speakers'] as List<dynamic>;

        setState(() {
          for (var speakerEntry in speakers) {
            final key = (speakerEntry as Map<String, dynamic>).keys.first;
            final data = speakerEntry[key] as Map<String, dynamic>;
            final name = data['name'] as String? ?? 'Unknown';
            final text = data['spoken_text'] as String? ?? '';
            final time = TimeOfDay.now().format(context);

            if (text.trim().isEmpty) {
              continue;
            }
            if (!_showTextMyLanguage &&
                !_isTextInLanguage(text, _appLanguageCode)) {
              continue;
            }

            _messages.add({
              'user': name,
              'text': text,
              'time': time,
              'isMe': false,
              'spoken': false,
              'audioLabel': label,
            });
            _latestSentence = text;
            _latestSentenceTimer?.cancel();
            _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
              setState(() {
                _latestSentence = '';
              });
            });
            _speakerIndex++;
          }
        });

        await _saveCurrentMeetingToFirestore();
        if (_shouldAutoscroll) _scrollToBottom(animate: true);
      } else {
        final errorBody = response.body.isNotEmpty
            ? response.body
            : 'No error message from API';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API error ${response.statusCode}: $errorBody'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to call API: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sendTextMessage() async {
    final msg = _textController.text.trim();
    if (msg.isEmpty) return;

    setState(() {
      _messages.add({
        'user': _myName,
        'text': msg,
        'time': TimeOfDay.now().format(context),
        'isMe': true,
        'spoken': false,
      });
      _textController.clear();
      _latestSentence = msg;
      _latestSentenceTimer?.cancel();
      _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
        setState(() {
          _latestSentence = '';
        });
      });
    });

    await _saveCurrentMeetingToFirestore();
    await Future.delayed(const Duration(milliseconds: 120));
    if (_speakOnMeeting) {
      await _speakMyLastMessage(msg);
    }

    if (_shouldAutoscroll) _scrollToBottom();
  }

  Future<void> _speakMyLastMessage(String msg) async {
    int lastIndex = _messages.lastIndexWhere(
            (m) => m['isMe'] == true && m['text'] == msg && m['spoken'] == false);
    if (lastIndex == -1) return;
    await _flutterTts.speak(msg);

    setState(() {
      _messages[lastIndex]['spoken'] = true;
    });
  }

  Future<void> _replaySpeak(int index) async {
    final msg = _messages[index]['text'] ?? '';
    if (msg.isNotEmpty) {
      await _flutterTts.speak(msg);
      setState(() {
        _messages[index]['spoken'] = true;
      });
    }
  }

  Future<void> _saveCurrentMeetingToFirestore() async {
    if (_savingHistory) return;
    _savingHistory = true;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final userDoc = _firestore
        .collection('meeting_histories')
        .doc('user_$email')
        .collection('meetings')
        .doc(_meetingDocId);

    await userDoc.set({
      'title': 'Group Chat',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'messages': _messages.map((m) {
        final copy = Map<String, dynamic>.from(m);
        copy.remove('color');
        return copy;
      }).toList(),
    });
    _savingHistory = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double waveSize = 90;
    final double micSize = 55;

    final gradientColors = widget.isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    final textPrimary = widget.isDarkMode ? Colors.white : Colors.black;
    final textSecondary = widget.isDarkMode ? Colors.white70 : Colors.blueGrey.shade900.withOpacity(0.6);
    final chatInputColor = widget.isDarkMode ? Colors.blueGrey.shade900.withOpacity(0.6) : Colors.white;
    final sendBtnColor = widget.isDarkMode ? Colors.cyanAccent : Colors.blueAccent;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,

        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            context.loc.messages,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 1.1,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 5,
                  offset: Offset(1, 2),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Tooltip(
            message: "Chat History",
            verticalOffset: 30,
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: widget.isDarkMode
                      ? [Colors.cyanAccent.withOpacity(0.14), Colors.blueAccent.withOpacity(0.13)]
                      : [Colors.deepPurpleAccent.withOpacity(0.11), Colors.amber.withOpacity(0.14)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isDarkMode
                        ? Colors.cyanAccent.withOpacity(0.13)
                        : Colors.deepPurpleAccent.withOpacity(0.07),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  Icons.history_edu_rounded,
                  color: widget.isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent,
                  size: 27,
                  shadows: [
                    Shadow(
                      color: widget.isDarkMode
                          ? Colors.cyanAccent.withOpacity(0.22)
                          : Colors.deepPurpleAccent.withOpacity(0.11),
                      blurRadius: 9,
                    ),
                  ],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetingHistoryScreen(
                        isDark: widget.isDarkMode,
                        userColors: _userColors,
                      ),
                    ),
                  );
                },
                splashRadius: 26,
              ),
            ),
          ),
          Tooltip(
            message: 'Language',
            verticalOffset: 30,
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: widget.isDarkMode
                      ? [Colors.cyanAccent.withOpacity(0.14), Colors.blueAccent.withOpacity(0.13)]
                      : [Colors.deepPurpleAccent.withOpacity(0.11), Colors.amber.withOpacity(0.14)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isDarkMode
                        ? Colors.cyanAccent.withOpacity(0.13)
                        : Colors.deepPurpleAccent.withOpacity(0.07),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  Icons.translate,
                  color: _showTextMyLanguage
                      ? Colors.greenAccent
                      : widget.isDarkMode
                      ? Colors.cyanAccent
                      : Colors.deepPurpleAccent,
                  size: 27,
                  shadows: [
                    Shadow(
                      color: widget.isDarkMode
                          ? Colors.cyanAccent.withOpacity(0.22)
                          : Colors.deepPurpleAccent.withOpacity(0.11),
                      blurRadius: 9,
                    ),
                  ],
                ),
                onPressed: _toggleShowTextMyLanguage,
                splashRadius: 26,
              ),
            ),
          ),
        ],
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CircleAvatar(
            backgroundColor: widget.isDarkMode
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: widget.isDarkMode ? Colors.white : Colors.black),
              onPressed: () {
                context.pop();
              },
            ),
          ),
        ),
      ),

      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _isRecording ? 12 : 8,
                        height: _isRecording ? 12 : 8,
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? Colors.redAccent
                              : widget.isDarkMode ? Colors.grey.shade800 : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          boxShadow: [
                            if (_isRecording)
                              BoxShadow(
                                color: Colors.redAccent.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 4,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecording ? context.loc.listening : context.loc.tapMicToStart,
                        style: TextStyle(
                          color: textPrimary.withOpacity(0.86),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(color: widget.isDarkMode ? Colors.black87 : Colors.black12, blurRadius: 5)
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) {
                        _handleScroll();
                        return false;
                      },
                      child: _messages.isEmpty
                          ? Center(
                        child: Text(
                          context.loc.noConversationYet,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                          : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(
                            bottom: 80, left: 16, right: 16, top: 16),
                        reverse: false,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['isMe'] ?? false;
                          final spoken = msg['spoken'] ?? false;
                          final color = isMe
                              ? (widget.isDarkMode ? Colors.blue : Colors.deepPurpleAccent)
                              : (msg['color'] ?? _userColors[index % _userColors.length]);
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 360),
                              margin: const EdgeInsets.symmetric(vertical: 7),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 15),
                              constraints: BoxConstraints(
                                maxWidth: size.width * 0.78,
                              ),
                              decoration: isMe
                                  ? BoxDecoration(
                                gradient: LinearGradient(
                                  colors: widget.isDarkMode
                                      ? [Colors.blueGrey.shade900, Colors.blueGrey.shade800]
                                      : [Color(0xFF1E88E5), Color(0xFF5AC8FA)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.isDarkMode
                                        ? Colors.black.withOpacity(0.18)
                                        : Color(0xFF1E88E5).withOpacity(0.18),
                                    blurRadius: 18,
                                    offset: const Offset(1, 4),
                                  )
                                ],
                              )
                                  : BoxDecoration(
                                color: color.withOpacity(widget.isDarkMode ? 0.21 : 0.14),
                                borderRadius: BorderRadius.circular(19),
                                border: Border.all(
                                  color: color.withOpacity(0.18),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 2,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: color,
                                        radius: 14,
                                        child: Text(
                                          (msg['user'] as String)[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        isMe
                                            ? _myName
                                            : msg['user'] as String,
                                        style: TextStyle(
                                          color: isMe
                                              ? Colors.white
                                              : color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (isMe)
                                        _speakOnMeeting
                                            ? spoken
                                            ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.23),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.volume_up_rounded,
                                                  size: 15, color: Colors.blue),
                                              const SizedBox(width: 2),
                                              const Text(
                                                'Spoken',
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              IconButton(
                                                padding: const EdgeInsets.only(left: 2, right: 2),
                                                constraints: const BoxConstraints(),
                                                tooltip: 'Speak again',
                                                icon: const Icon(Icons.replay_circle_filled,
                                                    size: 18,
                                                    color: Colors.blueAccent),
                                                onPressed: () => _replaySpeak(index),
                                              ),
                                            ],
                                          ),
                                        )
                                            : const SizedBox.shrink()
                                            : IconButton(
                                          icon: Icon(Icons.play_circle_fill_rounded,
                                              color: Colors.deepPurpleAccent, size: 26),
                                          tooltip: "Tap to play this message",
                                          onPressed: () => _replaySpeak(index),
                                        ),
                                      Text(
                                        msg['time'] as String,
                                        style: TextStyle(
                                          color: isMe
                                              ? Colors.white.withOpacity(0.88)
                                              : widget.isDarkMode
                                              ? Colors.white54
                                              : Colors.blueGrey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    msg['text'] as String,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : widget.isDarkMode
                                          ? Colors.white70
                                          : Colors.blueGrey[900],
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_latestSentence.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _latestSentence,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (_showScrollDownBtn && _messages.isNotEmpty)
                Positioned(
                  bottom: 90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        _scrollToBottom();
                        setState(() {
                          _showScrollDownBtn = false;
                          _shouldAutoscroll = true;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade800.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.19),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.arrow_downward, color: Colors.white, size: 22),
                            SizedBox(width: 6),
                            Text("New message", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: chatInputColor,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: widget.isDarkMode
                                    ? Colors.black.withOpacity(0.12)
                                    : Colors.blueGrey.withOpacity(0.11),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              Flexible(
                                child: TextField(
                                  controller: _textController,
                                  textInputAction: TextInputAction.send,
                                  minLines: 1,
                                  maxLines: 3,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 17,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: context.loc.typeAMsg,
                                    hintStyle: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white54
                                          : Colors.blueGrey,
                                      fontSize: 16,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendTextMessage(),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: _sendTextMessage,
                                child: Padding(
                                  padding: const EdgeInsets.all(5.0),
                                  child: Icon(
                                    Icons.send_rounded,
                                    size: 27,
                                    color: sendBtnColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedOpacity(
                            opacity: _isRecording ? 1.0 : 0.18,
                            duration: const Duration(milliseconds: 350),
                            child: SizedBox(
                              width: waveSize,
                              height: waveSize,
                              child: WaveBlob(
                                amplitude: _amplitude,
                                autoScale: true,
                                blobCount: 2,
                                centerCircle: true,
                                overCircle: true,
                                circleColors: widget.isDarkMode
                                    ? [Colors.cyanAccent, Colors.deepPurple]
                                    : [Color(0xFF50E3C2), Color(0xFF8E54E9)],
                                child: const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          ScaleTransition(
                            scale: _isRecording
                                ? _micGlowController
                                : const AlwaysStoppedAnimation(1.0),
                            child: GestureDetector(
                              onTap: () {
                                if (_isRecording) {
                                  _stopListening();
                                } else {
                                  _startListening();
                                  _micGlowController.forward(from: 0.97);
                                }
                              },
                              child: Container(
                                width: micSize,
                                height: micSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: _isRecording
                                        ? [
                                      Colors.red,
                                      Colors.deepOrange,
                                    ]
                                        : widget.isDarkMode
                                        ? [Colors.deepPurple, Colors.cyanAccent]
                                        : [Color(0xFF8E54E9), Color(0xFF50E3C2)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isRecording
                                          ? Colors.cyanAccent.withOpacity(0.18)
                                          : widget.isDarkMode
                                          ? Colors.cyanAccent.withOpacity(0.12)
                                          : Colors.deepPurpleAccent.withOpacity(0.07),
                                      blurRadius: 18,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isRecording
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioQueueItem {
  final File file;
  final int label;
  _AudioQueueItem({required this.file, required this.label});
}

class MeetingHistoryScreen extends StatelessWidget {
  final bool isDark;
  final List<Color> userColors;
  const MeetingHistoryScreen({Key? key, required this.isDark, required this.userColors}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final bgColors = isDark
        ? [const Color(0xFF232526), const Color(0xFF181A20), const Color(0xFF232526)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(
            color: isDark ? Colors.cyanAccent : Colors.deepPurpleAccent),
        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: isDark
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
          ).createShader(rect),
          child: Text(
            context.loc.chatHistory,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 1.2,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 6,
                  offset: const Offset(1, 2),
                ),
              ],
            ),
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CircleAvatar(
            backgroundColor: isDark
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
              onPressed: () {
                context.pop();
              },
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bgColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (!isDark)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FutureBuilder<SharedPreferences>(
                future: SharedPreferences.getInstance(),
                builder: (context, prefsSnapshot) {
                  if (!prefsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final email = prefsSnapshot.data!.getString('email') ?? '';
                  final meetingsRef = firestore
                      .collection('meeting_histories')
                      .doc('user_$email')
                      .collection('meetings')
                      .orderBy('timestamp', descending: true);

                  return StreamBuilder<QuerySnapshot>(
                    stream: meetingsRef.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.forum_rounded, color: isDark ? Colors.cyanAccent : Colors.deepPurpleAccent, size: 66),
                              const SizedBox(height: 10),
                              ShaderMask(
                                shaderCallback: (rect) => LinearGradient(
                                  colors: isDark
                                      ? [Colors.cyanAccent, Colors.white]
                                      : [Colors.deepPurple, Colors.amber],
                                ).createShader(rect),
                                child: Text(
                                  "No meetings yet.\nLet's talk!",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      letterSpacing: 0.3),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                        itemBuilder: (_, i) {
                          final data = docs[i].data() as Map<String, dynamic>;
                          final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
                          final dt = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0);

                          return AnimatedContainer(
                            duration: Duration(milliseconds: 320 + (i * 25)),
                            curve: Curves.easeInOut,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Card(
                                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.83),
                                  elevation: 8,
                                  shadowColor: isDark ? Colors.cyanAccent.withOpacity(0.11) : Colors.amber.withOpacity(0.13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        width: 1.5,
                                        color: isDark
                                            ? Colors.cyanAccent.withOpacity(0.12)
                                            : Colors.deepPurpleAccent.withOpacity(0.09),
                                      )
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                      splashColor: Colors.amber.withOpacity(0.09),
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: i == 0,
                                      collapsedBackgroundColor: Colors.transparent,
                                      backgroundColor: Colors.transparent,
                                      title: ShaderMask(
                                        shaderCallback: (rect) => LinearGradient(
                                          colors: isDark
                                              ? [Colors.cyanAccent, Colors.white]
                                              : [Colors.deepPurple, Colors.indigo, Colors.amber],
                                        ).createShader(rect),
                                        child: Text(
                                          data['title'] ?? context.loc.groupChat,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            letterSpacing: 0.6,
                                            shadows: [
                                              Shadow(
                                                  color: isDark ? Colors.cyanAccent.withOpacity(0.16) : Colors.deepPurpleAccent.withOpacity(0.15),
                                                  blurRadius: 7,
                                                  offset: Offset(1, 2)
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 16, color: isDark ? Colors.white60 : Colors.blueGrey),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} @ "
                                                "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                                            style: TextStyle(
                                              color: isDark ? Colors.white60 : Colors.blueGrey,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 13, left: 12, right: 12, top: 3),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 3),
                                                child: ShaderMask(
                                                  shaderCallback: (rect) => LinearGradient(
                                                    colors: isDark
                                                        ? [Colors.cyanAccent, Colors.white]
                                                        : [Colors.deepPurple, Colors.amber],
                                                  ).createShader(rect),
                                                  child: Text(
                                                    context.loc.conversation,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15.8,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              ...messages.asMap().entries.map((entry) {
                                                final msg = entry.value;
                                                final isMe = msg['isMe'] ?? false;
                                                final color = isMe
                                                    ? (isDark ? Colors.cyanAccent : Colors.deepPurpleAccent)
                                                    : userColors[entry.key % userColors.length];
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              color.withOpacity(0.82),
                                                              color.withOpacity(0.66)
                                                            ],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          ),
                                                          borderRadius: BorderRadius.circular(50),
                                                        ),
                                                        child: CircleAvatar(
                                                          backgroundColor: Colors.transparent,
                                                          radius: 16,
                                                          child: Text(
                                                            (msg['user'] as String?)?.isNotEmpty == true
                                                                ? (msg['user'] as String)[0].toUpperCase()
                                                                : "?",
                                                            style: const TextStyle(
                                                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: AnimatedContainer(
                                                          duration: const Duration(milliseconds: 340),
                                                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 13),
                                                          decoration: BoxDecoration(
                                                            color: color.withOpacity(isMe ? 0.19 : 0.16),
                                                            borderRadius: BorderRadius.circular(15),
                                                            border: Border.all(
                                                              color: color.withOpacity(0.22),
                                                              width: 1.1,
                                                            ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: color.withOpacity(0.08),
                                                                blurRadius: 8,
                                                                offset: Offset(0, 3),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Text(
                                                                    msg['user'] ?? '',
                                                                    style: TextStyle(
                                                                      fontWeight: FontWeight.bold,
                                                                      color: color,
                                                                      fontSize: 14.5,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 6),
                                                                  if (isMe)
                                                                    Container(
                                                                      decoration: BoxDecoration(
                                                                        color: Colors.amber.withOpacity(0.12),
                                                                        borderRadius: BorderRadius.circular(9),
                                                                      ),
                                                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                      child: Row(
                                                                        children: [
                                                                          Icon(Icons.verified, size: 14, color: Colors.amber),
                                                                          SizedBox(width: 2),
                                                                          Text("You", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w700, fontSize: 11)),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 3),
                                                              Text(
                                                                msg['text'] ?? '',
                                                                style: TextStyle(
                                                                  color: isDark ? Colors.white.withOpacity(0.92) : Colors.black87,
                                                                  fontSize: 15.1,
                                                                  height: 1.26,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 4),
                                                              Align(
                                                                alignment: Alignment.bottomRight,
                                                                child: Text(
                                                                  msg['time'] ?? '',
                                                                  style: TextStyle(
                                                                    color: isDark ? Colors.white54 : Colors.blueGrey,
                                                                    fontSize: 12,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
