import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

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
  static const _kSpeakersKey = 'local_speakers_v1';

  bool _loading = true;
  String? _error;
  List<Speaker> _speakers = [];
  String _email = '';
  String _loginType = '';
  bool _showIntro = false;

  late final AnimationController _listAnimController;

  final List<List<Color>> _avatarGradients = const [
    [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
    [Color(0xFFF7971E), Color(0xFFFFD200)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFF9795F0), Color(0xFFFBC7D4)],
    [Color(0xFFF857A6), Color(0xFFFF5858)],
    [Color(0xFF30CFD0), Color(0xFF330867)],
    [Color(0xFF5F2C82), Color(0xFF49A09D)],
  ];

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _loadSettingsAndLocalData();
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _email = prefs.getString('email') ?? '';
        _loginType = prefs.getString('login_type') ?? '';
        _showIntro = !(prefs.getBool('speaker_intro_shown') ?? false);
      });
      if (_showIntro) await prefs.setBool('speaker_intro_shown', true);

      await _loadSpeakersFromLocal();
      _listAnimController.forward(from: 0);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSpeakersFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSpeakersKey);
    if (raw == null || raw.isEmpty) {
      setState(() => _speakers = []);
      return;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final items = list.map((e) => Speaker.fromJson(e)).toList();
      setState(() => _speakers = items);
    } catch (e) {
      setState(() {
        _speakers = [];
        _error = 'Failed to read local speakers ($e).';
      });
    }
  }

  Future<void> _saveSpeakersToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_speakers.map((s) => s.toJson()).toList());
    await prefs.setString(_kSpeakersKey, data);
  }

  Future<void> _goToAddSpeaker() async {
    final result = await _showAddSpeakerDialog();
    if (result == null) return;

    final newSpeaker = Speaker(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: result.name.trim(),
      email: result.email?.trim() ?? '',
      embeddingCount: result.samples ?? 0,
    );

    setState(() => _speakers.add(newSpeaker));
    await _saveSpeakersToLocal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('context.loc.speakerAdded' ?? 'Speaker added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteSpeaker(Speaker s) async {
    setState(() => _speakers.removeWhere((e) => e.id == s.id));
    await _saveSpeakersToLocal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('context.loc.speakerDeleted' ?? 'Speaker deleted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, Speaker s) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: widget.isDarkMode ? const Color(0xFF262635) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black87),
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
            child: Text(context.loc.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<_NewSpeakerFormResult?> _showAddSpeakerDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: _email);
    final samplesCtrl = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();

    return showDialog<_NewSpeakerFormResult>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded),
              const SizedBox(width: 8),
              Text(context.loc.registerSpeaker),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'context.loc.name' ?? 'Name',
                      hintText: 'e.g., Vivek',
                    ),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? ('context.loc.name' ?? 'Name') + ' required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: InputDecoration(
                      labelText: 'context.loc.email' ?? 'Email',
                      hintText: 'name@example.com',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: samplesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Voice samples (optional)',
                      hintText: '0',
                    ),
keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(context.loc.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final samples = int.tryParse(samplesCtrl.text.trim());
                Navigator.pop(
                  ctx,
                  _NewSpeakerFormResult(
                    name: nameCtrl.text,
                    email: emailCtrl.text,
                    samples: samples ?? 0,
                  ),
                );
              },
              icon: const Icon(Icons.check),
              label: Text('context.loc.save' ?? 'Save'),
            ),
          ],
        );
      },
    );
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
            context.loc.registerSpeaker,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 1.1,
              shadows: [Shadow(color: Colors.black26, blurRadius: 5, offset: Offset(1, 2))],
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
      floatingActionButton: _speakers.isNotEmpty
          ? FloatingActionButton.extended(
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
        onPressed: (){
          context.pushNamed(
            'addContact',
            extra: {
              'name': '',
              'phoneNumber': widget.phoneNumber,
              'isDarkMode': widget.isDarkMode
            },
          );
        },
      )
          : const SizedBox(),
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
                onRefresh: _loadSpeakersFromLocal,
                color: widget.isDarkMode ? Colors.cyanAccent : Colors.deepPurpleAccent,
                backgroundColor: widget.isDarkMode ? Colors.grey[900]! : Colors.white,
                edgeOffset: 20,
                child: _speakers.isEmpty
                    ? _NoSpeakersWidget(
                  isDarkMode: widget.isDarkMode,
                  phoneNumber: widget.phoneNumber,
                  onAdd: () => context.pushNamed(
                    'addContact',
                    extra: {
                      'name': '',
                      'phoneNumber': widget.phoneNumber,
                      'isDarkMode': widget.isDarkMode
                    },
                  ),
                )
                    : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                  const EdgeInsets.only(top: 12, left: 18, right: 18, bottom: 40),
                  itemCount: _speakers.length,
                  itemBuilder: (_, i) {
                    final s = _speakers[i];
                    final avatarColors =
                    _avatarGradients[i % _avatarGradients.length];
                    final anim = Tween<Offset>(
                      begin: Offset(0, 0.16 * (i + 1)),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _listAnimController,
                        curve: Interval(0.05 * i, 0.4 + 0.10 * i, curve: Curves.easeOut),
                      ),
                    );
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
                                    duration: const Duration(seconds: 2),
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
                                      offset: const Offset(0, 8),
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
                                          offset: const Offset(0, 4),
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 4),
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
                                              style: const TextStyle(
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
                                      if (s.embeddingCount > 0)
                                        Text(
                                          '${s.embeddingCount} voice sample${s.embeddingCount == 1 ? '' : 's'}',
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
    return Speaker(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      embeddingCount: json['embedding_count'] is int
          ? json['embedding_count'] as int
          : int.tryParse('${json['embedding_count'] ?? 0}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'embedding_count': embeddingCount,
  };
}

class _NewSpeakerFormResult {
  final String name;
  final String? email;
  final int? samples;

  _NewSpeakerFormResult({required this.name, this.email, this.samples});
}
