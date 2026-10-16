class CourseActivity {
  final String id;
  final String name;
  final String courseName;
  final String type;
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
