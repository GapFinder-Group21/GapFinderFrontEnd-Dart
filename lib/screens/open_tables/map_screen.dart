import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/open_table.dart';
import '../../models/open_table_status_enum.dart';
import '../../models/open_table_participant.dart';
import '../../services/open_table_service.dart';
import '../../services/open_table_participant_service.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../core/widgets/custom_button.dart';
import '../../services/location_service.dart';
import '../../widgets/open_tables/current_location_banner.dart';
import 'package:geolocator/geolocator.dart';

/// Open Tables tab: shows the current building and the list of open tables you can join.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _openTableService = OpenTableService();
  final _participantService = OpenTableParticipantService();
  
  List<OpenTable> _openTables = [];
  Set<int> _joinedTableIds = {};
  bool _isLoading = true;
  int? _userId;
  String? _errorMessage;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  @override
  // Load the tables and reload them when the GPS is turned on or off
  void initState() {
    super.initState();
    _loadData();
    _listenToLocationChanges();
  }

  // Reload the list when the GPS is turned on or off
  void _listenToLocationChanges() {
    if (!kIsWeb) {
      _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
        debugPrint('DEBUG: GPS Status changed to: $status');
        _loadData();
      });
    }
  }

  @override
  // Stop listening to the GPS when leaving the screen
  void dispose() {
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }

  // Load the open tables that are still open - GET /open-tables
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = await TokenStorage.getUserId();
      if (mounted) setState(() => _userId = userId);
      if (userId == null) return;

      final hasLocation = await LocationService.isLocationEnabled();
      if (!hasLocation) {
        setState(() => _errorMessage = 'Location is required to discover tables nearby.');
        return;
      }

      final all = await _openTableService.getAll();
      final now = DateTime.now();
      _openTables = all
          .where((t) => t.status == OpenTableStatusEnum.OPEN && t.endTime.isAfter(now))
          .toList();

      final checks = await Future.wait(_openTables.map((t) => _isParticipant(t.id, userId)));
      final joinedIds = <int>{};
      for (int i = 0; i < _openTables.length; i++) {
        if (checks[i]) {
          joinedIds.add(_openTables[i].id);
        }
      }
      setState(() {
        _joinedTableIds = joinedIds;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Checks if the user already joined a table - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    try {
      final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId);
      return list.any((p) => p.user?.id == userId);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Dark header with the title, the current building and the buttons
          _buildHeader(),

          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // List of Open Tables
                        _buildTablesList(),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  // Header: current building (location banner) and the "Mine" and "New" buttons
  Widget _buildHeader() {
    return Container(
      color: AppColors.contrast,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Open Table',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              if (_userId != null)
                CurrentLocationBanner(userId: _userId!)
              else
                Text(
                  'Locating...',
                  style: AppFonts.subtitle().copyWith(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/my-open-tables'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent3,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: AppFonts.subtitle(weight: FontWeight.w700).copyWith(fontSize: 12),
                ),
                child: const Text('Mine'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/create-open-table'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent2,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: AppFonts.subtitle(weight: FontWeight.w700).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // List of tables, or an error / empty message
  Widget _buildTablesList() {
    if (_errorMessage != null) {
      final isLocationError = _errorMessage!.contains('Location is required');
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              isLocationError ? Icons.location_off_rounded : Icons.info_outline_rounded, 
              size: 48, 
              color: AppColors.accent1
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: AppFonts.body(weight: FontWeight.w700).copyWith(color: AppColors.accent1),
            ),
            const SizedBox(height: 24),
            CustomButton(
              label: isLocationError ? 'Enable Location' : 'Retry', 
              onClick: isLocationError 
                  ? () => Navigator.pushNamed(context, '/location-permission').then((_) => _loadData())
                  : _loadData, 
              small: true
            ),
          ],
        ),
      );
    }

    if (_openTables.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.coffee_maker_rounded, size: 48, color: AppColors.contrast.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            Text(
              'No active tables available to discover right now.',
              textAlign: TextAlign.center,
              style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.4)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _openTables.length,
      itemBuilder: (context, index) {
        final table = _openTables[index];
        return _buildTableCard(table);
      },
    );
  }

  // Card of a table: creator, building, activity, time left, description and Join button
  Widget _buildTableCard(OpenTable table) {
    final remainingMins = table.endTime.difference(DateTime.now()).inMinutes;
    final bool isCreator = table.creator?.id == _userId;
    final bool isMember = _joinedTableIds.contains(table.id);
    final bool alreadyIn = isCreator || isMember;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.07), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Creator and table info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                AvatarWidget(url: table.creator?.avatarUrl, name: table.creator?.name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.creator?.name ?? 'User',
                        style: AppFonts.display(weight: FontWeight.w800).copyWith(
                          fontSize: 15,
                          color: AppColors.contrast,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Wrap (not Row) so the info goes to a new line instead of overflowing
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on_rounded, size: 12, color: AppColors.contrast.withValues(alpha: 0.35)),
                              const SizedBox(width: 4),
                              Text(
                                table.building?.name ?? 'Unknown location',
                                style: AppFonts.body().copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.contrast.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent3.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              table.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                                fontSize: 11,
                                color: AppColors.accent3,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time_rounded, size: 12, color: AppColors.contrast.withValues(alpha: 0.35)),
                              const SizedBox(width: 4),
                              Text(
                                '${remainingMins}m left',
                                style: AppFonts.body().copyWith(
                                  fontSize: 12,
                                  color: AppColors.contrast.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Text(
              'DESCRIPTION',
              style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                fontSize: 10,
                letterSpacing: 1,
                color: AppColors.contrast.withValues(alpha: 0.35),
              ),
            ),
          ),

          // Description
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent3, width: 1.5),
            ),
            child: Text(
              '"${table.description}"',
              style: AppFonts.body().copyWith(
                fontSize: 13,
                color: AppColors.contrast.withValues(alpha: 0.65),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

          // Max people and the Join / Joined button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Text(
                  'Up to ${table.maxParticipants} people',
                  style: AppFonts.body(weight: FontWeight.w700).copyWith(
                    fontSize: 11,
                    color: AppColors.contrast.withValues(alpha: 0.45),
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/open-table-detail', arguments: table.id).then((_) => _loadData()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: alreadyIn ? Colors.grey[300] : AppColors.accent3,
                    foregroundColor: alreadyIn ? AppColors.contrast.withValues(alpha: 0.5) : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    textStyle: AppFonts.body(weight: FontWeight.w800).copyWith(fontSize: 12),
                  ),
                  child: Text(alreadyIn ? 'Joined' : 'Join'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
