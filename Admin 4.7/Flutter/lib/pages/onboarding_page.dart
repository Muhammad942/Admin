import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart';
import 'feed_page.dart';
import '../courses_table.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _nameController = TextEditingController();
  final _collegeIdController = TextEditingController();
  final _collegePassController = TextEditingController();
  // final _passwordController = TextEditingController();
  final _emailController = TextEditingController();

  int _selectedSemester = 1;
  final List<String> _availableCourses = [
    'معالجة الإشارات الرقمية',
    'نظم التشغيل',
    'إنترنت الأشياء',
    'الرسم بالحاسب',
    'المعالجة المتوازية',
    'تطوير تطبيقات الجوال',
    'تعلم الآلة',
  ];
  final List<String> _selectedCourses = [];
  final List<int> _coursesId = [];
  bool _isLoading = false;

  Future<void> _completeRegistration() async {
    final name = _nameController.text.trim();
    final collegeId = _collegeIdController.text.trim();
    final collegePass = _collegePassController.text.trim();
    // final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty ||
        collegeId.isEmpty ||
        collegePass.isEmpty ||
        email.isEmpty) {
      context.showSnackBar('Please fill in all fields 📝', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;

      // 1. Update User Password in Supabase Auth (deprecated approach)
      // await supabase.auth.updateUser(UserAttributes(password: password));

      // Loop directly through each selected course name
      for (final courseName in _selectedCourses) {
        final courseId = allStudentCourse[courseName];

        // If the course exists in the map, add its ID
        if (courseId != null) {
          _coursesId.add(courseId);
        }
      }

      // 2. Save Profile details in DB

      await http.post(
        Uri.parse('${dotenv.get('NGROK_URL')}/api/profile/college-pass'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${supabase.auth.currentSession?.accessToken}',
        },
        body: jsonEncode({'collegePass': collegePass,
        'userId':user!.id}),
      );
      await supabase.from('profiles').upsert({
        'id': user.id,
        'display_name': name,
        'college_id': collegeId,
        'semester': _selectedSemester,
        'courses': _selectedCourses,
        'courses_id': _coursesId,
        'updated_at': DateTime.now().toIso8601String(),
        'email': email,
      });
      /*
FeedPage(studentId: collegeId, studentPassword: collegePass,allStudentCourses: _coursesId),
          ) */
      if (mounted) {
        context.showSnackBar('Profile setup completed successfully! 🎉');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FeedPage(
              studentId: collegeId,
              studentPassword: collegePass,
              allStudentCourses: _coursesId,
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) context.showSnackBar(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        context.showSnackBar('Failed to update profile', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _collegeIdController.dispose();
    // _passwordController.dispose();
    _collegePassController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Profile 🎓')),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _collegeIdController,
            decoration: const InputDecoration(
              labelText: 'College ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _collegePassController,
            decoration: const InputDecoration(
              labelText: 'College Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _selectedSemester,
            decoration: const InputDecoration(
              labelText: 'Semester',
              border: OutlineInputBorder(),
            ),
            items: List.generate(8, (i) => i + 1)
                .map(
                  (sem) => DropdownMenuItem(
                    value: sem,
                    child: Text('Semester $sem'),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedSemester = val!),
          ),
          const SizedBox(height: 20),
          const Text(
            'Select Your Semester Courses:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ..._availableCourses.map((course) {
            return CheckboxListTile(
              title: Text(course),
              value: _selectedCourses.contains(course),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedCourses.add(course);
                  } else {
                    _selectedCourses.remove(course);
                  }
                });
              },
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _completeRegistration,
            child: Text(_isLoading ? 'Saving...' : 'Finish Registration 🚀'),
          ),
        ],
      ),
    );
  }
}
