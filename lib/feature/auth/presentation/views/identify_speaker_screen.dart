
import 'package:flutter/material.dart';

import '../../../../core/speaker/speaker_service.dart';

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
  Map<String, int> _registered = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.init();
    await _refreshRegisteredList();
  }

  Future<void> _refreshRegisteredList() async {
    final map = await _service.listRegisteredWithCounts();
    if (mounted) setState(() => _registered = map);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes')),
        ],
      ),
    );
  }
}
