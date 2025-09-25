import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher_string.dart';

class TranscriptLine {
  final String text;
  final DateTime time;
  final int index;
  final String speaker; // "A" or "B" (or empty)

  TranscriptLine({
    required this.text,
    required this.time,
    required this.index,
    required this.speaker,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'time': time.millisecondsSinceEpoch,
        'index': index,
        'speaker': speaker,
      };

  static TranscriptLine fromJson(Map<String, dynamic> m) {
    // robust parsing: JSON numeric types can be int/double/string
    final timeVal = m['time'];
    int millis = 0;
    if (timeVal is int) {
      millis = timeVal;
    } else if (timeVal is double) {
      millis = timeVal.toInt();
    } else if (timeVal is String) {
      millis = int.tryParse(timeVal) ?? 0;
    }

    final indexVal = m['index'];
    int idx = 0;
    if (indexVal is int) {
      idx = indexVal;
    } else if (indexVal is double) {
      idx = indexVal.toInt();
    } else if (indexVal is String) {
      idx = int.tryParse(indexVal) ?? 0;
    }

    final speakerVal = m['speaker'];
    String sp = '';
    if (speakerVal is String) {
      sp = speakerVal;
    } else if (speakerVal != null) {
      sp = speakerVal.toString();
    }

    return TranscriptLine(
      text: m['text']?.toString() ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(millis),
      index: idx,
      speaker: sp,
    );
  }
}

class GroupSpeechToTextScreen extends StatefulWidget {
  const GroupSpeechToTextScreen({super.key});

  @override
  State<GroupSpeechToTextScreen> createState() =>
      _GroupSpeechToTextScreenState();
}

// Added WidgetsBindingObserver so we can resume/ensure listening across app lifecycle changes.
class _GroupSpeechToTextScreenState extends State<GroupSpeechToTextScreen>
    with WidgetsBindingObserver {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // IMPORTANT: _keepListening indicates whether we want continuous listening.
  // We also track _autoStarted to only auto-start once during init if needed.
  // NOTE: Auto-start behavior has been disabled per user request; user must tap mic to start.
  bool _keepListening = false;
  bool _autoStarted = false;

  final List<TranscriptLine> _transcriptLines = [];
  String _currentPartial = '';
  double _confidence = 0.0;

  List<stt.LocaleName> _locales = [];
  List<stt.LocaleName> _mergedLocales = [];

  String? _systemLocaleId;
  String? _currentLocaleId;
  final ScrollController _scrollController = ScrollController();

  static const String _prefsKey = 'minimal_speech_transcript_v1';

  // Speaker handling:
  // _chosenSpeaker: null => auto (alternating or detection)
  // otherwise 'A' or 'B' selected manually
  String? _chosenSpeaker;
  String _lastSpeaker = 'B'; // so first assigned will be 'A'

  // For simple text-based "frequency" / voice fingerprinting fallback.
  // We aggregate text per speaker and use letter-frequency profiles to
  // decide whether a new line matches speaker A or B.
  final Map<String, String> _speakerAggregates = {
    'A': '',
    'B': '',
  };

  // New: maintain word-set based speaker profiles for improved detection.
  final Map<String, Set<String>> _speakerWordSets = {
    'A': <String>{},
    'B': <String>{},
  };

  // similarity threshold for auto-detection: if similarity to one speaker
  // exceeds the other's by this margin, we assign to that speaker.
  static const double _similarityMargin = 0.06; // small margin
  // minimum data length required in aggregate to attempt similarity-based detection
  static const int _minAggregateCharsForDetection = 30;
  // minimum word-set size to attempt word-based detection
  static const int _minAggregateWordsForDetection = 6;

  // microphone permission state
  bool _micPermissionGranted = false;

  // Helpful language name mappings for when plugin/device gives only codes.
  // This is used to display friendly names like "Punjabi" instead of "pa".
  final Map<String, String> _languageNames = {
    'hi': 'Hindi',
    'hi_IN': 'Hindi (India)',
    'bn': 'Bengali',
    'bn_IN': 'Bengali (India)',
    'te': 'Telugu',
    'te_IN': 'Telugu (India)',
    'mr': 'Marathi',
    'mr_IN': 'Marathi (India)',
    'ta': 'Tamil',
    'ta_IN': 'Tamil (India)',
    'ur': 'Urdu',
    'ur_IN': 'Urdu (India)',
    'kn': 'Kannada',
    'kn_IN': 'Kannada (India)',
    'ml': 'Malayalam',
    'ml_IN': 'Malayalam (India)',
    'gu': 'Gujarati',
    'gu_IN': 'Gujarati (India)',
    'pa': 'Punjabi',
    'pa_IN': 'Punjabi (India)',
    'or': 'Odia',
    'or_IN': 'Odia (India)',
    'as': 'Assamese',
    'as_IN': 'Assamese (India)',
    'en': 'English',
    'en_US': 'English (US)',
    'en_GB': 'English (UK)',
    'fr': 'French',
    'es': 'Spanish',
    'de': 'German',
    'it': 'Italian',
    // add more common mappings as needed
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load persisted transcript first so previous transcript is visible immediately
    _loadTranscript().then((_) async {
      // Ask for microphone permission proactively on startup so the user sees
      // the permission prompt immediately instead of only after tapping buttons.
      await _askForMicPermission();

      // Then check microphone permission and initialize speech if allowed.
      // IMPORTANT: We intentionally do NOT auto-start listening here. The user must tap the mic to activate.
      _checkAndInitSpeech();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepListening = false;
    try {
      _speech.stop();
    } catch (_) {}
    _scrollController.dispose();
    super.dispose();
  }

  // Ensure when app resumes we re-start listening only if the user had explicitly requested continuous listening.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // Only attempt to restart if:
      // - speech plugin is available
      // - mic permission granted
      // - we are currently not listening
      // - AND the user had requested continuous listening (_keepListening == true)
      if (_speechAvailable && _micPermissionGranted && !_isListening && _keepListening) {
        // Start listening again after a short delay to allow engine to be ready.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            try {
              _startListening();
            } catch (_) {}
          }
        });
      }
    }
  }

  /// Prompt the user for microphone permission unconditionally if not yet granted.
  /// This is a direct request (no "first time" gating) so the permission dialog
  /// appears on app start if needed.
  Future<void> _askForMicPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        setState(() {
          _micPermissionGranted = true;
          _currentPartial = '';
        });
        return;
      }

      final result = await Permission.microphone.request();

      if (result.isGranted) {
        setState(() {
          _micPermissionGranted = true;
          _currentPartial = '';
        });
        // initialize speech if possible (does NOT auto-start listening)
        await _initSpeech();
      } else if (result.isPermanentlyDenied) {
        setState(() {
          _micPermissionGranted = false;
          _currentPartial =
              'Microphone permission permanently denied. Open app settings to enable.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showPermanentlyDeniedDialog();
        });
      } else {
        // denied (but not permanent)
        setState(() {
          _micPermissionGranted = false;
          _currentPartial =
              'Microphone permission denied. Tap "Request Mic" to try again.';
        });
      }
    } catch (_) {
      // If permission_handler isn't available on this platform, just update state
      setState(() {
        _micPermissionGranted = false;
      });
    }
  }

  Future<void> _showPermanentlyDeniedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Microphone permission required'),
          content: const Text(
              'Microphone permission has been permanently denied. To use speech recognition please open app settings and enable the microphone permission.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeniedDialog() async {
    if (!mounted) return;
    final res = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Microphone permission'),
          content: const Text(
              'Microphone permission is required for speech recognition. Would you like to retry the permission request or open app settings?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(2); // Cancel
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(1); // Open settings
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(0); // Retry
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );

    if (res == null) return;
    if (res == 1) {
      // Open app settings
      openAppSettings();
    } else if (res == 0) {
      // Retry permission request
      try {
        final result = await Permission.microphone.request();
        if (result.isGranted) {
          if (mounted) {
            setState(() {
              _micPermissionGranted = true;
              _currentPartial = '';
            });
            // initialize speech if required
            if (!_speechAvailable) {
              await _initSpeech();
            }
          }
        } else if (result.isPermanentlyDenied) {
          if (mounted) {
            setState(() {
              _micPermissionGranted = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showPermanentlyDeniedDialog();
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _micPermissionGranted = false;
              _currentPartial =
                  'Microphone permission denied. Tap "Request Mic" to try again or open app settings.';
            });
          }
        }
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> _checkAndInitSpeech() async {
    final granted = await _ensureMicPermission();
    setState(() {
      _micPermissionGranted = granted;
    });
    if (granted) {
      await _initSpeech();
    } else {
      setState(() {
        _currentPartial =
            'Microphone permission not granted. Tap "Request Mic" to allow or grant via system settings.';
        _speechAvailable = false;
      });
    }
  }

  /// Request microphone permission using permission_handler
  ///
  /// This function centrally handles all permission outcomes:
  /// - granted => returns true
  /// - permanently denied => shows dialog guiding user to app settings and returns false
  /// - denied (but not permanent) => shows a dialog offering retry or open settings and returns false
  Future<bool> _ensureMicPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;

      final result = await Permission.microphone.request();
      if (result.isGranted) return true;

      if (result.isPermanentlyDenied) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showPermanentlyDeniedDialog();
        });
        return false;
      }

      // If denied (not permanent) show a dialog offering retry/open settings
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDeniedDialog();
      });
      return false;
    } catch (_) {
      // If permission_handler isn't available on the platform, return false.
      return false;
    }
  }

  /// Convert a ui.Locale to an id like "hi_IN" or "en"
  String _uiLocaleToId(ui.Locale l) {
    if (l.countryCode != null && l.countryCode!.isNotEmpty) {
      return '${l.languageCode}_${l.countryCode}';
    }
    return l.languageCode;
  }

  void _buildMergedLocales() {
    final seen = <String>{};
    final List<stt.LocaleName> merged = [];

    for (var l in _locales) {
      if (l.localeId.isNotEmpty && !seen.contains(l.localeId)) {
        merged.add(l);
        seen.add(l.localeId);
      }
    }

    for (final uiLoc in ui.window.locales) {
      final id = _uiLocaleToId(uiLoc);
      if (id.isNotEmpty && !seen.contains(id)) {
        // stt.LocaleName(name, localeId) - if plugin didn't supply name use id
        merged.add(stt.LocaleName(id, id));
        seen.add(id);
      }
    }

    // Add common Indian locales (human-friendly names) if not already present
    final Map<String, String> commonIndian = {
      'hi_IN': 'Hindi (India)',
      'bn_IN': 'Bengali (India)',
      'te_IN': 'Telugu (India)',
      'mr_IN': 'Marathi (India)',
      'ta_IN': 'Tamil (India)',
      'ur_IN': 'Urdu (India)',
      'kn_IN': 'Kannada (India)',
      'ml_IN': 'Malayalam (India)',
      'gu_IN': 'Gujarati (India)',
      'pa_IN': 'Punjabi (India)',
      'or_IN': 'Odia (India)',
      'as_IN': 'Assamese (India)',
    };

    for (final entry in commonIndian.entries) {
      final id = entry.key;
      if (!seen.contains(id)) {
        merged.add(stt.LocaleName(entry.value, id));
        seen.add(id);
      }
    }

    // Sort for a better UX: prefer system locale first, then alphabetical by display name.
    merged.sort((a, b) {
      if (_systemLocaleId != null) {
        if (a.localeId == _systemLocaleId) return -1;
        if (b.localeId == _systemLocaleId) return 1;
      }
      final an = a.name.toLowerCase();
      final bn = b.name.toLowerCase();
      return an.compareTo(bn);
    });

    _mergedLocales = merged;
  }

  Future<void> _initSpeech() async {
    // Ensure microphone permission before calling plugin
    if (!_micPermissionGranted) {
      setState(() {
        _currentPartial = 'No microphone permission. Tap "Request Mic" to allow.';
        _speechAvailable = false;
      });
      return;
    }

    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) async {
          if (mounted) {
            // Keep the UI showing "listening" when we intend continuous listening (_keepListening).
            // This avoids a quick flicker of the mic icon turning off briefly while the engine restarts.
            setState(() {
              if (status == 'listening') {
                _isListening = true;
              } else {
                // If the user/app has requested continuous listening, keep the UI as "listening"
                // while we attempt to restart in background. This reduces UI flicker.
                _isListening = _keepListening ? true : false;
              }
            });
          }
          // Auto-restart if listening stopped unexpectedly and the USER explicitly requested continuous listening.
          // Note: _keepListening is only set to true when the user taps the mic to start.
          if (status != 'listening' && _keepListening && _speechAvailable) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted && !_isListening) {
              try {
                // Try to restart listening quickly if the user wanted continuous listening.
                await _startListening();
              } catch (_) {}
            } else if (mounted && _keepListening) {
              // If our UI is showing listening due to _keepListening, still attempt restart.
              try {
                await _startListening();
              } catch (_) {}
            }
          }
        },
        onError: (errorNotification) {
          // keep minimal UI; errors can be reflected in partial text if needed
        },
      );

      if (_speechAvailable) {
        try {
          _locales = await _speech.locales();
        } catch (_) {
          _locales = [];
        }

        _buildMergedLocales();

        try {
          final systemLocale = await _speech.systemLocale();
          _systemLocaleId = systemLocale?.localeId;
          // If user hasn't chosen a locale yet, use system
          _currentLocaleId ??= _systemLocaleId;
        } catch (_) {
          _systemLocaleId =
              _mergedLocales.isNotEmpty ? _mergedLocales.first.localeId : null;
          _currentLocaleId ??= _systemLocaleId;
        }

        setState(() {
          _currentPartial = '';
        });

        // NOTE: Auto-start has been intentionally disabled. User must tap mic to start listening.
      } else {
        setState(() {
          _currentPartial = 'Speech recognition unavailable';
        });
      }
    } on MissingPluginException catch (_) {
      // This happens if the plugin isn't registered on the platform (e.g., forgot to run flutter pub get / platform setup).
      setState(() {
        _speechAvailable = false;
        _currentPartial =
            'Speech plugin not implemented on this platform. Ensure platform integration (e.g., run "flutter pub get", rebuild the app) and required platform setup.';
      });
    } catch (e) {
      setState(() {
        _currentPartial = 'Error initializing speech: $e';
        _speechAvailable = false;
      });
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      setState(() {
        _currentPartial = 'Speech recognition not available';
      });
      return;
    }

    // Check permission again just before starting
    final granted = await _ensureMicPermission();
    setState(() {
      _micPermissionGranted = granted;
    });
    if (!granted) {
      setState(() {
        _currentPartial =
            'Microphone permission not granted. Tap "Request Mic" to allow.';
      });
      return;
    }

    // When the user (or auto-start) starts listening, record intent for continuous listening.
    _keepListening = true;

    final localeToUse = _currentLocaleId ?? _systemLocaleId;

    try {
      // Set UI to listening immediately to avoid brief icon flicker while the engine starts.
      setState(() {
        _isListening = true;
        if (_currentPartial.isEmpty) _currentPartial = 'Listening...';
      });

      // Use long listenFor and long pauseFor to keep microphone active and avoid silence timeouts.
      await _speech.listen(
        onResult: (val) {
          setState(() {
            if (val.hasConfidenceRating && val.confidence > 0) {
              _confidence = val.confidence;
            }

            // If partial contains Devanagari and plugin/platform has hi locale, attempt to switch
            if (val.recognizedWords.isNotEmpty &&
                RegExp(r'[\u0900-\u097F]').hasMatch(val.recognizedWords)) {
              final hindiLocale = _mergedLocales.firstWhere(
                (l) => l.localeId.toLowerCase().startsWith('hi'),
                orElse: () => stt.LocaleName('', ''),
              );
              if (hindiLocale.localeId.isNotEmpty &&
                  _currentLocaleId != hindiLocale.localeId) {
                _currentLocaleId = hindiLocale.localeId;
                // schedule a restart with the Hindi locale if we're still listening
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _isListening) {
                    _restartListeningWithLocale(hindiLocale.localeId);
                  }
                });
              }
            }

            if (val.finalResult) {
              _processFinalText(val.recognizedWords);
            } else {
              _currentPartial = val.recognizedWords;
            }
          });
          _scrollToBottom();
        },
        localeId: localeToUse,
        partialResults: true,
        // Keep listenFor long (e.g., 24 hours) to reduce forced stops by the plugin.
        listenFor: const Duration(hours: 24),
        // Increase pauseFor (silence duration before stopping) to avoid stopping on brief silence.
        pauseFor: const Duration(hours: 1),
        cancelOnError: true,
      );

      // If we reach here, listen call started successfully; ensure UI reflects actual listening.
      setState(() {
        _isListening = true;
        if (_currentPartial == 'Listening...') _currentPartial = '';
      });
    } on MissingPluginException catch (_) {
      setState(() {
        _currentPartial =
            'Speech plugin not implemented on this platform. Ensure platform integration and rebuild the app.';
        _isListening = false;
        _speechAvailable = false;
      });
    } catch (e) {
      // If starting failed, revert UI to not listening but keep the intent for continuous listening.
      setState(() {
        _currentPartial = 'Error starting to listen: $e';
        _isListening = false;
      });
      // Try to restart after a small delay if we still want continuous listening.
      if (_keepListening) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _startListening();
        });
      }
    }
  }

  Future<void> _restartListeningWithLocale(String localeId) async {
    if (!_speechAvailable) return;
    if (localeId.isEmpty) return;

    // Ensure mic permission still present
    final granted = await _ensureMicPermission();
    setState(() {
      _micPermissionGranted = granted;
    });
    if (!granted) {
      setState(() {
        _currentPartial = 'Microphone permission not granted. Cannot switch language.';
      });
      return;
    }

    // Only attempt restart if we (user/auto) previously requested continuous listening.
    if (!_keepListening) return;

    try {
      await _speech.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    try {
      // Keep UI showing listening while switching to avoid flicker.
      setState(() {
        _isListening = true;
        _currentPartial = 'Switching language...';
      });

      await _speech.listen(
        onResult: (val) {
          setState(() {
            if (val.hasConfidenceRating && val.confidence > 0) {
              _confidence = val.confidence;
            }
            if (val.finalResult) {
              _processFinalText(val.recognizedWords);
            } else {
              _currentPartial = val.recognizedWords;
            }
          });
          _scrollToBottom();
        },
        localeId: localeId,
        partialResults: true,
        listenFor: const Duration(hours: 24),
        pauseFor: const Duration(hours: 1),
        cancelOnError: true,
      );

      setState(() {
        _isListening = true;
        if (_currentPartial == 'Switching language...') _currentPartial = '';
      });
    } on MissingPluginException catch (_) {
      setState(() {
        _currentPartial =
            'Speech plugin not implemented on this platform. Ensure platform integration and rebuild the app.';
      });
    } catch (e) {
      setState(() {
        _currentPartial = 'Failed to switch language: $e';
      });
    }
  }

  // Build a 26-dim letter frequency profile for a text (a-z).
  // Non-letter characters are ignored. Returns normalized vector (L2 norm).
  List<double> _textProfile(String text) {
    final counts = List<double>.filled(26, 0);
    final lower = text.toLowerCase();
    for (var i = 0; i < lower.length; i++) {
      final code = lower.codeUnitAt(i);
      if (code >= 97 && code <= 122) {
        counts[code - 97] += 1;
      }
    }
    // If nothing, return zero vector
    final sum = counts.reduce((a, b) => a + b);
    if (sum == 0) {
      return counts;
    }
    // Normalize to unit vector (L2)
    double sqSum = 0;
    for (var v in counts) sqSum += v * v;
    if (sqSum == 0) return counts;
    final norm = sqrt(sqSum);
    return counts.map((v) => v / norm).toList();
  }

  double _dotProduct(List<double> a, List<double> b) {
    double sum = 0;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  // Compute cosine similarity between two profiles. Both should be normalized (unit length).
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    return _dotProduct(a, b); // if both normalized, this equals cosine similarity
  }

  // Extract normalized words from text for word-set based fingerprinting.
  // Removes short tokens and punctuation; returns lowercase words of length >= 2.
  Set<String> _extractWordSet(String text) {
    final t = text.toLowerCase();
    final words = <String>{};
    final reg = RegExp(r"[a-z\u0900-\u097F0-9]+", unicode: true); // include devanagari and numbers
    for (final m in reg.allMatches(t)) {
      final w = m.group(0)?.trim() ?? '';
      if (w.length >= 2) {
        words.add(w);
      }
    }
    return words;
  }

  // Simple Jaccard similarity for sets.
  double _jaccardSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final inter = a.intersection(b).length;
    final union = a.union(b).length;
    if (union == 0) return 0.0;
    return inter / union;
  }

  // Detect speaker for the given text using aggregated text fingerprints.
  // Returns 'A' or 'B' (or fallback to alternation).
  String _detectSpeakerByText(String text) {
    // If user explicitly chose manual speaker, respect that elsewhere.
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      // Fallback to alternating
      return (_lastSpeaker == 'A') ? 'B' : 'A';
    }

    // First attempt: word-set based detection if speaker profiles have enough words.
    final newWords = _extractWordSet(cleaned);
    final wsA = _speakerWordSets['A'] ?? <String>{};
    final wsB = _speakerWordSets['B'] ?? <String>{};

    if (wsA.length >= _minAggregateWordsForDetection &&
        wsB.length >= _minAggregateWordsForDetection) {
      final jacA = _jaccardSimilarity(newWords, wsA);
      final jacB = _jaccardSimilarity(newWords, wsB);

      // If one clearly larger than the other, choose it
      if (jacA > jacB + 0.08) {
        return 'A';
      } else if (jacB > jacA + 0.08) {
        return 'B';
      } else {
        // Not decisive: continue to letter-frequency fallback below
      }
    }

    // Fallback: letter-frequency profile detection (existing method)
    final profileNew = _textProfile(cleaned);

    final aggA = _speakerAggregates['A'] ?? '';
    final aggB = _speakerAggregates['B'] ?? '';

    // If neither speaker has enough data, fallback to alternation
    if (aggA.length < _minAggregateCharsForDetection &&
        aggB.length < _minAggregateCharsForDetection) {
      return (_lastSpeaker == 'A') ? 'B' : 'A';
    }

    final profileA = aggA.length >= _minAggregateCharsForDetection
        ? _textProfile(aggA)
        : List<double>.filled(26, 0);
    final profileB = aggB.length >= _minAggregateCharsForDetection
        ? _textProfile(aggB)
        : List<double>.filled(26, 0);

    final simA = _cosineSimilarity(profileNew, profileA);
    final simB = _cosineSimilarity(profileNew, profileB);

    // If both sims are zero (e.g., non-latin), but word-sets exist, use alternation
    if (simA == 0 && simB == 0) {
      return (_lastSpeaker == 'A') ? 'B' : 'A';
    }

    // Choose the higher similarity, but require it to be greater than the other by margin
    if (simA > simB + _similarityMargin) {
      return 'A';
    } else if (simB > simA + _similarityMargin) {
      return 'B';
    } else {
      // Ambiguous: fallback to alternation
      return (_lastSpeaker == 'A') ? 'B' : 'A';
    }
  }

  // Allow enrolling speaker profiles from the last N finalized lines.
  // This helps the app learn who is speaker A / B for more accurate auto-detection.
  void _enrollLastLinesForSpeaker(String speaker, {int lastN = 3}) {
    if (_transcriptLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transcript lines to enroll from')),
      );
      return;
    }
    final selected =
        _transcriptLines.reversed.take(lastN).map((e) => e.text).join(' ');
    final words = _extractWordSet(selected);
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough text to enroll')),
      );
      return;
    }

    setState(() {
      final prevAgg = _speakerAggregates[speaker] ?? '';
      final combined = (prevAgg + ' ' + selected).trim();
      _speakerAggregates[speaker] =
          combined.length > 2000 ? combined.substring(combined.length - 2000) : combined;

      final prevSet = _speakerWordSets[speaker] ?? <String>{};
      prevSet.addAll(words);
      _speakerWordSets[speaker] = prevSet;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enrolled recent speech for speaker $speaker')),
    );
  }

  void _resetSpeakerProfiles() {
    setState(() {
      _speakerAggregates['A'] = '';
      _speakerAggregates['B'] = '';
      _speakerWordSets['A'] = <String>{};
      _speakerWordSets['B'] = <String>{};
      _lastSpeaker = 'B';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Speaker profiles reset')),
    );
  }

  // Simplified and more robust: always append final recognized text as a new transcript line.
  // This ensures previous recognized/finalized sentences are kept and displayed.
  void _processFinalText(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    final normalized = cleaned.replaceAll('।', '.');

    // Avoid adding exactly duplicate consecutive lines (common if plugin returns the same final multiple times)
    if (_transcriptLines.isNotEmpty && _transcriptLines.last.text == normalized) {
      setState(() {
        _currentPartial = '';
      });
      return;
    }

    // Determine speaker: chosenSpeaker (manual) or detection/alternate between A and B
    String assignedSpeaker;
    if (_chosenSpeaker == 'A' || _chosenSpeaker == 'B') {
      assignedSpeaker = _chosenSpeaker!;
    } else {
      // Auto: try detection by text (word-jaccard + letter frequency fallback).
      assignedSpeaker = _detectSpeakerByText(normalized);
    }

    final idx = _transcriptLines.length + 1;
    setState(() {
      _transcriptLines.add(TranscriptLine(
          text: normalized,
          time: DateTime.now(),
          index: idx,
          speaker: assignedSpeaker));
      _currentPartial = '';
      _lastSpeaker = assignedSpeaker;
      // update aggregates for detection
      if (assignedSpeaker == 'A' || assignedSpeaker == 'B') {
        final prev = _speakerAggregates[assignedSpeaker] ?? '';
        // keep aggregates to a bounded length to avoid unbounded growth
        final combined = (prev + ' ' + normalized).trim();
        // keep last ~2000 chars
        _speakerAggregates[assignedSpeaker] =
            combined.length > 2000 ? combined.substring(combined.length - 2000) : combined;

        // update word-set
        final prevSet = _speakerWordSets[assignedSpeaker] ?? <String>{};
        prevSet.addAll(_extractWordSet(normalized));
        _speakerWordSets[assignedSpeaker] = prevSet;
      }
    });

    _saveTranscript();
    _scrollToBottom();
  }

  Future<void> _stopListening({bool userRequested = true}) async {
    if (userRequested) _keepListening = false;
    try {
      await _speech.stop();
    } on MissingPluginException catch (_) {
      // ignore
    } catch (_) {}
    setState(() {
      _isListening = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        try {
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.animateTo(
            max,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
    });
  }

  void _clearTranscript() {
    setState(() {
      _transcriptLines.clear();
      _currentPartial = '';
      _confidence = 0.0;
      _speakerAggregates['A'] = '';
      _speakerAggregates['B'] = '';
      _speakerWordSets['A'] = <String>{};
      _speakerWordSets['B'] = <String>{};
      _lastSpeaker = 'B';
    });
    _saveTranscript(); // persist cleared state
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transcript cleared')),
    );
  }

  Future<void> _saveTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _transcriptLines.map((t) => t.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {
      // ignore persistence errors silently
    }
  }

  Future<void> _loadTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_prefsKey);
      if (s == null || s.isEmpty) return;
      final decoded = jsonDecode(s);
      if (decoded is List) {
        final List<TranscriptLine> loaded = [];
        for (var item in decoded) {
          if (item is Map) {
            // convert keys to String and values as-is
            final map = <String, dynamic>{};
            item.forEach((k, v) {
              map[k.toString()] = v;
            });
            try {
              loaded.add(TranscriptLine.fromJson(map));
            } catch (_) {
              // skip any malformed entry
            }
          } else if (item is String) {
            // attempt to parse a stringified json object (defensive)
            try {
              final dynamic obj = jsonDecode(item);
              if (obj is Map) {
                final map = <String, dynamic>{};
                obj.forEach((k, v) {
                  map[k.toString()] = v;
                });
                loaded.add(TranscriptLine.fromJson(map));
              }
            } catch (_) {
              // ignore
            }
          }
        }

        // sort by index/time to preserve chronological order
        loaded.sort((a, b) {
          if (a.index != b.index) return a.index.compareTo(b.index);
          return a.time.compareTo(b.time);
        });

        // rebuild aggregates from loaded transcript lines
        _speakerAggregates['A'] = '';
        _speakerAggregates['B'] = '';
        _speakerWordSets['A'] = <String>{};
        _speakerWordSets['B'] = <String>{};
        for (final l in loaded) {
          if (l.speaker.toUpperCase() == 'A' || l.speaker.toUpperCase() == 'B') {
            final key = l.speaker.toUpperCase();
            final prev = _speakerAggregates[key] ?? '';
            final combined = (prev + ' ' + l.text).trim();
            _speakerAggregates[key] =
                combined.length > 2000 ? combined.substring(combined.length - 2000) : combined;

            // build word sets
            final prevSet = _speakerWordSets[key] ?? <String>{};
            prevSet.addAll(_extractWordSet(l.text));
            _speakerWordSets[key] = prevSet;
          }
        }

        if (mounted) {
          setState(() {
            _transcriptLines
              ..clear()
              ..addAll(loaded);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        } else {
          _transcriptLines
            ..clear()
            ..addAll(loaded);
        }
      }
    } catch (_) {
      // ignore load errors
    }
  }

  // Nice pulsing indicator when listening
  Widget _listeningPulse({required bool show, Color color = Colors.redAccent}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: show ? 1 : 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: show ? 0.6 : 0.0, end: show ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        builder: (context, val, child) {
          return Container(
            width: 22 * val + 22,
            height: 22 * val + 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12 * val),
            ),
          );
        },
      ),
    );
  }

  // Chat bubble like transcript list
  Widget _buildCombinedTranscriptList() {
    // This returns a ListView that shows:
    // - all finalized transcript lines (older -> newer)
    // - a live partial line (if present) as the last item
    final totalItems =
        _transcriptLines.length + (_currentPartial.trim().isEmpty ? 0 : 1);

    if (totalItems == 0) {
      // placeholder when nothing to show
      return Center(
        child: Text(
          'No transcript yet. Press the mic and speak.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      itemCount: totalItems,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index < _transcriptLines.length) {
          final line = _transcriptLines[index];
          final isA = line.speaker.toUpperCase() == 'A';
          final bg = isA ? Colors.blue.shade50 : Colors.green.shade50;
          final accent = isA ? Colors.blue.shade700 : Colors.green.shade700;

          // Align right for B, left for A to emphasize conversation
          final alignment = isA ? CrossAxisAlignment.start : CrossAxisAlignment.end;
          final radius = isA
              ? const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                );

          return Row(
            mainAxisAlignment:
                isA ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (isA) ...[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue.shade700,
                  child: Text('A',
                      style:
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    border: Border.all(color: accent.withOpacity(0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: alignment,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              line.text,
                              style: const TextStyle(fontSize: 16, height: 1.35),
                            ),
                          ),

                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTimestamp(line.time),
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (!isA) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.green.shade700,
                  child: Text('B',
                      style:
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          );
        } else {
          // live partial item
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.yellow.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.volume_up, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentPartial.isNotEmpty ? _currentPartial : 'Listening...',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                              fontStyle: _currentPartial.isNotEmpty ? FontStyle.italic : FontStyle.normal),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isListening)
                        Row(
                          children: [
                            _listeningPulse(show: true, color: Colors.redAccent),
                            const SizedBox(width: 6),
                            Text(
                              _confidence > 0 ? '${(_confidence * 100).toStringAsFixed(0)}%' : '',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  String _formatTimestamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  // Show a helpful dialog directing the user to device settings to add languages.
  Future<void> _showLanguageSettingsDialog() async {
    if (!mounted) return;
    final instructions = Platform.isAndroid
        ? 'To add regional languages on Android:\n\n'
            '1. Open Settings → System → Languages & input → Languages.\n'
            "2. Tap 'Add a language' and choose your preferred language (e.g., Punjabi, Hindi, Gujarati).\n"
            '3. After adding the language, return to this app and select it from the language picker.'
        : Platform.isIOS
            ? 'To add regional languages on iOS:\n\n'
                '1. Open Settings → General → Language & Region.\n'
                "2. Tap 'Add Language' and choose your preferred language (e.g., Punjabi, Hindi, Gujarati).\n"
                '3. After adding the language, return to this app and select it from the language picker.'
            : 'To add regional languages:\n\n'
                'Open your device settings, look for "Language" or "Region" settings, and add the languages you need (e.g., Punjabi, Hindi, Gujarati). Then return to this app and select the language from the picker.';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add languages on your device'),
          content: SingleChildScrollView(child: Text(instructions)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openSystemSettingsForLanguages();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  // Attempt to open system language settings. On Android try several intents; on iOS try known URL schemes.
  // If direct language/locale page cannot be opened (varies by OEM and OS version) we fall back to opening
  // general settings or showing clear instructions to the user (we avoid opening the app's page by default,
  // since the user specifically needs the device language settings).
  Future<void> _openSystemSettingsForLanguages() async {
    if (!mounted) return;

    bool openedSpecific = false;
    String fallbackUsed = '';

    try {
      if (Platform.isAndroid) {
        // First try the standard LOCALE_SETTINGS action which should open Language settings on many devices.
        try {
          final intent = AndroidIntent(action: 'android.settings.LOCALE_SETTINGS');
          await intent.launch();
          openedSpecific = true;
          return;
        } catch (_) {
          // continue to other attempts
        }

        // Some OEMs expose the language picker in an activity; try a set of component names that are commonly observed.
        // These are fragile across Android versions/OEMs but worth trying before giving up.
        final possibleComponents = <String>[
          // Common Attempts:
          'com.android.settings/.LanguageSettings', // hypothetical
          'com.android.settings/.Settings\$LanguageAndInputSettingsActivity',
          'com.android.settings/.Settings\$LocalePickerActivity',
          'com.android.settings/.LocalePickerActivity',
          // Samsung / OEM variants:
          'com.samsung.android.settings/.LanguageSettings',
          'com.samsung.android.settings/.Settings\$LanguageAndInputSettingsActivity',
        ];

        for (final comp in possibleComponents) {
          try {
            final intent = AndroidIntent(componentName: comp, package: 'com.android.settings');
            await intent.launch();
            openedSpecific = true;
            return;
          } catch (_) {
            // ignore and try next
          }
        }

        // As a more general fallback, open the main Settings screen.
        try {
          final intent = AndroidIntent(action: 'android.settings.SETTINGS');
          await intent.launch();
          openedSpecific = true;
          fallbackUsed = 'System Settings';
          return;
        } catch (_) {
          // continue to final fallback
        }

        // If nothing worked, do not open the app-specific settings automatically.
        // Instead inform the user with clear instructions on how to navigate to Language & Region.
        fallbackUsed = '';
        return;
      } else if (Platform.isIOS) {
        // Try known iOS URL schemes. These schemes are not officially public API and may fail on some iOS versions.
        final candidates = <String>[
          'App-Prefs:root=General&path=LANGUAGE_AND_REGION', // sometimes works
          'App-Prefs:root=General', // fallback to general
          'prefs:root=General', // another legacy fallback
        ];

        for (final url in candidates) {
          try {
            final can = await canLaunchUrlString(url);
            if (can) {
              final launched = await launchUrlString(url);
              if (launched) {
                openedSpecific = true;
                return;
              }
            }
          } catch (_) {
            // ignore and try next
          }
        }

        // If no scheme worked, do not open the app settings automatically. Instead let the user know.
        fallbackUsed = '';
        return;
      } else {
        // Other platforms: just inform the user; opening system settings programmatically may not be supported.
        fallbackUsed = '';
        return;
      }
    } catch (_) {
      // fall through to final notification
    } finally {
      if (mounted) {
        if (!openedSpecific) {
          // Inform user we couldn't open language page directly.
          final message = fallbackUsed.isEmpty
              ? 'Could not open language settings directly. Please open your device Settings → Languages & Region (or System → Languages) and add the language there.'
              : 'Opened $fallbackUsed. From there navigate to Languages & Region to add languages.';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    }
  }

  // Return a friendly name for a locale id. If plugin provided name exists, prefer it;
  // otherwise use the mapping or fall back to the id.
  String _friendlyLocaleLabelForId(String localeId) {
    // try to find in merged locales
    final found = _mergedLocales.firstWhere(
      (l) => l.localeId == localeId,
      orElse: () => stt.LocaleName('', ''),
    );
    if (found.name.isNotEmpty) return found.name + ' ($localeId)';

    // try mapping by full id
    if (_languageNames.containsKey(localeId)) {
      return '${_languageNames[localeId]} ($localeId)';
    }

    // try language code only
    final code = localeId.split('_')[0];
    if (_languageNames.containsKey(code)) {
      return '${_languageNames[code]} ($localeId)';
    }

    // fallback: show id but try to present language code nicely
    return localeId;
  }

  // Find a localeId in _mergedLocales that best matches a short language code like 'en' or 'hi'.
  // Prefer exact matches like 'en_US'/'en_GB' if available by checking system locale, otherwise first that startsWith code.
  String? _bestLocaleForCode(String shortCode) {
    if (shortCode.isEmpty) return null;
    // try exact match on language+country with system locale preference
    final sysCode = _systemLocaleId;
    if (sysCode != null && sysCode.toLowerCase().startsWith(shortCode.toLowerCase())) {
      final found = _mergedLocales.firstWhere(
          (l) => l.localeId.toLowerCase() == sysCode.toLowerCase(),
          orElse: () => stt.LocaleName('', ''));
      if (found.localeId.isNotEmpty) return found.localeId;
    }
    // otherwise find first that starts with shortCode
    final found = _mergedLocales.firstWhere(
        (l) => l.localeId.toLowerCase().startsWith(shortCode.toLowerCase()),
        orElse: () => stt.LocaleName('', ''));
    return found.localeId.isNotEmpty ? found.localeId : null;
  }

  // Handle locale selection: check whether language is activated on device and supported by plugin.
  // If not activated, prompt / redirect user to system language settings.
  // If plugin doesn't support the language, inform the user and offer options.
  Future<void> _handleLocaleSelection(String selectedLocaleId) async {
    if (!mounted) return;

    final selected = selectedLocaleId.trim();
    if (selected.isEmpty) return;

    final selectedLangCode = selected.split('_')[0].toLowerCase();

    // Check whether the device system has the language activated
    final systemHas = ui.window.locales.any(
      (u) => u.languageCode.toLowerCase() == selectedLangCode,
    );

    // Check whether the speech plugin reports support for the language.
    final pluginHas = _locales.any((l) {
      final id = l.localeId.toLowerCase();
      // Some plugins might return different separators or variants; compare startsWith language code
      return id == selected.toLowerCase() || id.startsWith(selectedLangCode);
    });

    // Friendly label for dialogs
    final friendly = _friendlyLocaleLabelForId(selected);

    if (!systemHas) {
      // Language not activated on the device. Prompt to open system language settings to add it.
      final res = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Language not activated'),
            content: Text(
                '$friendly is not currently activated on your device. To use it with speech recognition, please add it in your system language settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(0),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(1),
                child: const Text('Open Settings'),
              ),
            ],
          );
        },
      );

      if (res == 1) {
        _openSystemSettingsForLanguages();
      }
      return;
    }

    if (!pluginHas && _speechAvailable) {
      // Plugin doesn't report support: inform user. Offer to proceed anyway or open settings.
      final res = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Language not supported by speech engine'),
            content: Text(
                '$friendly appears not to be supported by the speech recognition engine on this device. You can try enabling additional languages in system settings or choose another language. Do you want to proceed and select this language anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(0),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(2),
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(1),
                child: const Text('Proceed'),
              ),
            ],
          );
        },
      );

      if (res == 2) {
        _openSystemSettingsForLanguages();
        return;
      } else if (res == 1) {
        // proceed: set and restart if needed
        setState(() {
          _currentLocaleId = selected;
        });
        if (_isListening) {
          _restartListeningWithLocale(selected);
        }
        return;
      } else {
        // cancelled
        return;
      }
    }

    // Everything looks OK: set the locale
    setState(() {
      _currentLocaleId = selected;
    });
    if (_isListening) {
      _restartListeningWithLocale(selected);
    }
  }

  // Show a searchable modal bottom sheet to pick a locale from _mergedLocales.
  Future<void> _showLocalePicker() async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        List<stt.LocaleName> filtered = List.from(_mergedLocales);

        return StatefulBuilder(
          builder: (context, setInnerState) {
            filtered = _mergedLocales.where((l) {
              final q = query.trim().toLowerCase();
              if (q.isEmpty) return true;
              final combined =
                  '${l.name} ${l.localeId}'.toLowerCase(); // fallback
              return combined.contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search languages (e.g., Hindi, Punjabi)',
                            ),
                            onChanged: (v) {
                              setInnerState(() {
                                query = v;
                              });
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Add languages in device settings',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            // show the same dialog with platform-specific instructions
                            Navigator.of(context).pop();
                            _showLanguageSettingsDialog();
                          },
                        )
                      ],
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'No languages found for "$query".\nYou can add languages from device settings (tap the info icon).',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 0),
                            itemBuilder: (context, index) {
                              final l = filtered[index];
                              final label = _friendlyLocaleLabelForId(l.localeId);
                              final isSystem = l.localeId == _systemLocaleId;
                              return ListTile(
                                title: Text(label),
                                subtitle: Text(l.localeId),
                                trailing: isSystem
                                    ? Text('System',
                                        style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600))
                                    : null,
                                onTap: () {
                                  Navigator.of(context).pop(l.localeId);
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      await _handleLocaleSelection(selected);
    }
  }

  Future<void> _exportTranscriptToClipboard() async {
    try {
      final data = _transcriptLines.map((t) => t.toJson()).toList();
      final s = jsonEncode(data);
      await Clipboard.setData(ClipboardData(text: s));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transcript copied to clipboard (JSON)')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to copy transcript')),
        );
      }
    }
  }

  // Find if dropdown items already contain a value
  bool _dropdownContainsValue(List<DropdownMenuItem<String>> items, String value) {
    for (final it in items) {
      if (it.value == value) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final localeLabel = _currentLocaleId ?? _systemLocaleId ?? 'auto';
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;

    // Prepare a compact informative line count label for the app bar subtitle
    final linesText = _transcriptLines.isNotEmpty
        ? '${_transcriptLines.length} saved'
        : (_currentPartial.isNotEmpty ? 'Live' : 'No lines');

    final clearEnabled =
        !(_transcriptLines.isEmpty && _currentPartial.trim().isEmpty);

    // List of recommended short language codes to show in the compact dropdown (user-friendly)
    final recommendedCodes = ['en', 'hi', 'pa', 'bn', 'te', 'mr'];

    // Build dropdown items based on merged locales; find best match for each recommended code.
    final List<DropdownMenuItem<String>> dropdownItems = [];

    // 'Auto (System)' as the top option
    dropdownItems.add(DropdownMenuItem(
      value: '__auto__',
      child: Text(
        _systemLocaleId != null
            ? 'Auto (${_friendlyLocaleLabelForId(_systemLocaleId!)})'
            : 'Auto (System)',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ));

    for (final code in recommendedCodes) {
      final best = _bestLocaleForCode(code);
      if (best != null) {
        dropdownItems.add(DropdownMenuItem(
          value: best,
          child: Text(
            // Show a short friendly label without the long "(xx_YY)" to keep dropdown compact.
            _languageNames.containsKey(best)
                ? _languageNames[best]!
                : _languageNames.containsKey(code)
                    ? _languageNames[code]!
                    : _friendlyLocaleLabelForId(best),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ));
      }
    }

    // Add a separator-ish disabled item (can't do real separator in Dropdown) or just add a "More..." option
    dropdownItems.add(DropdownMenuItem(
      value: '__more__',
      child: Row(
        children: const [
          Icon(Icons.more_horiz, size: 18, color: Colors.black54),
          SizedBox(width: 8),
          Text('More languages...', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ));

    // If the currently selected locale isn't in the items (e.g., user selected a specific region variant),
    // add it so the Dropdown can display it.
    final selectedValueStr = _currentLocaleId ?? _systemLocaleId;
    if (selectedValueStr != null &&
        !_dropdownContainsValue(dropdownItems, selectedValueStr)) {
      // Add a dropdown item for the selected locale so it can be displayed in the button.
      dropdownItems.insert(
          1,
          DropdownMenuItem(
              value: selectedValueStr,
              child: Text(
                _friendlyLocaleLabelForId(selectedValueStr),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )));
    }

    // Colors & theme accents for a more attractive visual
    final primaryGradient = LinearGradient(
      colors: [Colors.indigo.shade800, Colors.blue.shade600],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: AppBar(
          elevation: 2,
          centerTitle: false,
          toolbarHeight: 96,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: primaryGradient,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 10,
                ),
              ],
            ),
            padding: const EdgeInsets.only(left: 18, right: 12, top: 18, bottom: 12),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Group Speech',
                          style: TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '$linesText • $localeLabel',
                              style: const TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                            const SizedBox(width: 8),
                            if (_isListening)
                              Row(
                                children: [
                                  const SizedBox(width: 6),
                                  const Icon(Icons.circle, size: 10, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Listening',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Replaced single export icon with a popup menu that includes enroll actions
                  PopupMenuButton<int>(
                    tooltip: 'Options',
                    onSelected: (val) async {
                      if (val == 0) {
                        await _exportTranscriptToClipboard();
                      } else if (val == 1) {
                        _enrollLastLinesForSpeaker('A');
                      } else if (val == 2) {
                        _enrollLastLinesForSpeaker('B');
                      } else if (val == 3) {
                        _resetSpeakerProfiles();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 0,
                        child: ListTile(
                          leading: Icon(Icons.file_download),
                          title: Text('Export transcript (JSON)'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 1,
                        child: ListTile(
                          leading: Icon(Icons.person_add),
                          title: Text('Enroll recent → Speaker A'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 2,
                        child: ListTile(
                          leading: Icon(Icons.person_add_alt_1),
                          title: Text('Enroll recent → Speaker B'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 3,
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('Reset speaker profiles'),
                        ),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.more_vert, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: clearEnabled ? _clearTranscript : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          clearEnabled ? Colors.redAccent.shade700 : Colors.redAccent.shade200,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
              child: Column(
                // use max so Expanded children can take available space and avoid overflow
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Improved Language selector - visually nicer and clearer using a compact dropdown + "More..."
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.language,
                            size: 20, color: Colors.blueAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _mergedLocales.isEmpty
                              ? const Text('Loading locales...',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.black54))
                              : DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: (_currentLocaleId ?? _systemLocaleId) ??
                                        '__auto__',
                                    items: dropdownItems,
                                    onChanged: (val) async {
                                      if (val == null) return;
                                      if (val == '__more__') {
                                        // open the detailed searchable picker
                                        await _showLocalePicker();
                                      } else if (val == '__auto__') {
                                        setState(() {
                                          _currentLocaleId = null;
                                        });
                                        if (_isListening) {
                                          // restart to use system locale
                                          await _restartListeningWithLocale(_systemLocaleId ?? '');
                                        }
                                      } else {
                                        await _handleLocaleSelection(val);
                                      }
                                    },
                                    selectedItemBuilder: (context) {
                                      // This controls how the selected value appears in the button
                                      return dropdownItems.map((item) {
                                        return Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            // Provide a compact user-friendly label for the selected item
                                            (item.value == '__auto__')
                                                ? (_systemLocaleId != null
                                                    ? 'Auto (${_friendlyLocaleLabelForId(_systemLocaleId!)})'
                                                    : 'Auto (System)')
                                                : (item.value == '__more__'
                                                    ? 'More languages...'
                                                    : _friendlyLocaleLabelForId(item.value.toString())),
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        );
                                      }).toList();
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),

                        const SizedBox(width: 10),
                        // Request mic permission button if not granted
                        if (!_micPermissionGranted)
                          ElevatedButton(
                            onPressed: () async {
                              final granted = await _ensureMicPermission();
                              setState(() {
                                _micPermissionGranted = granted;
                              });
                              if (granted) {
                                // attempt to initialize speech if not already available
                                if (!_speechAvailable) {
                                  await _initSpeech();
                                }
                                setState(() {
                                  _currentPartial = '';
                                });
                              } else {
                                setState(() {
                                  _currentPartial =
                                      'Microphone permission denied. Please enable it in system settings or retry.';
                                });
                              }
                            },
                            child: const Text('Request Mic'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Provide info button to instruct user how to add device languages
                        IconButton(
                          tooltip: 'How to add languages on device',
                          icon: const Icon(Icons.info_outline),
                          onPressed: _showLanguageSettingsDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Transcription area (centered) — make it expand to avoid overflow
                  Expanded(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // a small header row showing locale + confidence + count + speaker mode
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Locale: ${_currentLocaleId != null ? _friendlyLocaleLabelForId(_currentLocaleId!) : (_systemLocaleId != null ? _friendlyLocaleLabelForId(_systemLocaleId!) : 'Auto')}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const SizedBox(height: 12),
                            // Combined transcript list
                            Expanded(child: _buildCombinedTranscriptList()),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Single microphone button grouped with label; kept compact to avoid overflow
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Glow + animated mic button
                      GestureDetector(
                        onTap: !_speechAvailable || !_micPermissionGranted
                            ? null
                            : () {
                                if (_isListening) {
                                  // User requested stop -> stop listening and disable auto-restart
                                  _stopListening(userRequested: true);
                                } else {
                                  // User requests start -> enable continuous listening and start
                                  _keepListening = true;
                                  _startListening();
                                }
                              },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // glowing ring when listening
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 450),
                              width: _isListening ? 116 : 78,
                              height: _isListening ? 116 : 78,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _isListening
                                    ? RadialGradient(
                                        colors: [
                                          Colors.redAccent.withOpacity(0.18),
                                          Colors.redAccent.withOpacity(0.06),
                                          Colors.transparent
                                        ],
                                      )
                                    : RadialGradient(
                                        colors: [
                                          Colors.blue.withOpacity(0.06),
                                          Colors.transparent
                                        ],
                                      ),
                              ),
                            ),
                            Material(
                              shape: const CircleBorder(),
                              color: _isListening ? Colors.redAccent : Colors.blue,
                              elevation: 6,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isListening ? Icons.mic_off : Icons.mic,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
