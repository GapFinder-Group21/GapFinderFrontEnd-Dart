import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/match_mode_enum.dart';

const Map<MatchModeEnum, String> matchModeLabels = {
  MatchModeEnum.career: 'Career',
  MatchModeEnum.interests: 'Interests',
  MatchModeEnum.effort: 'Effort',
};

class MatchModeSelector extends StatelessWidget {
  final MatchModeEnum selected;
  final ValueChanged<MatchModeEnum> onChanged;

  const MatchModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIORITIZE BY',
          style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
            fontSize: 13,
            letterSpacing: 1.6,
            color: AppColors.contrast.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: MatchModeEnum.values.map((mode) {
            final bool isSelected = mode == selected;
            return InkWell(
              onTap: () => onChanged(mode),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent1 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent1
                        : AppColors.contrast.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  matchModeLabels[mode] ?? mode.name,
                  style: AppFonts.body(
                    weight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  ).copyWith(
                    fontSize: 14,
                    color: isSelected ? Colors.white : AppColors.contrast,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
