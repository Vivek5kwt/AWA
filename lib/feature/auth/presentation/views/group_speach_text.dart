import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wave_blob/wave_blob.dart';

import '../../../../core/speaker/speaker_service.dart';
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
  bool _isRecording = false;
  double _amplitude = 0;
  Timer? _amplitudeTimer;
  late AnimationController _micGlowController;
  final AudioRecorder _recorder = AudioRecorder();

  final List<Map<String, dynamic>> _messages = [];
  int _speakerIndex = 0;
  final List<Color> _userColors = [
    const Color(0xFF50E3C2),
    const Color(0xFF8E54E9),
    const Color(0xFF4776E6),
    const Color(0xFFFFA726),
  ];

  String? _currentFilePath;
  final TextEditingController _textController = TextEditingController();
  String _myName = '';
  Color _myColor = const Color(0xFF1E88E5);

  final FlutterTts _flutterTts = FlutterTts();

  String _appLanguageCode = 'en';

  bool _speakOnMeeting = true;
  bool _showTextMyLanguage = false;

  final SpeakerService _speakerService = SpeakerService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _currentText = '';

  late final ScrollController _scrollController;
  bool _showScrollDownBtn = false;
  bool _shouldAutoscroll = true;

  String _latestSentence = '';
  String _latestSpeaker = '';
  Timer? _latestSentenceTimer;

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

    _speakerService.init();
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
    _micGlowController.dispose();
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    _speech.stop();
    _speakerService.dispose();
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

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;

    setState(() {
      _isRecording = true;
      _speakerIndex = 0;
    });

    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!_isRecording) return;
      setState(() {
        _amplitude = 2200 + Random().nextInt(3400).toDouble();
      });
    });

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

    _currentText = '';
    _speech.listen(onResult: (result) {
      if (!mounted) return;
      setState(() {
        _currentText = result.recognizedWords;
        _latestSentence = _currentText;
        _latestSpeaker = '';
      });
      _latestSentenceTimer?.cancel();
    });
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
    _amplitudeTimer?.cancel();
    await _speech.stop();

    String? stoppedPath;
    if (await _recorder.isRecording()) {
      stoppedPath = await _recorder.stop();
    } else if (_currentFilePath != null) {
      stoppedPath = _currentFilePath;
    }

    if (stoppedPath != null) {
      final file = File(stoppedPath);
      if (await file.exists() && await _isAudioSignificant(file)) {
        String? id;
        try {
          id = await _speakerService.identify(stoppedPath);
        } catch (_) {}
        final text = _currentText.trim();
        if (text.isNotEmpty) {
          setState(() {
            _messages.add({
              'user': id ?? 'Unknown',
              'text': text,
              'time': TimeOfDay.now().format(context),
              'isMe': false,
              'spoken': false,
            });
            _latestSentence = text;
            _latestSpeaker = id ?? 'Unknown';
            _currentText = '';
          });
          _latestSentenceTimer?.cancel();
          _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _latestSentence = '';
                _latestSpeaker = '';
              });
            }
          });
          if (_shouldAutoscroll) _scrollToBottom(animate: true);
        }
      }
    }
  }

  // Aliases matching speaker screen controls
  Future<void> _startRecording() => _startListening();

  Future<void> _stopAndIdentify() => _stopListening();

  // Allow English and major Indian scripts so that Hindi or other
  // Indian languages are not filtered out when app language is English.
  bool _isTextInLanguage(String text, String languageCode) {
    if (languageCode == 'en') {
      final englishLetters =
      text.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').replaceAll(' ', '');
      final hasIndianChars =
      RegExp(r'[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF'
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

  void _processAudioQueue() async {}

  Future<void> _hitIdentifySpeaker(File audioFile, int label) async {
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
                          color:
                          widget.isDarkMode ? Colors.black : Colors.white,
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
                          )),
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
      _latestSpeaker = _myName;
      _latestSentenceTimer?.cancel();
      _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
        setState(() {
          _latestSentence = '';
          _latestSpeaker = '';
        });
      });
    });

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
                          color: textPrimary.withOpacity(0.86),
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
                              : _userColors[index % _userColors.length];
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 360),
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
                                      if (isMe)
                                        _speakOnMeeting
                                            ? spoken
                                            ? Container(
                                          padding:
                                          const EdgeInsets
                                              .symmetric(
                                              horizontal: 8,
                                              vertical: 2),
                                          decoration:
                                          BoxDecoration(
                                            color: Colors.white
                                                .withOpacity(
                                                0.23),
                                            borderRadius:
                                            BorderRadius
                                                .circular(
                                                8),
                                          ),
                                          child: Row(
                                            mainAxisSize:
                                            MainAxisSize
                                                .min,
                                            children: [
                                              Icon(
                                                  Icons
                                                      .volume_up_rounded,
                                                  size: 15,
                                                  color: Colors
                                                      .blue),
                                              const SizedBox(
                                                  width: 2),
                                              const Text(
                                                'Spoken',
                                                style:
                                                TextStyle(
                                                  color: Colors
                                                      .blue,
                                                  fontSize: 11,
                                                  fontWeight:
                                                  FontWeight
                                                      .bold,
                                                ),
                                              ),
                                              IconButton(
                                                padding:
                                                const EdgeInsets
                                                    .only(
                                                    left: 2,
                                                    right:
                                                    2),
                                                constraints:
                                                const BoxConstraints(),
                                                tooltip:
                                                'Speak again',
                                                icon: const Icon(
                                                    Icons
                                                        .replay_circle_filled,
                                                    size: 18,
                                                    color: Colors
                                                        .blueAccent),
                                                onPressed: () =>
                                                    _replaySpeak(
                                                        index),
                                              ),
                                            ],
                                          ),
                                        )
                                            : const SizedBox.shrink()
                                            : IconButton(
                                          icon: Icon(
                                              Icons
                                                  .play_circle_fill_rounded,
                                              color: Colors
                                                  .deepPurpleAccent,
                                              size: 26),
                                          tooltip:
                                          "Tap to play this message",
                                          onPressed: () =>
                                              _replaySpeak(index),
                                        ),
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
                      _latestSpeaker.isNotEmpty
                          ? '$_latestSpeaker: $_latestSentence'
                          : _latestSentence,
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
                                if (_isRecording) {
                                  _stopAndIdentify();
                                } else {
                                  _startRecording();
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

