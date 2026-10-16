import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'package:supabase_quickstart/main.dart';
import '../main.dart';

class NewsItem {
  final String id;
  final String title;
  final String snippet;
  final String url;
  final DateTime publishedAt;

  NewsItem({
    required this.id,
    required this.title,
    required this.snippet,
    required this.url,
    required this.publishedAt,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'No Title',
      snippet: json['snippet'] ?? '',
      url: json['url'] ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] ?? '') ?? DateTime.now(),
    );
  }
}

// Add this model to your feed_service.dart
class CourseActivity {
  final String id;
  final String name;
  final String courseName;
  final String type; // 'assignment', 'lecture', 'forum', 'resource'
  final String? description;
  final String? pdfUrl;
  final String activityUrl;
  final DateTime? dueDate;
  final bool isDeadline;

  CourseActivity({
    required this.id,
    required this.name,
    required this.courseName,
    required this.type,
    this.description,
    this.pdfUrl,
    required this.activityUrl,
    this.dueDate,
    required this.isDeadline,
  });

  factory CourseActivity.fromJson(Map<String, dynamic> json) {
    return CourseActivity(
      id: json['id'],
      name: json['name'],
      courseName: json['course_name'] ?? 'General',
      type: json['type'] ?? 'resource',
      description: json['description'],
      pdfUrl: json['pdf_url'],
      activityUrl: json['activity_url'],
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'])
          : null,
      isDeadline: json['is_deadline'] ?? false,
    );
  }
}

class FeedService {
  // Replace this with your active ngrok HTTPS URL
  static final String baseUrl = dotenv.get('NGROK_URL');

  static Future<List<NewsItem>> fetchGeneralNews() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/feed/general'),
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true', // Bypasses ngrok landing page
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['items'] ?? [];
      return items.map((json) => NewsItem.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load news (Status ${response.statusCode})');
    }
  }

  // 2. Personalized Course Activities Fetcher
  static Future<List<CourseActivity>> fetchPersonalizedFeed(
    String collegeId,
    String password,
    List<dynamic> allStudentCourses,{
    bool refresh = false,
  }) async {

    final user = supabase.auth.currentUser;

    final url = Uri.parse(
      '$baseUrl/api/feed/personalized${refresh ? '?refresh=true' : ''}',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true', // Bypasses ngrok landing page
        'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken}',
      },
      body: json.encode({
        'collegeId': collegeId,
        'password': password, // encrypted blob
        'allStudentCourses': allStudentCourses,
        'uuid':user!.id
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print("backend personalized feed");
      print(data);
      // Matches your backend response structure: { "data": { "all_activities": [...] } }
      final List<dynamic> activities = data['data'] ?? [];
            print("formatted activities");
      print(activities);
      return activities.map((json) => CourseActivity.fromJson(json)).toList();
    } else {
      throw Exception(
        'Failed to load course feed (Status ${response.statusCode})',
      );
    }
  }
}
