import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ContactSupportScreen extends StatefulWidget {
  final bool isDarkMode;

  const ContactSupportScreen({Key? key, this.isDarkMode = false})
      : super(key: key);

  @override
  _ContactSupportScreenState createState() => _ContactSupportScreenState();
}

class ChatMessage {
  final String text;
  final DateTime timestamp;
  final bool isUser;

  ChatMessage({
    required this.text,
    required this.timestamp,
    required this.isUser,
  });
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _userEmail;
  CollectionReference? _userMsgsCol;
  CollectionReference? _adminMsgsCol;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'ankush5kwt@gmail.com';
    if (email.isEmpty) {
      if (context.mounted && context.canPop()) context.pop();
      return;
    }
    setState(() {
      _userEmail = email;
      final chatDoc = FirebaseFirestore.instance
          .collection('supportChats')
          .doc(_userEmail);
      _userMsgsCol = chatDoc.collection('messages');
      _adminMsgsCol = chatDoc.collection('adminMessages');
      _loading = false;
    });
  }

  Stream<List<ChatMessage>> get _chatStream {
    if (_userMsgsCol == null || _adminMsgsCol == null) {
      return const Stream<List<ChatMessage>>.empty();
    }
    return Rx.combineLatest2<QuerySnapshot, QuerySnapshot, List<ChatMessage>>(
      _userMsgsCol!.orderBy('timestamp').snapshots(),
      _adminMsgsCol!.orderBy('timestamp').snapshots(),
          (userSnap, adminSnap) {
        final all = <ChatMessage>[];
        for (var d in userSnap.docs) {
          final data = d.data() as Map<String, dynamic>;
          final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          all.add(ChatMessage(text: data['text'] ?? '', timestamp: ts, isUser: true));
        }
        for (var d in adminSnap.docs) {
          final data = d.data() as Map<String, dynamic>;
          final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          all.add(ChatMessage(text: data['text'] ?? '', timestamp: ts, isUser: false));
        }
        all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return all;
      },
    );
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _userMsgsCol == null) return;
    _inputController.clear();
    await _userMsgsCol!.add({
      'text': text,
      'sender': 'user',
      'timestamp': FieldValue.serverTimestamp(),
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CircleAvatar(
            backgroundColor: widget.isDarkMode
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: widget.isDarkMode ? Colors.white : Colors.black),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/homeScreen');
                }
              },
            ),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            context.loc.contactSupport,
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.1, 0.7, 1.0],
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
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
            children: [
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _chatStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && (snapshot.data == null || snapshot.data!.isEmpty)) {
                      return const Center(
                          child: CircularProgressIndicator(color: Colors.white));
                    }
                    final msgs = snapshot.data ?? [];
                    if (msgs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No messages yet.\nSend us a message below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: msgs.length,
                      itemBuilder: (ctx, i) {
                        final m = msgs[i];
                        return _SupportChatBubble(
                          text: m.text,
                          timestamp: m.timestamp,
                          isUser: m.isUser,
                          isDarkMode: widget.isDarkMode,
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Colors.white54),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: widget.isDarkMode ? Colors.black54 : Colors.white70,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        style: TextStyle(
                            color: widget.isDarkMode ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: context.loc.typeAMsg,
                          hintStyle: TextStyle(
                              color: widget.isDarkMode ? Colors.white38 : Colors.black45),
                          border: InputBorder.none,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.send,
                        color: widget.isDarkMode ? Colors.tealAccent : Colors.blueAccent,
                      ),
                      onPressed: _handleSend,
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportChatBubble extends StatelessWidget {
  final String text;
  final DateTime timestamp;
  final bool isUser;
  final bool isDarkMode;

  const _SupportChatBubble({
    Key? key,
    required this.text,
    required this.timestamp,
    required this.isUser,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.purpleAccent,
                  child: Icon(Icons.support_agent,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text(context.loc.supportReplied,
                    style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDarkMode
                      ? [Colors.deepPurpleAccent, Colors.tealAccent]
                      : [Colors.blueAccent, Colors.lightBlueAccent],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style:
                      const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('h:mm a').format(timestamp),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final bubbleColor = isDarkMode
        ? Colors.tealAccent.withOpacity(0.8)
        : Colors.blueAccent;
    final textColor = isDarkMode ? Colors.black : Colors.white;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(text,
                  style: TextStyle(color: textColor, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                DateFormat('h:mm a').format(timestamp),
                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
