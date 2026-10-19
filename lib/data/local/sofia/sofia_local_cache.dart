import 'package:flutter/foundation.dart';
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
      debugPrint('[Cache] SQLite: saved ${blocks.length} class_blocks and ${userGaps.length} gaps');
    });
  }

  // SQLite: open_tables_cache ('ALL' or 'MINE', see OpenTableListType)
  Future<void> saveOpenTables(String listType, List<OpenTable> tables) {
    return _safe('open tables $listType (SQLite)', () async {
      await openTables.replaceAll(listType, tables);
      debugPrint('[Cache] SQLite: saved ${tables.length} open_tables_cache rows ($listType)');
    });
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

  Future<void> _safe(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Cache] Could not save $what: $e');
    }
  }
}
