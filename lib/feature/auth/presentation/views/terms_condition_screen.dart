import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  final bool isDarkMode;

  const TermsAndConditionsScreen({Key? key, required this.isDarkMode})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColors = isDarkMode
        ? [const Color(0xFF181A20), const Color(0xFF232526), const Color(0xFF181A20)]
        : [const Color(0xFF0093E9), const Color(0xFF80D0C7), const Color(0xFFFCF6BA)];

    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
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
            'Terms & Conditions',
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
                  Text('1. Acceptance of Terms',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Text(
                    'By downloading or using AWA, you agree to be bound by these Terms & Conditions.',
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
                    'AWA grants you a revocable, non-exclusive, non-transferable, limited license to download, install, and use the app solely for your personal, non-commercial purposes.',
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
                    'In no event shall AWA be liable for any indirect, incidental, or consequential damages arising out of your use of the app.',
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
                      'Thank you for using AWA!',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textColor),
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
