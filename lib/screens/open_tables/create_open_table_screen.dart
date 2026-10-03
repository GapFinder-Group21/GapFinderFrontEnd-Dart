import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/activity.dart';
import '../../models/building.dart';
import '../../models/open_table.dart';
import '../../models/open_table_abandonment.dart';
import '../../models/open_table_status_enum.dart';
import '../../services/activity_service.dart';
import '../../services/building_service.dart';
import '../../services/open_table_abandonment_service.dart';
import '../../services/open_table_participant_service.dart';
import '../../services/open_table_service.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';

/// Form to create an open table: activity, description, max participants and building.
/// If the user leaves without publishing, it reports in which step they quit (abandonment).
class CreateOpenTableScreen extends StatefulWidget {
  const CreateOpenTableScreen({super.key});

  @override
  State<CreateOpenTableScreen> createState() => _CreateOpenTableScreenState();
}

class _CreateOpenTableScreenState extends State<CreateOpenTableScreen> {
  final _activityService = ActivityService();
  final _buildingService = BuildingService();
  final _openTableService = OpenTableService();
  final _participantService = OpenTableParticipantService();
  final _abandonmentService = OpenTableAbandonmentService();

  final _descController = TextEditingController();

  List<Activity> _activities = [];
  List<Building> _buildings = [];

  Activity? _selectedActivity;
  Building? _selectedBuilding;
  int _durationMinutes = 0;
  int _maxParticipants = 4;

  // Last form step the user touched (sent when they quit without publishing)
  OpenTableCreationStep _currentStep = OpenTableCreationStep.activity;
  bool _abandonmentSent = false;

  bool _isLoading = true;
  bool _isPublishing = false;
  String? _errorMessage;

  @override
  // Load the activities and buildings when the screen opens
  void initState() {
    super.initState();
    _loadData();
  }

  // Loads the activities and buildings - GET /activities, GET /buildings
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('CRITICAL ERROR in Create Open Table: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // Bottom sheet to pick the activity (it also sets the duration)
  void _showActivityPicker() {
    _currentStep = OpenTableCreationStep.activity;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SELECT ACTIVITY',
                style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                  fontSize: 14,
                  letterSpacing: 1.2,
                  color: AppColors.contrast.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              if (_activities.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No activities found in catalog',
                    style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _activities.length,
                    itemBuilder: (context, index) {
                      final a = _activities[index];
                      final bool isSelected = a.id == _selectedActivity?.id;

                      return ListTile(
                        onTap: () {
                          setState(() {
                            _selectedActivity = a;
                            _durationMinutes = a.durationMinutes;
                          });
                          Navigator.pop(context);
                        },
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? AppColors.accent3 : AppColors.contrast.withValues(alpha: 0.2),
                        ),
                        title: Text(
                          a.name,
                          style: AppFonts.body(
                            weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ).copyWith(
                            color: isSelected ? AppColors.accent3 : AppColors.contrast,
                          ),
                        ),
                        subtitle: Text(
                          '${a.durationMinutes} minutes · ${a.effortType.name.toLowerCase()}',
                          style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.contrast.withValues(alpha: 0.45)),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Bottom sheet to pick the building where the table will be
  void _showBuildingPicker() {
    _currentStep = OpenTableCreationStep.location;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SELECT LOCATION',
                style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                  fontSize: 14,
                  letterSpacing: 1.2,
                  color: AppColors.contrast.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              if (_buildings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No buildings found in system',
                    style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _buildings.length,
                    itemBuilder: (context, index) {
                      final b = _buildings[index];
                      final bool isSelected = b.id == _selectedBuilding?.id;

                      return ListTile(
                        onTap: () {
                          setState(() => _selectedBuilding = b);
                          Navigator.pop(context);
                        },
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? AppColors.accent2 : AppColors.contrast.withValues(alpha: 0.2),
                        ),
                        title: Text(
                          b.name,
                          style: AppFonts.body(
                            weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ).copyWith(
                            color: isSelected ? AppColors.accent2 : AppColors.contrast,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Creates the open table and joins the creator to it - POST /open-tables
  Future<void> _publish() async {
    if (_selectedActivity == null || _selectedBuilding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an activity and location')),
      );
      return;
    }

    final userId = await TokenStorage.getUserId();
    if (userId == null) return;

    setState(() => _isPublishing = true);

    try {
      final now = DateTime.now();
      final newTable = OpenTable(
        id: 0,
        title: _selectedActivity!.name,
        description: _descController.text.trim(),
        startTime: now,
        endTime: now.add(Duration(minutes: _durationMinutes)),
        maxParticipants: _maxParticipants,
        status: OpenTableStatusEnum.OPEN,
        activity: _selectedActivity,
      );

      final created = await _openTableService.createOpenTable(userId, _selectedBuilding!.id, newTable);

      // Register the creator as a participant - POST /open-table-participants/table/{id}/join
      await _participantService.join(created.id, userId);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error publishing: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  // Reports the step where the user quit and closes the screen
  // POST /open-table-abandonments/user/{userId}. If it fails, the user can still leave.
  Future<void> _onCancel() async {
    // Avoid reporting twice (and closing two screens) on quick double taps
    if (_abandonmentSent) return;
    _abandonmentSent = true;

    final userId = await TokenStorage.getUserId();
    if (userId != null) {
      _abandonmentService
          .createAbandonment(OpenTableAbandonment(
        userId: userId,
        step: _currentStep,
        activityId: _selectedActivity?.id,
        durationMinutes: _selectedActivity != null && _durationMinutes > 0 ? _durationMinutes : null,
        maxParticipants: _currentStep == OpenTableCreationStep.participants ? _maxParticipants : null,
        buildingId: _currentStep == OpenTableCreationStep.location ? _selectedBuilding?.id : null,
      ))
          .catchError((e) => debugPrint('Abandonment not registered: $e'));
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: const CustomTopBar(title: 'Create Open Table', showBack: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.accent1, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 24),
                CustomButton(label: 'Retry', onClick: _loadData),
              ],
            ),
          ),
        ),
      );
    }

    // The back arrow and the back gesture also count as quitting
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onCancel();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomTopBar(
        title: 'Create Open Table',
        showBack: true,
        onBack: _onCancel,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Activity selector
            _buildSelectableField(
              title: 'Activity',
              value: _selectedActivity?.name ?? 'Select an activity',
              subtitle: _selectedActivity != null ? '${_selectedActivity!.durationMinutes} min' : null,
              onTap: _showActivityPicker,
            ),

            const SizedBox(height: 12),

            // Description
            _buildSection(
              title: 'What do you propose?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _descController,
                    maxLength: 160,
                    maxLines: 4,
                    onTap: () => _currentStep = OpenTableCreationStep.description,
                    onChanged: (_) => setState(() {}),
                    style: AppFonts.body().copyWith(fontSize: 13, color: AppColors.contrast),
                    decoration: InputDecoration(
                      hintText: "Describe what you want to do, where exactly you'll be...",
                      hintStyle: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: AppColors.background,
                      counterText: '',
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_descController.text.length}/160',
                    style: AppFonts.body().copyWith(fontSize: 11, color: AppColors.contrast.withValues(alpha: 0.3)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Max participants (+ / - buttons)
            _buildSection(
              title: 'Max participants',
              child: Row(
                children: [
                  IconButton(
                    onPressed: _maxParticipants > 2 ? () => setState(() {
                      _currentStep = OpenTableCreationStep.participants;
                      _maxParticipants--;
                    }) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$_maxParticipants',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 16, color: AppColors.contrast),
                  ),
                  IconButton(
                    onPressed: _maxParticipants < 20 ? () => setState(() {
                      _currentStep = OpenTableCreationStep.participants;
                      _maxParticipants++;
                    }) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Building selector
            _buildSelectableField(
              title: 'Location',
              value: _selectedBuilding?.name ?? 'Select a building',
              onTap: _showBuildingPicker,
            ),

            const SizedBox(height: 32),

            _isPublishing
                ? const Center(child: CircularProgressIndicator())
                : Column(
              children: [
                CustomButton(
                  label: 'Publish Open Table',
                  color: AppColors.accent3,
                  onClick: _publish,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _onCancel,
                    child: Text(
                      'Cancel',
                      style: AppFonts.body(weight: FontWeight.w700).copyWith(
                        fontSize: 14,
                        color: AppColors.contrast.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  // Tappable field that shows the current value and opens a picker
  Widget _buildSelectableField({required String title, required String value, String? subtitle, required VoidCallback onTap}) {
    return _buildSection(
      title: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(
                      fontSize: 14,
                      color: AppColors.contrast,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.accent3, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              Icon(Icons.unfold_more_rounded, color: AppColors.contrast.withValues(alpha: 0.4), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // White card with a title, used for each part of the form
  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.contrast.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
