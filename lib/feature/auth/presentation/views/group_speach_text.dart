import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wave_blob/wave_blob.dart';

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
  State<GroupSpeechToTextScreen> createState() =>
      _GroupSpeechToTextScreenState();
}

class _GroupSpeechToTextScreenState extends State<GroupSpeechToTextScreen>
    with TickerProviderStateMixin {
  // ===================== CONFIG =====================
  static const String _elevenLabsApiKey =
      ApiConstants.elevenLabsApiKey; // <-- set your key
  static const Duration _chunkDuration = Duration(seconds: 5);
  static const int _minChunkBytes = 10 * 1024; // skip tiny/silent chunks

  // ===================== UI / STATE =====================
  bool _isRecording = false;
  double _amplitude = 0;
  Timer? _amplitudeTimer;
  late AnimationController _micGlowController;

  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  String _myName = '';
  Color _myColor = const Color(0xFF1E88E5);

  final FlutterTts _flutterTts = FlutterTts();

  String _appLanguageCode = 'en';
  bool _speakOnMeeting = true; // used only when sending typed messages
  bool _showTextMyLanguage = false; // kept for UI toggle (typed text only)

  late final ScrollController _scrollController;
  bool _showScrollDownBtn = false;
  bool _shouldAutoscroll = true;

  late final FirebaseFirestore _firestore;
  late String _meetingDocId;
  bool _savingHistory = false;

  String _latestSentence = '';
  Timer? _latestSentenceTimer;

  // ===================== AUDIO REC/CHUNKING =====================
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _chunkTimer;
  String? _currentFilePath;

  // ===================== INIT =====================
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

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _latestSentenceTimer?.cancel();
    _chunkTimer?.cancel();

    _micGlowController.dispose();
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ===================== PREFS & USER =====================
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
        _messages.addAll(
            List<Map<String, dynamic>>.from(data['messages'] ?? []));
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

  // ===================== AMPLITUDE ANIM =====================
  void _startAmplitude() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!_isRecording) return;
      setState(() {
        // simple visual animation (not actual mic level)
        _amplitude = 2200 + Random().nextInt(3400).toDouble();
      });
    });
  }

  void _stopAmplitude() {
    _amplitudeTimer?.cancel();
    setState(() => _amplitude = 0);
  }

  // ===================== RECORDING (5s CHUNKS) =====================
  String _newTempWavPath() =>
      "${Directory.systemTemp.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav";

  Future<void> _startListening() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission denied.")),
      );
      return;
    }

    _currentFilePath = _newTempWavPath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1,
      ),
      path: _currentFilePath!,
    );

    _startAmplitude();
    _chunkTimer?.cancel();
    _chunkTimer =
        Timer.periodic(_chunkDuration, (_) => _sliceAndSendChunk());

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopListening() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;

    final lastPath = await _recorder.stop();
    _stopAmplitude();
    setState(() {
      _isRecording = false;
    });

    if (lastPath != null) {
      final file = File(lastPath);
      if (_shouldSendChunk(file)) {
        unawaited(_transcribeAuto(file));
      } else {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _sliceAndSendChunk() async {
    if (!_isRecording) return;

    String? finished;
    try {
      finished = await _recorder.stop();
    } catch (_) {}

    try {
      _currentFilePath = _newTempWavPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: _currentFilePath!,
      );
    } catch (e) {
      _stopAmplitude();
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Recorder error: $e")),
      );
      return;
    }

    if (finished != null) {
      final file = File(finished);
      if (_shouldSendChunk(file)) {
        unawaited(_transcribeAuto(file));
      } else {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  bool _shouldSendChunk(File f) {
    try {
      final len = f.lengthSync();
      return len >= _minChunkBytes;
    } catch (_) {
      return false;
    }
  }

  // ===================== STT (AUTO-DETECT ONLY) =====================
  Future<void> _transcribeAuto(File file) async {
    try {
      final data = await _stt(file); // auto detect; no language_code param
      if (data != null) {
        final text = (data['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          final code = _code3ToLang((data['language_code'] ?? '').toString());
          _addTranscriptLine(text, lang: code);

          // Log potential noise without dropping the transcript
          if (!_isLikelySpeech(text, data)) {
            debugPrint("Filtered as noise: $text");
          }
        } else {
          debugPrint("STT returned empty text.");
        }
      } else {
        debugPrint("STT failed for a chunk.");
      }
    } catch (e) {
      debugPrint("STT exception: $e");
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _stt(File file) async {
    final uri = Uri.parse("https://api.elevenlabs.io/v1/speech-to-text");

    final req = http.MultipartRequest("POST", uri)
      ..headers['xi-api-key'] = _elevenLabsApiKey
      ..fields['model_id'] = 'scribe_v1'
      ..files.add(await http.MultipartFile.fromPath("file", file.path));

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final body = utf8.decode(res.bodyBytes);

    debugPrint("STT auto → ${res.statusCode}");
    if (res.statusCode == 200) {
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint("JSON parse error: $e");
        return null;
      }
    } else {
      debugPrint("STT error ${res.statusCode}: $body");
      return null;
    }
  }

  // ===================== HEURISTICS (no translation, stricter noise filter) =====================
  bool _hasIndicScript(String t) {
    return RegExp(
      r'[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF\u0B00-\u0B7F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]',
    ).hasMatch(t);
  }

  bool _hasArabicScript(String t) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(t);
  }

  bool _isEnvironmentNoiseText(String t) {
    final text = t.toLowerCase().trim();

    // environmental keywords (EN + Hindi)
    const env = [
      'wind', 'blowing', 'gust', 'breeze', 'fan', 'ac', 'air conditioner',
      'ac noise', 'hum', 'static', 'mic noise', 'traffic', 'car horn',
      'horn', 'horns', 'sirens', 'rain', 'raindrops', 'thunder',
      'storm', 'thunderstorm', 'waves', 'ocean', 'sea', 'water',
      'waterfall', 'river', 'stream', 'running water', 'keyboard', 'typing',
      'footsteps', 'door closing', 'door slam', 'background music', 'music',
      'applause', 'clapping', 'crowd', 'crowded', 'noise', 'ambient', 'echo',
      // Hindi
      'हवा', 'तेज हवा', 'फैन', 'पंखा', 'एसी', 'ए सी', 'शोर', 'आवाज़', 'शोरगुल',
      'बारिश', 'बूंदें', 'तूफान', 'गर्जना', 'लहर', 'लहरें', 'समुद्र', 'पानी',
      'नदी', 'जलप्रपात', 'कीबोर्ड', 'टाइपिंग', 'कदमों', 'दरवाज़ा', 'दरवाजा',
      'तालियाँ', 'तालियां', 'क्लैप', 'भीड़', 'संगीत', 'हॉर्न', 'हॉर्न्स', 'सायरन'
    ];

    // clearly speechy keywords — if present, don't treat as noise
    const speechy = [
      // English
      'i', 'we', 'you', 'he', 'she', 'they', 'my', 'your', 'our', 'me', 'us',
      'is', 'are', 'am', 'have', 'do', 'say', 'want', 'need', 'please', 'hello', 'hi', 'name',
      // Hindi
      'मैं', 'मुझे', 'मेरा', 'आप', 'तुम', 'हम', 'हैं', 'हूँ', 'है', 'कर', 'रहा', 'रही',
      'चाहता', 'चाहती', 'कहना', 'कह', 'नाम', 'कृपया', 'नमस्ते', 'हैलो'
    ];

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final hasEnv = env.any((k) => text.contains(k));
    final hasSpeechy = speechy.any((k) => text.contains(k));

    // if it mentions environment and lacks speech markers and is short, drop
    if (hasEnv && !hasSpeechy && words.length <= 12) return true;

    return false;
  }

  String _code3ToLang(String code3) {
    switch (code3) {
      case 'eng':
        return 'en';
      case 'hin':
        return 'hi';
      case 'tam':
        return 'ta';
      case 'tel':
        return 'te';
      case 'ben':
        return 'bn';
      case 'mar':
        return 'mr';
      case 'kan':
        return 'kn';
      case 'guj':
        return 'gu';
      case 'mal':
        return 'ml';
      case 'urd':
        return 'ur';
      default:
        return code3;
    }
  }

  bool _isLikelySpeech(String text, Map<String, dynamic> data) {
    final t = text.trim();
    if (t.isEmpty) return false;

    // filter obvious environment lines
    if (_isEnvironmentNoiseText(t)) return false;

    // minimum substance
    if (t.length < 4) return false;

    // letters share
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(t).length;
    final lettersRatio = letters / max(1, t.length);
    if (lettersRatio < 0.45) return false;

    // punctuation density
    final punct = RegExp(r'[^\p{L}\p{N}\s]', unicode: true).allMatches(t).length;
    final punctRatio = punct / max(1, t.length);
    if (punctRatio > 0.35) return false;

    // at least 2 words or >= 10 chars
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 && t.length < 10) return false;

    // filler-only
    final fillers = {'uh', 'umm', 'um', 'hmm', 'huh', 'ah', 'oh', 'hmmm', 'अं', 'हूं'};
    if (words.length <= 2 &&
        words.every((w) => fillers.contains(w.toLowerCase()))) {
      return false;
    }

    // repetition
    final norm = t.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final counts = <String, int>{};
    for (final ch in norm.split('')) {
      counts[ch] = (counts[ch] ?? 0) + 1;
    }
    if (norm.isNotEmpty) {
      final maxRepeat = counts.values.reduce((a, b) => a > b ? a : b);
      if ((maxRepeat / norm.length) > 0.6) return false;
    }

    // language probability (auto)
    final prob = (data['language_probability'] is num)
        ? (data['language_probability'] as num).toDouble()
        : null;

    final hasIndic = _hasIndicScript(t);
    final hasArabic = _hasArabicScript(t);

    // Be friendly for non-English scripts and allow shorter phrases
    if (hasIndic || hasArabic) {
      // Lower probability threshold to reduce false negatives for Indic/Arabic text
      if (prob == null || prob >= 0.30) {
        if (words.length >= 2 || t.length >= 8) return true;
      }
    }

    // General accept if probability high enough
    if (prob != null && prob >= 0.70) return true;

    // As a last resort, accept longer lines that look like sentences
    if (t.length >= 18 && lettersRatio >= 0.6) return true;

    return false;
  }

  // ===================== APPENDING TRANSCRIPTS =====================
  void _addTranscriptLine(String text, {required String lang}) async {
    final line = text.trim();
    if (line.isEmpty) return;

    setState(() {
      _messages.add({
        'user': 'Mic',
        'text': line,
        'time': TimeOfDay.now().format(context),
        'isMe': false,
        'spoken': false,
      });
      _latestSentence = line;
    });

    _latestSentenceTimer?.cancel();
    _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _latestSentence = '');
    });

    await _saveCurrentMeetingToFirestore();
    if (_shouldAutoscroll) _scrollToBottom(animate: true);
  }

  // ===================== SENDING TYPED MESSAGE (optional TTS) =====================
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
    });

    _latestSentenceTimer?.cancel();
    _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _latestSentence = '');
    });

    await _saveCurrentMeetingToFirestore();
    await Future.delayed(const Duration(milliseconds: 120));
    if (_speakOnMeeting) {
      await _speakMyLastMessage(msg);
    }

    if (_shouldAutoscroll) _scrollToBottom();
  }

  Future<void> _speakMyLastMessage(String msg) async {
    final lastIndex = _messages.lastIndexWhere(
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

  // ===================== SAVE HISTORY =====================
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

  // ===================== UI HELPERS =====================
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: animate
              ? const Duration(milliseconds: 350)
              : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

  // kept for language toggle on typed text (STT always shows original language)
  bool _isTextInLanguage(String text, String languageCode) {
    if (languageCode == 'en') {
      final englishLetters =
      text.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').replaceAll(' ', '');
      final hasIndianChars = RegExp(
        r'[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF'
        r'\u0B00-\u0B7F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF'
        r'\u0D00-\u0D7F\u0D80-\u0DFF]',
      ).hasMatch(text);
      if (englishLetters.length > text.length * 0.6 || hasIndianChars) {
        return true;
      }
      return false;
    }
    return true;
  }

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double waveSize = 90;
    const double micSize = 55;

    final gradientColors = widget.isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    final textPrimary =
    widget.isDarkMode ? Colors.white : Colors.black;
    final textSecondary = widget.isDarkMode
        ? Colors.white70
        : Colors.blueGrey.shade900.withOpacity(0.6);
    final chatInputColor = widget.isDarkMode
        ? Colors.blueGrey.shade900.withOpacity(0.6)
        : Colors.white;
    final sendBtnColor =
    widget.isDarkMode ? Colors.cyanAccent : Colors.blueAccent;

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
                    offset: const Offset(0, 3),
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
                    offset: const Offset(0, 3),
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
                              : _myColor;
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
                                          (msg['user'] as String).isNotEmpty
                                              ? (msg['user'] as String)[0].toUpperCase()
                                              : "?",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        isMe ? _myName : (msg['user'] as String),
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
                                          icon: const Icon(Icons.play_circle_fill_rounded,
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                        ? [Colors.red, Colors.deepOrange]
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
                                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
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

  // small helper to ignore unawaited futures
  void unawaited(Future<void> f) {}
}

class MeetingHistoryScreen extends StatelessWidget {
  final bool isDark;
  const MeetingHistoryScreen({Key? key, required this.isDark}) : super(key: key);

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
                                child: const Text(
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
                                                  offset: const Offset(1, 2)
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
                                                    style: const TextStyle(
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
                                                    : Colors.blueGrey;
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
                                                                offset: const Offset(0, 3),
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
                                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                      child: const Row(
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
