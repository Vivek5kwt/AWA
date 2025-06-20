import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumIntroScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final String logoAsset;

  const PremiumIntroScreen({
    super.key,
    required this.onContinue,
    this.logoAsset = 'assets/images/awa_logo.webp',
  });

  @override
  State<PremiumIntroScreen> createState() => _PremiumIntroScreenState();
}

class _PremiumIntroScreenState extends State<PremiumIntroScreen>
    with SingleTickerProviderStateMixin {
  bool _freeTrialEnabled = true;
  bool _yearlySelected = true;

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
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
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
                        //  _buildFeature(Icons.offline_pin_rounded, "Offline access"),
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
                          Row(
                            children: [
                              _buildPlanTile(
                                selected: _yearlySelected,
                                label: "Yearly",
                                price: "₹599/year",
                                subtitle: "Save 50%",
                                onTap: () => setState(() => _yearlySelected = true),
                              ),
                              const SizedBox(width: 10),
                              _buildPlanTile(
                                selected: !_yearlySelected,
                                label: "Monthly",
                                price: "₹99/mo",
                                subtitle: null,
                                onTap: () => setState(() => _yearlySelected = false),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          // Info
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
                              onPressed: () {
                                // You can trigger payment flow here.
                                widget.onContinue();
                              },
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
                          const SizedBox(height: 12),
                          // Links
                         /* Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () {}, // Restore purchase
                                child: const Text("Restore Purchase"),
                              ),
                              TextButton(
                                onPressed: () {}, // Privacy
                                child: const Text("Privacy Policy"),
                              ),
                              TextButton(
                                onPressed: () {}, // Terms
                                child: const Text("Terms of Use"),
                              ),
                            ],
                          )*/
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // How Free Trial Works
                    _HowTrialWorksPanel(
                      isYearly: _yearlySelected,
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

  Widget _buildPlanTile({
    required bool selected,
    required String label,
    required String price,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 0),
          margin: EdgeInsets.only(
            top: selected ? 0 : 4,
            bottom: selected ? 0 : 4,
          ),
          decoration: BoxDecoration(
            color: selected ? Colors.amber[700] : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
              BoxShadow(
                color: Colors.amber.withOpacity(0.22),
                blurRadius: 16,
                offset: const Offset(0, 3),
              )
            ]
                : [],
            border: Border.all(
              color: selected ? Colors.amber[300]! : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                price,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
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
  }
}

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
