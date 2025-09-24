import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/routing/routes.dart';

class SpeakerScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isDarkMode;

  const SpeakerScreen({
    Key? key,
    required this.phoneNumber,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  SpeakerScreenState createState() => SpeakerScreenState();
}

class SpeakerScreenState extends State<SpeakerScreen> with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<Speaker> _speakers = [];
  String _email = '';
  String _loginType = '';
  bool _showIntro = false;

  late final AnimationController _listAnimController;

  final List<List<Color>> _avatarGradients = [
    [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
    [Color(0xFFf7971e), Color(0xFFFFD200)],
    [Color(0xFF43e97b), Color(0xFF38f9d7)],
    [Color(0xFF9795f0), Color(0xFFfbc7d4)],
    [Color(0xFFf857a6), Color(0xFFFF5858)],
    [Color(0xFF30cfd0), Color(0xFF330867)],
    [Color(0xFF5f2c82), Color(0xFF49a09d)],
  ];

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(vsync: this, duration: Duration(milliseconds: 900));
    _loadSettingsAndFetch();
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
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

  Future<void> _loadSettingsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _email = prefs.getString('email') ?? '';
      _loginType = prefs.getString('login_type') ?? '';
      _showIntro = !(prefs.getBool('speaker_intro_shown') ?? false);
    });
    if (_showIntro) await prefs.setBool('speaker_intro_shown', true);
    await _fetchSpeakers();
  }

  /// Fetch speakers from server.
  /// If [showLoading] is false, we won't show the full-screen loading spinner or clear the current list.
  /// This is useful when performing background refreshes (e.g. after delete) to avoid flicker.
  Future<void> _fetchSpeakers({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _speakers = [];
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      final uri = Uri.parse('${ApiConstants.listSpeaker}$_email');
      final resp = await http.get(uri);

      if (resp.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        if (showLoading) {
          setState(() {
            _loading = false;
          });
        }
        return;
      } else if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = data['speakers'] as List<dynamic>? ?? [];
        if (mounted) {
          setState(() {
            _speakers = raw.map((e) => Speaker.fromJson(e as Map<String, dynamic>)).toList();
            _error = null;
          });
          _listAnimController.forward(from: 0);
        }
      } else {
        if (mounted) setState(() => _error = 'Load failed: ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (showLoading && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _goToAddSpeaker() async {
    final result = await context.push<bool>(
      '/addContact',
      extra: {
        'phoneNumber': widget.phoneNumber,
        'isDarkMode': widget.isDarkMode,
      },
    );
    if (result == true) {
      await _fetchSpeakers();
    }
  }

  Future<void> _deleteSpeaker(Speaker s) async {
   final speakerEmail = s.email.isNotEmpty ? s.email : s.id;
    final encodedSpeaker = Uri.encodeComponent(speakerEmail);

    final operatorRaw =  s.name;
    final encodedOperator = Uri.encodeComponent(operatorRaw);

    final endpoint = Uri .parse('${ApiConstants.deleteSpeaker}$encodedSpeaker/$encodedOperator');
    print('eggedfsfsf $endpoint');

    try {
      final response = await http.delete(endpoint);

      if (response.statusCode == 200 || response.statusCode == 204) {
        String serverMessage = 'Speaker deleted successfully';
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map && data['message'] != null) {
              serverMessage = data['message'].toString();
            }
          } catch (_) {
          }
        }

        setState(() {
          _speakers.removeWhere((element) => element.id == s.id || element.email == s.email);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverMessage),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );

        await _fetchSpeakers(showLoading: false);
        return;
      }

      String message = 'Delete failed: ${response.statusCode}';
      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] != null) {
            message = data['message'].toString();
          } else if (data is Map && data['errors'] != null) {
            message = data['errors'].toString();
          } else if (data is String) {
            message = data;
          }
        } catch (_) {
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext ctx, Speaker s) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor:
        widget.isDarkMode ? const Color(0xFF262635) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          context.loc.deleteSpeaker,
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '${context.loc.areYouSure} ${s.name} ${context.loc.removeFromFriend}',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => context.pop(),
            child: Text(
              context.loc.cancel,
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () {
              context.pop();
              _deleteSpeaker(s);
            },
            child:  Text(
              context.loc.delete,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isDarkMode
        ? [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];

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
            context.loc.registerSpeaker,
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
      floatingActionButton: _speakers.isNotEmpty?
      FloatingActionButton.extended(
        backgroundColor: widget.isDarkMode
            ? Colors.cyanAccent.withOpacity(0.9)
            : Colors.deepPurpleAccent,
        elevation: 5,
        icon: Icon(Icons.person_add_alt_1_rounded,
            color: widget.isDarkMode ? Colors.black : Colors.white, size: 27),
        label: Text(
          context.loc.addSpeaker,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: widget.isDarkMode ? Colors.black : Colors.white),
        ),
        onPressed: _goToAddSpeaker,
      ):SizedBox(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                  : _error != null
                  ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
              )
                  : RefreshIndicator(
                onRefresh: _fetchSpeakers,
                color: widget.isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent,
                backgroundColor: widget.isDarkMode ? Colors.grey[900]! : Colors.white,
                edgeOffset: 20,
                child: _speakers.isEmpty
                    ? _NoSpeakersWidget(
                  isDarkMode: widget.isDarkMode,
                  phoneNumber: widget.phoneNumber,
                  onAdd: _goToAddSpeaker,
                )
                    : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12, left: 18, right: 18, bottom: 40),
                  itemCount: _speakers.length,
                  itemBuilder: (_, i) {
                    final s = _speakers[i];
                    final avatarColors = _avatarGradients[i % _avatarGradients.length];
                    final anim = Tween<Offset>(
                        begin: Offset(0, 0.16 * (i + 1)), end: Offset.zero)
                        .animate(CurvedAnimation(
                      parent: _listAnimController,
                      curve: Interval(0.05 * i, 0.4 + 0.10 * i, curve: Curves.easeOut),
                    ));
                    return SlideTransition(
                      position: anim,
                      child: FadeTransition(
                        opacity: _listAnimController,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Slidable(
                            key: ValueKey(s.id),
                            endActionPane: ActionPane(
                              motion: const DrawerMotion(),
                              extentRatio: 0.32,
                              children: [
                                SlidableAction(
                                  borderRadius: BorderRadius.circular(20),
                                  autoClose: true,
                                  onPressed: (_) => _confirmDelete(context, s),
                                  backgroundColor: Colors.redAccent.withOpacity(0.09),
                                  foregroundColor: Colors.redAccent,
                                  icon: Icons.delete_outline_rounded,
                                  label: context.loc.delete,
                                  spacing: 6,
                                ),
                              ],
                            ),
                            child: GestureDetector(
                              onLongPress: () => _confirmDelete(context, s),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      "This is a registered speaker (voice only)",
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    backgroundColor: Colors.blueGrey[800],
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.isDarkMode
                                          ? Colors.black.withOpacity(0.12)
                                          : Colors.black.withOpacity(0.10),
                                      blurRadius: 14,
                                      spreadRadius: 0,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                  color: widget.isDarkMode
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.white.withOpacity(0.18),
                                  border: Border(
                                    left: BorderSide(
                                      color: avatarColors[0],
                                      width: 7,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  leading: Container(
                                    width: 53,
                                    height: 53,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: avatarColors,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: avatarColors[1].withOpacity(0.14),
                                          blurRadius: 14,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        s.name.isNotEmpty
                                            ? s.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 26,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(1, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 10,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        s.name,
                                        style: TextStyle(
                                          color: widget.isDarkMode
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 19,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: widget.isDarkMode
                                              ? Colors.cyanAccent.withOpacity(0.19)
                                              : Colors.deepPurpleAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.record_voice_over,
                                                size: 15,
                                                color: widget.isDarkMode
                                                    ? Colors.cyanAccent
                                                    : Colors.deepPurpleAccent),
                                            const SizedBox(width: 5),
                                            Text(
                                              context.loc.voiceRegisteredOnly,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (s.embeddingCount > 1)
                                        Text(
                                          '${s.embeddingCount} voice samples',
                                          style: TextStyle(
                                            color: widget.isDarkMode
                                                ? Colors.cyanAccent.withOpacity(0.85)
                                                : Colors.deepPurpleAccent,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                  },
                ),
              ),
            ),
            if (_showIntro) _buildIntroOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroOverlay(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showIntro = false),
        child: Container(
          color: Colors.black87.withOpacity(0.7),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_search, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                Text(
                  context.loc.speakerListIntro,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  context.loc.speakerAddIntro,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoSpeakersWidget extends StatelessWidget {
  final bool isDarkMode;
  final String phoneNumber;
  final Future<void> Function() onAdd;
  const _NoSpeakersWidget({
    required this.isDarkMode,
    required this.phoneNumber,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            isDarkMode
                ? 'assets/images/empty_dark.png'
                : 'assets/images/empty_light.png',
            width: 135,
            height: 135,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Text(
            context.loc.noSpeakerRegister,
            style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.blueGrey.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 19),
          ),
          const SizedBox(height: 7),
          Text(
            context.loc.tapBelowToRegister,
            style: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.blueGrey.shade400,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode
                  ? Colors.cyanAccent.withOpacity(0.9)
                  : Colors.deepPurpleAccent,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.person_add_alt_1_rounded,
                color: isDarkMode ? Colors.black : Colors.white, size: 26),
            label: Text(
              context.loc.registerSpeaker,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.black : Colors.white),
            ),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class Speaker {
  final String id;
  final String name;
  final String email;
  final int embeddingCount;

  Speaker({
    required this.id,
    required this.name,
    required this.email,
    required this.embeddingCount,
  });

  factory Speaker.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final idStr = rawId != null ? rawId.toString() : '';

    final rawName = json['name'];
    final nameStr = rawName != null ? rawName.toString() : '';

    final rawEmail = json['email'];
    final emailStr = rawEmail != null ? rawEmail.toString() : '';

    final rawEmbedding = json['embedding_count'];
    int embedding = 0;
    if (rawEmbedding is int) {
      embedding = rawEmbedding;
    } else if (rawEmbedding is String) {
      embedding = int.tryParse(rawEmbedding) ?? 0;
    } else if (rawEmbedding is double) {
      embedding = rawEmbedding.toInt();
    }

    return Speaker(
      id: idStr,
      name: nameStr,
      email: emailStr,
      embeddingCount: embedding,
    );
  }
}
