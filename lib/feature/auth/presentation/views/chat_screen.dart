import 'dart:async';
import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';
import '../../../../config/firebase_push.dart';

class ChatScreen extends StatefulWidget {
  final String name;
  final String phoneNumber;
  final String id;
  final String? token;
  final bool isDarkMode;

  const ChatScreen({
    Key? key,
    required this.name,
    required this.phoneNumber,
    required this.id,
    this.token,
    this.isDarkMode = false,
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
      message: text,
    );
    _scrollToLatest();
  }

  Future<void> _sendNotification({
    required String fromEmail,
    required String message,
  }) async {
    if (widget.token == null || widget.token!.isEmpty) return;
    try {
      final url = Uri.parse('https://fcm.googleapis.com/fcm/send');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=${FcmConfig.serverKey}',
        },
        body: jsonEncode({
          'to': widget.token,
          'notification': {
            'title': fromEmail,
            'body': message,
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }),
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
    final chatGradient = widget.isDarkMode
        ? [const Color(0xFF232526), const Color(0xFF414345)]
        : [const Color(0xFF7F7FD5), const Color(0xFF86A8E7), const Color(0xFF91EAE4)];
    final backgroundColor = widget.isDarkMode ? const Color(0xFF232526) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF35394B);
    final hintTextColor = widget.isDarkMode ? Colors.white60 : Colors.black45;
    final bubbleColorMe = widget.isDarkMode ? const Color(0xFF3D8BE9) : const Color(0xFF5B86E5);
    final bubbleColorOther = widget.isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.92);
    final myIconColor = widget.isDarkMode ? Colors.white : Colors.black;
    final shadowColor = widget.isDarkMode ? Colors.black26 : Colors.black.withOpacity(0.09);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: backgroundColor,
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
                  color: shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: myIconColor, size: 28),
                  onPressed: () {
                    context.pop();
                  },
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: widget.isDarkMode
                      ? const Color(0xFF1F6E8C)
                      : const Color(0xFF38f9d7),
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Colors.black12,
                              blurRadius: 4,
                            ),
                          ],
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
                            typing ? context.loc.typing : context.loc.online,
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
                  icon: Icon(Icons.videocam_rounded, color: myIconColor, size: 29),
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
                      return Center(
                        child: CircularProgressIndicator(
                          color: widget.isDarkMode
                              ? Colors.white
                              : Colors.blueAccent,
                        ),
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
                                color: widget.isDarkMode
                                    ? Colors.white12
                                    : Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 18),
                            Text(
                              '${context.loc.noMsgYet}\n${context.loc.startTheConversation}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white54
                                      : Colors.white.withOpacity(0.8),
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
                          isDarkMode: widget.isDarkMode,
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
                    color: widget.isDarkMode
                        ? Colors.white10
                        : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
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
                          style: TextStyle(color: textColor, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: context.loc.typeAMsg,
                            hintStyle: TextStyle(color: hintTextColor),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: _onTextChanged,
                          onSubmitted: (_) => _handleSend(),
                          cursorColor: widget.isDarkMode
                              ? Colors.lightBlueAccent
                              : Colors.blueAccent,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send_rounded,
                            color: widget.isDarkMode
                                ? Colors.blueAccent.shade100
                                : Colors.white,
                            size: 26),
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
  final bool isDarkMode;

  const _ChatBubble({
    Key? key,
    required this.text,
    required this.timestamp,
    this.isMe = false,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final myColor = isDarkMode ? const Color(0xFF1565C0) : const Color(0xFF5B86E5);
    final otherColor = isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.92);
    final textColor = isMe
        ? Colors.white
        : (isDarkMode ? Colors.white70 : const Color(0xFF35394B));
    final timeColor = (isMe
        ? Colors.white
        : (isDarkMode ? Colors.white70 : const Color(0xFF35394B)))
        .withOpacity(0.57);

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
              color: isDarkMode
                  ? Colors.black.withOpacity(0.14)
                  : Colors.black.withOpacity(0.10),
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
                color: textColor,
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
                    color: timeColor,
                    fontSize: 11.7,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all_rounded,
                      color: isDarkMode
                          ? Colors.lightBlueAccent
                          : Colors.lightBlueAccent.shade100,
                      size: 16),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
