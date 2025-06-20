import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/routing/routes.dart';

class SplashView extends StatefulWidget {
  const SplashView({Key? key}) : super(key: key);

  @override
  _SplashViewState createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _shapesController;
  late final AnimationController _lettersController;
  late final Animation<double> _letter1Scale;
  late final Animation<double> _letter2Scale;
  late final Animation<double> _letter3Scale;
  late final Animation<double> _letter1Opacity;
  late final Animation<double> _letter2Opacity;
  late final Animation<double> _letter3Opacity;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    _shapesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _lettersController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _letter1Scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );
    _letter2Scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.2, 0.6, curve: Curves.elasticOut),
      ),
    );
    _letter3Scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.4, 0.8, curve: Curves.elasticOut),
      ),
    );

    _letter1Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.0, 0.4),
      ),
    );
    _letter2Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.2, 0.6),
      ),
    );
    _letter3Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _lettersController,
        curve: const Interval(0.4, 0.8),
      ),
    );

    _lettersController.forward();
    _startSplash();
  }

  Future<void> _startSplash() async {
    await Future.delayed(const Duration(seconds: 4));
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedIn') ?? false;
    final phone = prefs.getString('phoneNumber') ?? '';
    final email = prefs.getString('email') ?? '';
    final isOnboarded = prefs.getBool('isOnboarded') ?? false;

    if (!isOnboarded) {
      if (mounted) context.goNamed('onboarding');
    } else if (loggedIn && (phone.isNotEmpty || email.isNotEmpty)) {
      if (mounted) context.goNamed(
        Routes.homeScreen,
        queryParameters: {'phoneNumber': phone},
      );
    } else {
      if (mounted) context.goNamed('login');
    }
  }

  @override
  void dispose() {
    _shapesController.dispose();
    _lettersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 48,
      fontWeight: FontWeight.bold,
      letterSpacing: 4,
    );

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
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _shapesController,
              builder: (_, __) {
                const count = 8;
                final radius = size.width * 0.35;
                return Stack(
                  children: List.generate(count, (i) {
                    final angle = _shapesController.value * 2 * pi +
                        (2 * pi / count) * i;
                    final dx = radius * cos(angle);
                    final dy = radius * sin(angle);
                    return Positioned(
                      left: size.width / 2 + dx - 12,
                      top: size.height / 2 + dy - 12,
                      child: Transform.rotate(
                        angle: angle,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.primaries[
                            i % Colors.primaries.length
                            ],
                            shape: i.isEven ? BoxShape.circle : BoxShape.rectangle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _letter1Scale,
                  child: FadeTransition(
                    opacity: _letter1Opacity,
                    child: const Text('A', style: textStyle),
                  ),
                ),
                const SizedBox(width: 8),
                ScaleTransition(
                  scale: _letter2Scale,
                  child: FadeTransition(
                    opacity: _letter2Opacity,
                    child: const Text('W', style: textStyle),
                  ),
                ),
                const SizedBox(width: 8),
                ScaleTransition(
                  scale: _letter3Scale,
                  child: FadeTransition(
                    opacity: _letter3Opacity,
                    child: const Text('A', style: textStyle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
