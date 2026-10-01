class InsightModel {
  final String period;
  final String summary;
  final List<String> highlights;
  final List<String> areasToImprove;
  final String coachingNotes;
  final bool cached;
  final String generatedAt;
  final Map<String, dynamic> statsSummary;
  final bool insufficientData;
  final int daysLogged;

  // v3: raw AI object for flexible access
  final Map<String, dynamic>? ai;
  // v3: progress block (includes daily[], alerts, needs, etc.)
  final Map<String, dynamic>? progress;
  // v3: needs list
  final List<dynamic>? needs;

  InsightModel({
    required this.period,
    required this.summary,
    required this.highlights,
    required this.areasToImprove,
    required this.coachingNotes,
    this.cached = false,
    this.generatedAt = '',
    this.statsSummary = const {},
    this.insufficientData = false,
    this.daysLogged = 0,
    this.ai,
    this.progress,
    this.needs,
  });

  factory InsightModel.fromJson(Map<String, dynamic> json) {
    final bool insufficient = json['insufficient_data'] == true;
    final int logged = (json['days_logged'] as num?)?.toInt() ?? 0;

    // Try "insight" nested object first, then top-level
    final insightObj = json['insight'] as Map<String, dynamic>? ?? {};
    final statsObj = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : <String, dynamic>{};

    // Progress block (has daily[], alerts, needs)
    final progressObj = json['progress'] as Map<String, dynamic>?;

    // Needs: could be top-level or inside progress
    final needsRaw = json['needs'] as List?
        ?? (progressObj?['needs'] as List?);

    return InsightModel(
      period: json['period'] ?? 'weekly',
      summary: insightObj['summary'] ?? json['summary_text'] ?? '',
      highlights: (insightObj['highlights'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      areasToImprove: (insightObj['areas_to_improve'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      coachingNotes: insightObj['coaching_notes'] ?? '',
      cached: json['cached'] ?? false,
      generatedAt: json['generated_at'] ?? '',
      statsSummary: statsObj,
      insufficientData: insufficient,
      daysLogged: logged,
      ai: insightObj.isNotEmpty ? insightObj : null,
      progress: progressObj,
      needs: needsRaw,
    );
  }
}
