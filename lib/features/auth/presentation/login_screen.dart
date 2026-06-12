import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:metrosafar/design_system/components/brand_logo.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import '../../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _authService = AuthService();

  // Sign-in fields
  final _signInEmailCtrl = TextEditingController();
  final _signInPasswordCtrl = TextEditingController();

  // Register fields
  final _regNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  bool _signInPasswordVisible = false;
  bool _regPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _errorMessage = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _signInEmailCtrl.dispose();
    _signInPasswordCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _signInEmailCtrl.text.trim();
    final password = _signInPasswordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email and password.');
      return;
    }
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await _authService.signIn(email, password);
      if (mounted) {
        // Existing account without a verified phone — prompt (skippable).
        context.go(_authService.isPhoneVerified ? '/home' : '/verify-phone');
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final name = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPasswordCtrl.text;
    final confirm = _regConfirmCtrl.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters.');
      return;
    }

    setState(() { _loading = true; _errorMessage = null; });
    try {
      await _authService.register(name, email, password);
      // Phone verification unlocks earning (skippable inside the screen).
      if (mounted) context.go('/verify-phone');
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _signInEmailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email above, then tap Forgot password.');
      return;
    }
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await _authService.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent. Check your inbox.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('user-not-found') || raw.contains('wrong-password') ||
        raw.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (raw.contains('email-already-in-use')) return 'An account with this email already exists.';
    if (raw.contains('weak-password')) return 'Password is too weak. Use at least 8 characters.';
    if (raw.contains('invalid-email')) return 'Please enter a valid email address.';
    if (raw.contains('network-request-failed')) return 'No internet connection.';
    if (raw.contains('too-many-requests')) return 'Too many attempts. Please try again later.';
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
            child: ConstrainedBox(
              // Cap width so the form stays centered on tablets / foldables.
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              const SizedBox(height: AppSpacing.s8),
              // Logo / brand — consistent with launcher icon & onboarding
              const MetroSafarLogo(size: 80),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'MetroSafar',
                style: AppTypography.headlineLarge.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Commute. Earn. Explore.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),

              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabs,
                  indicator: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: colorScheme.onPrimary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Sign In'),
                    Tab(text: 'Create Account'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.bodySmall.copyWith(color: colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
              ],

              // Tab content — fixed height to avoid layout shifts
              SizedBox(
                height: _tabs.index == 0 ? 280 : 400,
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _SignInForm(
                      emailCtrl: _signInEmailCtrl,
                      passwordCtrl: _signInPasswordCtrl,
                      passwordVisible: _signInPasswordVisible,
                      onTogglePassword: () => setState(() => _signInPasswordVisible = !_signInPasswordVisible),
                      onSignIn: _loading ? null : _signIn,
                      onForgotPassword: _loading ? null : _forgotPassword,
                      loading: _loading,
                    ),
                    _RegisterForm(
                      nameCtrl: _regNameCtrl,
                      emailCtrl: _regEmailCtrl,
                      passwordCtrl: _regPasswordCtrl,
                      confirmCtrl: _regConfirmCtrl,
                      passwordVisible: _regPasswordVisible,
                      onTogglePassword: () => setState(() => _regPasswordVisible = !_regPasswordVisible),
                      onRegister: _loading ? null : _register,
                      loading: _loading,
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool passwordVisible;
  final VoidCallback? onTogglePassword;
  final VoidCallback? onSignIn;
  final VoidCallback? onForgotPassword;
  final bool loading;

  const _SignInForm({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onSignIn,
    required this.onForgotPassword,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailField(ctrl: emailCtrl),
        const SizedBox(height: AppSpacing.s4),
        _PasswordField(
          ctrl: passwordCtrl,
          label: 'Password',
          visible: passwordVisible,
          onToggle: onTogglePassword,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onForgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        FilledButton(
          onPressed: onSignIn,
          child: loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sign In'),
        ),
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool passwordVisible;
  final VoidCallback? onTogglePassword;
  final VoidCallback? onRegister;
  final bool loading;

  const _RegisterForm({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onRegister,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextField(ctrl: nameCtrl, label: 'Full Name', icon: Icons.person_outline),
        const SizedBox(height: AppSpacing.s3),
        _EmailField(ctrl: emailCtrl),
        const SizedBox(height: AppSpacing.s3),
        _PasswordField(
          ctrl: passwordCtrl,
          label: 'Password (min 8 chars)',
          visible: passwordVisible,
          onToggle: onTogglePassword,
        ),
        const SizedBox(height: AppSpacing.s3),
        _PasswordField(
          ctrl: confirmCtrl,
          label: 'Confirm Password',
          visible: passwordVisible,
          onToggle: null,
        ),
        const SizedBox(height: AppSpacing.s4),
        FilledButton(
          onPressed: onRegister,
          child: loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Account'),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;

  const _TextField({required this.ctrl, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: label,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: Icon(icon),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s5,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController ctrl;
  const _EmailField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: const InputDecoration(
        hintText: 'Email',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: Icon(Icons.email_outlined),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s5,
        ),
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool visible;
  final VoidCallback? onToggle;

  const _PasswordField({
    required this.ctrl,
    required this.label,
    required this.visible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: !visible,
      decoration: InputDecoration(
        hintText: label,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: const Icon(Icons.lock_outline),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s5,
        ),
        border: const OutlineInputBorder(),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                onPressed: onToggle,
              )
            : null,
      ),
    );
  }
}
