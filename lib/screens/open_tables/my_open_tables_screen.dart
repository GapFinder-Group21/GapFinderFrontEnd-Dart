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
import '../../core/widgets/custom_top_bar.dart';

/// Shows the open tables the user created and the ones they joined.
class MyOpenTablesScreen extends StatefulWidget {
  const MyOpenTablesScreen({super.key});

  @override
  State<MyOpenTablesScreen> createState() => _MyOpenTablesScreenState();
}

class _MyOpenTablesScreenState extends State<MyOpenTablesScreen> {
  final _openTableService = OpenTableService();
  final _participantService = OpenTableParticipantService();

  List<OpenTable> _createdTables = [];
  List<OpenTable> _joinedTables = [];
  bool _isLoading = true;
  String? _error;

  @override
  // Load the tables when the screen opens
  void initState() {
    super.initState();
    _loadAllTables();
  }

  // Load the tables created and joined by the user - GET /open-tables
  Future<void> _loadAllTables() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;

      final all = await _openTableService.getAll();
      final created = all.where((t) => t.creator?.id == userId).toList();
      final others = all.where((t) => t.creator?.id != userId).toList();

      final joined = <OpenTable>[];
      final checks = await Future.wait(others.map((t) => _isParticipant(t.id, userId)));
      for (var i = 0; i < others.length; i++) {
        if (checks[i]) joined.add(others[i]);
      }

      setState(() {
        _createdTables = created;
        _joinedTables = joined;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Check if the user is a participant - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId);
    return list.any((p) => p.user?.id == userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomTopBar(
        title: 'My Open Tables',
        showBack: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllTables,
              child: _error != null 
                  ? _buildErrorState()
                  : (_createdTables.isEmpty && _joinedTables.isEmpty)
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_createdTables.isNotEmpty) ...[
                              _buildSectionHeader('Created by me'),
                              ..._createdTables.map((t) => _buildTableCard(t, isOwner: true)),
                              const SizedBox(height: 20),
                            ],
                            if (_joinedTables.isNotEmpty) ...[
                              _buildSectionHeader('Participated'),
                              ..._joinedTables.map((t) => _buildTableCard(t, isOwner: false)),
                            ],
                          ],
                        ),
            ),
    );
  }

  // Title of a section ("Created" or "Participated")
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
          fontSize: 12,
          letterSpacing: 1.2,
          color: AppColors.contrast.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  // Shown when the tables could not be loaded, with a Retry button
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.accent1, size: 48),
            const SizedBox(height: 16),
            Text('Error loading tables', style: AppFonts.display(weight: FontWeight.w700).copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: AppFonts.body().copyWith(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _loadAllTables, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  // Shown when the user has not created or joined any table
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: AppColors.contrast.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'No Open Tables found.',
              textAlign: TextAlign.center,
              style: AppFonts.body().copyWith(
                color: AppColors.contrast.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card of a table, with a button to open its detail
  Widget _buildTableCard(OpenTable table, {required bool isOwner}) {
    final bool isActive = (table.status == OpenTableStatusEnum.OPEN ||
            table.status == OpenTableStatusEnum.FULL) &&
        table.endTime.isAfter(DateTime.now());
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              isOwner ? 'You (Owner)' : (table.creator?.name ?? 'User'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                fontSize: 15,
                                color: AppColors.contrast,
                              ),
                            ),
                          ),
                          _buildStatusBadge(isActive),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent3.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          table.title,
                          style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                            fontSize: 11,
                            color: AppColors.accent3,
                          ),
                        ),
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

          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isActive ? AppColors.accent3 : Colors.grey.withValues(alpha: 0.3), width: 1.5),
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
                if (isActive)
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/open-table-detail', arguments: table.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.contrast,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      textStyle: AppFonts.body(weight: FontWeight.w800).copyWith(fontSize: 12),
                    ),
                    child: const Text('View'),
                  )
                else
                  Text(
                    'Table ended',
                    style: AppFonts.body().copyWith(
                      fontSize: 11,
                      color: AppColors.contrast.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Badge that says if the table is ACTIVE or ENDED
  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? AppColors.accent2.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'ENDED',
        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
          fontSize: 9,
          color: isActive ? AppColors.accent2 : Colors.grey,
        ),
      ),
    );
  }
}
