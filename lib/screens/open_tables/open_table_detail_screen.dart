import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/open_table.dart';
import '../../models/open_table_participant.dart';
import '../../models/open_table_status_enum.dart';
import '../../services/open_table_service.dart';
import '../../services/open_table_participant_service.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';

/// Details of one open table: creator, activity, building, time left and participants.
/// The user can join the table or leave it.
class OpenTableDetailScreen extends StatefulWidget {
  final int openTableId;

  const OpenTableDetailScreen({
    super.key,
    required this.openTableId,
  });

  @override
  State<OpenTableDetailScreen> createState() => _OpenTableDetailScreenState();
}

class _OpenTableDetailScreenState extends State<OpenTableDetailScreen> {
  final _openTableService = OpenTableService();
  final _participantService = OpenTableParticipantService();
  late Future<OpenTable> _tableFuture;
  List<OpenTableParticipant> _participants = [];
  int? _currentUserId;
  bool _isMember = false;
  bool _isJoining = false;

  @override
  // Load the table when the screen opens
  void initState() {
    super.initState();
    _loadData();
  }

  // Starts loading the table (also used to refresh after join / leave)
  void _loadData() {
    setState(() {
      _tableFuture = _initData();
    });
  }

  // Load the table and its participants - GET /open-tables/{id}, GET /open-table-participants/table/{tableId}
  Future<OpenTable> _initData() async {
    _currentUserId = await TokenStorage.getUserId();

    final results = await Future.wait([
      _openTableService.getOpenTable(widget.openTableId),
      _participantService.getByOpenTable(widget.openTableId),
    ]);

    final table = results[0] as OpenTable;
    _participants = results[1] as List<OpenTableParticipant>;
    _isMember = _participants.any((p) => p.user?.id == _currentUserId);

    return table;
  }

  // Join the table - POST /open-table-participants/table/{tableId}/join
  Future<void> _handleJoin() async {
    if (_currentUserId == null) return;

    setState(() => _isJoining = true);
    try {
      await _participantService.join(widget.openTableId, _currentUserId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined the table!'),
            backgroundColor: AppColors.accent2,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
        _loadData();
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // Leave the table - DELETE /open-table-participants/table/{tableId}/leave
  Future<void> _handleLeave() async {
    if (_currentUserId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave table?', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text('You will no longer be a participant of this table.', style: AppFonts.body()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.accent1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isJoining = true);
    try {
      await _participantService.leave(widget.openTableId, _currentUserId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You left the table')),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
        _loadData();
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OpenTable>(
      future: _tableFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: const CustomTopBar(title: 'Error', showBack: true),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final table = snapshot.data!;

        final bool isCreator = table.creator?.id == _currentUserId;
        final bool isFull = table.status != OpenTableStatusEnum.OPEN ||
            _participants.length >= table.maxParticipants;

        final remainingMins = table.endTime.difference(DateTime.now()).inMinutes;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: const CustomTopBar(
            title: 'Open Table Detail',
            showBack: true,
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCreatorCard(table),

                      const SizedBox(height: 28),

                      Text(
                        'ACTIVITY INFO',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppColors.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActivityCard(table),

                      const SizedBox(height: 28),

                      Text(
                        'LOGISTICS',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppColors.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildDetailItem(
                            icon: Icons.location_on_rounded,
                            label: 'Location',
                            value: table.building?.name ?? 'Unknown',
                          ),
                          const SizedBox(width: 12),
                          _buildDetailItem(
                            icon: Icons.access_time_filled_rounded,
                            label: 'Ends in',
                            value: '$remainingMins min',
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      Text(
                        'PROPOSAL',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppColors.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08), width: 1.5),
                        ),
                        child: Text(
                          table.description,
                          style: AppFonts.body().copyWith(
                            fontSize: 14,
                            color: AppColors.contrast.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                        'PARTICIPANTS (${_participants.length}/${table.maxParticipants})',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppColors.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildParticipantsList(),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: _isJoining
                    ? const CircularProgressIndicator()
                    : _isMember
                        ? CustomButton(
                            label: 'Leave Table',
                            color: AppColors.accent1,
                            outline: true,
                            onClick: _handleLeave,
                          )
                    : isCreator
                        ? CustomButton(
                            label: 'You created this table',
                            color: Colors.grey[400]!,
                            onClick: null,
                          )
                        : CustomButton(
                            label: isFull ? 'Table full' : 'Join Table',
                            color: isFull ? Colors.grey[400]! : AppColors.accent3,
                            onClick: isFull ? null : _handleJoin,
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Card with the photo and name of the creator
  Widget _buildCreatorCard(OpenTable table) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          AvatarWidget(url: table.creator?.avatarUrl, name: table.creator?.name, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Created by',
                  style: AppFonts.body().copyWith(
                    fontSize: 12,
                    color: AppColors.contrast.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  table.creator?.name ?? 'Unknown User',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 18,
                    color: AppColors.contrast,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card with the activity, max participants, effort and interest
  Widget _buildActivityCard(OpenTable table) {
    final activityName = table.activity?.name ?? table.title;
    final effortText = table.activity?.effortType != null ? '${table.activity!.effortType.name.toLowerCase()} effort' : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent2.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.rocket_launch_rounded, color: AppColors.accent2, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityName,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 16,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Up to ${table.maxParticipants} participants${effortText.isNotEmpty ? ' · $effortText' : ''}',
                  style: AppFonts.body().copyWith(
                    fontSize: 13,
                    color: AppColors.contrast.withValues(alpha: 0.5),
                  ),
                ),
                if (table.activity?.interest != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent2.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.accent2.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      table.activity!.interest!.name,
                      style: AppFonts.body(weight: FontWeight.w700).copyWith(
                        fontSize: 11,
                        color: AppColors.accent2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Small box with an icon, a label and a value (location, time left)
  Widget _buildDetailItem({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.contrast.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.accent1),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                    fontSize: 9,
                    color: AppColors.contrast.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                fontSize: 13,
                color: AppColors.contrast,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Avatars of the people who joined the table
  Widget _buildParticipantsList() {
    if (_participants.isEmpty) {
      return Text(
        'Be the first to join!',
        style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.4)),
      );
    }

    return Wrap(
      spacing: -12,
      children: _participants.map((p) {
        return Tooltip(
          message: p.user?.name ?? 'Participant',
          child: AvatarWidget(
            url: p.user?.avatarUrl,
            name: p.user?.name,
            size: 34,
            border: Border.all(color: AppColors.accent3, width: 2),
          ),
        );
      }).toList(),
    );
  }
}
