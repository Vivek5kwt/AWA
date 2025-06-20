import 'dart:convert';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/routing/routes.dart';

class NotificationItem {
  final String id;
  final String sender;
  final String message;
  final DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.sender,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      sender: json['sender'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class NotificationScreen extends StatefulWidget {
  final bool isDarkMode;
  const NotificationScreen({Key? key, this.isDarkMode = false}) : super(key: key);

  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _loading = true;
  String? _error;
  List<NotificationItem> _notifications = [];
  late String _userEmail;

  @override
  void initState() {
    super.initState();
    _initUserAndFetch();
  }

  Future<void> _initUserAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('email') ?? '';
    await _fetchNotifications();
  }

  void showAccountDeletedDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "accountDeleted",
      pageBuilder: (ctx, _, __) => WillPopScope(
        onWillPop: () async => false,
        child: Container(
          color: widget.isDarkMode ? Color(0xFF181A20) : Color(0xFFFCF6BA),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Material(
                borderRadius: BorderRadius.circular(26),
                color: widget.isDarkMode
                    ? Colors.blueGrey[900]!.withOpacity(0.98)
                    : Colors.white.withOpacity(0.97),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        color: widget.isDarkMode
                            ? Colors.cyanAccent
                            : Colors.deepPurpleAccent,
                        size: 55,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Your account has been blocked",
                        style: TextStyle(
                          color: widget.isDarkMode
                              ? Colors.cyanAccent
                              : Colors.deepPurpleAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "For security reasons, your account was blocked by admin. Please contact our support team for assistance.",
                        style: TextStyle(
                          color: widget.isDarkMode
                              ? Colors.white70
                              : Colors.blueGrey.shade700,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isDarkMode
                              ? Colors.cyanAccent.withOpacity(0.85)
                              : Colors.deepPurpleAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 38, vertical: 14),
                        ),
                        icon: Icon(
                          Icons.support_agent_rounded,
                          color: widget.isDarkMode ? Colors.black : Colors.white,
                          size: 26,
                        ),
                        label: Text(
                          "Contact Support",
                          style: TextStyle(
                              color: widget.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.3),
                        ),
                        onPressed: () {
                          context.go(Routes.login);
                        },
                      ),
                      const SizedBox(height: 15),
                      TextButton(
                          onPressed: () {
                            context.go(Routes.login);
                          },
                          child: Text(
                            "Exit App",
                            style: TextStyle(
                                color: widget.isDarkMode
                                    ? Colors.cyanAccent
                                    : Colors.deepPurpleAccent,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold),
                          )
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
        '${ApiConstants.getNotification}?to_email=${_userEmail}',
      );
      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = data['notifications'] as List<dynamic>? ?? [];
        setState(() {
          _notifications = raw
              .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }

      else if (resp.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        setState(() {
          _loading = false;
        });
        return;
      }
      else if (resp.statusCode == 404) {
        setState(() {
          _notifications = [];
        });
      }
      else {
        setState(() => _error = 'Failed to load: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteNotification(String id) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        '${ApiConstants.deleteNotification}?_id=${Uri.encodeComponent(id)}&to_email=${Uri.encodeComponent(_userEmail)}',
      );
      final resp = await http.delete(uri);
      if (resp.statusCode == 200) {
        await _fetchNotifications();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: ${resp.statusCode}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  void _markAsRead(NotificationItem note) {
    setState(() {
      note.isRead = true;
    });
    // Optionally: send read-status update to server
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isDarkMode
        ? [Color(0xFF121212), Color(0xFF1E1E1E)]
        : [Color(0xFF0093E9), Color(0xFF80D0C7)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title:  ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            "Notifications",
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
        centerTitle: true,
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _notifications.isEmpty
              ? _NoNotificationsWidget(isDarkMode: widget.isDarkMode)
              : RefreshIndicator(
            onRefresh: _fetchNotifications,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _notifications.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (ctx, i) {
                final note = _notifications[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Slidable(
                    key: ValueKey(note.id),
                    endActionPane: ActionPane(
                      motion: const StretchMotion(),
                      extentRatio: 0.32,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _deleteNotification(note.id),
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ],
                    ),
                    child: GestureDetector(
                      onTap: () => _markAsRead(note),
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.isDarkMode
                              ? Colors.white.withOpacity(0.05)
                              : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: Icon(
                            note.isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: note.isRead ? Colors.grey : Colors.blueAccent,
                            size: 28,
                          ),
                          title: Text(
                            note.sender,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: widget.isDarkMode
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                note.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white70
                                      : Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${note.timestamp.hour.toString().padLeft(2, '0')}:'
                                    '${note.timestamp.minute.toString().padLeft(2, '0')} '
                                    '${note.timestamp.day}/${note.timestamp.month}/${note.timestamp.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.isDarkMode
                                      ? Colors.white38
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NoNotificationsWidget extends StatelessWidget {
  final bool isDarkMode;

  const _NoNotificationsWidget({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off,
            size: 90,
            color: isDarkMode ? Colors.white70 : Colors.grey[700],
          ),
          const SizedBox(height: 18),
          Text(
            'No notifications found!',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.blueGrey.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 18.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'You’re all caught up.',
            style: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.blueGrey.shade400,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
