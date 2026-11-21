import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'legal_pages.dart';
import 'utils.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool signup = false;
  bool busy = false;
  bool hide = true;
  bool agreed = false;
  final name = TextEditingController();
  final username = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String _friendlyAuthError(AuthException ex) {
    final m = ex.message.toLowerCase();
    if (m.contains('email not confirmed')) {
      return 'Email is not confirmed yet. In Supabase: Authentication > Providers > Email > turn OFF "Confirm email", then run the latest supabase_setup.sql.';
    }
    if (m.contains('rate limit')) {
      return 'Too many emails sent. In Supabase turn OFF "Confirm email" (Authentication > Providers > Email), then try again.';
    }
    if (m.contains('invalid login')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered')) {
      return 'This email is already registered. Please log in.';
    }
    return ex.message;
  }

  Future<void> submit() async {
    final e = email.text.trim();
    final p = password.text;
    if (e.isEmpty || p.length < 6) {
      snack(
        context,
        'Enter a valid email and a password of at least 6 characters.',
      );
      return;
    }
    if (signup && !agreed) {
      snack(context, 'Please accept the Terms & Conditions to continue.');
      return;
    }
    setState(() => busy = true);
    try {
      if (signup) {
        final u = username.text.trim().toLowerCase();
        final n = name.text.trim();
        if (n.isEmpty) {
          snack(context, 'Please enter your name.');
          return;
        }
        if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(u)) {
          snack(context, 'Username: 3-20 letters, numbers or underscore.');
          return;
        }
        final free = await sb.rpc('username_available', params: {'u': u});
        if (free != true) {
          if (mounted)
            snack(context, 'That username is already taken. Try another one.');
          return;
        }
        final res = await sb.auth.signUp(
          email: e,
          password: p,
          data: {'username': u, 'display_name': n},
        );
        if (res.session == null) {
          // Email OTP/confirmation venda: server (SQL trigger) email auto-confirm
          // cheyyunnu, athinal udane login cheyyaam.
          await sb.auth.signInWithPassword(email: e, password: p);
        }
      } else {
        await sb.auth.signInWithPassword(email: e, password: p);
      }
    } on AuthException catch (ex) {
      if (mounted) snack(context, _friendlyAuthError(ex));
    } catch (ex) {
      if (mounted) snack(context, 'Something went wrong: $ex');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/brand/wordmark.png', height: 90),
                  const SizedBox(height: 8),
                  Text(
                    signup ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (signup) ...[
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: username,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Username (friends find you with this)',
                        prefixIcon: Icon(Icons.alternate_email),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          hide ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => hide = !hide),
                      ),
                    ),
                  ),
                  if (signup)
                    Row(
                      children: [
                        Checkbox(
                          value: agreed,
                          activeColor: purple,
                          onChanged: (v) => setState(() => agreed = v == true),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('I agree to the '),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const TermsPage(),
                                  ),
                                ),
                                child: const Text(
                                  'Terms & Conditions',
                                  style: TextStyle(
                                    color: purple,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            signup ? 'Sign up' : 'Log in',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => signup = !signup),
                    child: Text(
                      signup
                          ? 'Already have an account? Log in'
                          : 'New here? Create an account',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'by ${AppInfo.studioName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black38, fontSize: 12),
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
