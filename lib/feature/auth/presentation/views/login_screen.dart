import 'dart:io';
import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../../../../core/network/http_service.dart';
import '../../../common_widgets/login_button.dart';
import '../../../common_widgets/phone_number_input_container.dart';
import '../../../../core/utils/routing/routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _completePhoneNumber = '';
  String _rawPhoneNumber = '';
  bool _isPhoneValid = true;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isFacebookLoading = false;

  Future<void> _onLoginPressed() async {
    if (_rawPhoneNumber.length != 10) {
      setState(() => _isPhoneValid = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid 10-digit phone number'),
          backgroundColor: const Color(0xFF4E4376),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.amber.withOpacity(0.7),
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    final uri = Uri.parse('${ApiConstants.baseUrl}/send_otp/');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'phone_number': _completePhoneNumber},
      );
      print('djsdjdjs $uri');
      print('djsdjdjs ${response.statusCode}');
      if (response.statusCode == 204) {
        showAccountDeletedDialog();
        return;
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final apiMessage = responseBody['message']?.toString() ?? '';

      if (response.statusCode == 200) {
        if (apiMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(apiMessage),
              backgroundColor: Colors.teal,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Dismiss',
                disabledTextColor: Colors.white,
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }

        final details = responseBody['Details']?.toString() ?? '';
        if (details.isNotEmpty) {
          try {
            context.pushNamed(
              'verify',
              queryParameters: {
                'phoneNumber': _completePhoneNumber,
                'sessionId': details,
              },
            );

          } catch (e, st) {
            debugPrint('[ERROR] Navigation failed: $e');
            debugPrint(st.toString());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Navigation error: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Invalid session from server'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Dismiss',
                disabledTextColor: Colors.white,
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        final errorText = apiMessage.isNotEmpty
            ? apiMessage
            : 'Failed to send OTP. Please try again.\n(${response.statusCode})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } on SocketException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Network error. Please check your connection.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong. Please try again.\nError: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }


  Future<void> _handleSocialLogin({
    required String email,
    required String name,
    required String socialId,
    required String loginType,
  })
  async {
    setState(() {
      _isGoogleLoading = (loginType == 'google');
      _isAppleLoading = (loginType == 'apple');
      _isFacebookLoading = (loginType == 'facebook');
    });

    try {
      final fcmToken = await FirebaseMessaging.instance.getToken() ?? '';
      final loginUri = Uri.parse('${ApiConstants.baseUrl}/login_social/');
      final response = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'email': email,
          'name': name,
          'social_id': socialId,
          'login_type': loginType,
          'fcm_token': fcmToken,
        },
      );

      if (response.statusCode == 204) {
        showAccountDeletedDialog();
        return;
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final status = responseBody['status'] is int
          ? responseBody['status'] as int
          : int.tryParse(responseBody['status'].toString()) ?? 0;
      final message = responseBody['message']?.toString() ?? '';

      if (response.statusCode == 422) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please complete your profile'),
            backgroundColor: const Color(0xFF4E4376),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.amber.withOpacity(0.7),
              onPressed: () {},
            ),
          ),
        );
        context.goNamed(
          Routes.completeProfile,
          queryParameters: {
            'phoneNumber': email,
            'isUpdate': 'false',
          },
        );
        return;
      }

      if (response.statusCode == 200 && status == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Successfully logged in'),
            backgroundColor: const Color(0xFF4E4376),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.amber.withOpacity(0.7),
              onPressed: () {},
            ),
          ),
        );

        final user = responseBody['user_details'] as Map<String, dynamic>?;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('loggedIn', true);
        bool isSubscribed = false;
        if (user != null) {

          await prefs.setString('phoneNumber', user['phone_number']?.toString() ?? '');
          await prefs.setString('name', user['name']?.toString() ?? '');
          await prefs.setString('email', user['email']?.toString() ?? '');
          await prefs.setString('age', user['age']?.toString() ?? '');
          await prefs.setString('gender', user['gender']?.toString() ?? '');
          await prefs.setString('profilePhoto', user['profile_picture_url']?.toString() ?? '');
          await prefs.setString('marriedStatus', user['married_status']?.toString() ?? '');
          await prefs.setString('login_type', user['login_type']?.toString() ?? '');
          await prefs.setBool('isOnboarded', true);
          if (user.containsKey('is_subscribed')) {
            isSubscribed = user['is_subscribed'] == true;
            await prefs.setBool('isSubscribed', isSubscribed);
          } else {
            await prefs.setBool('isSubscribed', false);
          }

        }
        if (isSubscribed) {
          context.goNamed(
            Routes.homeScreen,
            extra: email,
          );
        } else {
          context.goNamed(
            'premiumIntro',
            extra: email,
          );
        }

      /*  context.goNamed(
          Routes.homeScreen,
          queryParameters: {'phoneNumber': email},
        );*/

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isNotEmpty ? message : 'Login failed'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } on SocketException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Network error. Please check your connection.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } finally {
      setState(() {
        _isGoogleLoading = false;
        _isAppleLoading = false;
        _isFacebookLoading = false;
      });
    }
  }


  Future<void> _onGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? account = await GoogleSignIn().signIn();
      if (account != null) {
        final name = account.displayName ?? '';
        final email = account.email;
        final socialId = account.id;
        await _handleSocialLogin(
          email: email,
          name: name,
          socialId: socialId,
          loginType: 'google',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google sign-in cancelled'),
            backgroundColor: const Color(0xFF4E4376),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.amber.withOpacity(0.7),
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Google sign-in failed.'),
          backgroundColor: const Color(0xFF4E4376),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.amber.withOpacity(0.7),
            onPressed: () {},
          ),
        ),
      );
    } finally {
      setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _onAppleSignIn() async {
    setState(() => _isAppleLoading = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final email = credential.email ?? '';
      final name = [
        credential.givenName,
        credential.familyName
      ].whereType<String>().join(' ');
      final socialId = credential.userIdentifier ?? '';
      await _handleSocialLogin(
        email: email,
        name: name,
        socialId: socialId,
        loginType: 'apple',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Apple sign-in failed.'),
          backgroundColor: const Color(0xFF4E4376),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.amber.withOpacity(0.7),
            onPressed: () {},
          ),
        ),
      );
    } finally {
      setState(() => _isAppleLoading = false);
    }
  }

  Future<void> _onFacebookSignIn() async {
    setState(() => _isFacebookLoading = true);

    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.success) {
        final userData = await FacebookAuth.instance.getUserData(
          fields: "name,email",
        );

        final String name = userData['name'] ?? '';
        final String email = userData['email'] ?? '';
        final String socialId = userData['id'] ?? '';

        if (email.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Facebook account has no email. Please use another account.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        await _handleSocialLogin(
          email: email,
          name: name,
          socialId: socialId,
          loginType: 'facebook',
        );
      } else if (result.status == LoginStatus.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Facebook sign-in cancelled'),
            backgroundColor: const Color(0xFF4E4376),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.amber.withOpacity(0.7),
              onPressed: () {},
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Facebook sign-in failed: ${result.message ?? "Unknown error"}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              disabledTextColor: Colors.white,
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Facebook sign-in failed. Error: $e'),
          backgroundColor: const Color(0xFF4E4376),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            disabledTextColor: Colors.white,
            textColor: Colors.amber.withOpacity(0.7),
            onPressed: () {},
          ),
        ),
      );
    } finally {
      setState(() => _isFacebookLoading = false);
    }
  }

  Widget _buildSocialButton({
    required String assetPath,
    required String text,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 46.0, vertical: 8.0),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          foregroundColor: textColor,
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          elevation: 4.0,
          shadowColor: Colors.black45,
        ),
        child: isLoading
            ? const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              assetPath,
              height: 24,
              width: 24,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showAccountDeletedDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "accountDeleted",
      pageBuilder: (ctx, _, __) => WillPopScope(
        onWillPop: () async => false,
        child: Container(
          color: Color(0xFF181A20),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Material(
                borderRadius: BorderRadius.circular(26),
                color: Colors.blueGrey[900]!.withOpacity(0.98),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        color: Colors.cyanAccent,
                        size: 55,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Your account has been blocked",
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "For security reasons, your account was blocked by admin. Please contact our support team for assistance.",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.withOpacity(0.85),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 38, vertical: 14),
                        ),
                        icon: Icon(
                          Icons.support_agent_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                        label: Text(
                          "Contact Support",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.3),
                        ),
                        onPressed: () {
                          context.go(Routes.login);
                        },
                      ),
                      const SizedBox(height: 15),
                      TextButton(
                        onPressed: () {
                          context.go(Routes.login);
                        },
                        child: Text(
                          "Exit App",
                          style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
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
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 46.0),
                  child: Image.asset('assets/images/awa_voice_logo.png'),
                ),
                const SizedBox(height: 40),
                Text(
                  context.loc.loginTo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 32),
                PhoneInputContainer(
                  onChanged: (raw, complete) {
                    setState(() {
                      _rawPhoneNumber = raw;
                      _completePhoneNumber = complete;
                      _isPhoneValid = (raw.length == 10);
                    });
                  },
                ),
                if (!_isPhoneValid)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Enter a valid 10-digit number',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                LoginButton(
                  onLoginPressed: _onLoginPressed,
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 46.0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Divider(
                          color: Colors.white70,
                          thickness: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Divider(
                          color: Colors.white70,
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSocialButton(
                  assetPath: 'assets/images/google_logo.webp',
                  text: 'Continue with Google',
                  bgColor: Colors.white,
                  textColor: Colors.black87,
                  onPressed: _onGoogleSignIn,
                  isLoading: _isGoogleLoading,
                ),
                if (Platform.isIOS)
                  _buildSocialButton(
                    assetPath: 'assets/images/apple_logo.webp',
                    text: 'Continue with Apple',
                    bgColor: Colors.black,
                    textColor: Colors.white,
                    onPressed: _onAppleSignIn,
                    isLoading: _isAppleLoading,
                  ),
                _buildSocialButton(
                  assetPath: 'assets/images/facebook_logo.webp',
                  text: 'Continue with Facebook',
                  bgColor: const Color(0xFF1877f3),
                  textColor: Colors.white,
                  onPressed: _onFacebookSignIn,
                  isLoading: _isFacebookLoading,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
