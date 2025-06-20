import 'dart:convert';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/routing/routes.dart';

class FriendBookScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isDarkMode;

  const FriendBookScreen({
    Key? key,
    required this.phoneNumber,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  _FriendBookScreenState createState() => _FriendBookScreenState();
}

class _FriendBookScreenState extends State<FriendBookScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<String> _friendEmails = [];
  String _email = '';

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
    _listAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 950),
    );
    _loadEmailAndFetch();
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadEmailAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _email = prefs.getString('email') ?? '';
    });
    await _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    setState(() {
      _loading = true;
      _error = null;
      _friendEmails = [];
    });

    try {
      final queryEmail = Uri.encodeComponent(_email);
      final uri = Uri.parse('${ApiConstants.listFriends}?user_email=$queryEmail');
      print('Friend API call: $uri');
      final resp = await http.get(uri);

      // If status code is 204 - Account deleted by admin
      if (resp.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        setState(() {
          _loading = false;
        });
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawList = data['friends'] as List<dynamic>? ?? [];
        List<String> parsedEmails = [];
        for (var entry in rawList) {
          final map = entry as Map<String, dynamic>;
          final email = (map['email'] ?? '').toString().trim();
          if (email.isNotEmpty) parsedEmails.add(email);
        }
        print('Loaded friend emails: $parsedEmails');
        setState(() {
          _friendEmails = parsedEmails;
        });
        _listAnimController.forward(from: 0);
      } else {
        setState(() => _error = 'Load failed: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteFriend(String friendEmail) async {
    final endpoint = Uri.parse(
      '${ApiConstants.deleteFriends}?user_email=$_email&friend_email=$friendEmail',
    );

    try {
      var request = http.Request('POST', endpoint)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({});

      var streamed = await request.send();
      var response = await http.Response.fromStream(streamed);

      if ((response.statusCode == 307 || response.statusCode == 302) &&
          streamed.headers.containsKey('location')) {
        final location = streamed.headers['location']!;
        final newUri = Uri.parse(location);

        request = http.Request('POST', newUri)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({});

        streamed = await request.send();
        response = await http.Response.fromStream(streamed);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = data['message']?.toString() ?? 'Friend removed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        await _fetchFriends();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: ${response.statusCode}'),
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

  void _confirmDelete(BuildContext ctx, String friendEmail) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor:
        widget.isDarkMode ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Remove Friend',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "${friendEmail.split('@').first}" from your friends?',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor:
              widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteFriend(friendEmail);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Mock profile for UI demo
  Future<FriendProfile> _getMockFriendProfile(String email) async {
    int hash = email.hashCode;
    return FriendProfile(
      name: email.split('@').first.capitalize(),
      email: email,
      age: 20 + (hash % 14), // 20..33
      married: (hash % 3 == 0),
      bio: "Passionate coder, explorer, and coffee lover. Always up for a new challenge!",
      hobbies: ["Reading", "Cycling", "Music", "Movies", "Coding"],
    );
  }

  void _showProfileSheet(String email, int avatarIndex) async {
    FriendProfile profile = await _getMockFriendProfile(email);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return _FriendProfileSheet(
          profile: profile,
          avatarColors: _avatarGradients[avatarIndex % _avatarGradients.length],
          isDarkMode: widget.isDarkMode,
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isDarkMode
        ? [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            "My Friends",
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
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CircleAvatar(
            backgroundColor: widget.isDarkMode
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back,
                  color: widget.isDarkMode ? Colors.white : Colors.black),
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
              ? const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          )
              : _error != null
              ? Center(
            child: Text(
              _error!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 16),
            ),
          )
              : RefreshIndicator(
            onRefresh: _fetchFriends,
            color: widget.isDarkMode
                ? Colors.cyanAccent
                : Colors.deepPurpleAccent,
            backgroundColor: widget.isDarkMode
                ? Colors.grey[900]!
                : Colors.white,
            edgeOffset: 20,
            child: _friendEmails.isEmpty
                ? _NoFriendsWidget(isDarkMode: widget.isDarkMode)
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                  top: 12, left: 18, right: 18, bottom: 40),
              itemCount: _friendEmails.length,
              itemBuilder: (_, i) {
                final friendEmail = _friendEmails[i];
                final displayName = friendEmail.split('@').first;
                final avatarColors =
                _avatarGradients[i % _avatarGradients.length];
                final anim = Tween<Offset>(
                  begin: Offset(0, 0.18 * (i + 1)),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _listAnimController,
                  curve: Interval(0.06 * i, 0.4 + 0.11 * i,
                      curve: Curves.easeOut),
                ));
                // Defensive: don't allow empty email to be sent
                return SlideTransition(
                  position: anim,
                  child: FadeTransition(
                    opacity: _listAnimController,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 7),
                      child: Slidable(
                        key: ValueKey(friendEmail),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.32,
                          children: [
                            SlidableAction(
                              borderRadius:
                              BorderRadius.circular(20),
                              autoClose: true,
                              onPressed: (_) => _confirmDelete(
                                  context, friendEmail),
                              backgroundColor: Colors.redAccent
                                  .withOpacity(0.09),
                              foregroundColor: Colors.redAccent,
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              spacing: 6,
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onTap: () =>
                              _showProfileSheet(friendEmail, i),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius:
                              BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.isDarkMode
                                      ? Colors.black
                                      .withOpacity(0.14)
                                      : Colors.black
                                      .withOpacity(0.11),
                                  blurRadius: 12,
                                  offset: Offset(0, 7),
                                ),
                              ],
                              color: widget.isDarkMode
                                  ? Colors.white.withOpacity(0.07)
                                  : Colors.white
                                  .withOpacity(0.16),
                              border: Border(
                                left: BorderSide(
                                    color: avatarColors[0],
                                    width: 7),
                              ),
                            ),
                            child: ListTile(
                              contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12),
                              leading: Container(
                                width: 49,
                                height: 49,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: avatarColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: avatarColors[1]
                                          .withOpacity(0.12),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName[0]
                                        .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                      FontWeight.bold,
                                      fontSize: 23,
                                      shadows: [
                                        Shadow(
                                            color:
                                            Colors.black26,
                                            blurRadius: 3,
                                            offset:
                                            Offset(1, 2)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18.5,
                                ),
                              ),

                              trailing: IconButton(
                                icon: Icon(
                                  Icons.chat_bubble_rounded,
                                  color: widget.isDarkMode
                                      ? Colors.cyanAccent
                                      : Colors.deepPurpleAccent,
                                  size: 30,
                                ),
                                onPressed: () {
                                  if (friendEmail.isNotEmpty) {
                                    print('Navigating to chatList for: $friendEmail');
                                    context.pushNamed(
                                      'chatList',
                                      extra: {
                                        'name': displayName,
                                        'phoneNumber':
                                        widget.phoneNumber,
                                        'id': friendEmail,
                                        friendEmail: friendEmail,
                                      },
                                    );

                                  } else {
                                    print('Error: Friend email empty, not navigating!');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Friend email missing!'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                                tooltip: 'Chat',
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
      ),
    );
  }
}

class _FriendProfileSheet extends StatefulWidget {
  final FriendProfile profile;
  final List<Color> avatarColors;
  final bool isDarkMode;
  const _FriendProfileSheet({
    required this.profile,
    required this.avatarColors,
    required this.isDarkMode,
  });

  @override
  State<_FriendProfileSheet> createState() => _FriendProfileSheetState();
}

class _FriendProfileSheetState extends State<_FriendProfileSheet> {
  bool showMore = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return DraggableScrollableSheet(
      initialChildSize: 0.47,
      minChildSize: 0.36,
      maxChildSize: 0.86,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: widget.isDarkMode
              ? const Color(0xFF232526).withOpacity(0.97)
              : Color(0xFFFCF6BA).withOpacity(0.97),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: widget.isDarkMode
                  ? Colors.black.withOpacity(0.23)
                  : Colors.blueGrey.withOpacity(0.09),
              blurRadius: 28,
              spreadRadius: 1,
            )
          ],
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          children: [
            Center(
              child: AnimatedContainer(
                duration: Duration(milliseconds: 900),
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: widget.avatarColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: widget.avatarColors[1].withOpacity(0.22),
                        blurRadius: 18,
                        offset: Offset(0, 7))
                  ],
                ),
                child: Center(
                  child: Text(
                    p.name.isNotEmpty ? p.name[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                            color: Colors.black38,
                            blurRadius: 6,
                            offset: Offset(1, 3))
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                p.name,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode
                      ? Colors.cyanAccent
                      : Colors.deepPurpleAccent,
                ),
              ),
            ),
            Center(
              child: Text(
                p.email,
                style: TextStyle(
                  color: widget.isDarkMode
                      ? Colors.white54
                      : Colors.blueGrey.shade700,
                  fontSize: 15.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _InfoChip(
                  icon: Icons.cake_rounded,
                  label: "Age: ${p.age}",
                  isDark: widget.isDarkMode,
                ),
                const SizedBox(width: 13),
                _InfoChip(
                  icon: Icons.favorite_rounded,
                  label: p.married ? "Married" : "Unmarried",
                  isDark: widget.isDarkMode,
                  color: p.married
                      ? Colors.pinkAccent.withOpacity(0.85)
                      : Colors.teal.withOpacity(0.8),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedCrossFade(
              duration: Duration(milliseconds: 330),
              crossFadeState:
              showMore ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      showMore = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDarkMode
                        ? Colors.cyanAccent.withOpacity(0.78)
                        : Colors.deepPurpleAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  ),
                  label: Text("Know More",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16.3,
                        color: widget.isDarkMode ? Colors.black : Colors.white,
                      )),
                ),
              ),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    p.bio,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: widget.isDarkMode
                          ? Colors.white70
                          : Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: p.hobbies
                        .map((h) => Chip(
                      label: Text(h),
                      backgroundColor: widget.isDarkMode
                          ? Colors.cyanAccent.withOpacity(0.14)
                          : Colors.deepPurpleAccent.withOpacity(0.09),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: widget.isDarkMode
                            ? Colors.cyanAccent
                            : Colors.deepPurpleAccent,
                      ),
                    ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color? color;
  const _InfoChip(
      {required this.icon, required this.label, required this.isDark, this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color ??
          (isDark
              ? Colors.white.withOpacity(0.13)
              : Colors.deepPurpleAccent.withOpacity(0.10)),
      avatar: Icon(icon,
          size: 18,
          color: isDark ? Colors.cyanAccent : Colors.deepPurpleAccent),
      label: Text(label,
          style: TextStyle(
              color: isDark ? Colors.cyanAccent : Colors.deepPurpleAccent,
              fontWeight: FontWeight.w600,
              fontSize: 15)),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    );
  }
}

class _NoFriendsWidget extends StatelessWidget {
  final bool isDarkMode;

  const _NoFriendsWidget({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            isDarkMode
                ? 'assets/images/empty_friends_dark.png'
                : 'assets/images/empty_friends_light.png',
            width: 132,
            height: 132,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 18),
          Text(
            'No friends yet!',
            style: TextStyle(
              color:
              isDarkMode ? Colors.white70 : Colors.blueGrey.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 18.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Find and add your friends to start chatting.',
            style: TextStyle(
              color: isDarkMode
                  ? Colors.white38
                  : Colors.blueGrey.shade400,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class FriendProfile {
  final String name;
  final String email;
  final int age;
  final bool married;
  final String bio;
  final List<String> hobbies;

  FriendProfile({
    required this.name,
    required this.email,
    required this.age,
    required this.married,
    required this.bio,
    required this.hobbies,
  });
}

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
