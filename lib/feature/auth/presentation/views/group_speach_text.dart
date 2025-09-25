import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wave_blob/wave_blob.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../open_ai_transcription.dart';


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
  StreamSubscription<Uint8List>? _audioStreamSub;

  OpenAIRealtimeTranscriptionService? _transcriptionService;

  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();

  String _myName = '';
  Color _myColor = const Color(0xFF1E88E5);
  final List<Map<String, String>> _availableLanguages = [
    {'code': 'en', 'name': 'English', 'emoji': '🇮🇳'},
    {'code': 'hi', 'name': 'Hindi', 'emoji': '🇮🇳'},
    {'code': 'pa', 'name': 'Punjabi', 'emoji': '🇮🇳'},
    {'code': 'gu', 'name': 'Gujarati', 'emoji': '🇮🇳'},
    {'code': 'mr', 'name': 'Marathi', 'emoji': '🇮🇳'},
    {'code': 'ta', 'name': 'Tamil', 'emoji': '🇮🇳'},
    {'code': 'bn', 'name': 'Bengali', 'emoji': '🇮🇳'},
    {'code': 'ur', 'name': 'Urdu', 'emoji': '🇮🇳'},
  ];

  String _SelectedLanguageCode = 'en';
  String _selectedLanguageCode = 'en';

  final FlutterTts _flutterTts = FlutterTts();
  String _appLanguageCode = 'en';
  bool _speakOnMeeting = false;
  bool _showTextMyLanguage = false;

  bool _languageSelected = false;

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

  final Map<String, Color> _speakerColors = {};

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

  String _formatSpeakerName(String? name) {
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return 'Unknown Speaker';
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty);
    return parts
        .map((part) => _capitalize(part.toLowerCase()))
        .join(' ')
        .trim();
  }

  Color _colorForSpeaker(String speaker) {
    final formatted = _formatSpeakerName(speaker);
    if (_speakerColors.containsKey(formatted)) {
      return _speakerColors[formatted]!;
    }
    const palette = [
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFF8E24AA),
      Color(0xFFEF6C00),
      Color(0xFF00838F),
      Color(0xFF6D4C41),
      Color(0xFF3949AB),
      Color(0xFF5E35B1),
      Color(0xFF0097A7),
    ];
    final index = formatted.hashCode.abs() % palette.length;
    final color = palette[index];
    _speakerColors[formatted] = color;
    return color;
  }

  Future<void> _loadSpeakOnMeeting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speakOnMeeting = prefs.getBool('speakOnMeeting') ?? false;
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
            'No voice detected for a while. Stop listening? You can start again anytime. Your meeting is saved.'),
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

    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);

    _firestore = FirebaseFirestore.instance;
    _meetingDocId = "meeting_${DateTime.now().millisecondsSinceEpoch}";
    _loadPreviousMessages();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askUserLanguage(force: true);
    });
  }

  /// Show language picker. If [force] is true, the sheet cannot be dismissed
  /// and the user must confirm a selection.
  Future<void> _askUserLanguage({bool force = false}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    String localSelected = _selectedLanguageCode;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: !force,
      enableDrag: !force,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final mq = MediaQuery.of(bottomSheetContext);
        final maxHeight = mq.size.height * 0.78;
        return WillPopScope(
          onWillPop: () async => !force,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: StatefulBuilder(builder: (context, setStateSheet) {
                return Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 700,
                      maxHeight: maxHeight,
                    ),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.isDarkMode
                          ? const Color(0xFF111217)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: widget.isDarkMode
                              ? Colors.black.withOpacity(0.6)
                              : Colors.black12,
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Select Meeting Language",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                widget.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Pick the language you'll be speaking in. This helps improve accuracy.",
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.isDarkMode
                                ? Colors.white70
                                : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: max(180, min(420, maxHeight - 180)),
                          ),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 3.2,
                            ),
                            itemCount: _availableLanguages.length,
                            itemBuilder: (context, index) {
                              final lang = _availableLanguages[index];
                              final code = lang['code']!;
                              final name = lang['name']!;
                              final emoji = lang['emoji'] ?? '';
                              final selected = localSelected == code;
                              return InkWell(
                                onTap: () {
                                  setStateSheet(() => localSelected = code);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? (widget.isDarkMode
                                            ? Colors.blueGrey.shade800
                                            : Colors.blue.shade50)
                                        : (widget.isDarkMode
                                            ? Colors.black
                                            : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(12),
                                    border: selected
                                        ? Border.all(
                                            color: widget.isDarkMode
                                                ? Colors.cyanAccent
                                                : Colors.blue,
                                            width: 2)
                                        : Border.all(
                                            color: widget.isDarkMode
                                                ? Colors.transparent
                                                : Colors.transparent,
                                            width: 1),
                                    boxShadow: [
                                      if (selected)
                                        BoxShadow(
                                          color: (widget.isDarkMode
                                                  ? Colors.cyanAccent
                                                  : Colors.blue)
                                              .withOpacity(0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 6),
                                        )
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Text(emoji,
                                          style: const TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: widget.isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              code.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: widget.isDarkMode
                                                    ? Colors.white70
                                                    : Colors.black45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (selected)
                                        Icon(
                                          Icons.check_circle,
                                          color: widget.isDarkMode
                                              ? Colors.cyanAccent
                                              : Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (!force)
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: widget.isDarkMode
                                          ? Colors.white12
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.of(bottomSheetContext).pop(null);
                                  },
                                  child: Text(
                                    "Cancel",
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            if (!force) const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.isDarkMode
                                      ? Colors.cyanAccent
                                      : Colors.blue,
                                ),
                                onPressed: () {
                                  Navigator.of(bottomSheetContext)
                                      .pop(localSelected);
                                },
                                child: Text(
                                  "Confirm",
                                  style: TextStyle(
                                    color: widget.isDarkMode
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );

    final chosen = result ?? _selectedLanguageCode;

    if (!mounted) return;

    setState(() {
      _selectedLanguageCode = chosen;
      _languageSelected = true;
    });

    try {
      await _transcriptionService?.close();
    } catch (_) {}
    _transcriptionService = null;

    // Read user email from shared preferences and append as query param to stream URL
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final urlWithEmail =
        ApiConstants.streamUrl + '?email=${Uri.encodeComponent(email)}';

    _transcriptionService = OpenAIRealtimeTranscriptionService(
        urlWithEmail, _selectedLanguageCode);
    await _initTranscriptionService();
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
        _messages
            .addAll(List<Map<String, dynamic>>.from(data['messages'] ?? []));
        for (final msg in _messages) {
          if (msg['text'] != null) {
            try {
              msg['text'] = msg['text']
                  .toString()
                  .split(RegExp('<fin>', caseSensitive: false))[0]
                  .trim();
            } catch (_) {}
          }

          final isMe = msg['isMe'] ?? false;
          if (!isMe) {
            final formattedName = _formatSpeakerName(msg['user'] as String?);
            msg['user'] = formattedName;
            msg['color'] = _colorForSpeaker(formattedName);
          }
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _initTranscriptionService() async {
    final svc = _transcriptionService;
    if (svc == null) return;

    await svc.connect(
      onTranscription: (speaker, text) {
        if (!mounted) return;

        final cleanedText =
            text.toString().split(RegExp('<fin>', caseSensitive: false))[0].trim();

        if (cleanedText.isEmpty) return;

        final speakerName = _formatSpeakerName(speaker);
        final isMe = speakerName.toLowerCase() == _myName.toLowerCase();
        final color = isMe ? _myColor : _colorForSpeaker(speakerName);

        setState(() {
          _messages.add({
            'user': speakerName,
            'text': cleanedText,
            'time': TimeOfDay.now().format(context),
            'isMe': isMe,
            'isFinal': true,
            'color': color,
            'spoken': false,
          });
          _latestSentence = cleanedText;
        });

        _latestSentenceTimer?.cancel();
        _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() => _latestSentence = '');
        });

        _saveCurrentMeetingToFirestore();
        if (_shouldAutoscroll) _scrollToBottom(animate: false);
      },
      onError: (err) => debugPrint("WebSocket Error: $err"),
    );

    try {
      final languagePayload = jsonEncode({
        "language": _selectedLanguageCode,
      });
      svc.sendLanguage(languagePayload);
      debugPrint(
          "✅ Language sent to transcription service: $_selectedLanguageCode");
    } catch (e) {
      debugPrint("❌ Failed to send language to service: $e");
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

  Future<void> _startListening() async {
    if (!_languageSelected) {
      await _askUserLanguage(force: true);
      return;
    }

    if (!await _recorder.hasPermission()) return;

    if (_transcriptionService != null) {
      try {
        await _transcriptionService!.close();
      } catch (_) {}
      _transcriptionService = null;
    }

    // Read user email and attach it to the stream URL as a query parameter
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final urlWithEmail =
        ApiConstants.streamUrl + '?email=${Uri.encodeComponent(email)}';

    _transcriptionService =
        OpenAIRealtimeTranscriptionService(urlWithEmail, _selectedLanguageCode);
    await _initTranscriptionService();

    setState(() {
      _isRecording = true;
    });
    _resetSilenceTimer();

    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!_isRecording) return;
      setState(() {
        _amplitude = 2200 + Random().nextInt(3400).toDouble();
      });
    });

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
      ),
    );

    await _audioStreamSub?.cancel();

    _audioStreamSub = stream.listen((audioBytes) {
      try {
        _transcriptionService?.sendAudio(audioBytes);
      } catch (e) {
        debugPrint("Failed to send audio: $e");
      }
    });
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
    try {
      await _transcriptionService?.close();
    } catch (_) {}
    _transcriptionService = null;
  }

  Future<void> _sendTextMessage() async {
    if (!_languageSelected) {
      await _askUserLanguage(force: true);
      return;
    }

    var msg = _textController.text.trim();
    if (msg.isEmpty) return;

    msg = msg.split(RegExp('<fin>', caseSensitive: false))[0].trim();

    setState(() {
      _messages.add({
        'user': _myName,
        'text': msg,
        'time': TimeOfDay.now().format(context),
        'isMe': true,
        'spoken': false,
        'isFinal': true,
      });
      _textController.clear();
      _latestSentence = msg;
      _latestSentenceTimer?.cancel();
      _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _latestSentence = '');
      });
    });

    await _saveCurrentMeetingToFirestore();

    if (_speakOnMeeting) {
      await _flutterTts.speak(msg);
      final idx = _messages
          .lastIndexWhere((m) => m['text'] == msg && m['isMe'] == true);
      if (idx != -1) {
        setState(() => _messages[idx]['spoken'] = true);
      }
    }

    if (_shouldAutoscroll) _scrollToBottom();
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
    _recorder.dispose();
    _micGlowController.dispose();
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    try {
      _transcriptionService?.close();
    } catch (_) {}
    _transcriptionService = null;
    super.dispose();
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
                  offset: const Offset(1, 2),
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
                onPressed: null,
                onLongPress: () {
                  _toggleShowTextMyLanguage();
                },
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
              onPressed: () => context.pop(),
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
              AbsorbPointer(
                absorbing: !_languageSelected,
                child: Column(
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
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isMe = msg['isMe'] ?? true;
                                final spoken = msg['spoken'] ?? false;
                                final fallbackColor = widget.isDarkMode
                                    ? Colors.blue
                                    : Colors.deepPurpleAccent;
                                final participantColor =
                                    (msg['color'] as Color?) ?? fallbackColor;
                                final participantName = isMe
                                    ? _myName
                                    : (msg['user'] as String? ?? 'Participant');

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
                                        maxWidth: size.width * 0.78),
                                    decoration: isMe
                                        ? BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: widget.isDarkMode
                                                  ? [
                                                      Colors.blueGrey.shade900,
                                                      Colors.blueGrey.shade800
                                                    ]
                                                  : [
                                                      const Color(0xFF1E88E5),
                                                      const Color(0xFF5AC8FA)
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
                                                    : const Color(0xFF1E88E5)
                                                        .withOpacity(0.18),
                                                blurRadius: 18,
                                                offset: const Offset(1, 4),
                                              )
                                            ],
                                          )
                                        : BoxDecoration(
                                            color: participantColor.withOpacity(
                                                widget.isDarkMode ? 0.21 : 0.14),
                                            borderRadius:
                                                BorderRadius.circular(19),
                                            border: Border.all(
                                              color: participantColor
                                                  .withOpacity(0.18),
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
                                              backgroundColor: isMe
                                                  ? _myColor
                                                  : participantColor,
                                              radius: 14,
                                              child: Text(
                                                participantName.isNotEmpty
                                                    ? participantName[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              participantName,
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                    : widget.isDarkMode
                                                        ? Colors.white
                                                        : participantColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (!isMe &&
                                                msg['confidence'] != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: participantColor
                                                      .withOpacity(
                                                          widget.isDarkMode
                                                              ? 0.25
                                                              : 0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Conf. ${(msg['confidence'] as num?)?.toStringAsFixed(2) ?? '-'}',
                                                  style: TextStyle(
                                                    color: widget.isDarkMode
                                                        ? Colors.white
                                                        : participantColor,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            if (_speakOnMeeting && spoken)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.23),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.volume_up_rounded,
                                                        size: 15,
                                                        color: Colors.blue),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'Spoken',
                                                      style: TextStyle(
                                                        color: Colors.blue,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
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
                  ],
                ),
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
                                    : [
                                        const Color(0xFF50E3C2),
                                        const Color(0xFF8E54E9)
                                      ],
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
                                            ? [
                                                Colors.deepPurple,
                                                Colors.cyanAccent
                                              ]
                                            : [
                                                const Color(0xFF8E54E9),
                                                const Color(0xFF50E3C2)
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
