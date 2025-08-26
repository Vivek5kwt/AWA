import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wave_blob/wave_blob.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/speaker/speaker_service.dart';

class AddContactScreen extends StatefulWidget {
  final String name;
  final String phoneNumber;
  final bool isDarkMode;

  const AddContactScreen({
    Key? key,
    required this.name,
    required this.phoneNumber,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen>
    with TickerProviderStateMixin {
  final List<String> _sentences = [
    "hello, how are you?",
    "What are you doing?",
    "having any plans for today?",
    "can you please repeat that",
    "i will call you later."
  ];
  int _currentIndex = 0;
  bool _isRecording = false;
  bool _showTryAgain = false;
  bool _isUploading = false;
  bool _showSuccess = false;
  double _amplitude = 1800;
  Timer? _ampTimer;
  Timer? _maxRecordTimer;
  double _progress = 0.0;
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  String? _currentRecordingPath;
  TextEditingController? _nameController;
  late final AnimationController _micPulse;
  late final AnimationController _checkBurst;
  late final Animation<double> _burstScale;
  List<bool> _wordVisible = [];
  final SpeakerService _speakerService = SpeakerService();
  bool _userStartedSpeaking = false;
  DateTime? _lastVoiceTime;
  bool _dialogActive = false;
  bool _showMicTutorial = false;
  bool _showRepeatTutorial = false;
  bool _repeatTutorialSeen = false;
  bool _showNameIntro = false;

  static const int silenceThresholdMs = 700;
  static const int ignoreInitialMs = 300;
  static const int maxRecordMs = 5000;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _speakerService.init();
    _loadTutorialFlags();

    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.9,
      upperBound: 1.1,
    )..addStatusListener((s) {
      if (s == AnimationStatus.completed) _micPulse.reverse();
      if (s == AnimationStatus.dismissed) _micPulse.forward();
    });
    _micPulse.forward();

    _checkBurst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _burstScale = Tween<double>(begin: 0, end: 2.0).animate(
      CurvedAnimation(parent: _checkBurst, curve: Curves.elasticOut),
    );

    _revealWords();
  }

  Future<void> _loadTutorialFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final micShown = prefs.getBool('add_contact_mic_tutorial_shown') ?? false;
    final repeatShown = prefs.getBool('add_contact_repeat_tutorial_shown') ?? false;
    final nameShown = prefs.getBool('add_contact_name_intro_shown') ?? false;
    if (mounted) {
      setState(() {
        _showMicTutorial = !micShown;
        _repeatTutorialSeen = repeatShown;
        _showNameIntro = !nameShown;
      });
    }
    if (!micShown) await prefs.setBool('add_contact_mic_tutorial_shown', true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nameShown) {
        _askForContactName();
      }
    });
  }

  void _revealWords() {
    final words = _sentences[_currentIndex].split(' ');
    _wordVisible = List<bool>.filled(words.length, false);
    for (var i = 0; i < words.length; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (!mounted) return;
        setState(() => _wordVisible[i] = true);
      });
    }
  }

  @override
  void dispose() {
    _ampTimer?.cancel();
    _maxRecordTimer?.cancel();
    _recorder.dispose();
    _speakerService.dispose();
    _micPulse.dispose();
    _checkBurst.dispose();
    _nameController?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!mounted) return;
    setState(() {
      _showTryAgain = false;
      _showSuccess = false;
      _progress = 0.0;
      _userStartedSpeaking = false;
      _lastVoiceTime = null;
    });

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      setState(() => _showTryAgain = true);
      return;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/sentence_${_currentIndex + 1}.wav';
    _currentRecordingPath = filePath;

    await _recorder.start(
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: filePath,
    );

    if (!mounted) return;
    setState(() => _isRecording = true);

    DateTime recordStart = DateTime.now();
    bool silenceDetected = false;

    _ampTimer = Timer.periodic(const Duration(milliseconds: 70), (_) async {
      if (!_isRecording) return;
      setState(() {
        _amplitude = 1800 + Random().nextInt(2200).toDouble();
      });

      double simulatedAmplitude = _amplitude;

      if (simulatedAmplitude > 2000) {
        _userStartedSpeaking = true;
        _lastVoiceTime = DateTime.now();
      }

      if (_userStartedSpeaking) {
        final now = DateTime.now();
        if (_lastVoiceTime != null &&
            now.difference(_lastVoiceTime!).inMilliseconds > silenceThresholdMs &&
            now.difference(recordStart).inMilliseconds > ignoreInitialMs) {
          silenceDetected = true;
        }
      }

      if (silenceDetected) {
        silenceDetected = false;
        await _stopRecording();
      }
    });
    _maxRecordTimer = Timer(Duration(milliseconds: maxRecordMs), () async {
      if (_isRecording) {
        await _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    _ampTimer?.cancel();
    _maxRecordTimer?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _onRecordingFinished();
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      ),
    );
  }
  Future<void> _askForContactName() async {
    _dialogActive = true;
    final isDark = widget.isDarkMode;
    final prefs = await SharedPreferences.getInstance();

    final enteredName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: isDark ? Color(0xFF232526) : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Close button with larger tap area
                  Positioned(
                    top: -16,
                    right: -16,
                    child: GestureDetector(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      behavior: HitTestBehavior.translucent,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.redAccent.withOpacity(0.9)
                                : Colors.grey.shade300,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Dialog content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header icon
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isDark
                                ? [Colors.cyanAccent, Colors.deepPurpleAccent]
                                : [Colors.deepPurple, Colors.cyan],
                          ),
                        ),
                        child: Icon(
                          Icons.contact_page_rounded,
                          size: 32,
                          color: isDark ? Colors.black87 : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Title
                      Text(
                        context.loc.registerSpeaker,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.cyanAccent : Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        context.loc.enterAFriendlyName,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // Name TextField (no labelText)
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: context.loc.hintName,
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey[500],
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade200,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            Navigator.of(dialogContext).pop(val.trim());
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      // Save & Continue button themed to app
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle, size: 20),
                          label:  Text(context.loc.saveContinue),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          onPressed: () {
                            final val = _nameController!.text.trim();
                            if (val.isEmpty) {
                              _showSnackbar(
                                  "Name cannot be empty", Colors.redAccent);
                              return;
                            }
                            Navigator.of(dialogContext).pop(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    _dialogActive = false;

    if (enteredName == null || enteredName.trim().isEmpty) {
      _nameController?.dispose();
      _nameController = null;
      if (mounted) context.pop();
      return;
    }
  }

  Future<bool> _isAudioValid(String path) async {
    try {
      final file = File(path);
      if (!(await file.exists())) return false;
      final bytes = await file.readAsBytes();
      if (bytes.length < 1200) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onRecordingFinished() async {
    if (!mounted) return;
    if (_currentRecordingPath != null &&
        File(_currentRecordingPath!).existsSync()) {
      final isValid = await _isAudioValid(_currentRecordingPath!);
      if (!isValid) {
        setState(() => _showTryAgain = true);
        _showSnackbar("Voice not clear or too quiet. Please speak clearly.", Colors.redAccent);
        return;
      }
      setState(() => _isUploading = true);
      await _registerSpeakerLocal(_currentRecordingPath!);
      if (!mounted) return;
      setState(() => _isUploading = false);
    } else {
      setState(() => _showTryAgain = true);
      _showSnackbar("No audio detected. Please try again.", Colors.redAccent);
    }
  }

  Future<void> _registerSpeakerLocal(String filePath) async {
    try {
      await _speakerService.enrollAppend(_nameController!.text, filePath);
      if (!mounted) return;
      setState(() => _showSuccess = true);
      _checkBurst.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      if (_currentIndex < _sentences.length - 1) {
        setState(() {
          _currentIndex++;
          _showSuccess = false;
          _progress = 0.0;
          _userStartedSpeaking = false;
        });
        _revealWords();
      } else {
        _showSnackbar(
          "${_nameController!.text.trim()} ${context.loc.addedSuccessFully}",
          Colors.greenAccent,
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        context.pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _showTryAgain = true);
      _showSnackbar("Error saving sample. Please try again.", Colors.redAccent);
    }
  }

  void _onMicTap() {
    if (!_repeatTutorialSeen) {
      setState(() => _showRepeatTutorial = true);
      _repeatTutorialSeen = true;
      SharedPreferences.getInstance().then((p) => p.setBool('add_contact_repeat_tutorial_shown', true));
      return;
    }
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  Widget _buildTutorialOverlay(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showMicTutorial = false),
        child: Container(
          color: Colors.black87.withOpacity(0.7),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white24,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 60),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    context.loc.tapMicToStart,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    context.loc.tapMicToRecord,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRepeatTutorialOverlay(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showRepeatTutorial = false),
        child: Container(
          color: Colors.black87.withOpacity(0.7),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.record_voice_over, color: Colors.white, size: 60),
                const SizedBox(height: 16),
                Text(
                  context.loc.repeatSentenceHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  context.loc.tapMicToRecord,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _hideNameIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('add_contact_name_intro_shown', true);
    if (!mounted) return;
    setState(() => _showNameIntro = false);
    _askForContactName();
  }

  Widget _buildNameIntroOverlay(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _hideNameIntro,
        child: Container(
          color: Colors.black87.withOpacity(0.7),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                Text(
                  context.loc.enterAFriendlyName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  context.loc.nameFieldIntro,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = _sentences[_currentIndex].split(' ');
    final size = MediaQuery.of(context).size;
    final gradientColors = widget.isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    final containerColor = widget.isDarkMode
        ? Colors.white.withOpacity(0.09)
        : Colors.white.withOpacity(0.13);
    final borderColor = widget.isDarkMode
        ? Colors.blueGrey.shade700.withOpacity(0.28)
        : Colors.pinkAccent.withOpacity(0.8);
    final progressBarBg = widget.isDarkMode
        ? Colors.blueGrey.shade900.withOpacity(0.14)
        : Colors.purple.shade200.withOpacity(0.16);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                if (_dialogActive) {
                  Navigator.of(context).pop();
                } else {
                  context.pop();
                }
              },
              tooltip: "Back",
            ),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  _ProgressDots(
                    current: _currentIndex,
                    total: _sentences.length,
                    isDarkMode: widget.isDarkMode,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "${context.loc.youAreOnQuestion} ${_currentIndex + 1} ${context.loc.of_text} ${_sentences.length}",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: size.width * 0.93,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: containerColor,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _sentences[_currentIndex],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: 0.2,
                        shadows: [Shadow(color: Colors.black12, blurRadius: 5)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedOpacity(
                            opacity: _isRecording ? 1 : 0.19,
                            duration: const Duration(milliseconds: 200),
                            child: SizedBox(
                              width: size.width * 0.6,
                              height: size.width * 0.6,
                              child: WaveBlob(
                                amplitude: _isRecording ? _amplitude : 1800,
                                autoScale: true,
                                blobCount: 2,
                                scale: 1.0,
                                centerCircle: true,
                                overCircle: true,
                                circleColors: widget.isDarkMode
                                    ? [const Color(0xFF5CE1E6), const Color(0xFF1F1C2C)]
                                    : [const Color(0xFF30DCFF), const Color(0xFF6C7BFF)],
                                child: const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          _showSuccess
                              ? ScaleTransition(
                            scale: _burstScale,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded,
                                    color: Colors.greenAccent.shade400,
                                    size: 90),
                                const SizedBox(height: 8),
                                ShaderMask(
                                  shaderCallback: (Rect bounds) {
                                    return const LinearGradient(
                                      colors: [
                                        Colors.greenAccent,
                                        Colors.white,
                                        Colors.greenAccent
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ).createShader(bounds);
                                  },
                                  child:  Text(
                                    context.loc.voiceMatched,
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          )
                              : ScaleTransition(
                            scale: _micPulse,
                            child: GestureDetector(
                              onTap: _onMicTap,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: _isRecording
                                        ? [Colors.redAccent, Colors.deepOrange]
                                        : [
                                      widget.isDarkMode
                                          ? Colors.white10
                                          : Colors.white24,
                                      widget.isDarkMode
                                          ? Colors.white24
                                          : Colors.white38
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black45, blurRadius: 8),
                                    if (_isRecording)
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(0.5),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                  ],
                                ),
                                child: Icon(
                                  _isRecording ? Icons.stop : Icons.mic,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: LinearProgressIndicator(
                      value: _isRecording ? null : (_currentIndex + 1) / _sentences.length,
                      minHeight: 6.5,
                      backgroundColor: progressBarBg,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isDarkMode ? Colors.cyanAccent : Colors.pinkAccent,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  Container(
                    width: size.width * 0.90,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: containerColor,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: borderColor,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: List.generate(words.length, (i) {
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: _wordVisible[i] ? 1 : 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              words[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 14, top: 8),
                      child:Text(
                        _isRecording
                            ? context.loc.recordingSpeakClearly
                            : context.loc.tapMicToRecord,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.83),
                          fontSize: 16,
                        ),
                      )

                  ),
                  if (_showTryAgain)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        context.loc.voiceNotClear,
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: Colors.purpleAccent),
                    ),
                ],
              ),
            ),
            if (_showNameIntro) _buildNameIntroOverlay(context),
            if (_showRepeatTutorial) _buildRepeatTutorialOverlay(context),
            if (_showMicTutorial) _buildTutorialOverlay(context),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  final bool isDarkMode;
  const _ProgressDots({
    required this.current,
    required this.total,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final bool selected = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: selected ? 34 : 13,
          height: selected ? 34 : 13,
          decoration: BoxDecoration(
            color: selected
                ? (isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent)
                : (isDarkMode
                ? Colors.blueGrey.shade800
                : Colors.deepPurple.shade200),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: selected
              ? Text(
            "Q${i + 1}",
            style: TextStyle(
                color: isDarkMode ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          )
              : null,
        );
      }),
    );
  }
}