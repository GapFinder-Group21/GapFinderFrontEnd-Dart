import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';

class BottomNav extends StatelessWidget {
  final String activeTab;
  final ValueChanged<String> onTab;

  const BottomNav({
    super.key,
    required this.activeTab,
    required this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.contrast,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNavItem(
                id: 'schedule',
                label: 'Schedule',
                icon: Icons.calendar_today_outlined,
              ),
              _buildNavItem(
                id: 'friends',
                label: 'Friends',
                icon: Icons.people_outline_rounded,
              ),
              _buildMainNavItem(),
              _buildNavItem(
                id: 'map',
                label: 'Open Tables',
                icon: Icons.location_on_outlined,
              ),
              _buildNavItem(
                id: 'suggest',
                label: 'Suggest',
                icon: Icons.lightbulb_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Ítems estándar (Schedule, Friends, Open Tables, Suggest)
  Widget _buildNavItem({
    required String id,
    required String label,
    required IconData icon,
  }) {
    final bool isActive = activeTab == id;
    final Color itemColor = isActive
        ? AppColors.background
        : AppColors.background.withValues(alpha: 0.5);

    return Expanded(
      child: InkWell(
        onTap: () => onTab(id),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: itemColor),
                if (isActive)
                  Positioned(
                    bottom: -6,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppFonts.body(
                weight: isActive ? FontWeight.w700 : FontWeight.w400,
              ).copyWith(
                fontSize: 10,
                color: itemColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Botón central flotante (Match)
  Widget _buildMainNavItem() {
    return Expanded(
      flex: 1,
      child: GestureDetector(
        onTap: () => onTab('match'),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -24,
              child: Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      AppColors.accent3, // Azul
                      AppColors.accent3,
                      AppColors.accent2, // Verde
                      AppColors.accent2,
                      AppColors.accent1, // Rojo
                      AppColors.accent1,
                    ],
                    stops: [
                      0.0, 0.33,
                      0.33, 0.66,
                      0.66, 1.0,
                    ],
                  ),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.contrast,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset(
                        'assets/images/logo_sin_fondo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              child: Text(
                'Match',
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 10,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
