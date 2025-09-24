import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wave_blob/wave_blob.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/http_service.dart';

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
    "The quick brown fox jumps over the lazy dog. This voice sample will be used to register your speech profile. Speak naturally and clearly in your normal tone.",
  ];
  int _currentIndex = 0;
  bool _isRecording = false;
  bool _showTryAgain = false;
  bool _isUploading = false;
  bool _showSuccess = false;
  double _amplitude = 1800;
  Timer? _ampTimer;
  Timer? _maxRecordTimer;
  Timer? _recordTimer;
  double _progress = 0.0;
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  String? _currentRecordingPath;
  TextEditingController? _nameController;
  late final AnimationController _micPulse;
  late final AnimationController _checkBurst;
  late final Animation<double> _burstScale;
  List<bool> _wordVisible = [];
  String _email = '';
  bool _userStartedSpeaking = false;
  DateTime? _lastVoiceTime;
  bool _dialogActive = false;
  bool _showMicTutorial = false;
  bool _showRepeatTutorial = false;
  bool _repeatTutorialSeen = false;
  bool _showNameIntro = false;

  bool _registrationLoading = false;
  String? _registrationTitle;
  String? _registrationText;
  String? _registrationError;
  String? _serverResponseMessage;
  bool _serverResponseIsError = false;
  bool _manualStopRequested = false;
  bool _silenceHintShown = false;

  static const int silenceThresholdMs = 700;
  static const int ignoreInitialMs = 300;
  static const int maxRecordMs = 5000000;
  DateTime? _recordingStartTime;
  int _recordSeconds = 0;
  bool _showTips = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _loadStoredEmail();
    _loadTutorialFlags();

    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.94,
      upperBound: 1.08,
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      () async {
        await _fetchRegistrationText();
        if (_nameController!.text.trim().isEmpty) {
          await _askForContactName();
        }
      }();
    });
  }

  Future<void> _loadStoredEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _email = prefs.getString('email') ?? '';
    });
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
  }

  void _revealWords() {
    final words = _sentences[_currentIndex].split(' ');
    _wordVisible = List<bool>.filled(words.length, true);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ampTimer?.cancel();
    _maxRecordTimer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
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
      _serverResponseMessage = null;
      _serverResponseIsError = false;
      _recordSeconds = 0;
      _showMicTutorial = false;
      _showRepeatTutorial = false;
      _manualStopRequested = false;
      _silenceHintShown = false;
    });

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      setState(() => _showTryAgain = true);
      _showSnackbar(context.loc.permissionRequiredMic, Colors.redAccent);
      return;
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/passage_${_currentIndex + 1}_$timestamp.m4a';
    _currentRecordingPath = filePath;

    try {
      _micPulse.duration = const Duration(milliseconds: 600);
      _micPulse.forward(from: 0.4);
    } catch (_) {}

    await _recorder.start(
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordSeconds = 0;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordSeconds++;
      });
    });

    DateTime recordStart = DateTime.now();

    double phase = 0.0;
    _ampTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!_isRecording) return;

      phase += 0.3;
      final base = 1700 + 300 * sin(phase) + Random().nextDouble() * 220;
      setState(() {
        _amplitude = base.clamp(1200, 4200);
      });

      double simulatedAmplitude = _amplitude;

      if (simulatedAmplitude > 2000) {
        _userStartedSpeaking = true;
        _lastVoiceTime = DateTime.now();
        _silenceHintShown = false;
      }

    });

    _maxRecordTimer = Timer(Duration(milliseconds: maxRecordMs), () async {
      if (_isRecording) {
        await _stopRecording();
        if (mounted) {
          setState(() => _showTryAgain = true);
          _showSnackbar(
            "Recording stopped automatically (time limit). Please tap mic to record and tap again to stop when done.",
            Colors.orangeAccent,
          );
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    _ampTimer?.cancel();
    _maxRecordTimer?.cancel();
    _recordTimer?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    try {
      _micPulse.duration = const Duration(milliseconds: 900);
      _micPulse.forward(from: 0.0);
    } catch (_) {}
    if (_manualStopRequested) {
      await _onRecordingFinished();
    } else {
      if (mounted) {
        setState(() => _showTryAgain = true);
      }
    }
    _manualStopRequested = false;
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
          backgroundColor: isDark ? const Color(0xFF121218) : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -14,
                    right: -14,
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
                                ? Colors.redAccent.withOpacity(0.95)
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

                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isDark
                                ? [Colors.cyanAccent, Colors.deepPurpleAccent]
                                : [Colors.deepPurple, Colors.cyan],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: Icon(
                          Icons.contact_page_rounded,
                          size: 32,
                          color: isDark ? Colors.black87 : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        context.loc.registerSpeaker,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.cyanAccent : Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        context.loc.enterAFriendlyName,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 14),

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
                              ? Colors.white.withOpacity(0.03)
                              : Colors.grey.shade100,
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
                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle, size: 20),
                          label: Text(context.loc.saveContinue),
                          style: ElevatedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
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
      if (mounted) context.pop();
      return;
    }
    if (mounted) {
      setState(() {
        _nameController?.text = enteredName.trim();
      });
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
        _showSnackbar(
            "Voice not clear or too quiet. Please speak clearly.",
            Colors.redAccent);
        return;
      }
      setState(() => _isUploading = true);
      await _registerSpeakerAPI(_currentRecordingPath!);
      if (!mounted) return;
      setState(() => _isUploading = false);
    } else {
      setState(() => _showTryAgain = true);
      _showSnackbar("No audio detected. Please try again.", Colors.redAccent);
    }
  }

  Future<void> _registerSpeakerAPI(String filePath) async {
    try {
      final base = ApiConstants.baseUrl;
      final uri = Uri.parse('$base/api/register-speaker');
      final req = http.MultipartRequest('POST', uri)
        ..fields['name'] = _nameController!.text.trim()
        ..fields['sentence_no'] = (_currentIndex + 1).toString()
        ..fields['email'] = _email
        ..fields['phone'] = widget.phoneNumber;
      req.files.add(await http.MultipartFile.fromPath(
        'audio_file',
        filePath,
        contentType: MediaType('audio', 'm4a'),
      ));

      final streamedResponse = await req.send();
      final respBytes = await streamedResponse.stream.toBytes();
      final respString = utf8.decode(respBytes);
      if (!mounted) return;

      String message;
      bool success = false;
      try {
        final parsed = jsonDecode(respString);
        if (parsed is Map && parsed.isNotEmpty) {
          message = (parsed['message'] ??
                  parsed['detail'] ??
                  parsed['msg'] ??
                  parsed['data']?['message'] ??
                  parsed['status']?.toString() ??
                  respString)
              .toString();
        } else {
          message = respString;
        }
      } catch (_) {
        message = respString;
      }

      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 201) {
        success = true;
      } else {
        success = false;
      }

      if (success) {
        setState(() {
          _showSuccess = true;
          _serverResponseMessage = message.isNotEmpty ? message : "Registered successfully.";
          _serverResponseIsError = false;
        });
        _checkBurst.forward(from: 0);
        _showSnackbar(_serverResponseMessage!, Colors.green);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        context.pop(true);
      } else {
        setState(() {
          _showTryAgain = true;
          _serverResponseMessage = message.isNotEmpty ? message : "Server error. Please try again.";
          _serverResponseIsError = true;
        });
        _showSnackbar(_serverResponseMessage!, Colors.redAccent);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showTryAgain = true;
        _serverResponseMessage = "Network error. Please try again.";
        _serverResponseIsError = true;
      });
      _showSnackbar(_serverResponseMessage!, Colors.redAccent);
    }
  }

  void _onMicTap() {
    if (_isRecording) {
      _manualStopRequested = true;
      _stopRecording();
    } else {
      setState(() {
        _showMicTutorial = false;
        _showRepeatTutorial = false;
      });
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
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Colors.white24, Colors.transparent],
                      center: Alignment.center,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 8))
                    ],
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 64),
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
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => setState(() => _showMicTutorial = false),
                  child: Text(/*context.loc.gotIt ??*/ 'Got it'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.deepPurpleAccent,
                  ),
                )
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
                  style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => setState(() => _showRepeatTutorial = false),
                  child: Text(/*context.loc.gotIt ?? */'Got it'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.deepPurpleAccent,
                  ),
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
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _hideNameIntro,
                  child: Text(/*context.loc.gotIt ??*/ 'Got it'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.deepPurpleAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicButton(double size) {
    final gradientColors = _isRecording
        ? [Colors.redAccent.shade400, Colors.deepOrangeAccent.shade200]
        : (widget.isDarkMode
            ? [const Color(0xFF7B61FF), const Color(0xFF00E5FF)]
            : [const Color(0xFF6A4DFF), const Color(0xFF00E5FF)]);
    return ScaleTransition(
      scale: _micPulse,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: _onMicTap,
          customBorder: const CircleBorder(),
          splashFactory: InkRipple.splashFactory,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(color: Colors.black45, blurRadius: 18, offset: const Offset(0, 10)),
                if (_isRecording)
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.32),
                    blurRadius: 48,
                    spreadRadius: 8,
                  ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: size * (_isRecording ? 0.82 : 0.76),
                  height: size * (_isRecording ? 0.82 : 0.76),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(_isRecording ? 0.06 : 0.08),
                  ),
                ),
                Center(
                  child: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic,
                    color: Colors.white,
                    size: size * 0.46,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _fetchRegistrationText() async {
    if (!mounted) return;
    setState(() {
      _registrationLoading = true;
      _registrationError = null;
    });

    try {
      Uri uri;
      try {
        final endpoint = ApiConstants.getRegistration;
        uri = Uri.parse(endpoint);
      } catch (_) {
        final base = ApiConstants.baseUrl;
        uri = Uri.parse('$base/api/registration-text');
      }

      final response = await http.get(uri);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = response.body.trim();
        try {
          final parsed = body.startsWith('{') ? jsonDecode(body) : null;
          if (parsed is Map && parsed.isNotEmpty) {
            final title = (parsed['title'] ?? parsed['instructions'] ?? parsed['name'])?.toString();
            final text = (parsed['text'] ?? parsed['registration_text'] ?? parsed['body'])?.toString();
            setState(() {
              _registrationTitle = (title != null && title.isNotEmpty) ? title : null;
              _registrationText = (text != null && text.isNotEmpty) ? text : body;
            });
          } else {
            setState(() {
              _registrationTitle = null;
              _registrationText = body;
            });
          }
        } catch (_) {
          setState(() {
            _registrationTitle = null;
            _registrationText = body;
          });
        }
      } else {
        setState(() {
          _registrationError = 'Failed to load instructions';
        });
      }
    } catch (e) {
      setState(() {
        _registrationError = 'Network error while fetching instructions';
      });
    } finally {
      if (!mounted) return;
      setState(() => _registrationLoading = false);
    }
  }

  String _formatDuration(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _buildInstructionPanel(double width) {
    final theme = Theme.of(context);
    final primaryGradient = widget.isDarkMode
        ? const LinearGradient(colors: [Color(0xFF6A4DFF), Color(0xFF00E5FF)])
        : const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]);
    final accent = widget.isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            gradient: widget.isDarkMode
                ? LinearGradient(colors: [Colors.white.withOpacity(0.02), Colors.white.withOpacity(0.01)])
                : LinearGradient(colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.02)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isRecording
                      ? const LinearGradient(colors: [Colors.redAccent, Colors.deepOrangeAccent])
                      : primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    transitionBuilder: (child, anim) {
                      return ScaleTransition(scale: anim, child: RotationTransition(turns: anim, child: child));
                    },
                    child: _isRecording
                        ? const Icon(Icons.mic, key: ValueKey('mic'), color: Colors.white, size: 28)
                        : const Icon(Icons.lightbulb, key: ValueKey('bulb'), color: Colors.white, size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRecording ? context.loc.recordingSpeakClearly : "Ready to capture your voice",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.98),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRecording
                          ? "Recording... Speak clearly and naturally. Tap mic to stop and submit."
                          : "Tap the mic and read the passage above in a natural tone. Keep device close and avoid background noise.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13.6,
                        height: 1.28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() => _showTips = !_showTips),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showTips ? Icons.expand_less : Icons.lightbulb_outlined,
                            color: accent.withOpacity(0.95),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showTips ? "Hide tips" : "Quick tips",
                            style: TextStyle(
                              color: accent.withOpacity(0.95),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),

        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: widget.isDarkMode ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TipChip(
                        icon: Icons.volume_up,
                        label: "Speak at a normal volume",
                        isDark: widget.isDarkMode,
                      ),
                      _TipChip(
                        icon: Icons.phone_android,
                        label: "Hold phone ~20–30 cm from your mouth",
                        isDark: widget.isDarkMode,
                      ),
                      _TipChip(
                        icon: Icons.noise_control_off,
                        label: "Avoid background noise",
                        isDark: widget.isDarkMode,
                      ),
                      _TipChip(
                        icon: Icons.repeat,
                        label: "If unsure, re-record",
                        isDark: widget.isDarkMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          crossFadeState: _showTips ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 320),
        ),

        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          child: _showTryAgain
              ? Container(
                  key: const ValueKey('tryAgainCard'),
                  width: width,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.48),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.12)),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 6))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent.withOpacity(0.18),
                            ),
                            child: const Center(child: Icon(Icons.error_outline, color: Colors.redAccent)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.loc.voiceNotClear,
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _serverResponseMessage ??
                                      "Voice unclear or too quiet. Try again keeping steady distance and speak clearly.",
                                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13.2),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showTryAgain = false;
                                  _showSuccess = false;
                                });
                                _startRecording();
                              },
                              icon: const Icon(Icons.replay),
                              label: Text(/*context.loc.tryAgain ??*/ 'Try again'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Colors.deepPurpleAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() => _showTryAgain = false);
                              },
                              child: Text(/*context.loc.dismiss ?? */'Dismiss'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: Colors.white.withOpacity(0.08)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = _sentences[_currentIndex].split(' ');
    final size = MediaQuery.of(context).size;
    final gradientColors = widget.isDarkMode
        ? [const Color(0xFF0F1724), const Color(0xFF0F1020), const Color(0xFF071229)]
        : [const Color(0xFF56CCF2), const Color(0x2F80ED), const Color(0xFFFFD3A5)];

    final containerColor = widget.isDarkMode
        ? Colors.white.withOpacity(0.04)
        : Colors.white.withOpacity(0.14);
    final borderColor = widget.isDarkMode
        ? Colors.blueGrey.shade700.withOpacity(0.18)
        : Colors.pinkAccent.withOpacity(0.18);
    final progressBarBg = widget.isDarkMode
        ? Colors.blueGrey.shade900.withOpacity(0.12)
        : Colors.purple.shade200.withOpacity(0.10);

    final middleBlobHeight = max(260.0, size.height * 0.36);

    final topInstruction = _registrationTitle ?? "Voice Registration";
    final topSubtitle = _registrationTitle == null
        ? "Tap the mic and read the passage below in a natural tone."
        : null;

    final passageText = _registrationText ?? _sentences[_currentIndex];

    final micSize = min(150.0, size.width * 0.34);

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
                ? Colors.white.withOpacity(0.04)
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
        actions: [
          IconButton(
            tooltip: /*context.loc.editName ?? */'Edit name',
            icon: Icon(Icons.edit, color: widget.isDarkMode ? Colors.white70 : Colors.black87),
            onPressed: () {
              _askForContactName();
            },
          ),
          if (widget.phoneNumber.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(
                  widget.phoneNumber,
                  style: TextStyle(
                    color: widget.isDarkMode ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDarkMode
                ? [const Color(0xFF0F1724), const Color(0xFF071229)]
                : [const Color(0xFF56CCF2), const Color(0xFF2F80ED), const Color(0xFFFFD3A5)],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      _ProgressDots(
                        current: _currentIndex,
                        total: _sentences.length,
                        isDarkMode: widget.isDarkMode,
                      ),
                      const SizedBox(height: 10),

                      Column(
                        children: [
                          Text(
                            topInstruction,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.98),
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                              letterSpacing: 0.6,
                              shadows: const [
                                Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          if (_nameController != null && _nameController!.text.trim().isNotEmpty)
                            Text(
                              "Speaker: ${_nameController!.text.trim()}",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (topSubtitle != null) const SizedBox(height: 6),
                          if (topSubtitle != null)
                            Text(
                              topSubtitle!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 15.0,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        child: Container(
                          key: ValueKey(passageText),
                          width: size.width * 0.94,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                          decoration: BoxDecoration(
                            gradient: widget.isDarkMode
                                ? LinearGradient(
                                    colors: [Colors.white.withOpacity(0.03), Colors.white.withOpacity(0.02)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : LinearGradient(
                                    colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.06)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: _registrationLoading
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 6),
                                    const CircularProgressIndicator(color: Colors.white70),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Loading...',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                )
                              : _registrationError != null
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Instructions unavailable',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _registrationError!,
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 13,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          margin: const EdgeInsets.only(right: 12, top: 2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: widget.isDarkMode
                                                  ? [Colors.cyanAccent, Colors.deepPurpleAccent]
                                                  : [Colors.deepPurple, Colors.cyan],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.text_snippet_rounded,
                                            size: 22,
                                            color: widget.isDarkMode ? Colors.black87 : Colors.white,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            passageText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 17,
                                              letterSpacing: 0.1,
                                              height: 1.45,
                                              shadows: [Shadow(color: Colors.black12, blurRadius: 4)],
                                            ),
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                      ],
                                    ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      SizedBox(
                        height: middleBlobHeight,
                        child: Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedOpacity(
                                opacity: _isRecording ? 1 : 0.40,
                                duration: const Duration(milliseconds: 240),
                                child: SizedBox(
                                  width: min(size.width * 0.78, 520),
                                  height: min(size.width * 0.78, 520),
                                  child: WaveBlob(
                                    amplitude: _isRecording ? _amplitude : 1500,
                                    autoScale: true,
                                    blobCount: 3,
                                    scale: 1.06,
                                    centerCircle: true,
                                    overCircle: true,
                                    circleColors: widget.isDarkMode
                                        ? [const Color(0xFF5CE1E6), const Color(0xFF1F1C2C)]
                                        : [const Color(0xFF50D3FF), const Color(0xFF9B65FF)],
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                              ),

                              if (_showSuccess)
                                ScaleTransition(
                                  scale: _burstScale,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded,
                                          color: Colors.greenAccent.shade400,
                                          size: 110),
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
                                        child: Text(
                                          context.loc.voiceMatched,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMicButton(micSize),
                                    const SizedBox(height: 12),
                                    AnimatedOpacity(
                                      duration: const Duration(milliseconds: 300),
                                      opacity: _isRecording ? 1 : 0.95,
                                      child: Text(
                                        _isRecording ? context.loc.recordingSpeakClearly : context.loc.tapMicToRecord,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.94),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_isRecording)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.timer, color: Colors.white70, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDuration(_recordSeconds),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 12),
                                            GestureDetector(
                                              onTap: () {
                                                _manualStopRequested = true;
                                                _stopRecording();
                                              },
                                              child: Row(
                                                children: const [
                                                  Icon(Icons.stop_circle, color: Colors.redAccent, size: 18),
                                                  SizedBox(width: 6),
                                                  Text('Stop', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                                                ],
                                              ),
                                            )
                                          ],
                                        ),
                                      )
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: _isRecording ? null : 1.0,
                            minHeight: 9.5,
                            backgroundColor: progressBarBg,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent,
                            ),
                          ),
                        ),
                      ),

                      if (_serverResponseMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _serverResponseIsError ? Colors.redAccent.withOpacity(0.12) : Colors.greenAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _serverResponseIsError ? Colors.redAccent.withOpacity(0.65) : Colors.greenAccent.withOpacity(0.65),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              _serverResponseMessage!,
                              style: TextStyle(
                                color: _serverResponseIsError ? Colors.redAccent.shade200 : Colors.green.shade900,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: _buildInstructionPanel(size.width * 0.92),
                      ),

                      if (_isUploading)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(color: Colors.purpleAccent),
                        ),

                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),

            if (_showNameIntro) _buildNameIntroOverlay(context),
            if (_showRepeatTutorial) _buildRepeatTutorialOverlay(context),
            if (_showMicTutorial) _buildTutorialOverlay(context),

            if (_isRecording)
              Positioned(
                bottom: 110,
                left: 24,
                right: 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(color: Colors.black45, blurRadius: 10, offset: const Offset(0, 6))
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mic, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Recording started",
                                style: TextStyle(color: Colors.white.withOpacity(0.96), fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Please read the passage aloud. Tap mic to stop.",
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _formatDuration(_recordSeconds),
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),

            if (_registrationLoading)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.black87.withOpacity(0.25),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.4,
                                  ),
                                ),
                                SizedBox(width: 12),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Loading instructions...',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
          width: selected ? 40 : 12,
          height: selected ? 40 : 12,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: isDarkMode
                        ? [Colors.cyanAccent, Colors.deepPurpleAccent]
                        : [Colors.deepPurpleAccent, Colors.pinkAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                : null,
            color: selected
                ? null
                : (isDarkMode
                    ? Colors.blueGrey.shade800
                    : Colors.deepPurple.shade100),
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: selected
              ? Icon(
                  Icons.mic,
                  size: 16,
                  color: isDarkMode ? Colors.black : Colors.white,
                )
              : null,
        );
      }),
    );
  }
}

class _TipChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _TipChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.02)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          )
        ],
      ),
    );
  }
}
