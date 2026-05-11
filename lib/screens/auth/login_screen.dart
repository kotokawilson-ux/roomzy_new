// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../utils/activity_logger.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN:
//  • Deep forest green (#0D3D2B) hero panel + warm cream (#F8F6F1) form panel
//  • Desktop: side-by-side split layout | Mobile: stacked compact hero + form
//  • Decorative overlapping circles for depth on the green panel
//  • Staggered fade+slide entrance animations via AnimationController
//  • Press-scale micro-interaction on the login button
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ── Palette ─────────────────────────────────────────────────────────────
  static const _green = Color(0xFF0D3D2B);
  static const _cream = Color(0xFFF8F6F1);

  // ── Entrance animation ───────────────────────────────────────────────────
  late final AnimationController _ctrl;
  late final List<Animation<double>> _anims;

  // ── Form state ───────────────────────────────────────────────────────────
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _passVisible = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anims = List.generate(6, (i) {
      final start = (i * 0.13).clamp(0.0, 0.9);
      final end = (start + 0.5).clamp(0.0, 1.0);
      return CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic));
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── UPDATED: role-based redirect after login ─────────────────────────────
  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    final authService = context.read<AuthService>();
    final success = await authService.loginStudent(email, pass);

    if (!mounted) return;

    if (success) {
      await ActivityLogger.log(
        action: 'User Login',
        details: 'Email: $email, Role: ${authService.userRole}',
      );
      final role = authService.userRole;
      if (role == 'admin') {
        context.go('/admin');
      } else if (role == 'landlord') {
        context.go('/landlord');
      } else {
        context.go('/home');
      }
    }
    // On failure, authService.errorMessage is set — the Consumer below rebuilds.
  }

  Future<void> _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter your email first, then tap Forgot Password.')),
      );
      return;
    }
    final authService = context.read<AuthService>();
    final error = await authService.sendPasswordReset(_emailCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Password reset email sent! Check your inbox.'),
        backgroundColor: error != null ? Colors.red : const Color(0xFF0D3D2B),
      ),
    );
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
        emailCtrl: _emailCtrl,
        passCtrl: _passCtrl,
        passVisible: _passVisible,
        loading: auth.isLoading,
        error: auth.errorMessage,
        onTogglePass: () => setState(() => _passVisible = !_passVisible),
        onSubmit: _submit,
        onForgotPassword: _forgotPassword,
        onRegister: () => context.go('/register'),
        narrow: narrow,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO PANEL (desktop full-height left panel)
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
                size: 240,
                top: -80,
                right: -80,
                color: Colors.white.withOpacity(0.04)),
            _circle(
                size: 170,
                bottom: 80,
                right: -50,
                color: _greenAccent.withOpacity(0.13)),
            _circle(
                size: 210,
                bottom: -60,
                left: 30,
                color: Colors.white.withOpacity(0.04)),
            _circle(
                size: 70,
                top: 130,
                right: 70,
                color: _greenAccent.withOpacity(0.22)),
            _circle(
                size: 40,
                top: 200,
                left: 60,
                color: Colors.white.withOpacity(0.08)),
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
                        child: Text('Find your\nperfect room.',
                            style: _display(
                                color: Colors.white, size: 42, height: 1.15)),
                      ),
                      const SizedBox(height: 16),
                      _FadeSlide(
                        anim: anims[2],
                        child: Text(
                          'Student-friendly hostels & shared\n'
                          'accommodation — all in one place.',
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
// COMPACT HERO (mobile top strip)
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
                    Text('Find your perfect room.',
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
    required this.emailCtrl,
    required this.passCtrl,
    required this.passVisible,
    required this.loading,
    required this.error,
    required this.onTogglePass,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onRegister,
    required this.narrow,
  });

  final List<Animation<double>> anims;
  final TextEditingController emailCtrl, passCtrl;
  final bool passVisible, loading, narrow;
  final String? error;
  final VoidCallback onTogglePass;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;
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
                        Text('Welcome back',
                            style: _display(
                                color: _green, size: narrow ? 28 : 34)),
                        const SizedBox(height: 6),
                        Text('Sign in to continue to your account',
                            style: _body(
                                color: const Color(0xFF888580), size: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 34),
                  if (error != null)
                    _FadeSlide(
                      anim: anims[1],
                      child: _ErrorBanner(message: error!),
                    ),
                  _FadeSlide(
                    anim: anims[2],
                    child: _InputField(
                      controller: emailCtrl,
                      label: 'Email',
                      hint: 'Enter your email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeSlide(
                    anim: anims[3],
                    child: _InputField(
                      controller: passCtrl,
                      label: 'Password',
                      hint: 'Enter your password',
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
                  const SizedBox(height: 12),
                  _FadeSlide(
                    anim: anims[3],
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onForgotPassword,
                        child: Text('Forgot password?',
                            style: _body(
                                color: _green,
                                size: 13,
                                weight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _FadeSlide(
                    anim: anims[4],
                    child: _SignInButton(loading: loading, onTap: onSubmit),
                  ),
                  const SizedBox(height: 30),
                  _FadeSlide(
                    anim: anims[4],
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
                  const SizedBox(height: 30),
                  _FadeSlide(
                    anim: anims[5],
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Don't have an account? ",
                              style: _body(
                                  color: const Color(0xFF888580), size: 14)),
                          GestureDetector(
                            onTap: onRegister,
                            child: Text('Sign up',
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
// SIGN IN BUTTON with press-scale micro-interaction
// ─────────────────────────────────────────────────────────────────────────────
class _SignInButton extends StatefulWidget {
  const _SignInButton({required this.loading, required this.onTap});
  final bool loading;
  final Future<void> Function() onTap;

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton>
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
                      Text('Sign In',
                          style: _body(
                              color: Colors.white,
                              size: 16,
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
// INPUT FIELD
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

// ─────────────────────────────────────────────────────────────────────────────
// LOGO
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// STAT CHIP (hero panel)
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// ERROR BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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

// ─────────────────────────────────────────────────────────────────────────────
// DECORATIVE CIRCLE
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// FADE + SLIDE ENTRANCE WIDGET
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// TYPOGRAPHY HELPERS
// ─────────────────────────────────────────────────────────────────────────────
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
