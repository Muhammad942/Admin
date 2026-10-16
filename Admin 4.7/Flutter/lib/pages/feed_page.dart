import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/feed_service.dart';
//import 'package:flutter_dotenv/flutter_dotenv.dart';

class FeedPage extends StatefulWidget {
  // Pass student credentials (or pull from SecureStorage / UserProvider)
  final String studentId;
  final String studentPassword; // encrypted blob
  final List<dynamic> allStudentCourses;
  

  // ignore: prefer_const_constructors_in_immutables
  FeedPage({super.key, required this.studentId, 
  required this.studentPassword , required this.allStudentCourses});

  @override
  State<FeedPage> createState() => _FeedPageState();
} 

class _FeedPageState extends State<FeedPage> {
  late Future<List<NewsItem>> _generalNewsFuture;
  late Future<List<CourseActivity>> _courseActivitiesFuture;

  @override
  void initState() {
    super.initState();
    _refreshFeed();
  }

  void _refreshFeed({bool forceRefreshBackend = true}) {
    setState(() {
      _generalNewsFuture = FeedService.fetchGeneralNews();
      _courseActivitiesFuture = FeedService.fetchPersonalizedFeed(
        widget.studentId,
        widget.studentPassword, // encrypted blob
        widget.allStudentCourses,
        refresh: forceRefreshBackend,
      );
    });
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'assignment':
        return Icons.assignment_outlined;
      case 'forum':
        return Icons.forum_outlined;
      case 'lecture':
        return Icons.menu_book_rounded;
      default:
        return Icons.picture_as_pdf_rounded;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'assignment':
        return Colors.orangeAccent;
      case 'forum':
        return Colors.purpleAccent;
      case 'lecture':
        return Colors.blueAccent;
      default:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshFeed(forceRefreshBackend: true),
            tooltip: 'Refresh Feed',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshFeed(forceRefreshBackend: true),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // ================= SECTION 1: COURSE ACTIVITIES =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📚 Course Updates',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Personalized',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CourseActivity>>(
              future: _courseActivitiesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Card(
                    color: Colors.orange.shade900.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Could not sync course activities',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${snapshot.error}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final activities = snapshot.data ?? [];
                if (activities.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No recent course activities found.'),
                    ),
                  );
                }

                return Column(
                  children: activities
                      .map((activity) => _buildCourseActivityCard(activity))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // ================= SECTION 2: GENERAL NEWS =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📢 General News',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Top 5 Updates',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<NewsItem>>(
              future: _generalNewsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Card(
                    color: Colors.red.shade900.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Error loading news',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${snapshot.error}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final newsList = snapshot.data ?? [];
                if (newsList.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No announcements found.'),
                    ),
                  );
                }

                return Column(
                  children: newsList
                      .map((news) => _buildNewsCard(news))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Card for Course Activities (Assignments, Lectures, PDFs)
  Widget _buildCourseActivityCard(CourseActivity activity) {
    final color = _getColorForType(activity.type);
    final icon = _getIconForType(activity.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          activity.name,
          textDirection: TextDirection.rtl, // Supports Arabic Titles
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              activity.courseName,
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            if (activity.dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Due: ${activity.dueDate!.toLocal().toString().split('.')[0]}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => _launchURL(activity.activityUrl),
      ),
    );
  }

  // Card for General Campus News (Your Original Code)
  Widget _buildNewsCard(NewsItem news) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _launchURL(news.url),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                news.title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (news.snippet.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  news.snippet,
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${news.publishedAt.day}/${news.publishedAt.month}/${news.publishedAt.year}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                  const Row(
                    children: [
                      Text(
                        'Read More',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
