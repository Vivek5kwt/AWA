import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../../config/app_strings.dart';
import '../../../../core/network/http_service.dart';
import '../../../../core/utils/routing/routes.dart';

class VerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String sessionId;

  const VerificationScreen({
    Key? key,
    required this.phoneNumber,
    required this.sessionId,
  }) : super(key: key);

  @override
  _VerificationScreenState createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  Timer? _timer;
  final ValueNotifier<int> _seconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> _canResend = ValueNotifier<bool>(true);
  bool _verifying = false;
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_otpFocusNode);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _seconds.dispose();
    _canResend.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _otpController.clear();
    FocusScope.of(context).requestFocus(_otpFocusNode);

    _seconds.value = 30;
    _canResend.value = false;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds.value == 0) {
        _canResend.value = true;
        timer.cancel();
      } else {
        _seconds.value -= 1;
      }
    });
  }

  Future<void> _sendOtpAgain() async {
    _startTimer();
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/send_otp/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'phone_number': widget.phoneNumber},
      );
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final apiMessage = responseBody['message']?.toString() ?? '';

      if (response.statusCode == 200) {
        final successMsg = apiMessage.isNotEmpty
            ? apiMessage
            : 'OTP has been resent successfully.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      } else {
        final errorText = apiMessage.isNotEmpty
            ? apiMessage
            : 'Failed to resend OTP. (${response.statusCode})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
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
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() => _verifying = true);
    try {
      final verifyUri = Uri.parse('${ApiConstants.baseUrl}/verify_otp/');
      final verifyResp = await http.post(
        verifyUri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'phone_number': widget.phoneNumber,
          'otp': otp,
          'session_id': widget.sessionId,
        },
      );

      final vData = jsonDecode(verifyResp.body) as Map<String, dynamic>;
      final vStatus = vData['status'] is int
          ? vData['status'] as int
          : int.tryParse(vData['status'].toString()) ?? 0;
      final vMessage = vData['message']?.toString() ?? '';

      if (vStatus != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(vMessage, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        _startTimer();
        setState(() => _verifying = false);
        return;
      }

      final loginUri = Uri.parse('${ApiConstants.baseUrl}/login_user/');
      final fcm = await FirebaseMessaging.instance.getToken() ?? '';
      final loginResp = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'phone_number': widget.phoneNumber,
          'fcm_token': fcm,
        },
      );

      if (loginResp.statusCode == 200) {
        final lData = jsonDecode(loginResp.body) as Map<String, dynamic>;
        final lStatus = lData['status'] is int
            ? lData['status'] as int
            : int.tryParse(lData['status'].toString()) ?? 0;
        final user = lData['user_details'] as Map<String, dynamic>?;

        if (lStatus == 1) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('loggedIn', true);
          if (user != null) {
            await prefs.setString('phoneNumber', user['phone_number']?.toString() ?? '');
            await prefs.setString('name', user['name']?.toString() ?? '');
            await prefs.setString('email', user['email']?.toString() ?? '');
            await prefs.setString('age', user['age']?.toString() ?? '');
            await prefs.setString('gender', user['gender']?.toString() ?? '');
            await prefs.setString('profilePhoto', user['profile_picture_url']?.toString() ?? '');
            await prefs.setString('marriedStatus', user['married_status']?.toString() ?? '');
          }
          if (mounted) {
            context.goNamed(
              Routes.homeScreen,
              extra: widget.phoneNumber,
            );
          }
          return;
        } else {
          if (mounted) {
            context.goNamed(
              'completeProfile',
              extra: {
                "phoneNumber": widget.phoneNumber,
                "isUpdate": false,
              },
            );
          }
          return;
        }
      } else {
        if (mounted) {
          context.goNamed(
            'completeProfile',
            extra: {
              "phoneNumber": widget.phoneNumber,
              "isUpdate": false,
            },
          );
        }
      }
    } on SocketException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Network error. Please check your connection.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      _startTimer();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      _startTimer();
    } finally {
      setState(() => _verifying = false);
    }
  }
  Widget _buildAnimatedOtpFields(BuildContext context) {
    String value = _otpController.text;
    List<String> otpDigits = List.filled(6, "");
    for (int i = 0; i < value.length && i < 6; i++) {
      otpDigits[i] = value[i];
    }
    final isFocused = _otpFocusNode.hasFocus;

    return LayoutBuilder(
      builder: (context, constraints) {
        double availableWidth = constraints.maxWidth;
        const minBoxWidth = 36.0;
        const maxBoxWidth = 56.0;
        double boxWidth = minBoxWidth;
        double spacing = 8.0;
        double totalSpacing = spacing * 5;
        double totalBox = maxBoxWidth * 6;

        if (totalBox + totalSpacing <= availableWidth) {
          boxWidth = maxBoxWidth;
        } else {
          boxWidth = ((availableWidth - (spacing * 5)) / 6)
              .clamp(minBoxWidth, maxBoxWidth);
          totalBox = boxWidth * 6;
          if (totalBox + totalSpacing > availableWidth) {
            spacing = ((availableWidth - (boxWidth * 6)) / 5).clamp(2.0, 8.0);
          }
        }

        return GestureDetector(
          onTap: () async {
            _otpFocusNode.unfocus();
            await Future.delayed(const Duration(milliseconds: 1));
            FocusScope.of(context).requestFocus(_otpFocusNode);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = otpDigits[i].isNotEmpty;
              final highlight = (value.length == i && isFocused) ||
                  (i == 5 && value.length == 6 && isFocused);
              return Container(
                margin:
                EdgeInsets.symmetric(horizontal: i == 0 ? 0 : spacing / 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: boxWidth,
                  height: boxWidth * 1.15,
                  decoration: BoxDecoration(
                    color: filled
                        ? Colors.white.withOpacity(0.24)
                        : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: highlight ? Colors.blueAccent : Colors.white30,
                      width: highlight ? 2.2 : 1.0,
                    ),
                    boxShadow: highlight
                        ? [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.13),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      )
                    ]
                        : [],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    filled ? otpDigits[i] : "",
                    style: TextStyle(
                      color: filled ? Colors.white : Colors.white38,
                      fontSize: boxWidth * 0.7,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final safeMargin = 32.0;
    final otpWidth = (screenWidth - safeMargin).clamp(240.0, 440.0);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.red,
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
                child: SingleChildScrollView(
                  padding:
                  const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        height: 80,
                        width: 80,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF4158D0),
                              Color(0xFFC850C0),
                              Color(0xFFFFCC70),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/ic_otp.webp',
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        AppStrings.verificationTitle,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code sent to ${widget.phoneNumber}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        color: Colors.white10,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        elevation: 4,
                        child: SizedBox(
                          width: otpWidth,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0.0,
                                child: TextField(
                                  focusNode: _otpFocusNode,
                                  controller: _otpController,
                                  maxLength: 6,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6)
                                  ],
                                  onChanged: (val) {
                                    setState(() {});
                                    if (val.length == 6) {
                                      _verifyOtp(val);
                                    }
                                  },
                                  textAlign: TextAlign.center,
                                  cursorColor: Colors.white,
                                  autofocus: true,
                                  showCursor: true,
                                ),
                              ),
                              _buildAnimatedOtpFields(context),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<bool>(
                        valueListenable: _canResend,
                        builder: (context, canResend, _) {
                          if (canResend) {
                            return TextButton(
                              onPressed: _sendOtpAgain,
                              child: const Text(
                                'Resend Code',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16),
                              ),
                            );
                          } else {
                            return ValueListenableBuilder<int>(
                              valueListenable: _seconds,
                              builder: (context, seconds, _) {
                                return Text(
                                  'Resend in 00:${seconds.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                );
                              },
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 32),
                      if (_verifying)
                        const CircularProgressIndicator(color: Colors.white),
                    ],
                  ),
                ),
              ),
              Container(
                height: 8,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
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
