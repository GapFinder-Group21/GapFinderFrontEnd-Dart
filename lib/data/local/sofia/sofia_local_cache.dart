import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/catalog_file_store.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/class_block_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/gap_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/last_building_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_detail_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/recommendations_hive_store.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';

// What the ViewModels of Sofia call when the network answers well.
// Saving never blocks or breaks the screen: every method catches its errors and only prints
// them, and the ViewModels do not await them.
class SofiaLocalCache {
  static final SofiaLocalCache instance = SofiaLocalCache._();
  SofiaLocalCache._();

  final classBlocks = ClassBlockDao();
  final gaps = GapDao();
  final openTables = OpenTableCacheDao();
  final openTableDetails = OpenTableDetailDao();
  final recommendations = RecommendationsHiveStore();
  final catalogs = CatalogFileStore();
  final lastBuilding = LastBuildingPrefs();

  // SQLite: class_blocks and gaps
  Future<void> saveSchedule(int userId, List<ClassBlock> blocks, List<Gap> userGaps) {
    return _safe('schedule (SQLite)', () async {
      await classBlocks.replaceAllForUser(userId, blocks);
      await gaps.replaceAllForUser(userId, userGaps);
      await markSaved(scheduleList, userId);
      debugPrint('[Cache] SQLite: saved ${blocks.length} class_blocks and ${userGaps.length} gaps');
    });
  }

  // SQLite: open_tables_cache ('ALL' or 'MINE', see OpenTableListType)
  Future<void> saveOpenTables(String listType, List<OpenTable> tables, {int? userId}) {
    return _safe('open tables $listType (SQLite)', () async {
      await openTables.replaceAll(listType, tables);
      if (userId != null) await markSaved(listType, userId);
      debugPrint('[Cache] SQLite: saved ${tables.length} open_tables_cache rows ($listType)');
    });
  }

  // A list that is saved empty has no rows, so the rows cannot tell "saved with nothing" from "never saved".
  // This marker (a time per list and user in SharedPreferences) can.
  static const scheduleList = 'SCHEDULE';
  static const _savedAtPrefix = 'list_saved_at:';

  Future<void> markSaved(String list, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_savedAtPrefix$list:$userId', DateTime.now().toIso8601String());
  }

  // When this list was last saved for the user, or null if it never was
  Future<DateTime?> savedAt(String list, int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('$_savedAtPrefix$list:$userId');
      return value == null ? null : DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  // The user left this table: it goes out of the saved 'MINE' list too
  Future<void> removeFromMyTables(int tableId) {
    return _safe('remove from my open tables (SQLite)', () => openTables.deleteById(OpenTableListType.mine, tableId));
  }

  // SQLite: open_table_details
  Future<void> saveOpenTableDetail(OpenTable table, List<OpenTableParticipant> participants) {
    return _safe('open table detail (SQLite)', () async {
      await openTableDetails.save(table, participants);
      debugPrint('[Cache] SQLite: saved open_table_details ${table.id} with ${participants.length} participants');
    });
  }

  // Files: catalogs/activities.json and catalogs/buildings.json
  Future<void> saveCatalogs(List<Activity> activities, List<Building> buildings) {
    return _safe('catalogs (file)', () async {
      await catalogs.saveActivities(activities);
      await catalogs.saveBuildings(buildings);
      debugPrint('[Cache] File: saved ${activities.length} activities and ${buildings.length} buildings');
    });
  }

  // Hive: sofia_recommendations
  Future<void> saveRecommendation(int userId, RecommendationResponse response) {
    return _safe('recommendation (Hive)', () async {
      await recommendations.save(userId, response);
      debugPrint('[Cache] Hive: saved ${RecommendationsHiveStore.keyFor(userId)} with ${response.tables.length} tables');
    });
  }

  // SharedPreferences: last_building_name and last_building_at
  Future<void> saveLastBuilding(String buildingName) {
    return _safe('last building (SharedPreferences)', () async {
      await lastBuilding.save(buildingName);
      debugPrint('[Cache] SharedPreferences: saved last_building_name=$buildingName');
    });
  }

  // The list 'MINE' belongs to the user who saved it: the open_tables_cache rows have no user, so the owner is
  // saved apart. Offline, another user never sees the tables of the previous one.
  static const _myTablesOwnerKey = 'my_open_tables_owner';

  Future<void> saveMyTablesOwner(int userId) {
    return _safe('owner of my open tables', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_myTablesOwnerKey, userId);
    });
  }

  // The user the saved 'MINE' list belongs to (null if none)
  Future<int?> myTablesOwner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_myTablesOwnerKey);
    } catch (_) {
      return null;
    }
  }

  // Logout or expired session: removes what was saved for this user so the next person on the phone does not
  // see it. The catalogs stay because they are the same for everyone. If the user is not known, only what does
  // not need it is removed. Each step has its own try, so one failure does not skip the rest.
  Future<void> clearUserData(int? userId) async {
    await _safe('class blocks on logout', () async {
      if (userId != null) await classBlocks.deleteForUser(userId);
    });
    await _safe('gaps on logout', () async {
      if (userId != null) await gaps.deleteForUser(userId);
    });
    await _safe('open tables on logout', () => openTables.clear());
    await _safe('open table details on logout', () => openTableDetails.clear());
    await _safe('recommendation on logout', () async {
      if (userId != null) await recommendations.delete(userId);
    });
    await _safe('last building on logout', () => lastBuilding.clear());
    await _safe('owner of my open tables on logout', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_myTablesOwnerKey);
    });
    await _safe('saved markers on logout', () async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_savedAtPrefix)).toList()) {
        await prefs.remove(key);
      }
    });
    debugPrint('[Cache] Removed the saved data of user $userId');
  }

  Future<void> _safe(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Cache] Could not save $what: $e');
    }
  }
}
