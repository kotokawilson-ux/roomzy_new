// lib/screens/auth/landlord_register_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../utils/activity_logger.dart';
// ─────────────────────────────────────────────────────────────────────────────
// LandlordRegisterScreen — self-service landlord signup.
//  • Same green/cream split aesthetic as LoginScreen / RegisterScreen
//  • Fields: business/full name, email, phone, address, password, confirm
//  • Wired to AuthService.registerLandlord()
//  • New landlords land in `verified: false` state — a "Pending Review"
//    banner explains this, and the admin panel surfaces it for approval.
// ─────────────────────────────────────────────────────────────────────────────

class LandlordRegisterScreen extends StatefulWidget {
  const LandlordRegisterScreen({super.key});

  @override
  State<LandlordRegisterScreen> createState() =>
      _LandlordRegisterScreenState();
}

class _LandlordRegisterScreenState extends State<LandlordRegisterScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF0D3D2B);
  static const _cream = Color(0xFFF8F6F1);

  late final AnimationController _ctrl;
  late final List<Animation<double>> _anims;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _passVisible = false;
  bool _confirmPassVisible = false;
  bool _loading = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anims = List.generate(9, (i) {
      final start = (i * 0.09).clamp(0.0, 0.9);
      final end = (start + 0.45).clamp(0.0, 1.0);
      return CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic));
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _localError = null);

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || phone.isEmpty || pass.isEmpty) {
      setState(() => _localError = 'Please fill in all required fields.');
      return;
    }
    if (pass != confirm) {
      setState(() => _localError = 'Passwords do not match.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _localError = 'Password must be at least 6 characters.');
      return;
    }

    setState(() => _loading = true);
    final authService = context.read<AuthService>();
    final success = await authService.registerLandlord(
      businessName: name,
      email: email,
      phone: phone,
      address: address,
      password: pass,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      await ActivityLogger.log(
        action: 'Landlord Self-Registered',
        details: 'Name: $name, Email: $email',
      );
      context.go('/landlord');
    }
    // On failure, authService.errorMessage is set → Consumer rebuilds.
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w >= 720;

    return Scaffold(
      backgroundColor: _cream,
      body: isWide ? _wideBody() : _narrowBody(),
    );
  }

  Widget _wideBody() => Row(
        children: [
          Expanded(flex: 5, child: _HeroPanel(anims: _anims)),
          Expanded(flex: 6, child: _buildFormPanel(narrow: false)),
        ],
      );

  Widget _narrowBody() => Column(
        children: [
          _CompactHero(anim: _anims[0]),
          Expanded(child: _buildFormPanel(narrow: true)),
        ],
      );

  Widget _buildFormPanel({required bool narrow}) {
    return Consumer<AuthService>(
      builder: (context, auth, _) => _FormPanel(
        anims: _anims,
        nameCtrl: _nameCtrl,
        emailCtrl: _emailCtrl,
        phoneCtrl: _phoneCtrl,
        addressCtrl: _addressCtrl,
        passCtrl: _passCtrl,
        confirmPassCtrl: _confirmPassCtrl,
        passVisible: _passVisible,
        confirmPassVisible: _confirmPassVisible,
        loading: _loading || auth.isLoading,
        error: _localError ?? auth.errorMessage,
        onTogglePass: () => setState(() => _passVisible = !_passVisible),
        onToggleConfirmPass: () =>
            setState(() => _confirmPassVisible = !_confirmPassVisible),
        onSubmit: _submit,
        onLogin: () => context.go('/login'),
        onStudentInstead: () => context.go('/register'),
        narrow: narrow,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.anims});
  final List<Animation<double>> anims;

  static const _green = Color(0xFF0D3D2B);
  static const _greenMid = Color(0xFF1A6645);
  static const _greenAccent = Color(0xFF34C77B);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anims[0],
      builder: (_, __) => Opacity(
        opacity: anims[0].value,
        child: Container(
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green, _greenMid],
            ),
          ),
          child: Stack(children: [
            _circle(
                size: 220,
                top: -70,
                right: -70,
                color: Colors.white.withOpacity(0.04)),
            _circle(
                size: 160,
                bottom: 100,
                right: -40,
                color: _greenAccent.withOpacity(0.13)),
            _circle(
                size: 200,
                bottom: -50,
                left: 20,
                color: Colors.white.withOpacity(0.04)),
            _circle(
                size: 60,
                top: 120,
                right: 80,
                color: _greenAccent.withOpacity(0.22)),
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 44, vertical: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      const _Logo(onDark: true),
                      const SizedBox(height: 44),
                      _FadeSlide(
                        anim: anims[1],
                        child: Text('List your\nproperty.',
                            style: _display(
                                color: Colors.white, size: 42, height: 1.15)),
                      ),
                      const SizedBox(height: 16),
                      _FadeSlide(
                        anim: anims[2],
                        child: Text(
                          'Reach thousands of students looking\n'
                          'for their next home — manage it\n'
                          'all from one dashboard.',
                          style: _body(
                              color: Colors.white.withOpacity(0.72), size: 15),
                        ),
                      ),
                      const SizedBox(height: 52),
                      _FadeSlide(
                        anim: anims[3],
                        child: const Row(
                          children: [
                            _Stat(value: '2,400+', label: 'Listings'),
                            SizedBox(width: 32),
                            _Stat(value: '98%', label: 'Satisfaction'),
                          ],
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _circle(
      {required double size,
      required Color color,
      double? top,
      double? bottom,
      double? left,
      double? right}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPACT HERO (mobile)
// ─────────────────────────────────────────────────────────────────────────────
class _CompactHero extends StatelessWidget {
  const _CompactHero({required this.anim});
  final Animation<double> anim;

  static const _green = Color(0xFF0D3D2B);
  static const _greenMid = Color(0xFF1A6645);
  static const _greenAccent = Color(0xFF34C77B);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Container(
          width: double.infinity,
          height: 196,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green, _greenMid],
            ),
          ),
          child: Stack(children: [
            Positioned(
                top: -40,
                right: -40,
                child: _DecorCircle(
                    size: 140, color: Colors.white.withOpacity(0.05))),
            Positioned(
                bottom: -20,
                left: 24,
                child: _DecorCircle(
                    size: 100, color: _greenAccent.withOpacity(0.14))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _Logo(onDark: true, compact: true),
                    const SizedBox(height: 12),
                    Text('List your property.',
                        style: _display(
                            color: Colors.white, size: 22, height: 1.2)),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORM PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.anims,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.addressCtrl,
    required this.passCtrl,
    required this.confirmPassCtrl,
    required this.passVisible,
    required this.confirmPassVisible,
    required this.loading,
    required this.error,
    required this.onTogglePass,
    required this.onToggleConfirmPass,
    required this.onSubmit,
    required this.onLogin,
    required this.onStudentInstead,
    required this.narrow,
  });

  final List<Animation<double>> anims;
  final TextEditingController nameCtrl,
      emailCtrl,
      phoneCtrl,
      addressCtrl,
      passCtrl,
      confirmPassCtrl;
  final bool passVisible, confirmPassVisible, loading, narrow;
  final String? error;
  final VoidCallback onTogglePass, onToggleConfirmPass, onLogin;
  final VoidCallback onStudentInstead;
  final Future<void> Function() onSubmit;

  static const _green = Color(0xFF0D3D2B);
  static const _cream = Color(0xFFF8F6F1);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: narrow ? 28 : 52, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!narrow)
                    _FadeSlide(
                      anim: anims[0],
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: _Logo(onDark: false),
                      ),
                    ),

                  _FadeSlide(
                    anim: anims[1],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Become a landlord',
                            style: _display(
                                color: _green, size: narrow ? 26 : 32)),
                        const SizedBox(height: 6),
                        Text('Register your hostel and start listing rooms',
                            style: _body(
                                color: const Color(0xFF888580), size: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Pending-review notice — sets the right expectation
                  // before they even submit.
                  _FadeSlide(
                    anim: anims[1],
                    child: _NoticeBanner(
                      icon: Icons.shield_outlined,
                      message:
                          'Your dashboard is available right away, but new landlord accounts are reviewed by our team shortly after signup.',
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Error banner
                  if (error != null)
                    _FadeSlide(
                      anim: anims[1],
                      child: _ErrorBanner(message: error!),
                    ),

                  // Business / full name
                  _FadeSlide(
                    anim: anims[2],
                    child: _InputField(
                      controller: nameCtrl,
                      label: 'Business / Full Name',
                      hint: 'e.g. Kofi Mensah or Golden Gate Hostel',
                      icon: Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Email
                  _FadeSlide(
                    anim: anims[3],
                    child: _InputField(
                      controller: emailCtrl,
                      label: 'Email',
                      hint: 'Enter your email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone
                  _FadeSlide(
                    anim: anims[4],
                    child: _InputField(
                      controller: phoneCtrl,
                      label: 'Phone Number',
                      hint: 'Enter your phone number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Address
                  _FadeSlide(
                    anim: anims[5],
                    child: _InputField(
                      controller: addressCtrl,
                      label: 'Address (optional)',
                      hint: 'Where are you based?',
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  _FadeSlide(
                    anim: anims[6],
                    child: _InputField(
                      controller: passCtrl,
                      label: 'Password',
                      hint: 'Create a password (min. 6 chars)',
                      icon: Icons.lock_outline_rounded,
                      obscure: !passVisible,
                      suffix: GestureDetector(
                        onTap: onTogglePass,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Icon(
                            passVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFFAAAAAA),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Confirm password
                  _FadeSlide(
                    anim: anims[7],
                    child: _InputField(
                      controller: confirmPassCtrl,
                      label: 'Confirm Password',
                      hint: 'Repeat your password',
                      icon: Icons.lock_outline_rounded,
                      obscure: !confirmPassVisible,
                      suffix: GestureDetector(
                        onTap: onToggleConfirmPass,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Icon(
                            confirmPassVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFFAAAAAA),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Register button
                  _FadeSlide(
                    anim: anims[8],
                    child: _RegisterButton(loading: loading, onTap: onSubmit),
                  ),
                  const SizedBox(height: 24),

                  _FadeSlide(
                    anim: anims[8],
                    child: Center(
                      child: GestureDetector(
                        onTap: onStudentInstead,
                        child: Text('Looking for a room instead? Sign up as a student',
                            textAlign: TextAlign.center,
                            style: _body(
                                color: _green,
                                size: 13,
                                weight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  _FadeSlide(
                    anim: anims[8],
                    child: Row(children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('or',
                            style: _body(
                                color: const Color(0xFFBBBBBB), size: 13)),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Already have account
                  _FadeSlide(
                    anim: anims[8],
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Already have an account? ',
                              style: _body(
                                  color: const Color(0xFF888580), size: 14)),
                          GestureDetector(
                            onTap: onLogin,
                            child: Text('Sign in',
                                style: _body(
                                    color: _green,
                                    size: 14,
                                    weight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTICE BANNER (pending-review explainer)
// ─────────────────────────────────────────────────────────────────────────────
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  static const _green = Color(0xFF0D3D2B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: _body(color: _green, size: 12.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _RegisterButton extends StatefulWidget {
  const _RegisterButton({required this.loading, required this.onTap});
  final bool loading;
  final Future<void> Function() onTap;

  @override
  State<_RegisterButton> createState() => _RegisterButtonState();
}

class _RegisterButtonState extends State<_RegisterButton>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF0D3D2B);
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.965)
        .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_green, Color(0xFF1A6645)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.32),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Create Landlord Account',
                          style: _body(
                              color: Colors.white,
                              size: 15,
                              weight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;

  static const _green = Color(0xFF0D3D2B);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: _body(
                color: const Color(0xFF2D2D2D),
                size: 13,
                weight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: _body(color: const Color(0xFF1A1A1A), size: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _body(color: const Color(0xFFBBBBBB), size: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(icon, color: const Color(0xFFAAAAAA), size: 20),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _green, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.onDark, this.compact = false});
  final bool onDark, compact;

  static const _green = Color(0xFF0D3D2B);
  static const _greenAccent = Color(0xFF34C77B);

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 18.0 : 22.0;
    final textSize = compact ? 19.0 : 24.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize + 10,
          height: iconSize + 10,
          decoration: BoxDecoration(
            color: _greenAccent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.home_work_rounded,
              color: Colors.white, size: iconSize - 2),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Roomzy',
                style: _display(
                    color: onDark ? Colors.white : _green, size: textSize),
              ),
              TextSpan(
                text: 'Find',
                style: _display(color: _greenAccent, size: textSize),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  static const _greenAccent = Color(0xFF34C77B);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: _display(color: _greenAccent, size: 22)),
        const SizedBox(height: 2),
        Text(label,
            style: _body(color: Colors.white.withOpacity(0.62), size: 12)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFD32F2F), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: _body(color: const Color(0xFFB71C1C), size: 13)),
          ),
        ],
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _FadeSlide extends StatelessWidget {
  const _FadeSlide({required this.anim, required this.child});
  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }
}

TextStyle _display({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w700,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'Georgia',
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: -0.4,
    );

TextStyle _body({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w400,
  double? height,
}) =>
    TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: height ?? 1.5,
      letterSpacing: 0.1,
    );