import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/open_table.dart';
import '../../services/recommendation_service.dart';
import '../../widgets/common/avatar_widget.dart';

/// Suggestions tab: your favorite building (where you spend more time)
/// and the open tables recommended for you.
class RecommendationsScreen extends StatefulWidget {
  final bool isActive;
  const RecommendationsScreen({super.key, this.isActive = false});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _recommendationService = RecommendationService();
  late Future<RecommendationResponse> _recommendationFuture;

  @override
  // Load the recommendations when the screen opens
  void initState() {
    super.initState();
    _recommendationFuture = _loadRecommendations();
  }

  @override
  // Reload the data every time the user comes back to this tab
  void didUpdateWidget(covariant RecommendationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      setState(() {
        _recommendationFuture = _loadRecommendations();
      });
    }
  }

  // Gets the favorite building and the recommended tables - GET /recommendations/user/{userId}/open-tables
  Future<RecommendationResponse> _loadRecommendations() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) {
      throw Exception('No user session found');
    }
    return _recommendationService.recommendOpenTables(userId);
  }

  // Reload everything (pull to refresh)
  Future<void> _refresh() async {
    setState(() {
      _recommendationFuture = _loadRecommendations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              color: AppColors.contrast,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent2.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lightbulb_rounded, color: AppColors.accent2, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Recommendation',
                    style: AppFonts.display(weight: FontWeight.w900).copyWith(
                      fontSize: 20,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<RecommendationResponse>(
                future: _recommendationFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.accent1.withValues(alpha: 0.7)),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load recommendations',
                              style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${snapshot.error}'.replaceAll('Exception: ', ''),
                              textAlign: TextAlign.center,
                              style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _refresh,
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent2, foregroundColor: Colors.white),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data!;

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Favorite building card
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.accent2, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent2.withValues(alpha: 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent2.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.star_rounded, color: AppColors.accent2, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TOP FREQUENTED',
                                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                                          fontSize: 11,
                                          letterSpacing: 1.2,
                                          color: AppColors.accent2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Favorite Building',
                                        style: AppFonts.display(weight: FontWeight.w900).copyWith(
                                          fontSize: 18,
                                          color: AppColors.contrast,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.business_rounded, color: AppColors.contrast, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        data.buildingName ?? 'No frequent building yet',
                                        style: AppFonts.display(weight: FontWeight.w900).copyWith(
                                          fontSize: 16,
                                          color: AppColors.contrast,
                                        ),
                                      ),
                                    ),
                                    if (data.totalMinutes > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent2.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${data.totalMinutes.toInt()} mins',
                                          style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                            fontSize: 12,
                                            color: AppColors.accent2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 13, color: AppColors.contrast.withValues(alpha: 0.4)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Recalculated daily based on your location activity',
                                    style: AppFonts.body().copyWith(
                                      fontSize: 11,
                                      color: AppColors.contrast.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: AppColors.accent2, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Recommended Open Tables',
                              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                fontSize: 16,
                                color: AppColors.contrast,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accent2.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${data.tables.length} available',
                                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                  fontSize: 11,
                                  color: AppColors.accent2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (data.tables.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(40),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.table_restaurant_outlined, size: 48, color: AppColors.contrast.withValues(alpha: 0.2)),
                                const SizedBox(height: 16),
                                Text(
                                  'No open tables found',
                                  style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'There are no active open tables in your favorite building right now.',
                                  textAlign: TextAlign.center,
                                  style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.contrast.withValues(alpha: 0.5)),
                                ),
                              ],
                            ),
                          )
                        else
                          ...data.tables.map(_buildTableCard),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card of a recommended table, with a button to open its detail
  Widget _buildTableCard(OpenTable table) {
    final remainingMins = table.endTime.difference(DateTime.now()).inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                AvatarWidget(url: table.creator?.avatarUrl, name: table.creator?.name, size: 48),
                const SizedBox(width: 14),
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
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 12, color: AppColors.accent2),
                          const SizedBox(width: 4),
                          Text(
                            table.building?.name ?? 'Unknown location',
                            style: AppFonts.body().copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.contrast.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent2.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.table_bar_rounded, size: 14, color: AppColors.accent2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    table.title,
                    style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                      fontSize: 12,
                      color: AppColors.accent2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
                  onPressed: () => Navigator.pushNamed(context, '/open-table-detail', arguments: table.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent2,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    textStyle: AppFonts.body(weight: FontWeight.w800).copyWith(fontSize: 12),
                  ),
                  child: const Text('View'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
