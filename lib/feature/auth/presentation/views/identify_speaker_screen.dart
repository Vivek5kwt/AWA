import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../../core/speaker/speaker_service.dart';

/// A simplified speaker identification screen that performs all
/// processing offline using [SpeakerService].
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
  final Record _recorder = Record();

  bool _isRecording = false;
  String? _identifiedId;

  @override
  void initState() {
    super.initState();
    _service.init();
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      await _recorder.start();
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopAndIdentify() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path != null) {
      final id = await _service.identify(path);
      setState(() => _identifiedId = id);
    }
  }

  Future<void> _stopAndEnroll() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path != null) {
      final newId = DateTime.now().millisecondsSinceEpoch.toString();
      await _service.enroll(newId, path);
      setState(() => _identifiedId = newId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    return Scaffold(
      appBar: AppBar(title: const Text('Speaker Identification')),
      backgroundColor: widget.isDarkMode ? Colors.black : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _identifiedId == null ? 'Unknown speaker' : 'Matched: $_identifiedId',
              style: TextStyle(color: textColor, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isRecording ? _stopAndIdentify : _startRecording,
              child: Text(_isRecording ? 'Stop & Identify' : 'Record'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isRecording ? _stopAndEnroll : _startRecording,
        tooltip: 'Enroll new speaker',
        child: Icon(_isRecording ? Icons.check : Icons.mic),
      ),
    );
  }
}
