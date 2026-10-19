import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
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

// What happened when the user tapped "Publish"
enum PublishResult { published, missingFields, missingPhoto, noSession, failed }

// What happened when the user tried to take the table photo
enum PhotoResult { taken, cancelled, denied, permanentlyDenied, failed }

// State and logic of the create open table form
class CreateOpenTableViewModel extends ChangeNotifier {
  final ActivityService _activityService;
  final BuildingService _buildingService;
  final OpenTableService _openTableService;
  final OpenTableAbandonmentService _abandonmentService;

  CreateOpenTableViewModel({
    ActivityService? activityService,
    BuildingService? buildingService,
    OpenTableService? openTableService,
    OpenTableAbandonmentService? abandonmentService,
  })  : _activityService = activityService ?? ActivityService(),
        _buildingService = buildingService ?? BuildingService(),
        _openTableService = openTableService ?? OpenTableService(),
        _abandonmentService = abandonmentService ?? OpenTableAbandonmentService();

  List<Activity> _activities = [];
  List<Building> _buildings = [];

  Activity? _selectedActivity;
  Building? _selectedBuilding;
  int _durationMinutes = 0;
  int _maxParticipants = 4;

  // Photo of the table taken with the camera (required to publish)
  File? _photo;
  final ImagePicker _picker = ImagePicker();

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

  // Load the activities and buildings when the screen opens
  Future<void> init() => loadData();

  // Loads the activities and buildings - GET /activities, GET /buildings
  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      // Load both lists at the same time
      final catalogs = await Future.wait([
        _activityService.getActivities(),
        _buildingService.getBuildings(),
      ]);

      _activities = catalogs[0] as List<Activity>;
      _buildings = catalogs[1] as List<Building>;

      if (_activities.isNotEmpty) {
        _selectedActivity = _activities.first;
        _durationMinutes = _selectedActivity!.durationMinutes;
      }

      _isLoading = false;
      _notify();
    } catch (e) {
      debugPrint('CRITICAL ERROR in Create Open Table: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      _notify();
    }
  }

  // Marks the form step the user is on (no rebuild needed)
  void setStep(OpenTableCreationStep step) {
    _currentStep = step;
  }

  // Picks the activity (it also sets the duration)
  void selectActivity(Activity activity) {
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

  // Creates the open table - POST /open-tables
  // The creator is not a participant: the back rejects the creator joining their own table
  Future<PublishResult> publish(String description) async {
    if (_selectedActivity == null || _selectedBuilding == null) {
      return PublishResult.missingFields;
    }

    if (_photo == null) return PublishResult.missingPhoto;

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
      _publishError = 'Error publishing: $e';
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
      _abandonmentService
          .createAbandonment(OpenTableAbandonment(
        userId: userId,
        step: _currentStep,
        activityId: _selectedActivity?.id,
        durationMinutes: _selectedActivity != null && _durationMinutes > 0 ? _durationMinutes : null,
        // The back accepts the max participants from the PARTICIPANTS step onwards
        maxParticipants: _currentStep.index >= OpenTableCreationStep.participants.index ? _maxParticipants : null,
        buildingId: _currentStep == OpenTableCreationStep.location ? _selectedBuilding?.id : null,
      ))
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
