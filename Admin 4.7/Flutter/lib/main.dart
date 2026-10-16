import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_quickstart/pages/conversations_page.dart';
import 'pages/login_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/feed_page.dart';
//import 'pages/chat_page.dart';
import 'pages/account_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';



Future<void> main() async {

  await dotenv.load();
  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    publishableKey: dotenv.get('SUPABASE_KEY'),
  );
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getInitialScreen() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      return const LoginPage();
    }

    try {
      final response = await supabase
          .from('profiles')
          .select('display_name, college_id, college_pass, courses_id')
          .eq('id', session.user.id)
          .maybeSingle();

      if (response != null &&
          response['display_name'] != null &&
          (response['display_name'] as String).isNotEmpty) {
        final collegeId = (response['college_id'] as String?) ?? '';
        final collegePass = (response['college_pass'] as String?) ?? '';
        final coursesId = (response['courses_id'] as List<dynamic>?) ?? [];

        return MainScreen(
          collegeId: collegeId,
          collegePass: collegePass, // encrypted blob
          coursesId: coursesId,
        );
      }
    } catch (_) {}

    return const OnboardingPage();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Campus Assistant 🎓',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF121212),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ),
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.green),
              ),
            );
          }
          return snapshot.data ?? const LoginPage();
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String collegeId;
  final String collegePass;
  final List<dynamic> coursesId;

  const MainScreen({
    super.key,
    required this.collegeId,
    required this.collegePass,
    required this.coursesId,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      FeedPage(
        studentId: widget.collegeId,
        studentPassword: widget.collegePass, // encrypted blob
        allStudentCourses: widget.coursesId,
      ),
      ConversationsPage(),
      const AccountPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.newspaper), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Settings'),
        ],
      ),
    );
  }
}

extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).snackBarTheme.backgroundColor ?? Colors.green,
      ),
    );
  }
}