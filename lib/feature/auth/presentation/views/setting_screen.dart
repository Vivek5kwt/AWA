import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'transaction_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;

  const SettingsScreen({
    Key? key,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;
  String _selectedLanguage = 'English';
  bool _notificationsEnabled = true;
  bool _speakOnMeeting = true;
  final List<String> _languages = ['English', 'Hindi', 'Spanish', 'French'];

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'English';
      _notificationsEnabled = prefs.getBool('notifications') ?? true;
      _speakOnMeeting = prefs.getBool('speakOnMeeting') ?? true;
    });
  }

  Future<void> _updateLanguage(String? lang) async {
    if (lang == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    setState(() => _selectedLanguage = lang);
  }

  Future<void> _updateNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications', value);
    setState(() => _notificationsEnabled = value);
  }

  Future<void> _updateSpeakOnMeeting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('speakOnMeeting', value);
    setState(() => _speakOnMeeting = value);
  }

  void _navigateToTerms() {
    context.pushNamed(
      'termsCondition',
      extra: {'isDarkMode': _isDarkMode},
    );
  }

  void _navigateToPrivacy() {
    context.pushNamed(
      'privacyScreen',
      extra: {'isDarkMode': _isDarkMode},
    );
  }

  void _navigateToSupport() {
    context.pushNamed(
      'contactSupportScreen',
      extra: {'isDarkMode': _isDarkMode},
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _isDarkMode
        ? const [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : const [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];

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
            "Settings",
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
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 16),

              // App Language Card
            /*  Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.5)
                    : Colors.white.withOpacity(0.84),
                child: ListTile(
                  leading:
                  const Icon(Icons.language, color: Colors.deepPurple),
                  title: Text(
                    'App Language',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  trailing: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: _isDarkMode
                          ? Colors.grey[800]
                          : Colors.white,
                      iconTheme: IconThemeData(
                        color:
                        _isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      underline: const SizedBox(),
                      dropdownColor: _isDarkMode
                          ? Colors.grey[800]
                          : Colors.white,
                      iconEnabledColor:
                      _isDarkMode ? Colors.white : Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      style: TextStyle(
                        color:
                        _isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      items: _languages.map((lang) {
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Row(
                            children: [
                              Icon(
                                Icons.language,
                                size: 20,
                                color: Colors.deepPurpleAccent
                                    .withOpacity(0.8),
                              ),
                              const SizedBox(width: 10),
                              Text(lang),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _updateLanguage,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),*/

              // Notifications Toggle
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.5)
                    : Colors.white.withOpacity(0.84),
                child: SwitchListTile(
                  title: Text(
                    'Notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  secondary: Icon(
                    _notificationsEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: Colors.deepPurple,
                  ),
                  value: _notificationsEnabled,
                  onChanged: _updateNotifications,
                ),
              ),

              const SizedBox(height: 16),

              // Speak on Meeting Toggle
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.5)
                    : Colors.white.withOpacity(0.84),
                child: SwitchListTile(
                  title: Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          color: Colors.deepPurple),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Speak my messages in meetings',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _speakOnMeeting
                        ? "Your messages will be spoken aloud to everyone."
                        : "Your messages will not be auto-spoken. You can tap play to speak.",
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  value: _speakOnMeeting,
                  onChanged: _updateSpeakOnMeeting,
                ),
              ),

              const SizedBox(height: 16),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 5,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final email = prefs.getString('email') ?? '';
                    if (email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('User email not found'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }
                    context.pushNamed(
                      'transactions',
                      extra: {
                        'isDarkMode': _isDarkMode,
                        'email': email,
                      },
                    );
                  },

                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isDarkMode
                            ? [Theme.of(context).primaryColorDark, Theme.of(context).colorScheme.secondary]
                            : [Theme.of(context).primaryColor, Theme.of(context).colorScheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 30,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'My Transactions',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'View payment history & receipts',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- Rest as before ---

              const SizedBox(height: 16),

              // Legal & Policies Header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Legal & Policies',
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Terms & Conditions
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.4)
                    : Colors.white.withOpacity(0.9),
                child: ListTile(
                  leading: const Icon(Icons.description, color: Colors.teal),
                  title: Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey),
                  onTap: _navigateToTerms,
                ),
              ),

              const SizedBox(height: 8),

              // Privacy Policy
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.4)
                    : Colors.white.withOpacity(0.9),
                child: ListTile(
                  leading:
                  const Icon(Icons.privacy_tip, color: Colors.tealAccent),
                  title: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey),
                  onTap: _navigateToPrivacy,
                ),
              ),

              const SizedBox(height: 24),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 6,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _navigateToSupport,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isDarkMode
                            ? [
                          Theme.of(context).primaryColorDark,
                          Theme.of(context).colorScheme.secondary,
                        ]
                            : [
                          Theme.of(context).primaryColor,
                          Theme.of(context).colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Icon(
                          Icons.support_agent,
                          size: 30,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contact Support',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Get help or report issues',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                        ),
                      ],
                    ),
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
