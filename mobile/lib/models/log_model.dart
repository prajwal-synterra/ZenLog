class LogEntryModel {
  final String id;
  final String userId;
  final String date;
  final String timestamp;
  final String text;

  LogEntryModel({
    required this.id,
    required this.userId,
    required this.date,
    required this.timestamp,
    required this.text,
  });

  factory LogEntryModel.fromJson(Map<String, dynamic> json) {
    return LogEntryModel(
      id: json['id'] ?? json['_id'] ?? '',
      userId: json['user_id'] ?? '',
      date: json['date'] ?? '',
      timestamp: json['timestamp'] ?? '',
      text: json['text'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': date,
      'timestamp': timestamp,
      'text': text,
    };
  }
}
