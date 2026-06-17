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

  // One Form per tab so validation is scoped to the visible fields.
  final _signInFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

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
    // Rebuild on tab change so the visible form swaps and any server error
    // (which belongs to the previous tab) is cleared.
    _tabs.addListener(() {
      if (mounted) setState(() => _errorMessage = null);
    });
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
    if (!(_signInFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signIn(
        _signInEmailCtrl.text.trim(),
        _signInPasswordCtrl.text,
      );
      if (mounted) context.go('/home');
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!(_registerFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _authService.register(
        _regNameCtrl.text.trim(),
        _regEmailCtrl.text.trim(),
        _regPasswordCtrl.text,
      );
      if (mounted) context.go('/home');
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _signInEmailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage =
          'Enter your email above, then tap Forgot password.');
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
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
    if (raw.contains('user-not-found') ||
        raw.contains('wrong-password') ||
        raw.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (raw.contains('email-already-in-use')) {
      return 'An account with this email already exists.';
    }
    if (raw.contains('weak-password')) {
      return 'Password is too weak. Use at least 8 characters.';
    }
    if (raw.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    }
    if (raw.contains('network-request-failed')) return 'No internet connection.';
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Validators ────────────────────────────────────────────────────────────
  static String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? _validateRequiredPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Password is required.' : null;

  static String? _validateNewPassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required.';
    if (v.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  static String? _validateName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Please enter your name.' : null;

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

                  // Phone OTP — the primary, India-first sign-in path. Most
                  // metro commuters expect phone-number login, so it leads
                  // here; email stays available below as the secondary option.
                  FilledButton.icon(
                    onPressed:
                        _loading ? null : () => context.push('/phone-login'),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Continue with Phone'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  // Divider: "or use email"
                  Row(
                    children: [
                      Expanded(
                          child: Divider(color: colorScheme.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3,
                        ),
                        child: Text(
                          'or use email',
                          style: AppTypography.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: colorScheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s5),

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

                  // Error message (server/auth failures only)
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
                        style: AppTypography.bodySmall
                            .copyWith(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],

                  // Active form only — height follows its intrinsic content, so
                  // no hardcoded heights and no keyboard overflow (the whole
                  // page already scrolls).
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _tabs.index == 0
                        ? _SignInForm(
                            formKey: _signInFormKey,
                            emailCtrl: _signInEmailCtrl,
                            passwordCtrl: _signInPasswordCtrl,
                            passwordVisible: _signInPasswordVisible,
                            onTogglePassword: () => setState(() =>
                                _signInPasswordVisible =
                                    !_signInPasswordVisible),
                            onSignIn: _loading ? null : _signIn,
                            onForgotPassword:
                                _loading ? null : _forgotPassword,
                            loading: _loading,
                            emailValidator: _validateEmail,
                            passwordValidator: _validateRequiredPassword,
                          )
                        : _RegisterForm(
                            formKey: _registerFormKey,
                            nameCtrl: _regNameCtrl,
                            emailCtrl: _regEmailCtrl,
                            passwordCtrl: _regPasswordCtrl,
                            confirmCtrl: _regConfirmCtrl,
                            passwordVisible: _regPasswordVisible,
                            onTogglePassword: () => setState(() =>
                                _regPasswordVisible = !_regPasswordVisible),
                            onRegister: _loading ? null : _register,
                            loading: _loading,
                            nameValidator: _validateName,
                            emailValidator: _validateEmail,
                            passwordValidator: _validateNewPassword,
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
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool passwordVisible;
  final VoidCallback? onTogglePassword;
  final VoidCallback? onSignIn;
  final VoidCallback? onForgotPassword;
  final bool loading;
  final FormFieldValidator<String> emailValidator;
  final FormFieldValidator<String> passwordValidator;

  const _SignInForm({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onSignIn,
    required this.onForgotPassword,
    required this.loading,
    required this.emailValidator,
    required this.passwordValidator,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmailField(ctrl: emailCtrl, validator: emailValidator),
          const SizedBox(height: AppSpacing.s4),
          _PasswordField(
            ctrl: passwordCtrl,
            label: 'Password',
            visible: passwordVisible,
            onToggle: onTogglePassword,
            validator: passwordValidator,
            onSubmitted: onSignIn,
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
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool passwordVisible;
  final VoidCallback? onTogglePassword;
  final VoidCallback? onRegister;
  final bool loading;
  final FormFieldValidator<String> nameValidator;
  final FormFieldValidator<String> emailValidator;
  final FormFieldValidator<String> passwordValidator;

  const _RegisterForm({
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onRegister,
    required this.loading,
    required this.nameValidator,
    required this.emailValidator,
    required this.passwordValidator,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TextField(
            ctrl: nameCtrl,
            label: 'Full Name',
            icon: Icons.person_outline,
            validator: nameValidator,
          ),
          const SizedBox(height: AppSpacing.s3),
          _EmailField(ctrl: emailCtrl, validator: emailValidator),
          const SizedBox(height: AppSpacing.s3),
          _PasswordField(
            ctrl: passwordCtrl,
            label: 'Password (min 8 chars)',
            visible: passwordVisible,
            onToggle: onTogglePassword,
            validator: passwordValidator,
          ),
          const SizedBox(height: AppSpacing.s3),
          _PasswordField(
            ctrl: confirmCtrl,
            label: 'Confirm Password',
            visible: passwordVisible,
            onToggle: null,
            validator: (v) =>
                v != passwordCtrl.text ? 'Passwords do not match.' : null,
            onSubmitted: onRegister,
          ),
          const SizedBox(height: AppSpacing.s4),
          FilledButton(
            onPressed: onRegister,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create Account'),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final FormFieldValidator<String>? validator;

  const _TextField({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      textInputAction: TextInputAction.next,
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
  final FormFieldValidator<String>? validator;
  const _EmailField({required this.ctrl, this.validator});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
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
  final FormFieldValidator<String>? validator;
  final VoidCallback? onSubmitted;

  const _PasswordField({
    required this.ctrl,
    required this.label,
    required this.visible,
    required this.onToggle,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      obscureText: !visible,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
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
