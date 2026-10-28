import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';

// How the last Google Calendar import ended
class GoogleImportState {
  final DateTime date;
  final bool success;
  final String message;

  const GoogleImportState({required this.date, required this.success, required this.message});

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'success': success,
        'message': message,
      };

  factory GoogleImportState.fromJson(Map<String, dynamic> json) => GoogleImportState(
        date: DateTime.parse(json['date'] as String),
        success: json['success'] as bool,
        message: json['message'] as String? ?? '',
      );
}

// State of the last import in a file (imports/last_google_import.json)
class GoogleImportStore {
  static const path = 'imports/last_google_import.json';

  Future<void> save(GoogleImportState state) => LocalFileStore.instance.writeJson(path, state.toJson());

  // The state of the last import, or null if there was none
  Future<GoogleImportState?> get() async {
    final json = await LocalFileStore.instance.readJson(path);
    return json == null ? null : GoogleImportState.fromJson(json as Map<String, dynamic>);
  }
}
