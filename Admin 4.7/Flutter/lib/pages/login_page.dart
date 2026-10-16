import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_quickstart/pages/feed_page.dart';
import '../main.dart';
import 'onboarding_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // 1️⃣ Add a boolean toggle in _LoginPageState
  bool _isSigningUp = false;

  // 2️⃣ Sign Up Method for New Users
  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      context.showSnackBar('Please fill in all fields 📝', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      print(user);

      if (user != null && mounted) {
        // New account created successfully -> Navigate to Onboarding
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingPage()),
        );
      }
    } on AuthException catch (error) {
      if (mounted) context.showSnackBar(error.message, isError: true);
    } catch (e) {
      if (mounted)
        context.showSnackBar('Unexpected error occurred ⚠️', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      context.showSnackBar('Please fill in all fields 📝', isError: true);
      return;
    }
    print(email);
    print(password);

    setState(() => _isLoading = true);
    try {
      // 1️⃣ Sign in with email and password
      final authResponse = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      print("auth Response");
      print(authResponse);

      final user = authResponse.user;
      final session = authResponse.session;

      if (user == null || session == null) {
        context.showSnackBar(
          'Invalid credentials or session expired ❌',
          isError: true,
        );
        return;
      }

      // 2️⃣ Wait briefly for Auth session headers & DB trigger execution ⏳
      await Future.delayed(const Duration(milliseconds: 300));

      final response = await Supabase.instance.client
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();

      print("User id");
      print(user.id);

      print("User response");
      //print(response?[0]);
      print(response);

      // 3️⃣ Fetch student credentials and navigate to FeedPage or OnboardingPage
      if (mounted) {
        if (response != null) {
          final studentCred = await Supabase.instance.client
              .from('profiles')
              .select('college_id, college_pass, courses_id')
              .eq('id', user.id);

          print(studentCred);
          final studentId = studentCred[0]['college_id'];
          final studentPass = studentCred[0]['college_pass'];
          final coursesId = studentCred[0]['courses_id'];

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => FeedPage(
                studentId: studentId,
                studentPassword: studentPass,
                allStudentCourses: coursesId,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => OnboardingPage()),
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) context.showSnackBar(error.message, isError: true);
    } catch (e) {
      debugPrint('LOGIN_DEBUG error: $e');
      if (mounted) {
        context.showSnackBar('Unexpected error occurred ⚠️', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome Back! 👋')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Enter your credentials to sign in: 🔐'),
            const SizedBox(height: 24),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : (_isSigningUp ? _signUp : _signIn),
              child: Text(
                _isLoading
                    ? 'Processing...'
                    : (_isSigningUp ? 'Create Account ✨' : 'Sign In 🚀'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _isSigningUp = !_isSigningUp),
              child: Text(
                _isSigningUp
                    ? 'Already have an account? Sign In'
                    : 'Need an account? Sign Up',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
