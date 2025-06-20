import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:awa/config/local_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../../core/network/http_service.dart';

class HomeScreen extends StatefulWidget {
  final String phoneNumber;

  const HomeScreen({Key? key, required this.phoneNumber}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height - 30,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 60,
      size.width,
      size.height - 30,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(WaveClipper oldClipper) => false;
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _isDarkMode = false;
  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Hindi', 'Spanish'];
  String _userName = 'User';
  String _mobileNumber = '';
  String _email = '';
  String _profilePic = '';
  String _loginType = '';
  late List<bool> _itemVisible;
  bool _isImageDialogOpen = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  late final PageController _carouselController;
  late final Timer _carouselTimer;
  int _currentPage = 0;
  final List<String> _carouselImages = [
    'assets/images/voice_listen.webp',
    'assets/images/voice_listen2.webp',
    'assets/images/voice_listen3.webp',
  ];

  final GlobalKey<ShowCaseWidgetState> _showCaseKey = GlobalKey();
  final GlobalKey _registerSpeakerKey = GlobalKey();
  final GlobalKey _identifySpeakerKey = GlobalKey();
  final GlobalKey _speakerBookKey = GlobalKey();
  final GlobalKey _addFriendsKey = GlobalKey();
  final GlobalKey _friendBookKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _updateProfileKey = GlobalKey();

  bool _showTutorial = false;
  late AnimationController _identifyAnimController;
  late Animation<double> _glowAnim;

  late Razorpay _razorpay;
  bool _isSubscribed = false;

  static const int _yearlyAmount = 49900;

  late AnimationController _supportAnimController;
  late Animation<double> _supportGlowAnim;
  List<Map<String, dynamic>> _subscriptionPlans = [];
  bool _loadingPlans = false;
  String? _selectedPlanId;
  Map<String, dynamic>? _selectedPlan;
  bool _trialExists = true;
  bool _trialSkip = true;
  DateTime? _trialExpiresAt;
  String? _trialMessage;
  bool _trialLoading = true;

  @override
  void initState() {
    super.initState();
    final menuButtonsCount = 6;
    _itemVisible = List<bool>.filled(3 + menuButtonsCount, false);
    _loadSettings().then((_) async {
      await _checkTrialStatus();
      _checkAndUpdateSubscription();
      _runItemAnimation();
    });

    _carouselController = PageController(initialPage: 0);
    _carouselTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final nextPage = (_currentPage + 1) % _carouselImages.length;
      _carouselController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      _currentPage = nextPage;
    });

    _identifyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _identifyAnimController, curve: Curves.easeInOut),
    );

    _supportAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _supportGlowAnim = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _supportAnimController, curve: Curves.easeInOut),
    );

    _checkFirstLaunch();

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _carouselTimer.cancel();
    _carouselController.dispose();
    _identifyAnimController.dispose();
    _razorpay.clear();
    _supportAnimController.dispose();
    super.dispose();
  }
  void _showPremiumDialog(BuildContext context, String title, String? message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: isDark ? Color(0xFF181A20) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(26.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, color: Colors.amber[800], size: 54),
              const SizedBox(height: 10),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    Colors.amber,
                    Colors.orange,
                    Colors.deepOrangeAccent,
                  ],
                ).createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.amber[700],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message ??
                    "This feature is for Premium users only.\nUpgrade to continue.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(0.85)
                      : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[800],
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(Icons.workspace_premium,
                    color: Colors.white, size: 20),
                label: Text(
                  "Go Premium",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showSubscriptionDialog();
                },
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkTrialStatus() async {
    setState(() => _trialLoading = true);
    try {
      final url =
          Uri.parse('http://192.168.1.6:8000/check_trial?email=$_email');
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _trialExists = data['trial_exists'] == true;
          _trialSkip = data['trial_skipped'] == true;
          _trialExpiresAt = DateTime.tryParse(data['expires_at'] ?? '');
          _trialMessage = data['message'] ?? '';
          _trialLoading = false;
        });
      } else {
        setState(() => _trialLoading = false);
      }
    } catch (e) {
      setState(() => _trialLoading = false);
    }
  }

  Future<void> _fetchSubscriptionPlans() async {
    setState(() {
      _loadingPlans = true;
      _subscriptionPlans = [];
      _selectedPlan = null;
      _selectedPlanId = null;
    });
    try {
      final url = Uri.parse(ApiConstants.getSubPlan);
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final plans = (decoded['plans'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _subscriptionPlans = plans;
          if (plans.isNotEmpty) {
            _selectedPlan = plans.first;
            _selectedPlanId = plans.first['plan_name'];
          }
        });
      } else {
        throw Exception('Failed to load plans');
      }
    } catch (e) {
      setState(() => _subscriptionPlans = []);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load subscription plans. Try again.'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      setState(() {
        _loadingPlans = false;
      });
    }
  }

  Future<void> _checkAndUpdateSubscription({bool showSnackBar = false}) async {
    try {
      final resp = await http.get(Uri.parse(
          '${ApiConstants.baseUrl}/check_subscription/?email=$_email'));
      print('sjjjsjasjj ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final subscribed = data['subscribed'] == true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isSubscribed', subscribed);
        if (mounted) {
          setState(() => _isSubscribed = subscribed);
          if (showSnackBar && subscribed) {
            // Show creative premium SnackBar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                elevation: 10,
                backgroundColor: Colors.deepPurple[700],
                duration: Duration(seconds: 3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                margin: EdgeInsets.symmetric(horizontal: 25, vertical: 18),
                behavior: SnackBarBehavior.floating,
                content: Row(
                  children: [
                    Icon(Icons.workspace_premium,
                        color: Colors.amberAccent, size: 32),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        "Congratulations! You are now a Premium User 🎉",
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                                color: Colors.black38,
                                blurRadius: 4,
                                offset: Offset(1, 2))
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Subscription check failed: $e');
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final didTutorial = prefs.getBool('didHomeTutorial') ?? false;
    if (!didTutorial) {
      setState(() => _showTutorial = true);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          _showCaseKey.currentState?.startShowCase([
            _registerSpeakerKey,
            _identifySpeakerKey,
            _speakerBookKey,
            _addFriendsKey,
            _friendBookKey,
            _settingsKey,
            _updateProfileKey,
          ]);
        }
      });
      await prefs.setBool('didHomeTutorial', true);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('darkMode') ?? false;
      _selectedLanguage = prefs.getString('language') ?? 'English';
      _userName = prefs.getString('name') ?? 'User';
      _email = prefs.getString('email') ?? '';
      _mobileNumber = prefs.getString('phoneNumber') ?? '';
      _profilePic = prefs.getString('profilePhoto') ?? '';
      _loginType = prefs.getString('login_type') ?? '';
    });
  }

  void _runItemAnimation() {
    for (var i = 0; i < _itemVisible.length; i++) {
      Future.delayed(Duration(milliseconds: 160 * i), () {
        if (mounted) setState(() => _itemVisible[i] = true);
      });
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
    setState(() => _isDarkMode = value);
  }

  Future<void> _changeLanguage(String? lang) async {
    if (lang == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    setState(() => _selectedLanguage = lang);
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _pickedImage = image;
        _profilePic = image.path;
      });
    }
  }

  Future<void> _logout() async => _showLogoutDialog();

  Future<void> _deleteAccount() async => _showDeleteDialog();

  Future<void> _showLogoutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.exit_to_app,
              color: _isDarkMode ? Colors.white : Colors.redAccent,
            ),
            const SizedBox(width: 8),
            Text(
              'Logout',
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(
            color: _isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Logout',
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final client = http.Client();
      Uri uri = Uri.parse(ApiConstants.logoutUser);
      Map<String, String> body = _loginType == '0'
          ? {'email': _email}
          : {'phone_number': widget.phoneNumber};
      http.Response resp = await client.post(uri, body: body);

      if (resp.statusCode == 307 || resp.statusCode == 302) {
        final loc = resp.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          uri = Uri.parse(loc);
          resp = await client.post(uri, body: body);
        }
      }

      String feedback;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        feedback = data['message'] ?? 'Logged out.';
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (_loginType == '0') {
          try {
            await GoogleSignIn().signOut();
          } catch (_) {}
        }
        context.go('/login');
      } else {
        feedback = 'Logout failed: ${resp.statusCode}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback),
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
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              'Delete Account',
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete your account and all data. Continue?',
          style: TextStyle(
            color: _isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final client = http.Client();
      Uri uri = Uri.parse(ApiConstants.deleteUser);
      Map<String, String> body = _loginType == '0'
          ? {'email': _email}
          : {'phone_number': _mobileNumber};
      http.Response resp = await client.post(uri, body: body);
      if (resp.statusCode == 307 || resp.statusCode == 302) {
        final loc = resp.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          uri = Uri.parse(loc);
          resp = await client.post(uri, body: body);
        }
      }
      String feedback;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        feedback = data['message'] ?? 'Deleted.';
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (_loginType == '0') {
          try {
            await GoogleSignIn().signOut();
          } catch (_) {}
        }
        context.go('/login');
      } else {
        feedback = 'Delete failed: ${resp.statusCode}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback),
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
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSubscribed', true);
    setState(() => _isSubscribed = true);
    await _checkAndUpdateSubscription(showSnackBar: true);

    if (mounted) Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Subscription activated! Welcome to AWA Premium 🎉",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Payment failed: ${response.message ?? ''}"),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("External Wallet selected: ${response.walletName}"),
        backgroundColor: Colors.blueGrey,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildPlanToggle(
    BuildContext context, {
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 350),
        padding: EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? Colors.amber[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.25),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          title,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Future<void> _showSubscriptionDialog() async {
    await _fetchSubscriptionPlans();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDarkMode ? Color(0xFF232526) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final padding = MediaQuery.of(context).viewInsets.bottom;
            if (_loadingPlans) {
              return Padding(
                padding: EdgeInsets.fromLTRB(26, 48, 26, 32 + padding),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_subscriptionPlans.isEmpty) {
              return Padding(
                padding: EdgeInsets.fromLTRB(26, 48, 26, 32 + padding),
                child: Center(child: Text("No plans available.")),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(26, 32, 26, 32 + padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, color: Colors.amber, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    "AWA Premium Subscription",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 21,
                      color: _isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _subscriptionPlans.map((plan) {
                      final planName = plan['plan_name']?.trim() ?? '';
                      final selected = _selectedPlanId == planName;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedPlanId = planName;
                            _selectedPlan = plan;
                          });
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 350),
                          margin: EdgeInsets.symmetric(horizontal: 7),
                          padding: EdgeInsets.symmetric(
                              horizontal: 28, vertical: 13),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.amber[800]
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    )
                                  ]
                                : [],
                          ),
                          child: Text(
                            planName,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : (_isDarkMode
                                      ? Colors.white
                                      : Colors.black87),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  if (_selectedPlan != null) ...[
                    AnimatedContainer(
                      duration: Duration(milliseconds: 500),
                      padding: EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF7971E), Color(0xFFFFE259)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.13),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            "${_selectedPlan!['duration_days']} Days",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.brown[700],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "₹${(_selectedPlan!['price'] as num).toStringAsFixed(0)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.brown[900],
                              fontSize: 30,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...((_selectedPlan!['features'] as List?) ?? [])
                              .map((f) => Text(
                                    f.toString(),
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 15,
                                    ),
                                  ))
                              .toList(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      icon: Icon(Icons.lock_open, color: Colors.white),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[800],
                        padding:
                            EdgeInsets.symmetric(horizontal: 38, vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      label: Text(
                        "Subscribe Now",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _startSubscriptionPaymentFromPlan(_selectedPlan!);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Secured by Razorpay",
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                  ]
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _createOrderOnBackend(int amount) async {
    final url = Uri.parse('${ApiConstants.baseUrl}/create_order/');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'amount': amount.toString(), 'currency': 'INR'},
      );
      print('amount on create orderr $amount');
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return json;
      }
    } catch (e) {
      debugPrint("Create order error: $e");
    }
    return null;
  }

  Future<bool> _verifyPaymentWithBackend(
      Map<String, dynamic> razorpayPayment) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/verify_razorpay_payment')
        .replace(queryParameters: {
      "razorpay_order_id": razorpayPayment["razorpay_order_id"] ?? "",
      "razorpay_payment_id": razorpayPayment["razorpay_payment_id"] ?? "",
      "email": razorpayPayment["email"] ?? "",
      "amount": razorpayPayment["amount"] ?? "",
      "plan": razorpayPayment["plan"] ?? "",
      "days": razorpayPayment["days"] ?? "",
    });
    try {
      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        print('dsjdjsjsdj ${data['status']}');
        return data['status'] == 'success' || data['verified'] == true;
      }
    } catch (e) {
      debugPrint("Verify payment error: $e");
    }
    return false;
  }

  Future<void> _startSubscriptionPaymentFromPlan(
      Map<String, dynamic> plan) async {
    final amount = (plan['price'] as num).toInt();
    final planName = plan['plan_name'] ?? '';
    final durationDays = plan['duration_days'].toString();
    print('djsdjsj $amount');
    final order = await _createOrderOnBackend(amount);
    if (order == null || order['order_id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to create order. Try again."),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final orderId = order['order_id'];
    final paymentUrl = Uri.parse("${ApiConstants.baseUrl}/razorpay_checkout")
        .replace(queryParameters: {
      "razorpay_order_id": orderId,
      "email": _email,
      "amount": amount.toString(),
      "plan": planName,
      "days": durationDays,
    }).toString();

    print('Payment URL: $paymentUrl');

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: Container(
          height: 650,
          width: 390,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(paymentUrl)),
            onLoadStop: (controller, url) async {
              if (url != null && url.toString().contains("/payment_success")) {
                Navigator.of(context).pop();
                final params = Uri.parse(url.toString()).queryParameters;
                final verifyBody = {
                  "razorpay_order_id": orderId,
                  "razorpay_payment_id": params['payment_id'] ?? '',
                  "razorpay_signature": params['signature'] ?? '',
                  "email": _email,
                  "amount": amount.toString(),
                  "plan": planName,
                  "days": durationDays,
                };

                final isVerified = await _verifyPaymentWithBackend(verifyBody);
                if (isVerified) {
                  await _checkAndUpdateSubscription(showSnackBar: true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Payment verification failed!'),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> bgColors = _isDarkMode
        ? [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];

    final buttons = [
      {
        'icon': Icons.person_add,
        'label': 'Register Speaker',
        'key': _registerSpeakerKey,
        'desc': "Register a new speaker to begin speech identification.",
        'onTap': _trialSkip||_trialExists
            ? () => context.pushNamed(
                  'addContact',
                  extra: {
                    'name': '',
                    'phoneNumber': widget.phoneNumber,
                    'isDarkMode': _isDarkMode
                  },
                )
            : null,
        'lock':  _trialSkip?false:!_trialExists,
      },
      {
        'icon': Icons.book,
        'label': 'Speaker Book',
        'key': _speakerBookKey,
        'desc': "Access your complete list of registered speakers.",
        'onTap': _trialSkip||_trialExists
            ? () => context.pushNamed(
                  'speakerScreen',
                  extra: {
                    'phoneNumber': widget.phoneNumber,
                    'isDarkMode': _isDarkMode
                  },
                )
            : null,
        'lock': _trialSkip?false:!_trialExists,
      },
      {
        'icon': Icons.person_add_alt_1,
        'label': 'Add Friends',
        'key': _addFriendsKey,
        'desc': "Add new friends and invite them to your network.",
        'onTap': () => context.goNamed(
              'friendBookScreen',
              queryParameters: {
                'phoneNumber': widget.phoneNumber,
                'isDarkMode': _isDarkMode.toString()
              },
            ),
        'lock': false,
      },
      {
        'icon': Icons.book,
        'label': 'Friend Book',
        'key': _friendBookKey,
        'desc': "See your saved friends and manage your friend list.",
        'onTap':_trialSkip|| _trialExists
            ? () => context.pushNamed(
                  'friendListScreen',
                  extra: {
                    'phoneNumber': widget.phoneNumber,
                    'isDarkMode': _isDarkMode
                  },
                )
            : null,
        'lock':  _trialSkip?false:!_trialExists,
      },
      {
        'icon': Icons.settings,
        'label': 'Settings',
        'key': _settingsKey,
        'desc': "Configure your app preferences and settings here.",
        'onTap': () => context.pushNamed(
              'settingsScreen',
              extra: {'isDarkMode': _isDarkMode},
            ),
      },
      {
        'icon': Icons.edit,
        'label': 'Update Profile',
        'key': _updateProfileKey,
        'desc': "Update your personal information and profile picture.",
        'onTap': () async {
          final updated = await context.pushNamed<bool>(
            'completeProfile',
            extra: {
              'phoneNumber': _mobileNumber,
              'isUpdate': true,
              'isDarkMode': _isDarkMode,
            },
          );
          if (updated == true) {
            await _loadSettings();
            _runItemAnimation();
          }
        },
      },
    ];

    final supportFAB = AnimatedBuilder(
      animation: _supportGlowAnim,
      builder: (context, child) {
        final bool isDark = _isDarkMode;
        final Color fabGradientStart =
            isDark ? Color(0xFF0ED2F7) : Color(0xFF0093E9);
        final Color fabGradientEnd =
            isDark ? Color(0xFF29ECAC) : Color(0xFF80D0C7);
        final Color borderColor = isDark
            ? Colors.cyanAccent.withOpacity(0.95)
            : Colors.blueAccent.withOpacity(0.95);

        return Positioned(
          right: 20,
          bottom: _isSubscribed ? 28 : 20,
          child: GestureDetector(
            onTap: () {
              context.pushNamed(
                'contactSupportScreen',
                extra: {'isDarkMode': _isDarkMode},
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Material(
                  elevation: 18,
                  shape: CircleBorder(),
                  color: Colors.transparent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    width: 60 + _supportGlowAnim.value * 4,
                    height: 60 + _supportGlowAnim.value * 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          fabGradientStart,
                          fabGradientEnd,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: borderColor,
                        width: 2.3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: fabGradientEnd.withOpacity(0.23),
                          blurRadius: 15,
                          offset: Offset(0, 6),
                        ),
                        BoxShadow(
                          color: fabGradientStart.withOpacity(0.08),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.support_agent,
                        color: isDark ? Colors.white : Colors.blueGrey[900],
                        size: 35 + _supportGlowAnim.value * 3,
                        shadows: [
                          Shadow(
                            color: isDark
                                ? Colors.cyanAccent.withOpacity(0.25)
                                : Colors.blueAccent.withOpacity(0.12),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return ShowCaseWidget(
      builder: (context) => Stack(
        children: [
          Scaffold(
            backgroundColor: _isDarkMode ? Color(0xFF181A20) : Colors.black,
            extendBodyBehindAppBar: true,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(76),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isDarkMode
                        ? [
                      Color(0xFF0F2027),
                      Color(0xFF2C5364),
                      Color(0xFF232526),
                    ]
                        : [
                      Color(0xFF0093E9),
                      Color(0xFF80D0C7),
                      Color(0xFFFCF6BA),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isDarkMode
                          ? Colors.black.withOpacity(0.12)
                          : Colors.deepPurpleAccent.withOpacity(0.08),
                      blurRadius: 24,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: AppBar(
                      automaticallyImplyLeading: false,
                      toolbarHeight: 78,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      centerTitle: true,
                      leading: Builder(
                        builder: (ctx) => IconButton(
                          icon: Icon(
                            Icons.menu,
                            color: _isDarkMode ? Colors.cyanAccent : Colors.deepPurple,
                            size: 28,
                          ),
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                          splashRadius: 28,
                          tooltip: 'Menu',
                        ),
                      ),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isDarkMode
                                  ? Colors.cyanAccent.withOpacity(0.13)
                                  : Colors.white.withOpacity(0.19),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _isDarkMode
                                      ? Colors.cyanAccent.withOpacity(0.23)
                                      : Colors.blueAccent.withOpacity(0.16),
                                  blurRadius: 20,
                                  spreadRadius: 3,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/awa_logo.webp',
                              height: 32,
                              width: 32,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: _isDarkMode
                                  ? [
                                Colors.cyanAccent,
                                Colors.blueAccent,
                                Colors.white,
                              ]
                                  : [
                                Colors.deepPurple,
                                Colors.indigo,
                                Colors.amber,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'AWA',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.6,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isSubscribed || _trialSkip) ...[
                            const SizedBox(width: 8),
                            AnimatedContainer(
                              duration: Duration(milliseconds: 900),
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.amber.shade700,
                                    Colors.amberAccent.shade200,
                                    Colors.amber.shade400,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withOpacity(0.21),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.workspace_premium,
                                      color: Colors.white, size: 12),
                                  const SizedBox(width: 2),
                                  ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.amberAccent,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ).createShader(bounds),
                                    child: Text(
                                      "PREMIUM",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.amberAccent.withOpacity(0.36),
                                            blurRadius: 5,
                                            offset: Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                        ],
                      ),
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: IconButton(
                            icon: Icon(
                              Icons.notifications_none,
                              color: _isDarkMode ? Colors.cyanAccent : Colors.deepPurple,
                              size: 27,
                            ),
                            onPressed: () {
                              context.pushNamed(
                                'notificationScreen',
                                extra: {'isDarkMode': _isDarkMode},
                              );
                            },
                            splashRadius: 26,
                            tooltip: 'Notifications',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            drawer: Drawer(
              shape: const RoundedRectangleBorder(),
              child: buildDrawerContent(),
            ),
            body: buildBody(bgColors, buttons),
            floatingActionButton: _isSubscribed
                ? null
                : Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: _isDarkMode
                                    ? Colors.cyanAccent.withOpacity(0.22)
                                    : Colors.amber.withOpacity(0.25),
                                blurRadius: 30,
                                spreadRadius: 1,
                                offset: Offset(0, 8),
                              ),
                            ],
                            gradient: LinearGradient(
                              colors: _isDarkMode
                                  ? [
                                      Color(0xFF21D4FD),
                                      Color(0xFF2152FF),
                                      Color(0xFF004E92),
                                    ]
                                  : [
                                      Color(0xFFF7971E),
                                      Color(0xFFFFD200),
                                      Color(0xFFFFA700),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: FloatingActionButton.extended(
                            heroTag: "premiumFAB",
                            elevation: 14,
                            backgroundColor: Colors.transparent,
                            onPressed: _showSubscriptionDialog,
                            icon: Icon(
                              Icons.workspace_premium,
                              color: _isDarkMode
                                  ? Colors.cyanAccent
                                  : Colors.amberAccent,
                              size: 32,
                              shadows: [
                                Shadow(
                                  color: _isDarkMode
                                      ? Colors.cyanAccent.withOpacity(0.4)
                                      : Colors.amberAccent.withOpacity(0.44),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                )
                              ],
                            ),
                            label: ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  colors: _isDarkMode
                                      ? [
                                          Colors.cyanAccent,
                                          Colors.blueAccent,
                                          Colors.white
                                        ]
                                      : [
                                          Colors.orangeAccent,
                                          Colors.amber,
                                          Colors.yellow
                                        ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(
                                  Rect.fromLTWH(
                                      0, 0, bounds.width, bounds.height),
                                );
                              },
                              blendMode: BlendMode.srcIn,
                              child: Text(
                                "Go Premium",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 1.3,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.17),
                                      blurRadius: 2,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          ),
          supportFAB,
        ],
      ),
    );
  }

  Widget buildDrawerContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: _isDarkMode
            ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF181A20),
            Color(0xFF232526),
            Color(0xFF181A20),
          ],
        )
            : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0093E9),
            Color(0xFF80D0C7),
            Color(0xFFFCF6BA),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (!_trialExists && !_trialLoading && !_trialSkip)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GlassmorphicContainer(
                  width: double.infinity,
                  height: 80,
                  borderRadius: 18,
                  blur: 14,
                  border: 0,
                  linearGradient: LinearGradient(
                    colors: [
                      Colors.redAccent.withOpacity(0.24),
                      Colors.white.withOpacity(0.16)
                    ],
                  ),
                  borderGradient: LinearGradient(
                    colors: [Colors.red, Colors.transparent],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Icon(Icons.lock_clock,
                            color: Colors.redAccent, size: 38),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Trial Expired",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            /*Text(
                              _trialMessage ??
                                  "Your free trial has expired. Please upgrade to continue.",
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),*/
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.workspace_premium,
                              color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[800],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          label: Text(
                            "Go Premium",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _showSubscriptionDialog,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  GlassmorphicContainer(
                    width: double.infinity,
                    height: 200,
                    borderRadius: 0,
                    blur: 12,
                    border: 0,
                    linearGradient: LinearGradient(
                      colors: [
                        _isDarkMode
                            ? Colors.white.withOpacity(0.04)
                            : Colors.white.withOpacity(0.24),
                        _isDarkMode
                            ? Colors.white.withOpacity(0.01)
                            : Colors.white.withOpacity(0.10),
                      ],
                    ),
                    borderGradient: LinearGradient(
                      colors: [
                        _isDarkMode ? Colors.white24 : Colors.white,
                        Colors.transparent,
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: Hero(
                              tag: 'profilePic',
                              child: Container(
                                margin: const EdgeInsets.only(left: 28),
                                height: 82,
                                width: 82,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: !_isDarkMode
                                      ? [
                                    BoxShadow(
                                      color: Colors.deepPurpleAccent
                                          .withOpacity(0.13),
                                      blurRadius: 14,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                      : [],
                                ),
                                child: ClipOval(
                                  child: _pickedImage != null
                                      ? Image.file(
                                    File(_pickedImage!.path),
                                    fit: BoxFit.cover,
                                  )
                                      : _profilePic.isNotEmpty
                                      ? Image.network(
                                    ApiConstants.baseUrl + _profilePic,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                    errorBuilder: (context, error, _) =>
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.white54,
                                      size: 36,
                                    ),
                                  )
                                      : Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: _isDarkMode
                                            ? [
                                          Colors.grey.shade800,
                                          Colors.grey.shade700
                                        ]
                                            : [
                                          Colors.blueAccent
                                              .withOpacity(0.8),
                                          Colors.lightBlueAccent
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_add_alt_1,
                                            size: 32,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Add Photo',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
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
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Text(
                              '${context.loc.helloWorld}, $_userName',
                              style: TextStyle(
                                color: _isDarkMode ? Colors.white : Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Text(
                              _loginType == '0' ? _email : _mobileNumber,
                              style: TextStyle(
                                color: _isDarkMode ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      unselectedWidgetColor:
                      _isDarkMode ? Colors.white : Colors.black,
                      switchTheme: SwitchThemeData(
                        trackColor: MaterialStateProperty.resolveWith<Color>(
                              (_) {
                            return _isDarkMode
                                ? const Color(0xFF232526)
                                : Colors.grey;
                          },
                        ),
                        thumbColor: MaterialStateProperty.resolveWith<Color>(
                              (_) {
                            return _isDarkMode
                                ? Colors.white
                                : Colors.purpleAccent;
                          },
                        ),
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        context.loc.darkMode,
                        style: TextStyle(
                          color: _isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      value: _isDarkMode,
                      onChanged: _toggleDarkMode,
                      secondary: Icon(
                        Icons.brightness_6,
                        color: _isDarkMode ? Colors.white : Colors.black,
                      ),
                      activeColor: Theme.of(context).primaryColor,
                      inactiveThumbColor: Theme.of(context).primaryColor,
                      inactiveTrackColor:
                      Theme.of(context).primaryColor.withOpacity(0.4),
                    ),
                  ),

                  /*ListTile(
                    leading: Icon(Icons.language,
                        color: _isDarkMode ? Colors.white : Colors.black),
                    title: Text(
                      context.loc.language,
                      style: TextStyle(
                          color: _isDarkMode ? Colors.white : Colors.black),
                    ),
                    trailing: DropdownButton<String>(
                      value: _selectedLanguage,
                      dropdownColor:
                      _isDarkMode ? const Color(0xFF232526) : Colors.white,
                      underline: const SizedBox(),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: _isDarkMode ? Colors.white : Colors.black,
                      ),
                      onChanged: _changeLanguage,
                      items: _languages
                          .map((lang) => DropdownMenuItem(
                        value: lang,
                        child: Text(lang,
                            style: TextStyle(
                                color: _isDarkMode
                                    ? Colors.white
                                    : Colors.black)),
                      ))
                          .toList(),
                    ),
                  ),*/
                  Divider(
                      color: _isDarkMode ? Colors.white24 : Colors.black26),
                  const SizedBox(height: 15),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Image.asset(
                        'assets/images/awa_logo.webp',
                        height: 100,
                        width: 100,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Divider(
                      color: _isDarkMode ? Colors.white24 : Colors.black26),
// Logout
                  ListTile(
                    leading: Icon(Icons.exit_to_app,
                        color: _isDarkMode ? Colors.white : Colors.black),
                    title: Text(context.loc.logout,
                        style: TextStyle(
                            color:
                            _isDarkMode ? Colors.white : Colors.black)),
                    onTap: _logout,
                  ),
// Delete Account
                  ListTile(
                    leading: const Icon(Icons.delete_forever,
                        color: Colors.redAccent),
                    title: Text(context.loc.deleteAccount,
                        style: const TextStyle(color: Colors.redAccent)),
                    onTap: _deleteAccount,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBody(List<Color> bgColors, List<Map<String, dynamic>> buttons) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: bgColors,
              stops: const [0.1, 0.7, 1.0],
            ),
          ),
        ),
        if (!_isDarkMode)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.white.withOpacity(0.13)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 420),
                  opacity: _itemVisible[0] ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 420),
                    offset:
                        _itemVisible[0] ? Offset.zero : const Offset(0, -0.15),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final height = constraints.maxWidth * 9 / 16;
                          return GlassmorphicContainer(
                            width: constraints.maxWidth,
                            height: height,
                            borderRadius: 26,
                            blur: 0,
                            border: 0,
                            linearGradient: LinearGradient(
                              colors: _isDarkMode
                                  ? [Color(0xFF232526), Color(0xFF181A20)]
                                  : [
                                      Colors.white.withOpacity(0.20),
                                      Colors.white.withOpacity(0.09)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderGradient: LinearGradient(
                              colors: _isDarkMode
                                  ? [Colors.white12, Colors.transparent]
                                  : [
                                      Colors.deepPurpleAccent.withOpacity(0.16),
                                      Colors.blueAccent.withOpacity(0.07)
                                    ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: PageView.builder(
                                controller: _carouselController,
                                itemCount: _carouselImages.length,
                                itemBuilder: (context, index) {
                                  return Center(
                                    child: Image.asset(
                                      _carouselImages[index],
                                      fit: BoxFit.contain,
                                      width: constraints.maxWidth,
                                      height: height,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 17),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: _itemVisible[1] ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 600),
                    offset: _itemVisible[1] ? Offset.zero : const Offset(0, -0.12),
                    child: Showcase(
                      key: _identifySpeakerKey,
                      title: "Identify Speaker",
                      description: "Tap here to identify the speaker in real time.",
                      descriptionPadding: EdgeInsets.all(6),
                      child: AnimatedBuilder(
                        animation: _glowAnim,
                        builder: (context, child) {
                          final theme = Theme.of(context);
                          final bool isDark = _isDarkMode;

                          final Color gradientStart =
                          isDark ? Color(0xFF0ED2F7) : Color(0xFF0093E9);
                          final Color gradientEnd =
                          isDark ? Color(0xFF29ECAC) : Color(0xFF80D0C7);
                          final Color borderColor = isDark
                              ? Colors.cyanAccent.withOpacity(0.90)
                              : Colors.deepPurpleAccent.withOpacity(0.55);
                          final bool identifyLocked = !_trialSkip && !_trialExists;

                          return GestureDetector(
                            onTap: identifyLocked
                                ? () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: _isDarkMode
                                      ? Colors.grey[900]
                                      : Colors.white,
                                  title: Row(
                                    children: [
                                      Icon(Icons.lock_outline,
                                          color:
                                          Colors.redAccent),
                                      SizedBox(width: 8),
                                      Text("Trial Ended",
                                          style: TextStyle(
                                            color: _isDarkMode
                                                ? Colors.white
                                                : Colors
                                                .redAccent,
                                            fontWeight:
                                            FontWeight.bold,
                                          )),
                                    ],
                                  ),
                                  content: Text(
                                    _trialMessage ??
                                        "Your free trial has expired. Please subscribe to continue using this feature.",
                                    style: TextStyle(
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _showSubscriptionDialog();
                                      },
                                      child: Text(
                                        "Upgrade Now",
                                        style: TextStyle(
                                          color:
                                          Colors.amber[800],
                                          fontWeight:
                                          FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                                : () => context.pushNamed(
                              'identifySpeakerScreen',
                              extra: {
                                'isDarkMode': _isDarkMode,
                                'phoneNumber': widget.phoneNumber,
                              },
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 62,
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(38),
                                    gradient: LinearGradient(
                                      colors: [
                                        gradientStart.withOpacity(
                                            0.35 + _glowAnim.value * 0.19),
                                        gradientEnd.withOpacity(
                                            0.31 + _glowAnim.value * 0.13),
                                        Colors.white.withOpacity(isDark ? 0.05 : 0.13),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradientEnd
                                            .withOpacity(0.23 + _glowAnim.value * 0.18),
                                        blurRadius: 34 * _glowAnim.value + 8,
                                        spreadRadius: 3,
                                        offset: const Offset(0, 7),
                                      ),
                                      BoxShadow(
                                        color: gradientStart
                                            .withOpacity(0.09 + _glowAnim.value * 0.05),
                                        blurRadius: 16,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Container(),
                                ),
                                AnimatedContainer(
                                  duration: Duration(milliseconds: 600),
                                  width: double.infinity,
                                  height: 62,
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(38),
                                    border: Border.all(
                                      width: 3.2 + _glowAnim.value * 0.9,
                                      color: borderColor,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(38),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: isDark ? 3.5 : 8,
                                          sigmaY: isDark ? 3.5 : 8),
                                      child: Container(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                                // Content Row
                                Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: isDark
                                                  ? Colors.cyanAccent
                                                  .withOpacity(0.19 + _glowAnim.value * 0.08)
                                                  : Colors.deepPurpleAccent
                                                  .withOpacity(0.12 + _glowAnim.value * 0.07),
                                              blurRadius: 18 + 9 * _glowAnim.value,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.mic_rounded,
                                          color: theme.colorScheme.onPrimary,
                                          size: 34 + 3 * _glowAnim.value,
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      Text(
                                        "Identify Speaker",
                                        style: theme.textTheme.titleLarge!.copyWith(
                                          color: theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 22,
                                          letterSpacing: 1.12,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withOpacity(0.15),
                                              blurRadius: 2,
                                              offset: const Offset(1, 1),
                                            )
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        color: theme.colorScheme.onPrimary,
                                        size: 27,
                                      ),
                                    ],
                                  ),
                                ),
                                // Lock overlay and shimmer when locked
                                if (identifyLocked)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black.withOpacity(0.31)
                                            : Colors.white.withOpacity(0.23),
                                        borderRadius: BorderRadius.circular(38),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Shimmer lock icon
                                          TweenAnimationBuilder<double>(
                                            tween: Tween(begin: 0.6, end: 1.0),
                                            duration: Duration(seconds: 2),
                                            curve: Curves.easeInOut,
                                            builder: (context, val, _) {
                                              return ShaderMask(
                                                shaderCallback: (rect) {
                                                  return LinearGradient(
                                                    colors: [
                                                      Colors.amber.withOpacity(val),
                                                      Colors.orange.withOpacity(val * 0.8),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ).createShader(rect);
                                                },
                                                child: Icon(Icons.lock_rounded,
                                                    size: 44 + 9 * (1 - val),
                                                    color: Colors.amberAccent.withOpacity(0.81)),
                                              );
                                            },
                                          ),
                                          // Tap overlay
                                          Positioned.fill(
                                            child: IgnorePointer(), // Prevent tap through
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                      itemCount: buttons.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemBuilder: (context, index) {
                        final btn = buttons[index];
                        int originalIndex = index + 2;

                        final List<Color> boxGradientColors = _isDarkMode
                            ? [
                                Color(0xFF232526),
                                Color(0xFF414345),
                                Color(0xFF181A20), // Almost black
                              ]
                            : [
                                Color(0xFF0093E9), // App blue
                                Color(0xFF80D0C7), // App teal
                                Color(0xFFFCF6BA), // App yellow
                              ];

                        final List<BoxShadow> boxShadows = _isDarkMode
                            ? [
                                BoxShadow(
                                  color: Colors.blueGrey.shade900
                                      .withOpacity(0.42),
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                  offset: Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.14),
                                  blurRadius: 18,
                                  offset: Offset(-3, 6),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Color(0xFF0093E9).withOpacity(0.38),
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                  offset: Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Color(0xFFFCF6BA).withOpacity(0.16),
                                  blurRadius: 20,
                                  offset: Offset(-2, 3),
                                ),
                              ];

                        final borderColor = _isDarkMode
                            ? Colors.blueAccent.withOpacity(0.36)
                            : Color(0xFF80D0C7).withOpacity(0.95);
                        final bool locked = btn['lock'] == true;

                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 420),
                          opacity: _itemVisible[originalIndex] ? 1 : 0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 420),
                            offset: _itemVisible[originalIndex]
                                ? Offset.zero
                                : const Offset(0, -0.15),
                            child: Showcase(
                              key: btn['key'] as GlobalKey,
                              title: btn['label'] as String,
                              description: btn['desc'] as String,
                              descriptionPadding: EdgeInsets.all(6),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(26),
                                      gradient: LinearGradient(
                                        colors: boxGradientColors,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: boxShadows,
                                      border: Border.all(
                                        color: locked
                                            ? Colors.redAccent.withOpacity(0.65)
                                            : borderColor,
                                        width: 2.3,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(26),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 8, sigmaY: 8),
                                        child: Container(
                                          color: _isDarkMode
                                              ? Colors.white.withOpacity(0.04)
                                              : Colors.white.withOpacity(0.09),
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(26),
                                    onTap: locked
                                        ? () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                backgroundColor: _isDarkMode
                                                    ? Colors.grey[900]
                                                    : Colors.white,
                                                title: Row(
                                                  children: [
                                                    Icon(Icons.lock_outline,
                                                        color:
                                                            Colors.redAccent),
                                                    SizedBox(width: 8),
                                                    Text("Trial Ended",
                                                        style: TextStyle(
                                                          color: _isDarkMode
                                                              ? Colors.white
                                                              : Colors
                                                                  .redAccent,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        )),
                                                  ],
                                                ),
                                                content: Text(
                                                  _trialMessage ??
                                                      "Your free trial has expired. Please subscribe to continue using this feature.",
                                                  style: TextStyle(
                                                    color: _isDarkMode
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      _showSubscriptionDialog();
                                                    },
                                                    child: Text(
                                                      "Upgrade Now",
                                                      style: TextStyle(
                                                        color:
                                                            Colors.amber[800],
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        : btn['onTap'] as VoidCallback?,
                                    child: Opacity(
                                      opacity: locked ? 0.5 : 1.0,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            btn['icon'] as IconData,
                                            size: 40,
                                            color: locked
                                                ? Colors.redAccent
                                                : Colors.white,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            btn['label'] as String,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .copyWith(
                                              color: locked
                                                  ? Colors.redAccent
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary,
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.15),
                                                  blurRadius: 2,
                                                  offset: const Offset(1, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (locked)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 5.0),
                                              child: Icon(Icons.lock,
                                                  size: 20,
                                                  color: Colors.redAccent),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
