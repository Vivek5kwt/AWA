import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/routing/routes.dart';

class FriendListScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isDarkMode;

  const FriendListScreen({
    Key? key,
    required this.phoneNumber,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  _FriendListScreenState createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<User> _users = [];
  String _email = '';
  bool _showIntro = false;

  final List<List<Color>> _avatarGradients = [
    [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
    [Color(0xFFf7971e), Color(0xFFFFD200)],
    [Color(0xFF43e97b), Color(0xFF38f9d7)],
    [Color(0xFF9795f0), Color(0xFFfbc7d4)],
    [Color(0xFFf857a6), Color(0xFFFF5858)],
    [Color(0xFF30cfd0), Color(0xFF330867)],
    [Color(0xFF5f2c82), Color(0xFF49a09d)],
  ];
  late final AnimationController _listAnimController;

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 950),
    );
    _loadIntro();
    _loadEmailAndFetch();
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadIntro() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('friend_list_intro_shown') ?? false;
    if (mounted) setState(() => _showIntro = !shown);
    if (!shown) await prefs.setBool('friend_list_intro_shown', true);
  }

  Future<void> _loadEmailAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _email = prefs.getString('email') ?? '';
    });
    await _fetchUsers();
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

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
      _users = [];
    });

    try {
      final queryEmail = Uri.encodeComponent(_email);
      final uri = Uri.parse('${ApiConstants.listUsers}?email=$queryEmail');
      final resp = await http.post(uri);

      // ==== CORRECTED STATUS CODE LOGIC ====
      if (resp.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        setState(() {
          _loading = false;
        });
        return;
      } else if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawList = data['users'] as List<dynamic>? ?? [];

        setState(() {
          _users = rawList
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
          _error = null;
        });
        _listAnimController.forward(from: 0);
      } else {
        setState(() => _error = 'Load failed: ${resp.statusCode}');
      }
      // =======================================
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _sendFriendRequest(User u) async {
    final endpoint = Uri.parse(
      '${ApiConstants.addFriend}?user_email=$_email&friend_email=${u.email}',
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
        final message = data['message']?.toString() ?? 'Request sent';
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
        await _fetchUsers();
        _sendFriendNotification(friendEmail: u.email);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request failed: ${response.statusCode}'),
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

  Future<void> _sendFriendNotification({required String friendEmail}) async {
    try {
      final url = Uri.parse(ApiConstants.sendFriendNotification);
      final response = await http.post(
        url,
        body: {
          'user_email': _email,
          'friend_email': friendEmail,
        },
      );
      if (response.statusCode != 200) {
        debugPrint('Friend notification failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Friend notification error: $e');
    }
  }
  // Show bottom sheet with user info
  void _showUserProfileSheet(User u, List<Color> avatarColors) {

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UserProfileSheet(
        user: u,
        avatarColors: avatarColors,
        isDarkMode: widget.isDarkMode,
      ),
    );
  }

  Widget _buildIntroOverlay() {
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
                const Icon(Icons.person_add_alt_1, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                Text(
                  context.loc.friendListIntro,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  context.loc.friendAddIntro,
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
            context.loc.friendList,
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
      body: Stack(
        children: [
          Container(
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
              ? Center (
            child: Text(
              _error!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 16),
            ),
          )
              : RefreshIndicator(
            onRefresh: _fetchUsers,
            color: widget.isDarkMode
                ? Colors.cyanAccent
                : Colors.deepPurpleAccent,
            backgroundColor:
            widget.isDarkMode ? Colors.grey[900]! : Colors.white,
            edgeOffset: 20,
            child: _users.isEmpty
                ? _NoUsersWidget(isDarkMode: widget.isDarkMode)
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                  top: 12, left: 18, right: 18, bottom: 40),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final avatarColors = _avatarGradients[i % _avatarGradients.length];
                final anim = Tween<Offset>(
                    begin: Offset(0, 0.18 * (i + 1)),
                    end: Offset.zero)
                    .animate(CurvedAnimation(
                  parent: _listAnimController,
                  curve: Interval(0.06 * i, 0.4 + 0.11 * i,
                      curve: Curves.easeOut),
                ));
                return SlideTransition(
                  position: anim,
                  child: FadeTransition(
                    opacity: _listAnimController,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: GestureDetector(
                        onTap: () => _showUserProfileSheet(u, avatarColors),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: widget.isDarkMode
                                    ? Colors.black.withOpacity(0.14)
                                    : Colors.black.withOpacity(0.11),
                                blurRadius: 12,
                                offset: Offset(0, 7),
                              ),
                            ],
                            color: widget.isDarkMode
                                ? Colors.white.withOpacity(0.07)
                                : Colors.white.withOpacity(0.16),
                            border: Border(
                              left: BorderSide(
                                color: avatarColors[0],
                                width: 7,
                              ),
                            ),
                          ),
                          child: ListTile(
                            contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                    color: avatarColors[1].withOpacity(0.12),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  u.name.isNotEmpty
                                      ? u.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 23,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        blurRadius: 3,
                                        offset: Offset(1, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              u.name,
                              style: TextStyle(
                                color: widget.isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 18.5,
                              ),
                            ),

                            trailing: SizedBox(
                              width: 98,
                              child: IconButton(
                                icon: Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: widget.isDarkMode
                                      ? Colors.cyanAccent
                                      : Colors.deepPurpleAccent,
                                  size: 28,
                                ),
                                onPressed: () =>
                                    _sendFriendRequest(u),
                                tooltip: 'Add Friend',
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
          ),),
          if (_showIntro) _buildIntroOverlay(),
        ],
      ),
    );
  }
}

class _UserProfileSheet extends StatefulWidget {
  final User user;
  final List<Color> avatarColors;
  final bool isDarkMode;
  const _UserProfileSheet({
    required this.user,
    required this.avatarColors,
    required this.isDarkMode,
  });

  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet> {
  bool showMore = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    // Mock info for 'more' section
    final bio =
        "Hey, I'm ${u.name.split(' ').first}";
    final hobbies = ["Travel", "Sports", "Reading", "Coding", "Art"];

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.36,
      maxChildSize: 0.82,
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
                  ? Colors.black.withOpacity(0.21)
                  : Colors.blueGrey.withOpacity(0.09),
              blurRadius: 24,
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
                    u.name.isNotEmpty ? u.name[0].toUpperCase() : "?",
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
                u.name,
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
                u.email,
                style: TextStyle(
                  color: widget.isDarkMode
                      ? Colors.white54
                      : Colors.blueGrey.shade700,
                  fontSize: 15.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _InfoChip(
                  icon: Icons.calendar_month,
                  label: "Joined: ${_formatDate(u.registeredAt)}",
                  isDark: widget.isDarkMode,
                ),
              ],
            ),
            const SizedBox(height: 15),
            AnimatedCrossFade(
              duration: Duration(milliseconds: 340),
              crossFadeState:
              showMore ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      showMore = true;
                    });
                  },
                  icon: Icon(Icons.info_outline_rounded, size: 22),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    bio,
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
                    children: hobbies
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

  String _formatDate(String date) {
    try {
      final dt = DateTime.parse(date);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (_) {
      return date;
    }
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


class _NoUsersWidget extends StatelessWidget {
  final bool isDarkMode;

  const _NoUsersWidget({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_off,
            size: 90,
            color: isDarkMode ? Colors.white70 : Colors.grey[700],
          ),
          const SizedBox(height: 18),
          Text(
            context.loc.noUserFound,
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.blueGrey.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 18.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            context.loc.inviteOrSearch,
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

class User {
  final String name;
  final String email;
  final String registeredAt;

  User({
    required this.name,
    required this.email,
    required this.registeredAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] as String,
      email: json['email'] as String,
      registeredAt: json['registered_at'] as String,
    );
  }
}
