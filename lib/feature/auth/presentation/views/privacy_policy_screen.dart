import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  final bool isDarkMode;

  const PrivacyPolicyScreen({Key? key, required this.isDarkMode})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColors = isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];
    final gradientColors = isDarkMode
        ? const [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : const [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColors.first,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            context.loc.privacyPolicy,
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
            backgroundColor: isDarkMode
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.white : Colors.black),
              onPressed: () => Navigator.of(context).pop(),
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
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Introduction',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Welcome to AWA. Your privacy is critically important to us. This Policy explains how we collect, use, and protect your information.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '2. Information We Collect',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Personal Data: Name, email, phone number.\n'
                        '• Usage Data: App interactions, crash reports.\n'
                        '• Device Data: Device model, OS version, IP address.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '3. How We Use Your Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We use your information to:\n'
                        '• Provide and improve our service.\n'
                        '• Send you transactional notifications.\n'
                        '• Diagnose technical issues.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '4. Data Sharing',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We do not share personal data with third parties except:\n'
                        '• With your consent.\n'
                        '• For legal compliance.\n'
                        '• To service providers under NDA.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '5. Data Security',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We implement reasonable security measures to protect your data. However, no method of transmission is 100% secure.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '6. Children’s Privacy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'AWA is not directed to children under 13. We do not knowingly collect data from minors.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '7. Your Choices',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You may:\n'
                        '• Access, correct, or delete your personal data.\n'
                        '• Opt out of non-essential communications.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '8. Changes to Privacy Policy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We may update this Policy. Continued use after changes constitutes acceptance.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 32),

                  Center(
                    child: Text(
                      'Thank you for trusting AWA with your privacy.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
