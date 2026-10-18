// Where the app open delay comes from: the user's own history, all users, or a fixed default
enum AppOpenDelaySource {
  user,
  global,
  defaultValue;

  static AppOpenDelaySource fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'USER':
        return AppOpenDelaySource.user;
      case 'GLOBAL':
        return AppOpenDelaySource.global;
      default:
        return AppOpenDelaySource.defaultValue;
    }
  }
}

// Answer of the BQ "How long after a gap starts do students open the app?"
class AppOpenDelayResponse {
  // Minutes after the start of a gap when the reminder should arrive (2 to 30)
  final int offsetMinutes;
  final AppOpenDelaySource source;
  final double? userAverageMinutes;
  final int userGapsCounted;
  final double? globalAverageMinutes;
  final int globalGapsCounted;

  AppOpenDelayResponse({
    required this.offsetMinutes,
    required this.source,
    this.userAverageMinutes,
    this.userGapsCounted = 0,
    this.globalAverageMinutes,
    this.globalGapsCounted = 0,
  });

  factory AppOpenDelayResponse.fromJson(Map<String, dynamic> json) {
    return AppOpenDelayResponse(
      offsetMinutes: (json['offsetMinutes'] as num).toInt(),
      source: AppOpenDelaySource.fromString(json['source']),
      userAverageMinutes: (json['userAverageMinutes'] as num?)?.toDouble(),
      userGapsCounted: (json['userGapsCounted'] as num?)?.toInt() ?? 0,
      globalAverageMinutes: (json['globalAverageMinutes'] as num?)?.toDouble(),
      globalGapsCounted: (json['globalGapsCounted'] as num?)?.toInt() ?? 0,
    );
  }
}
