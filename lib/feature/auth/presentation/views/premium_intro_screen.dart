import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/network/http_service.dart';

class PremiumIntroScreen extends StatefulWidget {
  final VoidCallback onLater;
  final void Function(Map<String, dynamic> plan) onContinue;
  final String logoAsset;

  const PremiumIntroScreen({
    super.key,
    required this.onContinue,
    required this.onLater,
    this.logoAsset = 'assets/images/awa_logo.webp',
  });

  @override
  State<PremiumIntroScreen> createState() => _PremiumIntroScreenState();
}

class _PremiumIntroScreenState extends State<PremiumIntroScreen>
    with SingleTickerProviderStateMixin {
  bool _freeTrialEnabled = true;

  // Dynamic plans
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _selectedPlan;
  bool _isLoading = true;
  String? _error;

  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _fetchPlans();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoading = true;
      _error = null;
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
          _plans = plans;
          _selectedPlan = plans.isNotEmpty ? plans.first : null;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load plans.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load plans.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaGradient = const LinearGradient(
      colors: [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFFC837)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final glass = BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.3),
      boxShadow: [
        BoxShadow(
          color: Colors.amber.withOpacity(0.05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.blue.withOpacity(0.05),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // BG Gradient
          Container(
            decoration: BoxDecoration(
              gradient: awaGradient,
            ),
          ),
          // Glass overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: Colors.black.withOpacity(0.36),
            ),
          ),
          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with Glow
                    AnimatedBuilder(
                      animation: _glowAnim,
                      builder: (_, __) => Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amberAccent.withOpacity(0.19 * _glowAnim.value),
                              blurRadius: 48 * _glowAnim.value,
                              spreadRadius: 4,
                            ),
                          ],
                          gradient: LinearGradient(
                            colors: [
                              Colors.amber.withOpacity(0.22),
                              Colors.white.withOpacity(0.10),
                            ],
                          ),
                        ),
                        child: Image.asset(
                          widget.logoAsset,
                          width: 58,
                          height: 58,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Main Glass Panel
                    Container(
                      decoration: glass,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [Colors.amber, Colors.white, Colors.blueAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: const Text(
                              "Unlock Premium",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 27,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Enjoy these benefits when you upgrade to premium:",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w400,
                              fontSize: 16.5,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _buildFeature(Icons.lock_open_rounded, "Unlimited content access"),
                          _buildFeature(Icons.no_adult_content, "No annoying ads"),
                          const SizedBox(height: 22),
                          // Free trial toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.timer, color: Colors.amber, size: 24),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Enable 2-day free trial",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.88),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16.5,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _freeTrialEnabled,
                                activeColor: Colors.amber,
                                onChanged: (val) => setState(() => _freeTrialEnabled = val),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          // Plan picker
                          _buildPlansSection(),
                          const SizedBox(height: 13),
                          Text(
                            "No charges yet. Cancel anytime.",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.63),
                              fontSize: 13.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),
                          // Continue Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber[800],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 8,
                              ),
                              onPressed: _selectedPlan != null && !_isLoading
                                  ? () => widget.onContinue(_selectedPlan!)
                                  : null,
                              child: const Text(
                                "Continue",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                  fontSize: 19,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Maybe Later Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.amber.shade300, width: 1.3),
                                foregroundColor: Colors.amber[800],
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                              label: const Text(
                                "Maybe Later",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.4,
                                ),
                              ),
                              onPressed: widget.onLater,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // How Free Trial Works
                    _HowTrialWorksPanel(
                      isYearly: _selectedPlan?['plan_name']?.toLowerCase().contains('year') ?? false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, color: Colors.amber, size: 21),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.88),
            fontWeight: FontWeight.w500,
            fontSize: 16.2,
          ),
        ),
      ],
    ),
  );

  Widget _buildPlansSection() {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Text(
              _error!,
              style: TextStyle(color: Colors.redAccent, fontSize: 15),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _fetchPlans,
              icon: const Icon(Icons.refresh, color: Colors.amber),
              label: const Text("Retry", style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      );
    }
    if (_plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text("No subscription plans available.",
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      );
    }
    return Row(
      children: _plans.map((plan) {
        final isSelected = plan == _selectedPlan;
        final planLabel = plan['plan_name'] ?? 'Plan';
        final rawPrice = plan['price'];
        final priceValue = rawPrice is num
            ? rawPrice
            : num.tryParse(rawPrice?.toString() ?? '');
        final price =
            priceValue != null ? '₹${priceValue.toStringAsFixed(0)}' : '₹---';
        final subtitle = plan['subtitle'] ?? (plan['duration_days'] != null
            ? "${plan['duration_days']} days"
            : null);
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedPlan = plan),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 0),
              margin: EdgeInsets.only(
                right: _plans.last == plan ? 0 : 10,
                top: isSelected ? 0 : 4,
                bottom: isSelected ? 0 : 4,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber[700] : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
                  )
                ]
                    : [],
                border: Border.all(
                  color: isSelected ? Colors.amber[300]! : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    planLabel,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    price,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 15.6,
                    ),
                  ),
                  if (subtitle != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// How Free Trial Works panel
class _HowTrialWorksPanel extends StatelessWidget {
  final bool isYearly;
  const _HowTrialWorksPanel({required this.isYearly});

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withOpacity(0.92);
    final highlight = Colors.amber[600];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "How your free trial works",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: color,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 18),
          _timelineStep(
            icon: Icons.lock_open,
            label: "Today",
            desc: "Unlock access to all premium features instantly.",
            highlight: highlight,
          ),
          const SizedBox(height: 9),
          _timelineStep(
            icon: Icons.notifications,
            label: "Day 1",
            desc: "Get a reminder that your trial is about to end.",
            highlight: highlight,
          ),
          const SizedBox(height: 9),
          _timelineStep(
            icon: Icons.star,
            label: "Day 2",
            desc: "Your subscription starts. Cancel anytime before.",
            highlight: highlight,
          ),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required IconData icon,
    required String label,
    required String desc,
    required Color? highlight,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight!.withOpacity(0.15),
              border: Border.all(color: highlight.withOpacity(0.6), width: 1.6),
            ),
            child: Icon(icon, color: highlight, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: highlight,
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.84),
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
