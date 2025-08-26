import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/speaker/speaker_service.dart';

/// Identification UI (WAV 16k mono) with guided 5-phrase enrollment.
/// Automatically falls back to a local heuristic if the ONNX model is absent.
class SpeakerScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isDarkMode;

  const SpeakerScreen({
    super.key,
    required this.phoneNumber,
    this.isDarkMode = false,
  });

  @override
  State<SpeakerScreen> createState() => _SpeakerScreenState();
}

class _SpeakerScreenState extends State<SpeakerScreen> {
  final SpeakerService _service = SpeakerService();
  final AudioRecorder _recorder = AudioRecorder();

  static const List<String> _prompts = [
    "hello, how are you?",
    "What are you doing?",
    "having any plans for today?",
    "can you please repeat that",
    "i will call you later.",
  ];

  bool _isRecording = false;

  bool _guidedActive = false;
  int _promptIndex = 0;
  String? _currentEnrollName;

  String? _identifiedId;
  Map<String, int> _registered = {};

  static bool _modeToastShown = false;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _service.init();
    await _refreshRegisteredList();
    if (!mounted) return;

    if (!_modeToastShown) {
      _modeToastShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _toast(_service.isFallback
            ? 'Speaker model not found — using local fallback.'
            : 'High-accuracy speaker model loaded.');
      });
    }
  }

  Future<void> _refreshRegisteredList() async {
    final map = await _service.listRegisteredWithCounts();
    if (mounted) setState(() => _registered = map);
  }

  @override
  void dispose() {
    _recorder.dispose();
    _service.dispose();
    super.dispose();
  }

  // ---------- Recording helpers ----------

  Future<String> _nextFilePath({String suffix = ''}) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suf = suffix.isEmpty ? '' : '_$suffix';
    return '${dir.path}/rec_${ts}${suf}.wav';
  }

  Future<void> _startRecording() async {
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _toast('Microphone permission denied');
        return;
      }

      final path = await _nextFilePath();

      const config = RecordConfig(
        encoder: AudioEncoder.wav, // PCM 16-bit WAV
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      );

      await _recorder.start(config, path: path);
      setState(() => _isRecording = true);
    } catch (e) {
      _toast('Failed to start recording: $e');
    }
  }

  Future<String?> _stop() async {
    try {
      final isRec = await _recorder.isRecording();
      if (!isRec) return null;
      return await _recorder.stop(); // recorded file path
    } catch (e) {
      _toast('Failed to stop recording: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  // ---------- Identification flow ----------

  Future<void> _stopAndIdentify() async {
    if (_registered.isEmpty) {
      _toast('No users enrolled yet in this mode. Please run guided enrollment.');
      return;
    }
    final path = await _stop();
    if (path != null && await File(path).exists()) {
      try {
        final id = await _service.identify(
          path,
          threshold: 0.74,
          secondBestMargin: 0.035,
        );
        if (!mounted) return;
        setState(() => _identifiedId = id);
        if (id == null) {
          _toast('No confident match');
        } else {
          _toast('Matched: $id');
        }
      } catch (e) {
        _toast(e.toString()); // e.g., "Please speak clearly for at least 1.2 seconds."
      }
    } else {
      _toast('No recording found to identify');
    }
  }

  // ---------- Guided enrollment ----------

  Future<void> _beginGuidedEnrollment() async {
    final name = await _askForName(context);
    if (name == null || name.trim().isEmpty) {
      _toast('Name is required for enrollment');
      return;
    }
    setState(() {
      _currentEnrollName = name.trim();
      _guidedActive = true;
      _promptIndex = 0;
      _identifiedId = null;
    });
    _toast('Enrollment started for $_currentEnrollName');
  }

  Future<void> _cancelGuidedEnrollment() async {
    if (_isRecording) {
      await _stop(); // discard current file
    }
    setState(() {
      _guidedActive = false;
      _currentEnrollName = null;
      _promptIndex = 0;
    });
    _toast('Enrollment cancelled');
  }

  Future<void> _recordCurrentPrompt() async {
    if (!_guidedActive) return;
    await _startRecording();
    if (mounted) {
      _toast('Recording: "${_prompts[_promptIndex]}"');
    }
  }

  Future<void> _stopAndSaveCurrentPrompt() async {
    if (!_guidedActive) return;
    final path = await _stop();
    if (path == null || !await File(path).exists()) {
      _toast('No audio to save for this prompt');
      return;
    }
    try {
      final savedName = await _service.enrollAppend(_currentEnrollName!, path);
      if (!mounted) return;
      setState(() => _identifiedId = savedName);
      await _refreshRegisteredList();

      if (_promptIndex + 1 < _prompts.length) {
        setState(() => _promptIndex += 1);
        _toast('Saved. Next: "${_prompts[_promptIndex]}"');
      } else {
        setState(() {
          _guidedActive = false;
          _currentEnrollName = null;
          _promptIndex = 0;
        });
        _toast('Enrollment complete. You can add more samples later if needed.');
      }
    } catch (e) {
      _toast('Failed to save sample: $e');
    }
  }

  // ---------- Dialogs & toasts ----------

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _askForName(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Enter speaker name'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'e.g., Vivek'),
            onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final bg = widget.isDarkMode ? Colors.black : Colors.white;
    final totalUsers = _registered.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaker Identification'),
        actions: [
          IconButton(
            tooltip: 'Clear all users',
            onPressed: totalUsers == 0
                ? null
                : () async {
                    final yes =
                        await _confirm(context, 'Clear all enrolled users?');
                    if (yes == true) {
                      await _service.clearAll();
                      await _refreshRegisteredList();
                      setState(() {
                        _identifiedId = null;
                      });
                      _toast('All users cleared');
                    }
                  },
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _registered.isEmpty
              ? Text(
                  'No users enrolled yet.',
                  style: TextStyle(color: textColor.withOpacity(0.8)),
                )
              : ListView.separated(
                  itemCount: _registered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final name = _registered.keys.elementAt(i);
                    final count = _registered[name] ?? 0;
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(name, style: TextStyle(color: textColor)),
                      subtitle: Text(
                        '$count sample${count == 1 ? '' : 's'}',
                        style: TextStyle(color: textColor.withOpacity(0.7)),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );
  }
}
