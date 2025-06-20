import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  final bool isDarkMode;

  const PrivacyPolicyScreen({Key? key, required this.isDarkMode})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColors = isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColors.first,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bgColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: () => context.pop(),
          ),
          title: Text(
            'Privacy Policy',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 20,
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
