// Answer of GET /analytics/preferred-activity/user/{userId} (BQ 6, type 2).
// The back also sends the ranking of all the students; the app only needs the activity of the user.
class PreferredActivityResponse {
  // Activity the user chooses most often when creating open tables (null if they have not created any)
  final int? activityId;
  final String? activityName;

  // Open tables the user created with that activity
  final int timesChosen;

  const PreferredActivityResponse({this.activityId, this.activityName, this.timesChosen = 0});

  // The user has no open tables yet, so there is nothing to preselect
  const PreferredActivityResponse.none() : this();

  bool get hasPreferred => activityId != null;

  factory PreferredActivityResponse.fromJson(Map<String, dynamic> json) {
    final preferred = json['userPreferredActivity'];
    if (preferred is! Map<String, dynamic>) return const PreferredActivityResponse.none();

    return PreferredActivityResponse(
      activityId: preferred['activityId'] as int?,
      activityName: preferred['activityName'] as String?,
      timesChosen: (preferred['timesChosen'] as num?)?.toInt() ?? 0,
    );
  }
}
