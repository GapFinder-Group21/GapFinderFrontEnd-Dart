import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/user.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../models/activity.dart';
import '../../models/effort_type_enum.dart';

/// Shown when a match is accepted: the other person, their phone number
/// and the suggested activity to do together.
class ItsAMatchScreen extends StatefulWidget {
  final int matchId;
  final User candidateUser;
  final Activity? suggestedActivity;
  final Activity? chosenActivity;

  const ItsAMatchScreen({
    super.key,
    required this.matchId,
    required this.candidateUser,
    this.suggestedActivity,
    this.chosenActivity,
  });

  @override
  State<ItsAMatchScreen> createState() => _ItsAMatchScreenState();
}

class _ItsAMatchScreenState extends State<ItsAMatchScreen> {
  @override
  Widget build(BuildContext context) {
    // Show the suggested activity, or the one the user picked
    final activityToShow = widget.suggestedActivity ?? widget.chosenActivity;

    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "IT'S A MATCH!",
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 32,
                  color: AppColors.accent1,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: AvatarWidget(
                  url: widget.candidateUser.avatarUrl,
                  name: widget.candidateUser.name,
                  size: 120,
                  border: Border.all(color: Colors.white, width: 4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'You and ${widget.candidateUser.name} are free at the same time.',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              // Phone number display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone, color: AppColors.accent2, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      widget.candidateUser.phoneNumber?.isNotEmpty == true
                          ? widget.candidateUser.phoneNumber!
                          : 'No phone number available',
                      style: AppFonts.display(weight: FontWeight.w700).copyWith(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              if (activityToShow != null) ...[
                const SizedBox(height: 30),
                Text(
                  'SUGGESTED ACTIVITY',
                  style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildEffortIcon(activityToShow.effortType),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activityToShow.name,
                                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${activityToShow.durationMinutes} minutes · ${activityToShow.effortType.name.toLowerCase()}',
                                  style: AppFonts.body().copyWith(
                                    fontSize: 13,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (activityToShow.interest != null) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent3.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.accent3.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              activityToShow.interest!.name,
                              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                                fontSize: 11,
                                color: AppColors.accent3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent1,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Back to Schedule',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Icon and color for the effort level (low, medium, high)
  Widget _buildEffortIcon(EffortTypeEnum level) {
    IconData icon;
    Color color;

    switch (level) {
      case EffortTypeEnum.LOW:
        icon = Icons.self_improvement_rounded;
        color = AppColors.accent3;
        break;
      case EffortTypeEnum.MEDIUM:
        icon = Icons.directions_walk_rounded;
        color = AppColors.accent2;
        break;
      case EffortTypeEnum.HIGH:
        icon = Icons.bolt_rounded;
        color = AppColors.accent1;
        break;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
