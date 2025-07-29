import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'feature/common_widgets/custom_toast.dart';
import 'core/utils/routing/routes_generator.dart';
import 'dart:async';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final messaging = FirebaseMessaging.instance;
  String? token;
  try {
    token = await messaging.getToken();
    print('FCM token: $token');
  } catch (e) {
    print('Error fetching FCM token: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  if (token != null && token.isNotEmpty) {
    await prefs.setString('fcm_token', token);
  }

  final bool isOnboarded = prefs.getBool('isOnboarded') ?? false;
  String? langCode = prefs.getString('language_code');
  Locale initialLocale = langCode != null ? Locale(langCode) : const Locale('en');

  runApp(MyApp(
    isOnboarded: isOnboarded,
    initialLocale: initialLocale,
  ));
}

class MyApp extends StatefulWidget {
  final bool isOnboarded;
  final Locale initialLocale;

  const MyApp({
    Key? key,
    required this.isOnboarded,
    required this.initialLocale,
  }) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();

  /// Call this anywhere with: MyApp.setLocale(context, Locale('hi'));
  static void setLocale(BuildContext context, Locale newLocale) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }
}

class _MyAppState extends State<MyApp> {
  late Locale _locale;
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.none) {
        toast(
            msg: "Please check your Internet Connection",
            isError: true);
      }
    });
  }

  void setLocale(Locale locale) async {
    setState(() => _locale = locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) => MaterialApp.router(
        title: 'Awa',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primarySwatch: Colors.blue),
        routerConfig: appRouter,
        locale: _locale,
        supportedLocales: const [
          Locale('en'),
          Locale('hi'),
          Locale('pa'),
          Locale('gu'),
          Locale('ta'),
          Locale('mr'),
          Locale('bn'),
          Locale('ur'),
        ],

        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (deviceLocale, supportedLocales) {
          if (deviceLocale == null) return supportedLocales.first;
          for (var supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == deviceLocale.languageCode) {
              return supportedLocale;
            }
          }
          return supportedLocales.first;
        },
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
