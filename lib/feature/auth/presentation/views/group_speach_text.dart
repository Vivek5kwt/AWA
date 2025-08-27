import 'dart:async';
import 'dart:ui';

import 'package:awa/config/local_extension.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
// ADDED: sequential speaker-ID helpers (no parallel mic usage)
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wave_blob/wave_blob.dart';

import '../../../../core/speaker/speaker_service.dart';

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
  bool _isRecording = false;
  double _amplitude = 0;
  late AnimationController _micGlowController;
  final SpeechToText _speech = SpeechToText();

  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  String _myName = '';
  Color _myColor = const Color(0xFF1E88E5);

  final FlutterTts _flutterTts = FlutterTts();

  String _appLanguageCode = 'en';

  bool _speakOnMeeting = true;
  bool _showTextMyLanguage = false;

  late final ScrollController _scrollController;
  bool _showScrollDownBtn = false;
  bool _shouldAutoscroll = true;

  late final FirebaseFirestore _firestore;
  late String _meetingDocId;
  bool _savingHistory = false;

  // Live partial message index; -1 when none
  int _liveMsgIndex = -1;

  // ====== Speaker-ID (sequential) ======
  final AudioRecorder _segRec = AudioRecorder();
  final SpeakerService _spkSvc = SpeakerService();
  bool _idBusy = false;
  bool _identifyingNow = false;
  String _currentSpeaker = '';
  double _currentScore = 0.0;

  // Gate to ensure STT fully stopped before we grab the mic
  Completer<void>? _sttFullyStopped;

  // Prevent overlapping short recordings
  bool _segRecording = false;

  // Guard for async callbacks after dispose
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _micGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.97,
      upperBound: 1.13,
    )..repeat(reverse: true);

    _speech.initialize(onStatus: _onSpeechStatus, onError: _onSpeechError);

    _initUser();
    _loadSpeakOnMeeting();
    _loadShowTextMyLanguage();
    _loadAppLanguageCode();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);

    _firestore = FirebaseFirestore.instance;
    _meetingDocId = "meeting_${DateTime.now().millisecondsSinceEpoch}";
    _loadPreviousMessages();

    _initSpeakerSvc();
  }

  Future<void> _initSpeakerSvc() async {
    await _spkSvc.init();
  }

  Future<void> _loadPreviousMessages() async {
    if (_isDisposed || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final doc = await _firestore
        .collection('meeting_histories')
        .doc('user_$email')
        .collection('meetings')
        .doc(_meetingDocId)
        .get();
    if (!mounted || _isDisposed) return;
    if (doc.exists) {
      final data = doc.data()!;
      if (!mounted || _isDisposed) return;
      setState(() {
        _messages.clear();
        _messages
            .addAll(List<Map<String, dynamic>>.from(data['messages'] ?? []));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _scrollToBottom();
      });
    }
  }

  void _handleScroll() {
    if (!mounted || _isDisposed) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 50;
    if (atBottom && _showScrollDownBtn) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _showScrollDownBtn = false;
        _shouldAutoscroll = true;
      });
    } else if (!atBottom && !_showScrollDownBtn) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _showScrollDownBtn = true;
        _shouldAutoscroll = false;
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Stop STT / TTS safely
    try {
      if (_speech.isListening) {
        _speech.stop();
      }
    } catch (_) {}
    _sttFullyStopped = null;

    _micGlowController.dispose();
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    _segRec.dispose();
    super.dispose();
  }

  Future<void> _loadSpeakOnMeeting() async {
    if (_isDisposed || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _isDisposed) return;
    setState(() {
      _speakOnMeeting = prefs.getBool('speakOnMeeting') ?? true;
    });
  }

  Future<void> _loadShowTextMyLanguage() async {
    if (_isDisposed || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _isDisposed) return;
    setState(() {
      _showTextMyLanguage = prefs.getBool('useNativeApi') ?? false;
    });
  }

  Future<void> _toggleShowTextMyLanguage() async {
    if (_isDisposed) return;
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_showTextMyLanguage;
    await prefs.setBool('useNativeApi', newVal);
    if (!mounted || _isDisposed) return;
    setState(() => _showTextMyLanguage = newVal);
  }

  Future<void> _loadAppLanguageCode() async {
    if (_isDisposed || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language_code');
    if (!mounted || _isDisposed) return;
    setState(() {
      _appLanguageCode = code ?? Localizations.localeOf(context).languageCode;
    });
    await _initTTS();
  }

  Future<void> _initTTS() async {
    if (_isDisposed) return;
    final ttsLocale =
        _localeIdForLanguage(_appLanguageCode).replaceAll('_', '-');
    await _flutterTts.setLanguage(ttsLocale);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.32);
    await _flutterTts.setVolume(1.0);
  }

  Future<void> _initUser() async {
    if (_isDisposed || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'Me';
    final name = prefs.getString('name') ?? email.split('@')[0];
    if (!mounted || _isDisposed) return;
    setState(() {
      _myName = _capitalize(name);
      _myColor = const Color(0xFF1E88E5);
    });
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _localeIdForLanguage(String code) {
    switch (code) {
      case 'en':
        return 'en_IN';
      case 'hi':
        return 'hi_IN';
      case 'pa':
        return 'pa_IN';
      case 'gu':
        return 'gu_IN';
      case 'ta':
        return 'ta_IN';
      case 'mr':
        return 'mr_IN';
      case 'bn':
        return 'bn_IN';
      case 'ur':
        return 'ur_IN';
      default:
        return 'en_IN';
    }
  }

  // Pick a supported STT locale
  Future<String?> _chooseSupportedLocale(String preferred) async {
    try {
      final locales = await _speech.locales();
      if (locales.isEmpty) return null;
      final exact = locales.firstWhere(
        (l) => l.localeId == preferred,
        orElse: () => locales.first,
      );
      if (exact.localeId == preferred) return preferred;
      final lang = preferred.split('_').first;
      final byLang = locales.firstWhere(
        (l) => l.localeId.startsWith(lang),
        orElse: () => locales.first,
      );
      return byLang.localeId;
    } catch (_) {
      return null;
    }
  }

  int get _usersInMeetingCount {
    final users = <String>{_myName};
    for (var m in _messages) {
      final user = m['user'];
      if (user is String) users.add(user);
    }
    return users.length;
  }

  void _onSpeechStatus(String status) {
    if (_isDisposed) return;

    if (status == 'notListening' || status == 'done') {
      if (_sttFullyStopped != null && !_sttFullyStopped!.isCompleted) {
        _sttFullyStopped!.complete();
      }
      if (!_isDisposed && mounted && _isRecording && !_identifyingNow) {
        _startListening();
      }
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _isRecording = false;
      _amplitude = 0;
    });
    _toast(
        'Speech error: ${error.errorMsg} (${error.permanent ? "permanent" : "recoverable"})');
  }

  Future<void> _startListening() async {
    if (_isDisposed) return;
    if (_identifyingNow) return;
    if (_speech.isListening) return;

    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
      debugLogging: false,
    );
    if (_isDisposed) return;
    if (!available) {
      _toast('Speech recognition not available on this device.');
      return;
    }

    final preferred = _localeIdForLanguage(_appLanguageCode);
    final chosenLocale = await _chooseSupportedLocale(preferred) ?? preferred;
    if (_isDisposed) return;

    if (mounted && !_isDisposed) {
      setState(() {
        _isRecording = true;
      });
    }

    _speech.listen(
      onResult: _onSpeechResult,
      listenMode: ListenMode.dictation,
      localeId: chosenLocale,
      partialResults: true,
      listenFor: const Duration(hours: 1),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: false,
      onSoundLevelChange: (level) {
        if (!mounted || _isDisposed) return;
        setState(() {
          _amplitude = level * 1000;
        });
      },
    );
  }

  Future<void> _stopListening() async {
    if (_isDisposed) return;

    _sttFullyStopped = Completer<void>();

    try {
      await _speech.stop();
    } catch (_) {}

    if (mounted && !_isDisposed) {
      setState(() {
        _amplitude = 0;
      });
    }

    try {
      await _sttFullyStopped!.future.timeout(const Duration(milliseconds: 800));
    } catch (_) {}
    _sttFullyStopped = null;

    await Future.delayed(const Duration(milliseconds: 120));
  }

  Future<String?> _recordShortSegment({int milliseconds = 1200}) async {
    if (_isDisposed) return null;
    if (_segRecording) return null;
    _segRecording = true;
    try {
      final ok = await _segRec.hasPermission();
      if (!ok) {
        _toast('Microphone permission denied.');
        return null;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/stt_seg_${DateTime.now().millisecondsSinceEpoch}.wav';

      const cfg = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      );

      await _segRec.start(cfg, path: path);
      await Future.delayed(Duration(milliseconds: milliseconds));
      final saved = await _segRec.stop();
      if (saved == null) {
        _toast('No audio captured for speaker ID.');
      }
      return saved;
    } catch (e) {
      _toast('Record error: $e');
      return null;
    } finally {
      _segRecording = false;
    }
  }

  // Ensure there is a live (draft) message to update
  void _ensureLiveMessage() {
    if (_isDisposed) return;
    if (_liveMsgIndex >= 0 &&
        _liveMsgIndex < _messages.length &&
        _messages[_liveMsgIndex]['final'] == false) {
      return;
    }
    _messages.add({
      'user': 'Speaking…', // placeholder until ID
      'text': '',
      'time': TimeOfDay.now().format(context),
      'isMe': false,
      'spoken': false,
      'final': false, // mark as live
      // diarization candidates for this message:
      'cands': <Map<String, dynamic>>[],
    });
    _liveMsgIndex = _messages.length - 1;
  }

  // Helpers: normalize a candidate list for UI (≥ 20%)
  List<Map<String, dynamic>> _filterUiCandidates(
      List<Map<String, dynamic>> raw) {
    final out = <Map<String, dynamic>>[];
    for (final m in raw) {
      final name = (m['name'] ?? '').toString();
      final score = (m['score'] is num)
          ? (m['score'] as num).toDouble().clamp(0.0, 1.0)
          : 0.0;
      if (name.isNotEmpty && score >= 0.20) {
        out.add({'name': name, 'score': score});
      }
    }
    out.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return out;
  }

  // Finalize the live message text and run ID
  Future<void> _finalizeLiveMessage(String finalText) async {
    if (_isDisposed) return;
    if (_liveMsgIndex < 0 || _liveMsgIndex >= _messages.length) return;

    // Mark text final first
    if (mounted && !_isDisposed) {
      setState(() {
        _messages[_liveMsgIndex]['text'] = finalText;
        _messages[_liveMsgIndex]['final'] = true;
      });
    }

    // === Sequential speaker ID ===
    _idBusy = true;
    if (mounted && !_isDisposed) {
      setState(() {
        _identifyingNow = true;
      });
    }

    // Pause STT and capture a small ID clip
    await _stopListening();
    await _flutterTts.stop();

    String? bestName;
    double bestScore = 0.0;
    final allCands = <Map<String, dynamic>>[];

    try {
      final segPath = await _recordShortSegment(milliseconds: 1200);
      if (segPath != null && !_isDisposed) {
        // Try detailed API with scores first
        bool usedRich = false;
        try {
          final dynamic svc = _spkSvc;
          final dynamic res = await svc.identifyScores(
            segPath,
            topK: 5,
            includeBelowThreshold: true,
          );

          if (res is List && res.isNotEmpty) {
            usedRich = true;
            print('--- Speaker candidates ---');
            debugPrint('--- Speaker candidates ---');
            for (final c in res) {
              final name =
                  (c['id'] ?? c['name'] ?? c['speaker'] ?? c['label'] ?? '')
                      .toString();
              final scoreNum = c['score'] ??
                  c['confidence'] ??
                  c['prob'] ??
                  c['similarity'] ??
                  0.0;
              final score =
                  (scoreNum is num) ? scoreNum.toDouble().clamp(0.0, 1.0) : 0.0;
              print('  $name : ${(score * 100).toStringAsFixed(1)}%');
              debugPrint('  $name : ${(score * 100).toStringAsFixed(1)}%');
              allCands.add({'name': name, 'score': score});
            }
            final top = res.first;
            bestName = (top['id'] ??
                    top['name'] ??
                    top['speaker'] ??
                    top['label'] ??
                    '')
                .toString();
            final sc = top['score'] ??
                top['confidence'] ??
                top['prob'] ??
                top['similarity'] ??
                0.0;
            bestScore = (sc is num) ? sc.toDouble().clamp(0.0, 1.0) : 0.0;
            print(
                'Best match = $bestName @ ${(bestScore * 100).toStringAsFixed(1)}%');
            debugPrint(
                'Best match = $bestName @ ${(bestScore * 100).toStringAsFixed(1)}%');
          }
        } catch (_) {}

        if (!usedRich) {
          // Fallback to simple API
          final n = await _spkSvc.identify(
            segPath,
            threshold: 0.74,
            secondBestMargin: 0.035,
            displayThreshold: 0.40,
          );
          if (n != null) {
            bestName = n;
            bestScore = 1.0;
            allCands.add({'name': n, 'score': 1.0});
          }
          print(
              'Best match (fallback) = ${bestName ?? "null"} @ ${(bestScore * 100).toStringAsFixed(1)}%');
          debugPrint(
              'Best match (fallback) = ${bestName ?? "null"} @ ${(bestScore * 100).toStringAsFixed(1)}%');
        }
      }
    } catch (e) {
      _toast('Identify error: $e');
    }

    if (_isDisposed) return;

    // Only show a name if score >= 20%
    final showName = (bestName ?? '').isNotEmpty && bestScore >= 0.20;
    final detectedName = showName ? bestName! : 'Anonymous';
    final isMe = detectedName == _myName;

    // candidates (≥20%) for UI
    final candsForUi = _filterUiCandidates(allCands);

    if (mounted && !_isDisposed) {
      setState(() {
        _messages[_liveMsgIndex]['user'] = detectedName;
        _messages[_liveMsgIndex]['isMe'] = isMe;
        _messages[_liveMsgIndex]['cands'] = candsForUi;
        _currentSpeaker = showName ? detectedName : '';
        _currentScore = bestScore;
      });
    }

    // Persist
    unawaited(_saveCurrentMeetingToFirestore());

    // Speak my message if needed
    if (_speakOnMeeting && isMe && !_isDisposed) {
      await _speakMyLastMessage(finalText);
    }

    // Prepare for next live
    _liveMsgIndex = -1;

    if (mounted && !_isDisposed) {
      setState(() {
        _identifyingNow = false;
      });
    }
    _idBusy = false;

    // Resume STT (only if still on screen)
    if (mounted && !_isDisposed) _startListening();
  }

  void _onSpeechResult(SpeechRecognitionResult result) async {
    if (_isDisposed) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    // 1) Stream partials into a live bubble
    _ensureLiveMessage();
    if (mounted && !_isDisposed) {
      setState(() {
        _messages[_liveMsgIndex]['text'] = text;
        _messages[_liveMsgIndex]['time'] = TimeOfDay.now().format(context);
      });
    }
    if (_shouldAutoscroll) _scrollToBottom(animate: true);

    // 2) If final, lock text, run ID, then resume
    if (result.finalResult) {
      await _finalizeLiveMessage(text);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendTextMessage() async {
    if (_isDisposed) return;
    final msg = _textController.text.trim();
    if (msg.isEmpty) return;

    if (mounted && !_isDisposed) {
      setState(() {
        _messages.add({
          'user': _myName,
          'text': msg,
          'time': TimeOfDay.now().format(context),
          'isMe': true,
          'spoken': false,
          'final': true,
          'cands': <Map<String, dynamic>>[],
        });
        _textController.clear();
      });
    }
    unawaited(_saveCurrentMeetingToFirestore());
    if (_speakOnMeeting && !_isDisposed) {
      await _speakMyLastMessage(msg);
    }

    if (_shouldAutoscroll) _scrollToBottom();
  }

  Future<void> _speakMyLastMessage(String msg) async {
    if (_isDisposed) return;
    int lastIndex = _messages.lastIndexWhere((m) =>
        m['isMe'] == true &&
        m['text'] == msg &&
        (m['spoken'] == false || m['spoken'] == null));
    if (lastIndex == -1) return;
    await _flutterTts.speak(msg);

    if (!mounted || _isDisposed) return;
    setState(() {
      _messages[lastIndex]['spoken'] = true;
    });
  }

  Future<void> _saveCurrentMeetingToFirestore() async {
    if (_isDisposed) return;
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

  void _toast(String msg) {
    if (!mounted || _isDisposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double waveSize = 90;
    final double micSize = 55;

    final gradientColors = widget.isDarkMode
        ? [
            const Color(0xFF181A20),
            const Color(0xFF232526),
            const Color(0xFF181A20)
          ]
        : [
            const Color(0xFF0093E9),
            const Color(0xFF80D0C7),
            const Color(0xFFFCF6BA)
          ];

    final textPrimary = widget.isDarkMode ? Colors.white : Colors.black;
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
                      ? [
                          Colors.cyanAccent.withOpacity(0.14),
                          Colors.blueAccent.withOpacity(0.13)
                        ]
                      : [
                          Colors.deepPurpleAccent.withOpacity(0.11),
                          Colors.amber.withOpacity(0.14)
                        ],
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
                  color: widget.isDarkMode
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
                onPressed: () {
                  if (_isDisposed) return;
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
                      ? [
                          Colors.cyanAccent.withOpacity(0.14),
                          Colors.blueAccent.withOpacity(0.13)
                        ]
                      : [
                          Colors.deepPurpleAccent.withOpacity(0.11),
                          Colors.amber.withOpacity(0.14)
                        ],
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
              icon: Icon(Icons.arrow_back,
                  color: widget.isDarkMode ? Colors.white : Colors.black),
              onPressed: () {
                if (_isDisposed) return;
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
                  Text(
                    'Users in meeting: $_usersInMeetingCount',
                    style: TextStyle(
                      color: widget.isDarkMode
                          ? Colors.cyanAccent
                          : Colors.deepPurpleAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                              : widget.isDarkMode
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade400,
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
                        _isRecording
                            ? context.loc.listening
                            : context.loc.tapMicToStart,
                        style: TextStyle(
                          color:
                              widget.isDarkMode ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                                color: widget.isDarkMode
                                    ? Colors.black87
                                    : Colors.black12,
                                blurRadius: 5)
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_currentSpeaker.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Chip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(
                            '$_currentSpeaker ${((_currentScore * 100).toStringAsFixed(0))}%',
                          ),
                        ),
                      ],
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
                                    ? (widget.isDarkMode
                                        ? Colors.blue
                                        : Colors.deepPurpleAccent)
                                    : _myColor;
                                final isLive = msg['final'] == false;
                                final List<Map<String, dynamic>> cands =
                                    List<Map<String, dynamic>>.from(
                                        msg['cands'] ?? const []);

                                return Align(
                                  alignment: isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 7),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 15),
                                    constraints: BoxConstraints(
                                      maxWidth: size.width * 0.78,
                                    ),
                                    decoration: isMe
                                        ? BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: widget.isDarkMode
                                                  ? [
                                                      Colors.blueGrey.shade900,
                                                      Colors.blueGrey.shade800
                                                    ]
                                                  : [
                                                      Color(0xFF1E88E5),
                                                      Color(0xFF5AC8FA)
                                                    ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            boxShadow: [
                                              BoxShadow(
                                                color: widget.isDarkMode
                                                    ? Colors.black
                                                        .withOpacity(0.18)
                                                    : Color(0xFF1E88E5)
                                                        .withOpacity(0.18),
                                                blurRadius: 18,
                                                offset: const Offset(1, 4),
                                              )
                                            ],
                                          )
                                        : BoxDecoration(
                                            color: color.withOpacity(
                                                widget.isDarkMode
                                                    ? 0.21
                                                    : 0.14),
                                            borderRadius:
                                                BorderRadius.circular(19),
                                            border: Border.all(
                                              color: color.withOpacity(0.18),
                                              width: 1,
                                            ),
                                          ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 2,
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: color,
                                              radius: 14,
                                              child: Text(
                                                (msg['user'] as String)[0]
                                                    .toUpperCase(),
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
                                                color:
                                                    isMe ? Colors.white : color,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (isLive)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.circle,
                                                        size: 10,
                                                        color:
                                                            Colors.redAccent),
                                                    SizedBox(width: 6),
                                                    Text('Live',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              )
                                            else if (isMe && _speakOnMeeting)
                                              spoken
                                                  ? Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withOpacity(0.23),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: const [
                                                          Icon(
                                                              Icons
                                                                  .volume_up_rounded,
                                                              size: 15,
                                                              color:
                                                                  Colors.blue),
                                                          SizedBox(width: 2),
                                                          Text('Spoken',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .blue,
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                        ],
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            Text(
                                              msg['time'] as String,
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                        .withOpacity(0.88)
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

                                        // SHOW CANDIDATES (diarization) for finalized messages
                                        if (!isLive && cands.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (int i = 0;
                                                  i < cands.length;
                                                  i++)
                                                _CandidateChip(
                                                  name: cands[i]['name']
                                                      as String,
                                                  percent: ((cands[i]['score']
                                                          as double) *
                                                      100.0),
                                                  highlight: i == 0, // top-1
                                                  dark: widget.isDarkMode,
                                                ),
                                            ],
                                          ),
                                        ],
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

              // “Identifying…” overlay during mic handoff
              if (_identifyingNow)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Identifying speaker…',
                        style: TextStyle(color: Colors.white),
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
                        if (!mounted || _isDisposed) return;
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.arrow_downward,
                                color: Colors.white, size: 22),
                            SizedBox(width: 6),
                            Text("New message",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
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
                                if (_isDisposed) return;
                                if (_isRecording) {
                                  // user turns OFF the mic
                                  if (mounted) {
                                    setState(() => _isRecording = false);
                                  }
                                  _stopListening();
                                } else {
                                  // user turns ON the mic (continuous)
                                  if (!_speech.isListening) {
                                    _startListening();
                                  }
                                  if (mounted) {
                                    setState(() => _isRecording = true);
                                  }
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
                                            ? [
                                                Colors.deepPurple,
                                                Colors.cyanAccent
                                              ]
                                            : [
                                                Color(0xFF8E54E9),
                                                Color(0xFF50E3C2)
                                              ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isRecording
                                          ? Colors.cyanAccent.withOpacity(0.18)
                                          : widget.isDarkMode
                                              ? Colors.cyanAccent
                                                  .withOpacity(0.12)
                                              : Colors.deepPurpleAccent
                                                  .withOpacity(0.07),
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

class _CandidateChip extends StatelessWidget {
  final String name;
  final double percent;
  final bool highlight;
  final bool dark;

  const _CandidateChip({
    Key? key,
    required this.name,
    required this.percent,
    required this.highlight,
    required this.dark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? (dark
            ? Colors.cyanAccent.withOpacity(0.22)
            : Colors.deepPurpleAccent.withOpacity(0.18))
        : (dark ? Colors.white.withOpacity(0.08) : Colors.black12);
    final border = highlight
        ? (dark
            ? Colors.cyanAccent.withOpacity(0.45)
            : Colors.deepPurpleAccent.withOpacity(0.45))
        : (dark ? Colors.white24 : Colors.black26);
    final fg = highlight
        ? (dark ? Colors.cyanAccent : Colors.deepPurpleAccent)
        : (dark ? Colors.white70 : Colors.black87);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(highlight ? Icons.verified : Icons.person, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            '$name  ${percent.toStringAsFixed(0)}%',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class MeetingHistoryScreen extends StatelessWidget {
  final bool isDark;

  const MeetingHistoryScreen({Key? key, required this.isDark})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final bgColors = isDark
        ? [
            const Color(0xFF232526),
            const Color(0xFF181A20),
            const Color(0xFF232526)
          ]
        : [
            const Color(0xFF0093E9),
            const Color(0xFF80D0C7),
            const Color(0xFFFCF6BA)
          ];

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
              icon: Icon(Icons.arrow_back,
                  color: isDark ? Colors.white : Colors.black),
              onPressed: () {
                context.pop();
              },
            ),
          ),
        ),
      ),
      body: Stack(children: [
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
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.forum_rounded,
                                color: isDark
                                    ? Colors.cyanAccent
                                    : Colors.deepPurpleAccent,
                                size: 66),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 18),
                      itemBuilder: (_, i) {
                        final data = docs[i].data() as Map<String, dynamic>;
                        final messages = List<Map<String, dynamic>>.from(
                            data['messages'] ?? []);
                        final dt = DateTime.fromMillisecondsSinceEpoch(
                            data['timestamp'] ?? 0);

                        return AnimatedContainer(
                          duration: Duration(milliseconds: 320 + (i * 25)),
                          curve: Curves.easeInOut,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Card(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : Colors.white.withOpacity(0.83),
                                elevation: 8,
                                shadowColor: isDark
                                    ? Colors.cyanAccent.withOpacity(0.11)
                                    : Colors.amber.withOpacity(0.13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      width: 1.5,
                                      color: isDark
                                          ? Colors.cyanAccent.withOpacity(0.12)
                                          : Colors.deepPurpleAccent
                                              .withOpacity(0.09),
                                    )),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                    splashColor: Colors.amber.withOpacity(0.09),
                                  ),
                                  child: ExpansionTile(
                                    initiallyExpanded: i == 0,
                                    collapsedBackgroundColor:
                                        Colors.transparent,
                                    backgroundColor: Colors.transparent,
                                    title: ShaderMask(
                                      shaderCallback: (rect) => LinearGradient(
                                        colors: isDark
                                            ? [Colors.cyanAccent, Colors.white]
                                            : [
                                                Colors.deepPurple,
                                                Colors.indigo,
                                                Colors.amber
                                              ],
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
                                                color: isDark
                                                    ? Colors.cyanAccent
                                                        .withOpacity(0.16)
                                                    : Colors.deepPurpleAccent
                                                        .withOpacity(0.15),
                                                blurRadius: 7,
                                                offset: Offset(1, 2))
                                          ],
                                        ),
                                      ),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Icon(Icons.calendar_today,
                                            size: 16,
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.blueGrey),
                                        const SizedBox(width: 4),
                                        Text(
                                          "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} @ "
                                          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.blueGrey,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 13,
                                            left: 12,
                                            right: 12,
                                            top: 3),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3),
                                              child: ShaderMask(
                                                shaderCallback: (rect) =>
                                                    LinearGradient(
                                                  colors: isDark
                                                      ? [
                                                          Colors.cyanAccent,
                                                          Colors.white
                                                        ]
                                                      : [
                                                          Colors.deepPurple,
                                                          Colors.amber
                                                        ],
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
                                            ...messages
                                                .asMap()
                                                .entries
                                                .map((entry) {
                                              final msg = entry.value;
                                              final isMe = msg['isMe'] ?? false;
                                              final color = isMe
                                                  ? (isDark
                                                      ? Colors.cyanAccent
                                                      : Colors.deepPurpleAccent)
                                                  : Colors.blueGrey;
                                              final List<Map<String, dynamic>>
                                                  cands = List<
                                                          Map<String,
                                                              dynamic>>.from(
                                                      msg['cands'] ?? const []);
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 6),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        gradient:
                                                            LinearGradient(
                                                          colors: [
                                                            color.withOpacity(
                                                                0.82),
                                                            color.withOpacity(
                                                                0.66)
                                                          ],
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(50),
                                                      ),
                                                      child: CircleAvatar(
                                                        backgroundColor:
                                                            Colors.transparent,
                                                        radius: 16,
                                                        child: Text(
                                                          (msg['user'] as String?)
                                                                      ?.isNotEmpty ==
                                                                  true
                                                              ? (msg['user']
                                                                      as String)[0]
                                                                  .toUpperCase()
                                                              : "?",
                                                          style:
                                                              const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 17),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    340),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 10,
                                                                horizontal: 13),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: color
                                                              .withOpacity(isMe
                                                                  ? 0.19
                                                                  : 0.16),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(15),
                                                          border: Border.all(
                                                            color: color
                                                                .withOpacity(
                                                                    0.22),
                                                            width: 1.1,
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: color
                                                                  .withOpacity(
                                                                      0.08),
                                                              blurRadius: 8,
                                                              offset:
                                                                  Offset(0, 3),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  msg['user'] ??
                                                                      '',
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color:
                                                                        color,
                                                                    fontSize:
                                                                        14.5,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 6),
                                                                if (isMe)
                                                                  Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: Colors
                                                                          .amber
                                                                          .withOpacity(
                                                                              0.12),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              9),
                                                                    ),
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            2),
                                                                    child: Row(
                                                                      children: const [
                                                                        Icon(
                                                                            Icons
                                                                                .verified,
                                                                            size:
                                                                                14,
                                                                            color:
                                                                                Colors.amber),
                                                                        SizedBox(
                                                                            width:
                                                                                2),
                                                                        Text(
                                                                            "You",
                                                                            style: TextStyle(
                                                                                color: Colors.amber,
                                                                                fontWeight: FontWeight.w700,
                                                                                fontSize: 11)),
                                                                      ],
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 3),
                                                            Text(
                                                              msg['text'] ?? '',
                                                              style: TextStyle(
                                                                color: isDark
                                                                    ? Colors
                                                                        .white
                                                                        .withOpacity(
                                                                            0.92)
                                                                    : Colors
                                                                        .black87,
                                                                fontSize: 15.1,
                                                                height: 1.26,
                                                              ),
                                                            ),
                                                            if (cands
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                  height: 8),
                                                              Wrap(
                                                                spacing: 6,
                                                                runSpacing: 6,
                                                                children: [
                                                                  for (int i =
                                                                          0;
                                                                      i <
                                                                          cands
                                                                              .length;
                                                                      i++)
                                                                    _CandidateChip(
                                                                      name: cands[i]
                                                                              [
                                                                              'name']
                                                                          as String,
                                                                      percent: ((cands[i]['score']
                                                                              as double) *
                                                                          100.0),
                                                                      highlight:
                                                                          i ==
                                                                              0,
                                                                      dark:
                                                                          isDark,
                                                                    ),
                                                                ],
                                                              ),
                                                            ],
                                                            const SizedBox(
                                                                height: 4),
                                                            Align(
                                                              alignment: Alignment
                                                                  .bottomRight,
                                                              child: Text(
                                                                msg['time'] ??
                                                                    '',
                                                                style:
                                                                    TextStyle(
                                                                  color: isDark
                                                                      ? Colors
                                                                          .white54
                                                                      : Colors
                                                                          .blueGrey,
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
      ]),
    );
  }
}
