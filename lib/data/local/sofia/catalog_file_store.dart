import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';

// A saved catalog and the time it was saved
class SavedCatalog<T> {
  final List<T> items;
  final DateTime? savedAt;
  SavedCatalog(this.items, this.savedAt);
}

// The catalogs of the create open table form, saved as files with LocalFileStore.
// Each file looks like {"savedAt": "...", "items": [...]}
class CatalogFileStore {
  static const activitiesPath = 'catalogs/activities.json';
  static const buildingsPath = 'catalogs/buildings.json';

  final LocalFileStore _files;

  CatalogFileStore({LocalFileStore? files}) : _files = files ?? LocalFileStore.instance;

  Future<void> saveActivities(List<Activity> activities) {
    return _write(activitiesPath, activities.map((a) => a.toJson()).toList());
  }

  Future<void> saveBuildings(List<Building> buildings) {
    return _write(buildingsPath, buildings.map((b) => b.toJson()).toList());
  }

  Future<SavedCatalog<Activity>?> loadActivities() {
    return _read(activitiesPath, Activity.fromJson);
  }

  Future<SavedCatalog<Building>?> loadBuildings() {
    return _read(buildingsPath, Building.fromJson);
  }

  Future<void> _write(String path, List<Map<String, dynamic>> items) {
    return _files.writeJson(path, {
      'savedAt': DateTime.now().toIso8601String(),
      'items': items,
    });
  }

  Future<SavedCatalog<T>?> _read<T>(String path, T Function(Map<String, dynamic>) fromJson) async {
    final data = await _files.readJson(path);
    if (data is! Map) return null;

    final items = (data['items'] as List).map((i) => fromJson(Map<String, dynamic>.from(i as Map))).toList();
    return SavedCatalog(items, DateTime.tryParse(data['savedAt'] as String? ?? ''));
  }
}
