import 'dart:async';
import 'dart:ui';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:wave_blob/wave_blob.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

  String _latestSentence = '';
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
    _speech.initialize();
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
    _latestSentenceTimer?.cancel();
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

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available) return;
    setState(() {
      _isRecording = true;
    });
    _speech.listen(
      onResult: _onSpeechResult,
      listenMode: ListenMode.dictation,
      onSoundLevelChange: (level) {
        setState(() {
          _amplitude = level * 1000;
        });
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isRecording = false;
      _amplitude = 0;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) async {
    final text = result.recognizedWords.trim();
    if (text.isEmpty || !result.finalResult) return;
    if (!_showTextMyLanguage && !_isTextInLanguage(text, _appLanguageCode)) {
      return;
    }
    setState(() {
      _messages.add({
        'user': _myName,
        'text': text,
        'time': TimeOfDay.now().format(context),
        'isMe': true,
        'spoken': false,
      });
      _latestSentence = text;
    });
    _latestSentenceTimer?.cancel();
    _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
      setState(() => _latestSentence = '');
    });
    await _saveCurrentMeetingToFirestore();
    if (_speakOnMeeting) {
      await _speakMyLastMessage(text);
    }
    if (_shouldAutoscroll) _scrollToBottom(animate: true);

    // Restart listening to keep capturing subsequent speech input.
    if (_isRecording) {
      _startListening();
    }
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
        r'\u0D00-\u0D7F\u0D80-\u0DFF]'
      ).hasMatch(text);
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
