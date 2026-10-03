import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/gap.dart';
import '../../services/gap_service.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';

/// Shows the details of one free gap (start, end and duration).
class GapDetailScreen extends StatefulWidget {
  final int gapId;
  const GapDetailScreen({super.key, required this.gapId});

  @override
  State<GapDetailScreen> createState() => _GapDetailScreenState();
}

class _GapDetailScreenState extends State<GapDetailScreen> {
  final _gapService = GapService();
  late Future<Gap> _gapFuture;

  @override
  // Load the gap - GET /gaps/{id}
  void initState() {
    super.initState();
    _gapFuture = _gapService.getGap(widget.gapId);
  }

  // DateTime -> "9:30" (12h format without AM/PM)
  String _formatTime(DateTime time) {
    final localTime = TimeOfDay.fromDateTime(time);
    final hour = localTime.hourOfPeriod == 0 ? 12 : localTime.hourOfPeriod;
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomTopBar(title: 'GAP Details', showBack: true),
      body: FutureBuilder<Gap>(
        future: _gapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final gap = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accent1.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FREE TIME GAP',
                        style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                          fontSize: 12,
                          color: AppColors.accent1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatTime(gap.startTime)} – ${_formatTime(gap.endTime)}',
                        style: AppFonts.display(weight: FontWeight.w800).copyWith(
                          fontSize: 22,
                          color: AppColors.contrast,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${gap.durationMinutes} minutes available',
                        style: AppFonts.body().copyWith(
                          color: AppColors.contrast.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                CustomButton(
                  label: 'Find Match for this GAP',
                  color: AppColors.accent1,
                  onClick: () {
                    Navigator.pushNamed(
                      context,
                      '/searching-match',
                      arguments: {'userId': gap.userId, 'gapId': gap.id},
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
