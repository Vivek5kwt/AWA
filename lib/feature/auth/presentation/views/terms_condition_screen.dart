import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
class TermsAndConditionsScreen extends StatelessWidget {
  final bool isDarkMode;

  const TermsAndConditionsScreen({Key? key, required this.isDarkMode})
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
    final subTextColor  = isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
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
            context.loc.termsAndConditions,
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
                  Text('1. Acceptance of Terms',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'By downloading or using Hearing Access, you agree to be bound by these Terms & Conditions.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('2. Privacy Policy',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'Our Privacy Policy describes how we handle your personal data and protect your privacy when you use our app.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('3. License to Use',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'Hearing Access grants you a revocable, non-exclusive, non-transferable, limited license to download, install, and use the app solely for your personal, non-commercial purposes.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('4. Restrictions',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'You agree not to (a) reverse engineer or decompile the app; (b) distribute or sublicense the app; (c) remove any proprietary notices.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('5. Disclaimer of Warranties',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'The app is provided “AS IS” and “AS AVAILABLE” without warranties of any kind.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('6. Limitation of Liability',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'In no event shall Hearing Access be liable for any indirect, incidental, or consequential damages arising out of your use of the app.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('7. Governing Law',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'These Terms are governed by the laws of India without regard to conflict of laws principles.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 16),

                  Text('8. Changes to Terms',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'We may modify these Terms at any time. Continued use of the app means you accept those changes.',
                    style: TextStyle(color: subTextColor),
                  ),
                  const SizedBox(height: 32),

                  Center(
                    child: Text(
                      'Thank you for using Hearing Access!',
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
