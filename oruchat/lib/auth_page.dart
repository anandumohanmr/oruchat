import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
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
        if (res.session == null && mounted) {
          snack(
            context,
            'Account created. Please confirm your email, then log in.',
          );
          setState(() => signup = false);
        }
      } else {
        await sb.auth.signInWithPassword(email: e, password: p);
      }
    } on AuthException catch (ex) {
      if (mounted) snack(context, ex.message);
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
                  const SizedBox(height: 20),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
