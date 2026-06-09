// samples/twitter_app/lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  /// When true, the user has signed up and must enter the emailed verification
  /// code before a session is established. [_pendingEmail] is the address the
  /// code was sent to.
  bool _awaitingCode = false;
  String _pendingEmail = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(authClientProvider);
    final email = _email.text.trim();
    try {
      if (_isSignUp) {
        final res = await auth.signUp(email: email, password: _password.text);
        if (res.hasSession) {
          // Verification disabled — the authStateProvider stream flips the gate.
          return;
        }
        // Verification required: move to the code-entry step. Sign-up already
        // emailed a 6-digit code, so no need to resend here.
        await _startVerification(email, resend: false);
      } else {
        await auth.signIn(email: email, password: _password.text);
        // On success the authStateProvider stream flips the gate automatically.
      }
    } on InsforgeHttpException catch (e) {
      // A returning user whose email is still unverified gets a 403 here —
      // route them into the verification step instead of a dead-end error.
      if (!_isSignUp && _isEmailUnverified(e)) {
        await _startVerification(email, resend: true);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The backend returns 403 "Email verification required" when an unverified
  /// account tries to sign in.
  bool _isEmailUnverified(InsforgeHttpException e) =>
      e.statusCode == 403 && e.message.toLowerCase().contains('verif');

  /// Switches to the code-entry view for [email]. When [resend] is true (the
  /// returning-user path, where the original code has likely expired) a fresh
  /// code is requested.
  Future<void> _startVerification(String email, {required bool resend}) async {
    setState(() {
      _awaitingCode = true;
      _pendingEmail = email;
      _error = null;
      _info = resend
          ? "Your email isn't verified yet — sending a new code…"
          : 'We sent a 6-digit code to $email. Enter it below.';
    });
    if (!resend) return;
    try {
      await ref.read(authClientProvider).sendVerificationEmail(email);
      if (mounted) {
        setState(
          () => _info = 'We sent a 6-digit code to $email. Enter it below.',
        );
      }
    } on InsforgeHttpException catch (e) {
      if (mounted) {
        setState(
          () => _info = 'Enter the code from your email, or tap Resend. '
              '(${e.message})',
        );
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(authClientProvider);
    try {
      // On success this establishes a session and emits signedIn, so the
      // authStateProvider stream flips the gate — no manual navigation needed.
      await auth.verifyEmail(email: _pendingEmail, otp: code);
    } on InsforgeHttpException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(authClientProvider);
    try {
      await auth.sendVerificationEmail(_pendingEmail);
      setState(() => _info = 'A new code is on its way to $_pendingEmail.');
    } on InsforgeHttpException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancelVerification() {
    setState(() {
      _awaitingCode = false;
      _code.clear();
      _error = null;
      _info = null;
    });
  }

  Future<void> _oauth(OAuthProvider provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(insforgeServiceProvider).signInWithOAuth(provider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InsForge Twitter')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _awaitingCode
                ? _buildVerifyForm(context)
                : _buildAuthForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _isSignUp ? 'Create account' : 'Sign in',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_info != null)
          Text(_info!, style: const TextStyle(color: Colors.green)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isSignUp ? 'Sign up' : 'Sign in'),
        ),
        TextButton(
          onPressed:
              _busy ? null : () => setState(() => _isSignUp = !_isSignUp),
          child: Text(
            _isSignUp
                ? 'Have an account? Sign in'
                : 'New here? Create an account',
          ),
        ),
        const Divider(height: 32),
        const Text('Or continue with'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _oauth(OAuthProvider.google),
              icon: const Icon(Icons.g_mobiledata),
              label: const Text('Google'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _oauth(OAuthProvider.github),
              icon: const Icon(Icons.code),
              label: const Text('GitHub'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerifyForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Verify your email',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: '6-digit code',
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_info != null)
          Text(_info!, style: const TextStyle(color: Colors.green)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _verifyCode,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
        TextButton(
          onPressed: _busy ? null : _resendCode,
          child: const Text('Resend code'),
        ),
        TextButton(
          onPressed: _busy ? null : _cancelVerification,
          child: const Text('Back'),
        ),
      ],
    );
  }
}
