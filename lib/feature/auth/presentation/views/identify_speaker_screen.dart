import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/speaker/speaker_service.dart';

/// Identification UI (WAV 16k mono) with guided 5-phrase enrollment.
/// Now shows ranked candidates with confidence and highlights highest match.
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

  /// Confidence threshold (0..1) to accept a match.
  static const double _threshold = 0.74;

  bool _isRecording = false;

  bool _guidedActive = false;
  int _promptIndex = 0;
  String? _currentEnrollName;

  String? _identifiedId;
  Map<String, int> _registered = {};

  /// Ranked candidates from the last identification attempt.
  List<_Candidate> _candidates = [];

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

  // ---------- Identification flow (with ranked results) ----------

  Future<void> _stopAndIdentify() async {
    if (_registered.isEmpty) {
      _toast('No users enrolled yet in this mode. Please run guided enrollment.');
      return;
    }
    final path = await _stop();
    if (path == null || !await File(path).exists()) {
      _toast('No recording found to identify');
      return;
    }

    // First, try a dynamic call to a richer API if your SpeakerService provides it:
    //   identifyScores(path, {topK: 5, includeBelowThreshold: true}) -> List<Map{id, score}>
    try {
      final dynamic dynSvc = _service;
      final dynamic res = await dynSvc.identifyScores(
        path,
        topK: 5,
        includeBelowThreshold: true,
      );

      final parsed = _parseCandidates(res);
      parsed.sort((a, b) => b.score.compareTo(a.score));

      if (!mounted) return;

      String? topId;
      if (parsed.isNotEmpty && parsed.first.score >= _threshold) {
        topId = parsed.first.id;
      } else {
        topId = null;
      }

      setState(() {
        _candidates = parsed;
        _identifiedId = topId;
      });

      if (_candidates.isEmpty) {
        _toast('No candidates returned.');
      } else if (topId == null) {
        final top = _candidates.first;
        _toast('Closest: ${top.id} (${(top.score * 100).toStringAsFixed(1)}%), below threshold');
      } else {
        final top = _candidates.first;
        _toast('Matched: ${top.id} (${(top.score * 100).toStringAsFixed(1)}%)');
      }
      return;
    } catch (_) {
      // If the rich API is unavailable, fall back to the existing simple identify().
      // (Catches NoSuchMethodError or any service error and just falls back.)
    }

    try {
      final id = await _service.identify(
        path,
        threshold: _threshold,
        secondBestMargin: 0.035,
      );
      if (!mounted) return;
      setState(() {
        _identifiedId = id;
        _candidates = []; // no detailed scores from simple API
      });
      if (id == null) {
        _toast('No confident match');
      } else {
        _toast('Matched: $id');
      }
    } catch (e) {
      _toast(e.toString()); // e.g., "Please speak clearly for at least 1.2 seconds."
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
      _candidates = [];
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
      setState(() {
        _identifiedId = savedName;
        _candidates = [];
      });
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final bg = widget.isDarkMode ? Colors.black : Colors.white;
    final totalUsers = _registered.length;

    final headline = (() {
      if (_candidates.isNotEmpty) {
        final top = _candidates.first;
        final pct = (top.score * 100).toStringAsFixed(1);
        final ok = top.score >= _threshold;
        return ok
            ? 'Matched: ${top.id} ($pct%)'
            : 'Closest (below threshold): ${top.id} ($pct%)';
      }
      return _identifiedId == null
          ? 'Unknown speaker'
          : 'Matched/Enrolled: $_identifiedId';
    })();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaker Identification'),
        actions: [
          IconButton(
            tooltip: 'Clear all users',
            onPressed: totalUsers == 0
                ? null
                : () async {
              final yes = await _confirm(context, 'Clear all enrolled users?');
              if (yes == true) {
                await _service.clearAll();
                await _refreshRegisteredList();
                setState(() {
                  _identifiedId = null;
                  _candidates = [];
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: TextStyle(color: textColor),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _service.isFallback ? 'Mode: Fallback (local)' : 'Mode: ONNX model',
                    style: TextStyle(color: textColor.withOpacity(0.7)),
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: _guidedActive
                      ? null
                      : (_isRecording ? _stopAndIdentify : _startRecording),
                  child: Text(_isRecording ? 'Stop & Identify' : 'Record to Identify'),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isRecording
                        ? (_guidedActive ? 'Recording (guided)…' : 'Recording…')
                        : (_guidedActive ? 'Guided enrollment active' : 'Idle'),
                    style: TextStyle(color: textColor.withOpacity(0.7)),
                  ),
                ),

                // ----- Ranked candidates panel -----
                if (_candidates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.emoji_events),
                              const SizedBox(width: 8),
                              Text(
                                'Top candidates',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Threshold ${(_threshold * 100).toStringAsFixed(0)}%',
                                style: TextStyle(color: textColor.withOpacity(0.7)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _candidates.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, i) {
                              final c = _candidates[i];
                              final pct = (c.score * 100).toStringAsFixed(1);
                              final isTop = i == 0;
                              final passes = c.score >= _threshold;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isTop) const Icon(Icons.star, size: 18),
                                      if (isTop) const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${c.id} — $pct%',
                                          style: TextStyle(
                                            color: passes
                                                ? textColor
                                                : textColor.withOpacity(0.75),
                                            fontWeight:
                                            isTop ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (passes)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Icon(Icons.check_circle, size: 16),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: c.score.clamp(0.0, 1.0),
                                      minHeight: 8,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Divider(),

                // ----- Guided Enrollment -----
                Card(
                  color: widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.school),
                            const SizedBox(width: 8),
                            Text(
                              'Guided Enrollment',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (_guidedActive)
                              TextButton.icon(
                                onPressed: _isRecording ? null : _cancelGuidedEnrollment,
                                icon: const Icon(Icons.close),
                                label: const Text('Cancel'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_guidedActive) ...[
                          Text(
                            'Read 5 short phrases to create a robust voice print.',
                            style: TextStyle(color: textColor.withOpacity(0.85)),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _beginGuidedEnrollment,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Start Guided Enrollment'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Phrases:',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          for (final p in _prompts)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $p', style: TextStyle(color: textColor)),
                            ),
                        ] else ...[
                          Text(
                            'Step ${_promptIndex + 1} of ${_prompts.length}',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: textColor.withOpacity(0.2)),
                            ),
                            child: Text(
                              '"${_prompts[_promptIndex]}"',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isRecording ? null : _recordCurrentPrompt,
                                  icon: const Icon(Icons.mic),
                                  label: const Text('Start Recording'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isRecording ? _stopAndSaveCurrentPrompt : null,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Stop & Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(),

                // ----- Registered users -----
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Registered users (${_registered.length})',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_registered.isEmpty)
                  Text(
                    'No users enrolled yet. Start the guided enrollment above.',
                    style: TextStyle(color: textColor.withOpacity(0.8)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _registered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final name = _registered.keys.elementAt(i);
                      final count = _registered[name] ?? 0;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person),
                        title: Text(name, style: TextStyle(color: textColor)),
                        subtitle: Text(
                          '$count sample${count == 1 ? "" : "s"}',
                          style: TextStyle(color: textColor.withOpacity(0.7)),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),

      floatingActionButton: _guidedActive
          ? null
          : FloatingActionButton(
        tooltip: 'Start Guided Enrollment',
        onPressed: _beginGuidedEnrollment,
        child: const Icon(Icons.person_add),
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

  // ---------- Helpers for candidate parsing ----------

  List<_Candidate> _parseCandidates(dynamic raw) {
    final out = <_Candidate>[];
    if (raw == null) return out;

    // Accept: List<Map> or {candidates: List}
    final list = raw is List
        ? raw
        : (raw is Map<String, dynamic> && raw['candidates'] is List
        ? raw['candidates'] as List
        : null);

    if (list == null) return out;

    for (final e in list) {
      final c = _Candidate.fromUnknown(e);
      if (c != null) out.add(c);
    }
    return out;
  }
}

/// Simple holder for a candidate result.
class _Candidate {
  final String id;
  /// Confidence 0..1, higher is better.
  final double score;

  const _Candidate({required this.id, required this.score});

  static _Candidate? fromUnknown(dynamic e) {
    if (e is _Candidate) return e;

    // Common shapes:
    // {'id': 'Vivek', 'score': 0.83}
    // {'name': 'Vivek', 'confidence': 0.83}
    // ['Vivek', 0.83]
    if (e is Map) {
      final id =
      (e['id'] ?? e['name'] ?? e['speaker'] ?? e['label'] ?? '').toString().trim();
      if (id.isEmpty) return null;

      final scoreRaw = (e['score'] ?? e['confidence'] ?? e['prob'] ?? e['similarity']);
      double score;
      if (scoreRaw is num) {
        score = scoreRaw.toDouble();
      } else if (scoreRaw is String) {
        score = double.tryParse(scoreRaw) ?? 0.0;
      } else {
        score = 0.0;
      }

      // Clamp to 0..1 defensively.
      if (score.isNaN) score = 0.0;
      score = score.clamp(0.0, 1.0);

      return _Candidate(id: id, score: score);
    }
    if (e is List && e.length >= 2) {
      final id = e[0].toString();
      final numOrStr = e[1];
      double score = 0.0;
      if (numOrStr is num) {
        score = numOrStr.toDouble();
      } else if (numOrStr is String) {
        score = double.tryParse(numOrStr) ?? 0.0;
      }
      score = score.clamp(0.0, 1.0);
      return _Candidate(id: id, score: score);
    }

    return null;
  }
}
