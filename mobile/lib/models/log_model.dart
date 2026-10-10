class LogEntryModel {
  final String id;
  final String userId;
  final String date;
  final String timestamp;
  final String text;
  final String? loggedAt;
  final String? source;
  final String? clientId;

  LogEntryModel({
    required this.id,
    required this.userId,
    required this.date,
    required this.timestamp,
    required this.text,
    this.loggedAt,
    this.source,
    this.clientId,
  });

  factory LogEntryModel.fromJson(Map<String, dynamic> json) {
    return LogEntryModel(
      id: json['id'] ?? json['_id'] ?? '',
      userId: json['user_id'] ?? '',
      date: json['date'] ?? json['logical_date'] ?? '',
      timestamp: json['timestamp'] ?? '',
      text: json['text'] ?? '',
      loggedAt: json['logged_at'],
      source: json['source'],
      clientId: json['client_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': date,
      'timestamp': timestamp,
      'text': text,
      'logged_at': loggedAt,
      'source': source,
      'client_id': clientId,
    };
  }
}
