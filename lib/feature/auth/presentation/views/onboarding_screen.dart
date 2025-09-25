import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/routing/routes.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _pageIndex = 0;

  final List<_OnboardData> _pages = [
    _OnboardData(
      title: "Text Every Spoken Word",
      subtitle: "Real-time speech-to-text for the deaf.",
      description:
      "AWA instantly converts spoken conversations into clear, readable text—making it easy for deaf individuals to follow group discussions.",
      imageAsset: "https://cdn-icons-png.flaticon.com/512/1082/1082435.png",
    ),
    _OnboardData(
      title: "Instant Voice to Text",
      subtitle: "Never miss what’s said.",
      description:
      "AWA listens to every word and shows it as text immediately, helping the hearing impaired stay engaged in real time.",
      imageAsset: "https://cdn-icons-png.flaticon.com/512/2920/2920039.png",
    ),
    _OnboardData(
      title: "Inclusive Group Conversations",
      subtitle: "Empowering deaf communication.",
      description:
      "Feel confident and connected. AWA ensures deaf and hard-of-hearing users are part of every conversation—clearly and equally.",
      imageAsset: "https://cdn-icons-png.flaticon.com/512/3135/3135715.png",
    ),
  ];


  Future<void> finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOnboarded', true);
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0093E9),
              Color(0xFF80D0C7),
              Color(0xFFFCF6BA),
            ],
            stops: [0.1, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (index) => setState(() => _pageIndex = index),
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    final isCurrent = i == _pageIndex;
                    return AnimatedScale(
                      scale: isCurrent ? 1.0 : 0.92,
                      duration: Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 34),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 20),
                            Container(
                              height: 210,
                              width: 210,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(36),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12.withOpacity(0.10),
                                    blurRadius: 18,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(26.0),
                                child: Image.network(page.imageAsset, fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 27,
                                color: Colors.blue.shade900,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              page.subtitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Color(0xFF0B486B),
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              page.description,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.blueGrey.shade900.withOpacity(0.7),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              _OnboardIndicator(current: _pageIndex, total: _pages.length),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38.0),
                child: _GlassButton(
                  onPressed: () {
                    if (_pageIndex == _pages.length - 1) {
                      finishOnboarding();
                    } else {
                      _controller.nextPage(
                        duration: Duration(milliseconds: 420),
                        curve: Curves.easeInOutCubic,
                      );
                    }
                  },
                  label: _pageIndex == _pages.length - 1 ? "Get Started" : "Next",
                ),
              ),
              const SizedBox(height: 42),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardData {
  final String title;
  final String subtitle;
  final String description;
  final String imageAsset;

  _OnboardData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imageAsset,
  });
}

class _OnboardIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _OnboardIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        total,
            (i) => AnimatedContainer(
          duration: Duration(milliseconds: 370),
          width: i == current ? 38 : 10,
          height: 10,
          margin: EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            gradient: i == current
                ? const LinearGradient(
              colors: [Color(0xFF00B4DB), Color(0xFF3282B8)],
            )
                : null,
            color: i == current ? null : Colors.white.withOpacity(0.35),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _GlassButton({
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // Glass background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 0.4,
                  shadows: [
                    Shadow(
                      blurRadius: 7,
                      color: Colors.white.withOpacity(0.16),
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
