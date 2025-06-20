import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/app_strings.dart';
import '../../../../core/network/http_service.dart';
import '../../../../core/utils/routing/routes.dart';
import 'home_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isUpdate;
  final bool isDarkMode;

  const CompleteProfileScreen({
    Key? key,
    required this.phoneNumber,
    required this.isUpdate,
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  File? _profileImage;
  String? _existingPicUrl;

  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _emailCtrl;
  String? _gender;
  String? _married;
  bool _submitting = false;
  String? _errorMessage;
  bool _autoValidate = false;
  late AnimationController _animController;

  final List<Map<String, dynamic>> _genders = [
    {"label": "Male", "icon": Icons.male},
    {"label": "Female", "icon": Icons.female},
    {"label": "Other", "icon": Icons.transgender},
  ];
  final List<Map<String, dynamic>> _marital = [
    {"label": "Single", "icon": Icons.person_outline},
    {"label": "Married", "icon": Icons.favorite},
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    if (widget.isUpdate) _loadExistingProfile();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animController.forward();
  }

  Future<void> _loadExistingProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('name') ?? '';
      _ageCtrl.text = prefs.getString('age') ?? '';
      _gender = prefs.getString('gender');
      _married = prefs.getString('marriedStatus');
      _emailCtrl.text = prefs.getString('email') ?? '';
      _existingPicUrl = prefs.getString('profilePhoto');
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _emailCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (file != null) {
      setState(() {
        _profileImage = File(file.path);
        _existingPicUrl = null;
      });
    }
  }

  Future<http.MultipartRequest> _buildRequest(Uri uri) async {
    final req = http.MultipartRequest('POST', uri)
      ..fields['phone_number'] = widget.phoneNumber
      ..fields['name'] = _nameCtrl.text.trim()
      ..fields['age'] = _ageCtrl.text.trim()
      ..fields['gender'] = _gender ?? ''
      ..fields['married_status'] = _married ?? ''
      ..fields['email'] = _emailCtrl.text.trim();

    if (!widget.isUpdate) {
      final fcm = await FirebaseMessaging.instance.getToken() ?? '';
      req.fields['fcm_token'] = fcm;
    }

    if (_profileImage != null) {
      final bytes = await _profileImage!.readAsBytes();
      final name = _profileImage!.path.split('/').last;
      req.files.add(http.MultipartFile.fromBytes(
        'profile_picture',
        bytes,
        filename: name,
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    return req;
  }
  void showAccountDeletedDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "accountDeleted",
      pageBuilder: (ctx, _, __) => WillPopScope(
        onWillPop: () async => false,
        child: Container(
          color: widget.isDarkMode ? Color(0xFF181A20) : Color(0xFFFCF6BA),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Material(
                borderRadius: BorderRadius.circular(26),
                color: widget.isDarkMode
                    ? Colors.blueGrey[900]!.withOpacity(0.98)
                    : Colors.white.withOpacity(0.97),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        color: widget.isDarkMode
                            ? Colors.cyanAccent
                            : Colors.deepPurpleAccent,
                        size: 55,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Your account has been blocked",
                        style: TextStyle(
                          color: widget.isDarkMode
                              ? Colors.cyanAccent
                              : Colors.deepPurpleAccent,
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
                          color: widget.isDarkMode
                              ? Colors.white70
                              : Colors.blueGrey.shade700,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isDarkMode
                              ? Colors.cyanAccent.withOpacity(0.85)
                              : Colors.deepPurpleAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 38, vertical: 14),
                        ),
                        icon: Icon(
                          Icons.support_agent_rounded,
                          color: widget.isDarkMode ? Colors.black : Colors.white,
                          size: 26,
                        ),
                        label: Text(
                          "Contact Support",
                          style: TextStyle(
                              color: widget.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
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
                                color: widget.isDarkMode
                                    ? Colors.cyanAccent
                                    : Colors.deepPurpleAccent,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold),
                          )
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
  Future<void> _submitOrUpdate() async {
    setState(() {
      _autoValidate = true;
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() => _errorMessage = 'Please correct the errors above.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final endpoint = widget.isUpdate
          ? ApiConstants.updateUserProfile
          : ApiConstants.registerUser;
      Uri uri = Uri.parse(endpoint);

      var req = await _buildRequest(uri);
      var streamed = await req.send();

      if (streamed.statusCode == 302 || streamed.statusCode == 307) {
        final loc = streamed.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          uri = Uri.parse(loc);
          req = await _buildRequest(uri);
          streamed = await req.send();
        }
      }
      if (streamed.statusCode == 204) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) showAccountDeletedDialog();
        return;
      }
        final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;

        final userDetails = body['user_details'] as Map<String, dynamic>?;
        if (userDetails != null) {
          final picUrl = userDetails['profile_picture_url'] as String?;
          final prefs = await SharedPreferences.getInstance();

          if (picUrl != null && picUrl.isNotEmpty) {
            await prefs.setString('profilePhoto', picUrl);
            setState(() {
              _existingPicUrl = picUrl;
            });
          }

          await prefs.setString('name', userDetails['name'] as String? ?? '');
          await prefs.setString(
              'phoneNumber', userDetails['phone_number'] as String? ?? '');
          await prefs.setString('age', userDetails['age'].toString());
          await prefs.setString(
              'gender', userDetails['gender'] as String? ?? '');
          await prefs.setString(
              'marriedStatus', userDetails['married_status'] as String? ?? '');
          await prefs.setString('email', userDetails['email'] as String? ?? '');
        }

        if (!widget.isUpdate) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('loggedIn', true);
          if (context.mounted) {

            context.goNamed(
              Routes.homeScreen,
              extra: widget.phoneNumber,
            );

          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Profile updated successfully'),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Dismiss',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
            await Future.delayed(const Duration(milliseconds: 800));
            context.pop(true);
          }
        }
      } else {
        final data = resp.body.isNotEmpty
            ? jsonDecode(resp.body) as Map<String, dynamic>
            : null;
        setState(() =>
        _errorMessage = data?['message'] as String? ?? 'Update failed.');
      }
    } on SocketException {
      setState(() =>
      _errorMessage = 'Network error. Please check your connection.');
    } catch (e) {
      setState(() => _errorMessage = 'Error: $e');
    } finally {
      setState(() => _submitting = false);
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    bool readOnly = false,
  }) {
    final isDark = widget.isDarkMode;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        color: isDark ? Colors.white70 : Colors.white.withOpacity(0.80),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(
        icon,
        color: isDark ? Colors.white70 : Colors.white.withOpacity(0.84),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: readOnly
          ? (isDark ? Colors.grey[900] : Colors.grey[300])
          : (isDark ? Colors.grey[800] : Colors.white.withOpacity(0.09)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.pinkAccent, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth < 540 ? screenWidth - 24 : 500.0;

    return SafeArea(
      child: Scaffold(
        body: Container(
          height: double.infinity,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: isDark
                ? null
                : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0093E9),
                Color(0xFF80D0C7),
                Color(0xFFFCF6BA),
              ],
              stops: [0.1, 0.7, 1.0],
            ),
            color: isDark ? Colors.black : null,
          ),
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 240,
                            decoration: BoxDecoration(
                              gradient: isDark
                                  ? null
                                  : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF0093E9),
                                  Color(0xFF80D0C7),
                                  Color(0xFFFCF6BA),
                                ],
                                stops: [0.1, 0.7, 1.0],
                              ),
                              color: isDark ? Colors.grey[900] : null,
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(40)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withOpacity(isDark ? 0.5 : 0.26),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  const SizedBox(height: 30),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      widget.isUpdate
                                          ? GestureDetector(
                                        onTap: () => context.pop(),
                                        child: Icon(
                                          Icons.arrow_back,
                                          color:
                                          isDark ? Colors.white : Colors.white,
                                          size: 33,
                                        ),
                                      )
                                          : const SizedBox(),
                                      ShaderMask(
                                        shaderCallback: (rect) => LinearGradient(
                                          colors: widget.isDarkMode
                                              ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                                              : [Colors.deepPurple, Colors.indigo, Colors.amber],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ).createShader(rect),
                                        child: Text(
                                            widget.isUpdate
                                                ? "Update Your Profile"
                                                : AppStrings.completeProfileTitle,
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
                                      const SizedBox(width: 33),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            left: (maxWidth / 2) - 65,
                            child: GestureDetector(
                              onTap: _pickProfileImage,
                              child: GlassmorphicContainer(
                                width: 130,
                                height: 130,
                                borderRadius: 75,
                                blur: 16,
                                border: 2,
                                linearGradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(
                                        isDark ? 0.15 : 0.25),
                                    Colors.white.withOpacity(
                                        isDark ? 0.05 : 0.07),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderGradient: const LinearGradient(
                                  colors: [Colors.purpleAccent, Colors.blueAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                child: Stack(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                      const Duration(milliseconds: 350),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blueAccent.withOpacity(
                                                isDark ? 0.1 : 0.08),
                                            blurRadius: 24,
                                          )
                                        ],
                                      ),
                                      child: CircleAvatar(
                                        radius: 62,
                                        backgroundColor: Colors.transparent,
                                        backgroundImage:
                                        _profileImage != null
                                            ? FileImage(_profileImage!)
                                        as ImageProvider
                                            : (_existingPicUrl != null &&
                                            _existingPicUrl!
                                                .trim()
                                                .isNotEmpty
                                            ? NetworkImage(
                                            ApiConstants.baseUrl +
                                                _existingPicUrl!)
                                            : null),
                                        child: (_profileImage == null &&
                                            (_existingPicUrl == null ||
                                                _existingPicUrl!
                                                    .trim()
                                                    .isEmpty))
                                            ? Icon(
                                          Icons.camera_alt,
                                          size: 42,
                                          color: isDark
                                              ? Colors.white
                                              .withOpacity(0.7)
                                              : Colors.white
                                              .withOpacity(0.7),
                                        )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.grey[800]
                                              : Colors.white70,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.edit,
                                          size: 20,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GlassmorphicContainer(
                          width: double.infinity,
                          height: 500,
                          borderRadius: 28,
                          blur: 19,
                          border: 1,
                          linearGradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(isDark ? 0.10 : 0.18),
                              Colors.white.withOpacity(isDark ? 0.04 : 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderGradient: LinearGradient(
                            colors: [
                              Colors.purpleAccent.withOpacity(isDark ? 0.10 : 0.18),
                              Colors.blueAccent.withOpacity(isDark ? 0.05 : 0.10)
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Form(
                                key: _formKey,
                                autovalidateMode: _autoValidate
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
                                child: Column(
                                  children: [
                                    if (_errorMessage != null) ...[
                                      Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    TextFormField(
                                      controller: _nameCtrl,
                                      style: GoogleFonts.poppins(
                                        color: isDark ? Colors.white : Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      decoration: _inputDecoration(
                                        hint: 'Full Name',
                                        icon: Icons.person,
                                      ),
                                      validator: (v) => v!.trim().isEmpty
                                          ? 'Enter your name'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _ageCtrl,
                                      style: GoogleFonts.poppins(
                                          color: isDark ? Colors.white : Colors.white,
                                          fontWeight: FontWeight.w500),
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDecoration(
                                          hint: 'Age', icon: Icons.cake),
                                      validator: (v) {
                                        final a = int.tryParse(v ?? '');
                                        if (a == null || a < 1 || a > 120) {
                                          return 'Enter age between 1 and 120';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    _PillDropdown(
                                      label: "Gender",
                                      items: _genders,
                                      icon: Icons.wc,
                                      value: _genders.any((t) => t['label'] == _gender)
                                          ? _gender
                                          : null,
                                      onChanged: (v) {
                                        setState(() => _gender = v);
                                      },
                                      validator: (v) =>
                                      v == null || v.isEmpty ? 'Select Gender' : null,
                                      isDarkMode: widget.isDarkMode,
                                    ),
                                    const SizedBox(height: 16),
                                    _PillDropdown(
                                      label: "Marital Status",
                                      items: _marital,
                                      icon: Icons.favorite_border,
                                      value: _marital.any((t) => t['label'] == _married)
                                          ? _married
                                          : null,
                                      onChanged: (v) {
                                        setState(() => _married = v);
                                      },
                                      validator: (v) =>
                                      v == null || v.isEmpty
                                          ? 'Select Marital Status'
                                          : null,
                                      isDarkMode: widget.isDarkMode,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _emailCtrl,
                                      style: GoogleFonts.poppins(
                                        color: widget.isUpdate
                                            ? (isDark
                                            ? Colors.white60
                                            : Colors.grey[800])
                                            : (isDark
                                            ? Colors.white
                                            : Colors.white),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      keyboardType: TextInputType.emailAddress,
                                      readOnly: widget.isUpdate,
                                      decoration: _inputDecoration(
                                        hint: 'Email Address',
                                        icon: Icons.email,
                                        readOnly: widget.isUpdate,
                                      ),
                                      validator: (v) {
                                        final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                            .hasMatch(v ?? '');
                                        return ok ? null : 'Enter valid email';
                                      },
                                    ),
                                    const SizedBox(height: 28),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: ElevatedButton(
                                          key: ValueKey(_submitting),
                                          onPressed:
                                          _submitting ? null : _submitOrUpdate,
                                          style: ElevatedButton.styleFrom(
                                            elevation: 4,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(22)),
                                            padding: EdgeInsets.zero,
                                            backgroundColor: isDark
                                                ? Colors.deepPurpleAccent.shade200
                                                : Colors.deepPurpleAccent,
                                          ),
                                          child: _submitting
                                              ? Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  color:
                                                  isDark ? Colors.black : Colors.white,
                                                  strokeWidth: 2.5,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                widget.isUpdate
                                                    ? 'Updating...'
                                                    : 'Completing...',
                                                style: GoogleFonts.poppins(
                                                    color: isDark
                                                        ? Colors.black
                                                        : Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 17),
                                              )
                                            ],
                                          )
                                              : Text(
                                            widget.isUpdate
                                                ? 'Update Profile'
                                                : 'Complete Profile',
                                            style: GoogleFonts.poppins(
                                                color: isDark ? Colors.black : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 17),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
}

class _PillDropdown extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final IconData icon;
  final String? Function(String?)? validator;
  final bool isDarkMode;

  const _PillDropdown({
    required this.label,
    required this.items,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.isDarkMode,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return DropdownButtonFormField<String>(
      value: value,
      icon: Icon(icon, color: isDark ? Colors.white70 : Colors.white70),
      dropdownColor: isDark ? Colors.grey[850] : const Color(0xFF4527A0),
      validator: validator,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: GoogleFonts.poppins(
            color: isDark ? Colors.white70 : Colors.white.withOpacity(0.80),
            fontWeight: FontWeight.w500),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.white.withOpacity(0.10),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: Colors.pinkAccent, width: 2)),
        errorBorder:
        border.copyWith(borderSide: const BorderSide(color: Colors.redAccent)),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
      style: GoogleFonts.poppins(
          color: isDark ? Colors.white : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16),
      items: items
          .map<DropdownMenuItem<String>>((t) => DropdownMenuItem<String>(
        value: t['label'] as String,
        child: Row(
          children: [
            Icon(t['icon'],
                size: 20,
                color: isDark ? Colors.purple[200]! : Colors.purpleAccent),
            const SizedBox(width: 8),
            Text(t['label'],
                style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.white,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
