import 'package:awa/core/utils/routing/routes.dart';
import 'package:awa/feature/auth/presentation/views/setting_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../feature/auth/presentation/views/add_contact_screen.dart';
import '../../../feature/auth/presentation/views/chat_screen.dart';
import '../../../feature/auth/presentation/views/complete_profile_screen.dart';
import '../../../feature/auth/presentation/views/customer_support_screen.dart';
import '../../../feature/auth/presentation/views/friend_book.dart';
import '../../../feature/auth/presentation/views/friend_list_screen.dart';
import '../../../feature/auth/presentation/views/group_speach_text.dart';
import '../../../feature/auth/presentation/views/home_screen.dart';
import '../../../feature/auth/presentation/views/identify_speaker_screen.dart';
import '../../../feature/auth/presentation/views/login_screen.dart';
import '../../../feature/auth/presentation/views/notification_screen.dart';
import '../../../feature/auth/presentation/views/onboarding_screen.dart';
import '../../../feature/auth/presentation/views/premium_intro_screen.dart';
import '../../../feature/auth/presentation/views/privacy_policy_screen.dart';
import '../../../feature/auth/presentation/views/splash_view.dart';
import '../../../feature/auth/presentation/views/terms_condition_screen.dart';
import '../../../feature/auth/presentation/views/transaction_screen.dart';
import '../../../feature/auth/presentation/views/verification_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.splash,
  routes: [
    GoRoute(
      path: Routes.splash,
      name: 'splash',
      builder: (context, state) => const SplashView(),
    ),
    GoRoute(
      path: Routes.login,
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      name: 'verify',
      path: '/verify',
      builder: (context, state) => VerificationScreen(
        phoneNumber: state.uri.queryParameters['phoneNumber'] ?? '',
        sessionId: state.uri.queryParameters['sessionId'] ?? '',
      ),
    ),
    GoRoute(
      path: Routes.completeProfile,
      name: 'completeProfile',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final args = state.uri.queryParameters;
        return CompleteProfileScreen(
          phoneNumber: extra['phoneNumber'] ?? args['phoneNumber'] ?? '',
          isUpdate: extra['isUpdate'] ?? (args['isUpdate'] == 'true'),
          isDarkMode: extra['isDarkMode'] ?? (args['isDarkMode'] == 'true'),
        );
      },
    ),
    GoRoute(
      path: Routes.addContact,
      name: 'addContact',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>? ?? {};
        return AddContactScreen(
          name: args['name'] ?? '',
          phoneNumber: args['phoneNumber'] ?? '',
          isDarkMode: args['isDarkMode'] ?? false,
        );
      },
    ),
    GoRoute(
      path: Routes.homeScreen,
      name: Routes.homeScreen,
      builder: (context, state) {
        final extra = state.extra as String? ?? '';
        return HomeScreen(phoneNumber: extra);
      },
    ),
    GoRoute(
      path: '/contactSupport',
      name: 'contactSupportScreen',
      builder: (context, state) => ContactSupportScreen(
        isDarkMode:
            state.extra != null && (state.extra as Map)['isDarkMode'] == true,
      ),
    ),
    GoRoute(
      path: Routes.identifySpeakerScreen,
      name: 'identifySpeakerScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final phone = extra['phoneNumber'] ?? '';
        final isDarkMode = extra['isDarkMode'] ?? false;
        return GroupSpeechToTextScreen(
          phoneNumber: phone,
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.speakerScreen,
      name: 'speakerScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final phone = extra['phoneNumber'] ?? '';
        final isDarkMode = extra['isDarkMode'] ?? false;
        return SpeakerScreen(
          phoneNumber: phone,
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.chatList,
      name: 'chatList',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>? ?? {};
        final isDarkMode = (args['isDarkMode'] ?? 'false') == 'true';
        return ChatScreen(
          name: args['name'] ?? '',
          phoneNumber: args['phoneNumber'] ?? '',
          id: args['id'] ?? '',
          token: args['token'] as String?,
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.friendBookScreen,
      name: 'friendBookScreen',
      builder: (context, state) {
        final args = state.uri.queryParameters;
        final phone = args['phoneNumber'] ?? '';
        final isDarkMode = (args['isDarkMode'] ?? 'false') == 'true';
        return FriendListScreen(
          phoneNumber: phone,
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.friendListScreen,
      name: 'friendListScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final phone = extra['phoneNumber'] ?? '';
        final isDarkMode = extra['isDarkMode'] ?? false;
        return FriendBookScreen(
          phoneNumber: phone,
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.settingsScreen,
      name: 'settingsScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final isDarkMode = extra['isDarkMode'] ?? false;
        return SettingsScreen(
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.onboarding,
      name: 'onboarding',
      builder: (context, state) => OnboardingScreen(),
    ),
    GoRoute(
      path: Routes.notificationScreen,
      name: 'notificationScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final isDarkMode = extra['isDarkMode'] ?? false;
        return NotificationScreen(
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.privacyScreen,
      name: 'privacyScreen',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final isDarkMode = extra['isDarkMode'] ?? false;
        return PrivacyPolicyScreen(
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: Routes.termsCondition,
      name: 'termsCondition',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final isDarkMode = extra['isDarkMode'] ?? false;
        return TermsAndConditionsScreen(
          isDarkMode: isDarkMode,
        );
      },
    ),
    GoRoute(
      path: '/premiumIntro',
      name: 'premiumIntro',
      builder: (context, state) {
        final String phoneOrEmail = state.extra as String? ?? '';
        return PremiumIntroScreen(
          logoAsset: 'assets/images/awa_logo.webp',
          onContinue: (plan) {
            context.goNamed(
              Routes.homeScreen,
              extra: phoneOrEmail,
            );
          },
          onLater: () {
            context.goNamed(
              Routes.homeScreen,
              extra: phoneOrEmail,
            );
          },
        );
      },
    ),

    GoRoute(
      path: '/transactions',
      name: 'transactions',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final bool isDarkMode = extra['isDarkMode'] ?? false;
        final String email = extra['email'] ?? '';
        return TransactionScreen(
          isDarkMode: isDarkMode,
          email: email,
        );
      },
    ),

  ],
  errorBuilder: (context, state) => const Scaffold(
    body: Center(child: Text('No route defined for this screen')),
  ),
);
