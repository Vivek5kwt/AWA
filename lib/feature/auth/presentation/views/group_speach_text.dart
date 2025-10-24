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
    // Common Indian languages first (with India flag for user clarity)
    {'code': 'en', 'name': 'English', 'emoji': '🇮🇳'},
    {'code': 'hi', 'name': 'Hindi', 'emoji': '🇮🇳'},
    {'code': 'pa', 'name': 'Punjabi', 'emoji': '🇮🇳'},
    {'code': 'gu', 'name': 'Gujarati', 'emoji': '🇮🇳'},
    {'code': 'mr', 'name': 'Marathi', 'emoji': '🇮🇳'},
    {'code': 'ta', 'name': 'Tamil', 'emoji': '🇮🇳'},
    {'code': 'bn', 'name': 'Bengali', 'emoji': '🇮🇳'},
    {'code': 'ur', 'name': 'Urdu', 'emoji': '🇮🇳'},
    {'code': 'kn', 'name': 'Kannada', 'emoji': '🇮🇳'},
    {'code': 'ml', 'name': 'Malayalam', 'emoji': '🇮🇳'},
    {'code': 'es', 'name': 'Spanish', 'emoji': '🇪🇸'},
    {'code': 'fr', 'name': 'French', 'emoji': '🇫🇷'},
    {'code': 'de', 'name': 'German', 'emoji': '🇩🇪'},
    {'code': 'zh', 'name': 'Chinese', 'emoji': '🇨🇳'},
    {'code': 'ar', 'name': 'Arabic', 'emoji': '🇸🇦'},
    {'code': 'pt', 'name': 'Portuguese', 'emoji': '🇵🇹'},
    {'code': 'ru', 'name': 'Russian', 'emoji': '🇷🇺'},
    {'code': 'ja', 'name': 'Japanese', 'emoji': '🇯🇵'},
    {'code': 'ko', 'name': 'Korean', 'emoji': '🇰🇷'},
    {'code': 'tr', 'name': 'Turkish', 'emoji': '🇹🇷'},
    {'code': 'uk', 'name': 'Ukrainian', 'emoji': '🇺🇦'},
    {'code': 'fa', 'name': 'Persian / Farsi', 'emoji': '🇮🇷'},
  ];

  // Use a single selected language variable (avoid duplicate names/casing)
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

  List<String> _uniqueSpeakers = [];
  String? _selectedSpeakerFilter;

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

  _maybeScrollToBottom(
      {bool animate = true,
      Duration delay = const Duration(milliseconds: 120)}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final offset = _scrollController.offset;
      final distanceFromBottom = (maxExtent - offset).abs();
      const double threshold = 150.0;

      if (_shouldAutoscroll || distanceFromBottom <= threshold) {
        await Future.delayed(delay);
        if (!mounted) return;
        final target = _scrollController.position.maxScrollExtent;
        try {
          if (animate) {
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          } else {
            _scrollController.jumpTo(target);
          }
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _showScrollDownBtn = false;
          _shouldAutoscroll = true;
        });
      } else {
        if (mounted) {
          setState(() {
            _showScrollDownBtn = true;
            _shouldAutoscroll = false;
          });
        }
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

  Future<void> _askUserLanguage({bool force = false}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Prepare separated lists: Indian and International
    final indianLanguages = _availableLanguages
        .where((l) => (l['emoji'] ?? '') == '🇮🇳')
        .toList();
    final internationalLanguages = _availableLanguages
        .where((l) => (l['emoji'] ?? '') != '🇮🇳')
        .toList();

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
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 700,
                  maxHeight: maxHeight,
                ),
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      widget.isDarkMode ? const Color(0xFF111217) : Colors.white,
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
                child: StatefulBuilder(builder: (context, setStateSheet) {
                  return Column(
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
                      // Use an Expanded ListView so sections can scroll when needed
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            // Indian Languages Section
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0, vertical: 6),
                              child: Row(
                                children: [
                                  Text("Indian Languages",
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: widget.isDarkMode
                                              ? Colors.white
                                              : Colors.black87)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "(${indianLanguages.length})",
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white70
                                          : Colors.black54,
                                      fontSize: 12,
                                    ),
                                  )
                                ],
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(), // scrolling handled by outer ListView
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 3.2,
                              ),
                              itemCount: indianLanguages.length,
                              itemBuilder: (context, index) {
                                final lang = indianLanguages[index];
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
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
                                            style:
                                                const TextStyle(fontSize: 20)),
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
                            const SizedBox(height: 12),
                            // International Languages Section
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0, vertical: 6),
                              child: Row(
                                children: [
                                  Text("International Languages",
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: widget.isDarkMode
                                              ? Colors.white
                                              : Colors.black87)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "(${internationalLanguages.length})",
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white70
                                          : Colors.black54,
                                      fontSize: 12,
                                    ),
                                  )
                                ],
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(), // handled by outer ListView
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 3.2,
                              ),
                              itemCount: internationalLanguages.length,
                              itemBuilder: (context, index) {
                                final lang = internationalLanguages[index];
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
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
                                            style:
                                                const TextStyle(fontSize: 20)),
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
                          ],
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
                                  color:
                                      widget.isDarkMode ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ],
                  );
                }),
              ),
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

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final urlWithEmail =
        ApiConstants.streamUrl + '?email=${Uri.encodeComponent(email)}';

    _transcriptionService =
        OpenAIRealtimeTranscriptionService(urlWithEmail, _selectedLanguageCode);
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
          } else {
            msg['user'] = _myName;
            msg['color'] = _myColor;
          }
        }
      });
      _updateSpeakers();
      _maybeScrollToBottom(
          animate: false, delay: const Duration(milliseconds: 80));
    }
  }

  Future<void> _initTranscriptionService() async {
    final svc = _transcriptionService;
    if (svc == null) return;

    await svc.connect(
      onTranscription: (speaker, text) {
        if (!mounted) return;

        final cleanedText = text
            .toString()
            .split(RegExp('<fin>', caseSensitive: false))[0]
            .trim();

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

        _updateSpeakers();

        _latestSentenceTimer?.cancel();
        _latestSentenceTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() => _latestSentence = '');
        });

        _saveCurrentMeetingToFirestore();
        _maybeScrollToBottom(
            animate: true, delay: const Duration(milliseconds: 80));
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

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final urlWithEmail = ApiConstants.streamUrl + '?email=$email';
    print('getteteteetette ${urlWithEmail}');

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
        bitRate: 256000,
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

    _updateSpeakers();

    await _saveCurrentMeetingToFirestore();

    if (_speakOnMeeting) {
      await _flutterTts.speak(msg);
      final idx = _messages
          .lastIndexWhere((m) => m['text'] == msg && m['isMe'] == true);
      if (idx != -1) {
        setState(() => _messages[idx]['spoken'] = true);
      }
    }

    _maybeScrollToBottom(
        animate: true, delay: const Duration(milliseconds: 60));
  }

  void _handleScroll() {
    final threshold = 150.0;
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    final distanceFromBottom = (maxScroll - offset).abs();

    final atBottom = distanceFromBottom <= threshold;

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

  Map<String, dynamic> _computeCreativity(List<Map<String, dynamic>> messages) {
    final int count = messages.length;
    final uniqueParticipants = messages
        .map((m) => ((m['user'] as String?) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .length;
    final avgLen = messages.isEmpty
        ? 0.0
        : messages
                .map((m) => ((m['text'] as String?) ?? '').length)
                .reduce((a, b) => a + b) /
            messages.length;

    double score = (count * 0.7) + (uniqueParticipants * 4.0) + (avgLen / 10.0);
    score = score.clamp(0.0, 100.0);

    String label;
    Color color;
    if (score >= 70) {
      label = 'Very High';
      color = Colors.greenAccent;
    } else if (score >= 45) {
      label = 'High';
      color = Colors.lightGreenAccent;
    } else if (score >= 20) {
      label = 'Medium';
      color = Colors.orangeAccent;
    } else {
      label = 'Low';
      color = widget.isDarkMode ? Colors.redAccent.shade200 : Colors.redAccent;
    }

    return {
      'fraction': (score / 100.0).clamp(0.0, 1.0),
      'label': label,
      'color': color,
      'score': score
    };
  }

  Future<void> _showMeetingHistory() async {
    await _stopListening();

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final double maxSheetHeight = min(mq.size.height * 0.82, 780);
        final double listHeight =
            (min(maxSheetHeight - 220, 460)).clamp(200, 520).toDouble();

        final theme = Theme.of(ctx);
        final primary = widget.isDarkMode
            ? Colors.tealAccent.shade200
            : theme.colorScheme.primary;
        final cardGradient = widget.isDarkMode
            ? [Colors.grey.shade900, Colors.grey.shade800]
            : [Colors.indigo.shade400, Colors.purpleAccent.shade100];

        return SafeArea(
          child: Center(
            child: Container(
              constraints:
                  BoxConstraints(maxWidth: 900, maxHeight: maxSheetHeight),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    widget.isDarkMode ? const Color(0xFF0F1113) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 6,
                    width: 60,
                    decoration: BoxDecoration(
                      color:
                          widget.isDarkMode ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Meeting History",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: widget.isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Your past meetings — curated and visualized with creativity level",
                              style: TextStyle(
                                fontSize: 13,
                                color: widget.isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close,
                            color: widget.isDarkMode
                                ? Colors.white70
                                : Colors.black54),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: _firestore
                        .collection('meeting_histories')
                        .doc('user_$email')
                        .collection('meetings')
                        .orderBy('timestamp', descending: true)
                        .get()
                        .then((snap) =>
                            snap),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(
                          height: listHeight,
                          child:
                          const Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return SizedBox(
                          height: listHeight,
                          child: Center(
                            child: Text(
                              "No previous meetings found.",
                              style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white70
                                      : Colors.black54),
                            ),
                          ),
                        );
                      }
                      final docs = snapshot.data!.docs;
                      return SizedBox(
                        height: listHeight,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: docs.length,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data();
                            final title =
                                (data['title'] as String?) ?? 'Group Chat';
                            final ts = (data['timestamp'] as num?)?.toInt();
                            final messages = List<Map<String, dynamic>>.from(
                                data['messages'] ?? []);
                            final preview = messages.isNotEmpty
                                ? (messages.last['text'] as String? ?? '')
                                : 'No messages';
                            final messageCount = messages.length;
                            final timeStr = ts != null
                                ? DateTime.fromMillisecondsSinceEpoch(ts)
                                    .toLocal()
                                    .toString()
                                : '';
                            final creativity = _computeCreativity(messages);

                            return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: InkWell(
                                  onTap: () async {
                                    await _saveCurrentMeetingToFirestore();
                                    await _loadMeetingFromDoc(doc);
                                    if (mounted) {
                                      Navigator.of(ctx).pop();
                                      _maybeScrollToBottom(
                                          animate: false,
                                          delay:
                                              const Duration(milliseconds: 80));
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: LinearGradient(
                                        colors: widget.isDarkMode
                                            ? [
                                                Colors.grey.shade900,
                                                Colors.grey.shade50
                                              ]
                                            : cardGradient,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: widget.isDarkMode
                                              ? Colors.black54
                                              : Colors.black12,
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        )
                                      ],
                                      border: Border.all(
                                        color: widget.isDarkMode
                                            ? Colors.white10
                                            : Colors.white24,
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 28,
                                            backgroundColor: widget.isDarkMode
                                                ? Colors.tealAccent.shade700
                                                    .withOpacity(0.18)
                                                : Colors.indigo.shade700,
                                            child: Text(
                                              title.isNotEmpty
                                                  ? title[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                color: widget.isDarkMode
                                                    ? Colors.white
                                                    : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 20,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: widget
                                                                  .isDarkMode
                                                              ? Colors.white
                                                              : Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!widget.isDarkMode)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 6.0),
                                                        child: Icon(
                                                            Icons.auto_awesome,
                                                            color:
                                                                Colors.white24,
                                                            size: 18),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  preview,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: widget.isDarkMode
                                                        ? Colors.white70
                                                        : Colors.white
                                                            .withOpacity(0.92),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: widget.isDarkMode
                                                            ? Colors.black26
                                                            : Colors.white24,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.message,
                                                              size: 14,
                                                              color: widget
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .white70
                                                                  : Colors
                                                                      .white),
                                                          const SizedBox(
                                                              width: 6),
                                                          Text(
                                                            "$messageCount messages",
                                                            style: TextStyle(
                                                              color: widget
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .white70
                                                                  : Colors
                                                                      .white,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const SizedBox(
                                                              height: 6),
                                                          Text(
                                                            timeStr,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: widget
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .white54
                                                                  : Colors
                                                                      .white70,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: () async {
                                                  await _saveCurrentMeetingToFirestore();
                                                  await _loadMeetingFromDoc(
                                                      doc);
                                                  if (mounted) {
                                                    Navigator.of(ctx).pop();
                                                    _maybeScrollToBottom(
                                                        animate: false,
                                                        delay: const Duration(
                                                            milliseconds: 80));
                                                  }
                                                },
                                                icon: Icon(Icons.open_in_new,
                                                    color: widget.isDarkMode
                                                        ? Colors.white70
                                                        : Colors.white),
                                              ),
                                              const SizedBox(height: 6),
                                              PopupMenuButton<String>(
                                                onSelected: (val) async {
                                                  if (val == 'delete') {
                                                    final confirmed =
                                                        await showDialog<bool>(
                                                      context: context,
                                                      builder: (dctx) =>
                                                          AlertDialog(
                                                        title: const Text(
                                                            'Delete meeting?'),
                                                        content: const Text(
                                                            'This will permanently delete the selected meeting history. Continue?'),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          dctx)
                                                                      .pop(
                                                                          false),
                                                              child: const Text(
                                                                  'Cancel')),
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          dctx)
                                                                      .pop(
                                                                          true),
                                                              child: const Text(
                                                                  'Delete')),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirmed == true) {
                                                      try {
                                                        await _firestore
                                                            .collection(
                                                                'meeting_histories')
                                                            .doc('user_$email')
                                                            .collection(
                                                                'meetings')
                                                            .doc(doc.id)
                                                            .delete();
                                                        if (mounted) {
                                                          setState(() {});
                                                        }
                                                        Navigator.of(ctx).pop();
                                                        await Future.delayed(
                                                            const Duration(
                                                                milliseconds:
                                                                    250));
                                                        _showMeetingHistory();
                                                      } catch (e) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'Failed to delete meeting: $e')));
                                                      }
                                                    }
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.delete,
                                                              color: widget
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .redAccent
                                                                      .shade200
                                                                  : Colors
                                                                      .redAccent),
                                                          const SizedBox(
                                                              width: 8),
                                                          const Text('Delete'),
                                                        ],
                                                      )),
                                                ],
                                                icon: Icon(Icons.more_vert,
                                                    color: widget.isDarkMode
                                                        ? Colors.white70
                                                        : Colors.white),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ));
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _saveCurrentMeetingToFirestore();
                        setState(() {
                          _meetingDocId =
                              "meeting_${DateTime.now().millisecondsSinceEpoch}";
                          _messages.clear();
                        });
                      },
                      icon: const Icon(Icons.auto_awesome, size: 20),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          "Start New Meeting",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                widget.isDarkMode ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.isDarkMode
                            ? Colors.tealAccent.shade700
                            : Colors.deepPurpleAccent,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadMeetingFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final msgs = List<Map<String, dynamic>>.from(data['messages'] ?? []);
    final loaded = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final copy = Map<String, dynamic>.from(m);
      try {
        if (copy['text'] != null) {
          copy['text'] = copy['text']
              .toString()
              .split(RegExp('<fin>', caseSensitive: false))[0]
              .trim();
        }
      } catch (_) {}
      final isMe = copy['isMe'] ?? false;
      if (!isMe) {
        final formattedName = _formatSpeakerName(copy['user'] as String?);
        copy['user'] = formattedName;
        copy['color'] = _colorForSpeaker(formattedName);
      } else {
        copy['user'] = _myName;
        copy['color'] = _myColor;
      }
      loaded.add(copy);
    }

    setState(() {
      _messages.clear();
      _messages.addAll(loaded);
      _meetingDocId = doc.id;
    });

    _updateSpeakers();

    await _maybeScrollToBottom(
        animate: false, delay: const Duration(milliseconds: 60));
  }

  void _updateSpeakers() {
    final Set<String> s = {};
    for (final m in _messages) {
      final user = ((m['user'] as String?) ?? '').trim();
      if (user.isNotEmpty) s.add(_formatSpeakerName(user));
    }

    final list = s.toList();
    list.sort((a, b) {
      final ca = _messages
          .where(
              (m) => ((_formatSpeakerName((m['user'] as String?) ?? '')) == a))
          .length;
      final cb = _messages
          .where(
              (m) => ((_formatSpeakerName((m['user'] as String?) ?? '')) == b))
          .length;
      return cb.compareTo(ca);
    });

    if (_selectedSpeakerFilter != null &&
        !list.contains(_selectedSpeakerFilter)) {
      _selectedSpeakerFilter = null;
    }

    setState(() {
      _uniqueSpeakers = list;
    });
  }

  int _messageCountForSpeaker(String speaker) {
    return _messages
        .where(
            (m) => _formatSpeakerName((m['user'] as String?) ?? '') == speaker)
        .length;
  }

  Future<void> _showSpeakersList() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final maxHeight = mq.size.height * 0.6;
        return SafeArea(
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 700, maxHeight: maxHeight),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    widget.isDarkMode ? const Color(0xFF0F1113) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      height: 6,
                      width: 60,
                      decoration: BoxDecoration(
                          color: widget.isDarkMode
                              ? Colors.white12
                              : Colors.black12,
                          borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: Text("Speakers (${_uniqueSpeakers.length})",
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isDarkMode
                                      ? Colors.white
                                      : Colors.black87))),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedSpeakerFilter = null;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Text("Show all",
                            style: TextStyle(
                                color: widget.isDarkMode
                                    ? Colors.cyanAccent
                                    : Colors.blue)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_uniqueSpeakers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text("No speakers available yet.",
                          style: TextStyle(
                              color: widget.isDarkMode
                                  ? Colors.white70
                                  : Colors.black54)),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _uniqueSpeakers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final name = _uniqueSpeakers[index];
                          final color = _colorForSpeaker(name);
                          final count = _messageCountForSpeaker(name);
                          final selected = _selectedSpeakerFilter == name;
                          return ListTile(
                            onTap: () {
                              setState(() {
                                _selectedSpeakerFilter = name;
                              });
                              Navigator.of(ctx).pop();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!_scrollController.hasClients) return;
                                for (var i = 0; i < _messages.length; i++) {
                                  if (_formatSpeakerName(
                                          (_messages[i]['user'] as String?) ??
                                              '') ==
                                      name) {
                                    final estimatedPos = (i * 90).toDouble();
                                    final target = min(
                                        _scrollController
                                            .position.maxScrollExtent,
                                        estimatedPos);
                                    try {
                                      _scrollController.animateTo(target,
                                          duration:
                                              const Duration(milliseconds: 420),
                                          curve: Curves.easeOut);
                                    } catch (_) {}
                                    break;
                                  }
                                }
                              });
                            },
                            leading: CircleAvatar(
                                backgroundColor: color,
                                child: Text(name.isNotEmpty ? name[0] : '?',
                                    style:
                                        const TextStyle(color: Colors.white))),
                            title: Text(name,
                                style: TextStyle(
                                    color: widget.isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w600)),
                            subtitle: Text(
                                "$count message${count == 1 ? '' : 's'}",
                                style: TextStyle(
                                    color: widget.isDarkMode
                                        ? Colors.white70
                                        : Colors.black54)),
                            trailing: selected
                                ? Icon(Icons.check_circle,
                                    color: widget.isDarkMode
                                        ? Colors.cyanAccent
                                        : Colors.blue)
                                : null,
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedSpeakerFilter = null;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text("Clear Filter"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
            message: 'History',
            verticalOffset: 30,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: widget.isDarkMode
                      ? [
                          Colors.grey.withOpacity(0.06),
                          Colors.grey.withOpacity(0.04)
                        ]
                      : [
                          Colors.white.withOpacity(0.02),
                          Colors.white.withOpacity(0.02)
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.history,
                  color: widget.isDarkMode
                      ? Colors.cyanAccent
                      : Colors.deepPurpleAccent,
                  size: 26,
                ),
                onPressed: _showMeetingHistory,
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
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _showSpeakersList,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.isDarkMode
                                ? Colors.black26
                                : Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: widget.isDarkMode
                                    ? Colors.white10
                                    : Colors.black12),
                            boxShadow: [
                              BoxShadow(
                                color: widget.isDarkMode
                                    ? Colors.black26
                                    : Colors.black12,
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person,
                                  size: 18,
                                  color: widget.isDarkMode
                                      ? Colors.cyanAccent
                                      : Colors.deepPurple),
                              const SizedBox(width: 8),
                              Text(
                                'Speakers: ${_uniqueSpeakers.length}',
                                style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_selectedSpeakerFilter != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.isDarkMode
                                        ? Colors.cyanAccent.withOpacity(0.12)
                                        : Colors.blue.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        _selectedSpeakerFilter!,
                                        style: TextStyle(
                                          color: widget.isDarkMode
                                              ? Colors.cyanAccent
                                              : Colors.blueAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _selectedSpeakerFilter = null;
                                          });
                                        },
                                        child: Icon(Icons.close,
                                            size: 16,
                                            color: widget.isDarkMode
                                                ? Colors.cyanAccent
                                                : Colors.blueAccent),
                                      )
                                    ],
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Icon(Icons.arrow_drop_down,
                                  color: widget.isDarkMode
                                      ? Colors.white70
                                      : Colors.black54),
                            ],
                          ),
                        ),
                      ),
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
                              itemCount: _messages.where((m) {
                                if (_selectedSpeakerFilter == null) return true;
                                final user = _formatSpeakerName(
                                    (m['user'] as String?) ?? '');
                                return user == _selectedSpeakerFilter;
                              }).length,
                              itemBuilder: (context, index) {
                                final filtered = _messages.where((m) {
                                  if (_selectedSpeakerFilter == null)
                                    return true;
                                  final user = _formatSpeakerName(
                                      (m['user'] as String?) ?? '');
                                  return user == _selectedSpeakerFilter;
                                }).toList();

                                final msg = filtered[index];
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
                                                widget.isDarkMode
                                                    ? 0.21
                                                    : 0.14),
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: const [
                                                    Icon(
                                                        Icons.volume_up_rounded,
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
              if (_showScrollDownBtn && _messages.isNotEmpty)
                Positioned(
                  bottom: 90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        _maybeScrollToBottom(
                            animate: true,
                            delay: const Duration(milliseconds: 40));
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
