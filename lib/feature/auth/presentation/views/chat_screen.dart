import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';
import '../../../../core/network/http_service.dart';

class ChatScreen extends StatefulWidget {
  final String name;           // Friend's name (for app bar)
  final String phoneNumber;    // Friend's phone number
  final String id;             // Friend's email (ALWAYS friend's email)

  const ChatScreen({
    Key? key,
    required this.name,
    required this.phoneNumber,
    required this.id,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _userEmail;
  String? _chatId;
  CollectionReference? _messagesCol;
  DocumentReference? _chatDoc;

  bool _isTyping = false;
  Timer? _typingTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('email') ?? '';
    if (_userEmail == null || _userEmail!.isEmpty) {
      // handle user not logged in
      if (mounted) Navigator.of(context).pop();
      return;
    }
    List<String> emails = [_userEmail!, widget.id];
    emails.sort();
    _chatId = emails.join('_');
    _chatDoc = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    _messagesCol = _chatDoc!.collection('messages');
    setState(() {
      _isLoading = false;
    });
  }

  void _onTextChanged(String text) {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    if (!_isTyping && _chatDoc != null && _userEmail != null) {
      _isTyping = true;
      _chatDoc!.set({
        'typing': {_userEmail!: true}
      }, SetOptions(merge: true));
    }
    _typingTimer = Timer(const Duration(seconds: 1), () {
      _isTyping = false;
      if (_chatDoc != null && _userEmail != null) {
        _chatDoc!.set({
          'typing': {_userEmail!: false}
        }, SetOptions(merge: true));
      }
    });
  }

  Stream<bool> _friendTypingStream() {
    if (_chatDoc == null) return const Stream<bool>.empty();
    return _chatDoc!.snapshots().map((snap) {
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final typing = data['typing'] as Map<String, dynamic>? ?? {};
      return typing[widget.id] == true;
    });
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _messagesCol == null || _userEmail == null) return;
    _inputController.clear();
    _typingTimer?.cancel();
    _chatDoc?.set({
      'typing': {_userEmail!: false}
    }, SetOptions(merge: true));
    await _messagesCol!.add({
      'text': text,
      'sender': _userEmail,
      'receiver': widget.id,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _sendNotification(
      fromEmail: _userEmail!,
      toEmail: widget.id,
      message: text,
    );
    _scrollToLatest();
  }

  Future<void> _sendNotification({
    required String fromEmail,
    required String toEmail,
    required String message,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.sendNotification);
      final response = await http.post(
        url,
        body: {
          'from_email': fromEmail,
          'to_email': toEmail,
          'message': message,
        },
      );
      if (response.statusCode != 200) {
        debugPrint('Notification failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  void _scrollToLatest() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatGradient = const [
      Color(0xFF7F7FD5),
      Color(0xFF86A8E7),
      Color(0xFF91EAE4),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(75),
        child: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: chatGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.09),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                  onPressed: () {
                    context.pop();
                  },
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF38f9d7),
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      _isLoading || _chatDoc == null
                          ? Container(height: 17)
                          : StreamBuilder<bool>(
                        stream: _friendTypingStream(),
                        builder: (context, snapshot) {
                          final typing = snapshot.data ?? false;
                          return Text(
                            typing ? 'Typing...' : 'Online',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 14,
                              fontStyle: typing ? FontStyle.italic : null,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 29),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video call is under development')),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: chatGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _isLoading || _chatId == null || _userEmail == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _messagesCol!
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_rounded,
                                size: 70,
                                color: Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 18),
                            Text(
                              'No messages yet.\nStart the conversation!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final data = docs[i].data()! as Map<String, dynamic>;
                        final isMe = data['sender'] == _userEmail;
                        return _ChatBubble(
                          text: data['text'] ?? '',
                          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
                          isMe: isMe,
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                                color: Colors.white70.withOpacity(0.9)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: _onTextChanged,
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 26),
                        onPressed: _handleSend,
                        splashRadius: 27,
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

class _ChatBubble extends StatelessWidget {
  final String text;
  final DateTime timestamp;
  final bool isMe;

  const _ChatBubble({
    Key? key,
    required this.text,
    required this.timestamp,
    this.isMe = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final myColor = const Color(0xFF5B86E5);
    final otherColor = Colors.white.withOpacity(0.92);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe ? myColor : otherColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(isMe ? 19 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 19),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 9,
              offset: const Offset(1, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF35394B),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(
                  DateFormat('h:mm a').format(timestamp),
                  style: TextStyle(
                    color: (isMe ? Colors.white : const Color(0xFF35394B))
                        .withOpacity(0.57),
                    fontSize: 11.7,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all_rounded,
                      color: Colors.lightBlueAccent.shade100, size: 16),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
