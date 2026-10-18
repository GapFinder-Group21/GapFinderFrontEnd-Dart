import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/my_open_tables_view_model.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/open_tables/open_table_photo.dart';

/// Shows the open tables the user created and the ones they joined.
class MyOpenTablesView extends StatefulWidget {
  const MyOpenTablesView({super.key});

  @override
  State<MyOpenTablesView> createState() => _MyOpenTablesViewState();
}

class _MyOpenTablesViewState extends State<MyOpenTablesView> {
  // ViewModel for callbacks and helper builders (build() watches it)
  MyOpenTablesViewModel get _vm => context.read<MyOpenTablesViewModel>();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyOpenTablesViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: const CustomTopBar(
        title: 'My Open Tables',
        showBack: true,
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: vm.refresh,
              child: vm.error != null 
                  ? _buildErrorState()
                  : vm.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (vm.createdTables.isNotEmpty) ...[
                              _buildSectionHeader('Created by me'),
                              ...vm.createdTables.map((t) => _buildTableCard(t, isOwner: true)),
                              const SizedBox(height: 20),
                            ],
                            if (vm.joinedTables.isNotEmpty) ...[
                              _buildSectionHeader('Participated'),
                              ...vm.joinedTables.map((t) => _buildTableCard(t, isOwner: false)),
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
          color: context.palette.contrast.withValues(alpha: 0.4),
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
            Text(_vm.error!, textAlign: TextAlign.center, style: AppFonts.body().copyWith(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _vm.refresh, child: const Text('Retry')),
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
            Icon(Icons.history_rounded, size: 64, color: context.palette.contrast.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'No Open Tables found.',
              textAlign: TextAlign.center,
              style: AppFonts.body().copyWith(
                color: context.palette.contrast.withValues(alpha: 0.4),
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
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.contrast.withValues(alpha: 0.07), width: 1.5),
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
          // Table photo across the top of the card
          OpenTablePhoto(
            url: table.photoUrl,
            height: 140,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
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
                                color: context.palette.contrast,
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
                color: context.palette.contrast.withValues(alpha: 0.35),
              ),
            ),
          ),

          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.palette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isActive ? AppColors.accent3 : Colors.grey.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Text(
              '"${table.description}"',
              style: AppFonts.body().copyWith(
                fontSize: 13,
                color: context.palette.contrast.withValues(alpha: 0.65),
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
                    color: context.palette.contrast.withValues(alpha: 0.45),
                  ),
                ),
                const Spacer(),
                if (isActive)
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.openTableDetail, arguments: table.id),
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
                      color: context.palette.contrast.withValues(alpha: 0.4),
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
