import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/core/utils/photo_compression.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_abandonment.dart';
import 'package:gapfinderfrontend_dart/services/activity_service.dart';
import 'package:gapfinderfrontend_dart/services/building_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_abandonment_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/services/preferred_activity_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// What happened when the user tapped "Publish"
enum PublishResult { published, missingFields, missingPhoto, noSession, offline, failed }

// What happened when the user tried to take the table photo
enum PhotoResult { taken, cancelled, denied, permanentlyDenied, failed }

// State and logic of the create open table form
class CreateOpenTableViewModel extends ChangeNotifier with OfflineAwareMixin {
  final ActivityService _activityService;
  final BuildingService _buildingService;
  final OpenTableService _openTableService;
  final OpenTableAbandonmentService _abandonmentService;
  final PreferredActivityService _preferredActivityService;

  // The favorite activity must never hold the wizard: it is asked for this long at most
  static const preferredTimeout = Duration(seconds: 4);

  CreateOpenTableViewModel({
    ActivityService? activityService,
    BuildingService? buildingService,
    OpenTableService? openTableService,
    OpenTableAbandonmentService? abandonmentService,
    PreferredActivityService? preferredActivityService,
  })  : _activityService = activityService ?? ActivityService(),
        _buildingService = buildingService ?? BuildingService(),
        _openTableService = openTableService ?? OpenTableService(),
        _abandonmentService = abandonmentService ?? OpenTableAbandonmentService(),
        _preferredActivityService = preferredActivityService ?? PreferredActivityService();

  List<Activity> _activities = [];
  List<Building> _buildings = [];

  Activity? _selectedActivity;

  // BQ 6 (type 2): the activity this user creates most often, used to preselect it
  int? _preferredActivityId;
  bool _preferredFromNetwork = false;
  bool _preferredInFlight = false;
  // Once the user picks an activity themselves, the favorite never replaces it
  bool _activityPickedByUser = false;
  Building? _selectedBuilding;
  int _durationMinutes = 0;
  int _maxParticipants = 4;

  // Photo of the table taken with the camera (required to publish)
  File? _photo;
  final ImagePicker _picker = ImagePicker();

  // The catalogs saved in a file are used without asking the network while they are younger than this
  static const catalogMaxAge = Duration(hours: 24);

  // When the wizard was opened; with the user id it makes the abandonment report unique
  final DateTime _openedAt = DateTime.now();
  // True while the catalogs on screen are an old file (they are refreshed when the network is back)
  bool _catalogsStale = false;

  // Last form step the user touched (sent when they quit without publishing)
  OpenTableCreationStep _currentStep = OpenTableCreationStep.activity;
  bool _abandonmentSent = false;

  bool _isLoading = true;
  bool _isPublishing = false;
  String? _errorMessage;
  String? _publishError;
  bool _disposed = false;

  List<Activity> get activities => _activities;
  List<Building> get buildings => _buildings;
  Activity? get selectedActivity => _selectedActivity;

  // True when the selected activity is the favorite one (the View shows a small "Tu favorita" label)
  bool get isPreferredActivitySelected =>
      _preferredActivityId != null && _selectedActivity?.id == _preferredActivityId;
  Building? get selectedBuilding => _selectedBuilding;
  int get maxParticipants => _maxParticipants;
  File? get photo => _photo;
  bool get isLoading => _isLoading;
  bool get isPublishing => _isPublishing;
  // Error while loading the catalogs
  String? get errorMessage => _errorMessage;
  // Error while publishing
  String? get publishError => _publishError;

  bool get canDecrementParticipants => _maxParticipants > 2;
  bool get canIncrementParticipants => _maxParticipants < 20;

  // Publishing sends the table and the photo, so it needs the network; the form can still be filled
  bool get canPublish => !isOffline;

  // Load the activities and buildings when the screen opens; if the catalogs are missing or old,
  // they are asked again by themselves when the connection comes back.
  // It also brings back the photo taken before, if the app was closed or there was no connection.
  Future<void> init() {
    listenToConnectivity(onRestored: _refreshCatalogsIfNeeded);
    _restorePendingPhoto();
    return loadData();
  }

  Future<void> _refreshCatalogsIfNeeded() async {
    if (_activities.isEmpty || _buildings.isEmpty || _catalogsStale) {
      await loadData(forceNetwork: true);
    }
  }

  // Takes the photo saved in pending_photos/ (not awaited: it must not delay the form)
  Future<void> _restorePendingPhoto() async {
    try {
      final saved = await JoelLocalCache.instance.pendingPhoto.currentFile();
      if (saved == null || _photo != null || _disposed) return;
      _photo = saved;
      _notify();
    } catch (e) {
      debugPrint('Could not restore the pending photo: $e');
    }
  }

  // Cache falling back to network: the catalogs come from the saved files (catalogs/*.json) and the
  // network is only asked when there is no file or it is older than 24 hours and there is connection.
  // GET /activities, GET /buildings
  Future<void> loadData({bool forceNetwork = false}) async {
    _isLoading = _activities.isEmpty || _buildings.isEmpty;
    _errorMessage = null;
    _notify();

    // Asked at the same time as the catalogs and never awaited: it cannot delay the wizard
    _requestPreferredActivity();

    final saved = await _readSavedCatalogs();
    final savedAt = saved?.savedAt;
    final isFresh = savedAt != null && DateTime.now().difference(savedAt) < catalogMaxAge;

    if (saved != null && isFresh && !forceNetwork) {
      _applyCatalogs(saved.activities, saved.buildings);
      _catalogsStale = false;
      markUpdatedAt(savedAt);
      _finishLoading();
      return;
    }

    if (hasConnection) {
      try {
        // Load both lists at the same time
        final catalogs = await Future.wait([
          _activityService.getActivities(),
          _buildingService.getBuildings(),
        ]).timeout(OfflineAwareMixin.loadTimeout);

        final activities = catalogs[0] as List<Activity>;
        final buildings = catalogs[1] as List<Building>;
        _applyCatalogs(activities, buildings);
        _catalogsStale = false;
        markFresh();

        // Save the catalogs the network answered; it is not awaited and never breaks the screen
        SofiaLocalCache.instance.saveCatalogs(activities, buildings);
        _finishLoading();
        return;
      } catch (e) {
        debugPrint('Sin red para los catálogos: $e');
        if (saved == null) {
          _errorMessage = userMessage(e, network: 'No pudimos traer las actividades y edificios, intenta de nuevo');
          _finishLoading();
          return;
        }
      }
    }

    // No connection (or the network failed): an old file is better than nothing
    if (saved != null) {
      _applyCatalogs(saved.activities, saved.buildings);
      _catalogsStale = true;
      markFromCache(savedAt);
    } else {
      _errorMessage = 'Sin conexión y aún no hay actividades ni edificios guardados';
    }
    _finishLoading();
  }

  void _finishLoading() {
    _isLoading = false;
    _notify();
  }

  // Keeps what the user already picked if it is still in the new lists
  void _applyCatalogs(List<Activity> activities, List<Building> buildings) {
    _activities = activities;
    _buildings = buildings;

    final pickedActivity = _selectedActivity == null
        ? null
        : activities.where((a) => a.id == _selectedActivity!.id).firstOrNull;
    _selectedActivity = pickedActivity ?? (activities.isNotEmpty ? activities.first : null);
    if (_selectedActivity != null) _durationMinutes = _selectedActivity!.durationMinutes;
    _selectPreferredActivity(); // the favorite replaces the first one, if it is already known

    _selectedBuilding = _selectedBuilding == null
        ? null
        : buildings.where((b) => b.id == _selectedBuilding!.id).firstOrNull;
  }

  // The catalogs saved as files, or null if one of them is missing
  Future<({List<Activity> activities, List<Building> buildings, DateTime? savedAt})?> _readSavedCatalogs() async {
    try {
      final files = SofiaLocalCache.instance.catalogs;
      final activities = await files.loadActivities();
      final buildings = await files.loadBuildings();
      if (activities == null || buildings == null || activities.items.isEmpty || buildings.items.isEmpty) {
        return null;
      }

      // The oldest of the two files decides how old the catalogs are
      final dates = [activities.savedAt, buildings.savedAt];
      final savedAt = dates.contains(null) ? null : (dates[0]!.isBefore(dates[1]!) ? dates[0] : dates[1]);
      return (activities: activities.items, buildings: buildings.items, savedAt: savedAt);
    } catch (e) {
      debugPrint('No se pudieron leer los catálogos guardados: $e');
      return null;
    }
  }

  // Marks the form step the user is on (no rebuild needed)
  void setStep(OpenTableCreationStep step) {
    _currentStep = step;
  }

  // BQ 6 (type 2): asks for the activity the user creates most often. Network falling back to cache:
  // without connection (or if the back fails) the last one saved in SharedPreferences is used.
  // When the answer arrives it is applied only if the catalogs are loaded and the user has not picked
  // an activity. It does not touch the form step.
  void _requestPreferredActivity() {
    if (_preferredInFlight || _preferredFromNetwork) return;
    _preferredInFlight = true;

    _loadPreferredActivityId().then((id) {
      if (_disposed || id == null) return;
      _preferredActivityId = id;
      if (_selectPreferredActivity()) _notify();
    }).catchError((Object e) {
      debugPrint('Could not apply the preferred activity: $e');
    }).whenComplete(() => _preferredInFlight = false);
  }

  Future<int?> _loadPreferredActivityId() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;

    if (hasConnection) {
      try {
        final response = await _preferredActivityService.getPreferredActivity(userId).timeout(preferredTimeout);
        _preferredFromNetwork = true;
        // Saved for the next time (or forgotten if the back says the user has none); never breaks the screen
        JoelLocalCache.instance.savePreferredActivity(userId, response.activityId);
        return response.activityId;
      } catch (e) {
        debugPrint('Preferred activity not loaded, using the saved one: $e');
      }
    }

    final cache = JoelLocalCache.instance;
    return cache.safeRead('preferred activity', () => cache.preferredActivity.get(userId));
  }

  // Selects the favorite activity (and its duration) if it is in the catalog and the user has not picked one.
  // Returns true if the selection changed.
  bool _selectPreferredActivity() {
    final id = _preferredActivityId;
    if (id == null || _activityPickedByUser) return false;

    final preferred = _activities.where((a) => a.id == id).firstOrNull;
    if (preferred == null || _selectedActivity?.id == preferred.id) return false;

    _selectedActivity = preferred;
    _durationMinutes = preferred.durationMinutes;
    return true;
  }

  // Picks the activity (it also sets the duration)
  void selectActivity(Activity activity) {
    _activityPickedByUser = true;
    _selectedActivity = activity;
    _durationMinutes = activity.durationMinutes;
    _notify();
  }

  // Picks the building where the table will be
  void selectBuilding(Building building) {
    _selectedBuilding = building;
    _notify();
  }

  void decrementParticipants() {
    _currentStep = OpenTableCreationStep.participants;
    _maxParticipants--;
    _notify();
  }

  void incrementParticipants() {
    _currentStep = OpenTableCreationStep.participants;
    _maxParticipants++;
    _notify();
  }

  // Asks for the camera permission and takes the photo (camera only, never the gallery)
  // Taking it again replaces the previous one
  Future<PhotoResult> takePhoto() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isRestricted) return PhotoResult.permanentlyDenied;
    if (!status.isGranted) return PhotoResult.denied;

    try {
      // Smaller size and quality keep the upload light
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (image == null) return PhotoResult.cancelled;

      _photo = File(image.path);
      await _compressPhoto(_photo!);
      // Keep a copy in pending_photos/ so it is not lost if the app closes before publishing
      JoelLocalCache.instance.savePendingPhoto(_photo!);
      _notify();
      return PhotoResult.taken;
    } catch (e) {
      // Camera not available or closed with an error
      debugPrint('Camera error: $e');
      return PhotoResult.failed;
    }
  }

  // Makes the photo lighter before it is saved in pending_photos/ and uploaded.
  // Estrategia: Isolate. Compressing decodes and encodes the whole image, which is heavy,
  // so it runs in another isolate (its own thread and memory) and the screen does not freeze.
  // If it fails the original photo is kept.
  Future<void> _compressPhoto(File photo) async {
    try {
      final original = await photo.readAsBytes();
      debugPrint('Photo before compressing: ${(original.length / 1024).toStringAsFixed(1)} KB '
          '(takePhoto runs in isolate: ${Isolate.current.debugName})');

      final compressed = await Isolate.run(() => compressPhoto(original));
      debugPrint('Photo after compressing: ${(compressed.length / 1024).toStringAsFixed(1)} KB');

      // Only replace the file if it really got lighter
      if (compressed.length < original.length) await photo.writeAsBytes(compressed);
    } catch (e) {
      debugPrint('Could not compress the photo, using the original: $e');
    }
  }

  // Creates the open table - POST /open-tables
  // The creator is not a participant: the back rejects the creator joining their own table
  Future<PublishResult> publish(String description) async {
    if (_selectedActivity == null || _selectedBuilding == null) {
      return PublishResult.missingFields;
    }

    if (_photo == null) return PublishResult.missingPhoto;

    // The table and the photo need the network; what the user filled stays in the form
    if (!canPublish) return PublishResult.offline;

    final userId = await TokenStorage.getUserId();
    if (userId == null) return PublishResult.noSession;

    _isPublishing = true;
    _notify();

    try {
      final now = DateTime.now();
      final newTable = OpenTable(
        id: 0,
        title: _selectedActivity!.name,
        description: description,
        startTime: now,
        endTime: now.add(Duration(minutes: _durationMinutes)),
        maxParticipants: _maxParticipants,
        status: OpenTableStatusEnum.OPEN,
        activity: _selectedActivity,
      );

      await _openTableService.createOpenTable(userId, _selectedBuilding!.id, newTable, _photo!);
      JoelLocalCache.instance.clearPendingPhoto();
      return PublishResult.published;
    } catch (e) {
      _publishError = userMessage(e, network: 'No se pudo publicar por falta de conexión; lo que llenaste sigue aquí');
      return PublishResult.failed;
    } finally {
      _isPublishing = false;
      _notify();
    }
  }

  // Reports the step where the user quit - POST /open-table-abandonments/user/{userId}.
  // If it fails, the user can still leave. Returns false on a repeated tap (do not close twice).
  Future<bool> reportAbandonment() async {
    // Avoid reporting twice (and closing two screens) on quick double taps
    if (_abandonmentSent) return false;
    _abandonmentSent = true;

    final userId = await TokenStorage.getUserId();
    if (userId != null) {
      // Estrategia: Future con handler. There is no await: .catchError handles the failure and the
      // user leaves the wizard without waiting for the report.
      // Without connection the report goes to the outbox; the dedupeKey (user + time the wizard
      // was opened) makes sure it is sent only once
      _abandonmentService
          .createAbandonment(OpenTableAbandonment(
        userId: userId,
        step: _currentStep,
        activityId: _selectedActivity?.id,
        durationMinutes: _selectedActivity != null && _durationMinutes > 0 ? _durationMinutes : null,
        // The back accepts the max participants from the PARTICIPANTS step onwards
        maxParticipants: _currentStep.index >= OpenTableCreationStep.participants.index ? _maxParticipants : null,
        buildingId: _currentStep == OpenTableCreationStep.location ? _selectedBuilding?.id : null,
      ), dedupeKey: 'open_table_abandonment:$userId:${_openedAt.millisecondsSinceEpoch}')
          .catchError((e) => debugPrint('Abandonment not registered: $e'));
    }
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
