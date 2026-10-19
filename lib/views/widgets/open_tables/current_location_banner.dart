import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/current_location_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/open_tables/nearby_friends_alert_dialog.dart';

// Shows the building where the user is now; it brings its own ViewModel
class CurrentLocationBanner extends StatelessWidget {
  final int userId;
  const CurrentLocationBanner({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CurrentLocationViewModel(userId)..init(),
      child: const _CurrentLocationBannerView(),
    );
  }
}

class _CurrentLocationBannerView extends StatefulWidget {
  const _CurrentLocationBannerView();

  @override
  State<_CurrentLocationBannerView> createState() => _CurrentLocationBannerViewState();
}

class _CurrentLocationBannerViewState extends State<_CurrentLocationBannerView> {
  StreamSubscription<NearbyFriendsDetected>? _eventsSub;

  @override
  // Vibrate and show the friends when the user arrives to a building where they are
  void initState() {
    super.initState();
    _eventsSub = context.read<CurrentLocationViewModel>().events.listen((event) {
      HapticFeedback.vibrate();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => NearbyFriendsAlertDialog(
            buildingName: event.buildingName,
            friends: event.friends,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CurrentLocationViewModel>();
    String text;
    IconData icon = Icons.location_on_rounded;
    Color iconColor = Colors.white.withValues(alpha: 0.5);

    switch (vm.status) {
      case LocationBannerStatus.locating:
        text = 'Locating...';
      case LocationBannerStatus.disabled:
        text = 'Location disabled';
        icon = Icons.location_off_rounded;
        iconColor = AppColors.accent1.withValues(alpha: 0.7);
      case LocationBannerStatus.inBuilding:
        text = 'Current building: ${vm.buildingName}';
        iconColor = AppColors.accent2.withValues(alpha: 0.8);
      case LocationBannerStatus.outsideCampus:
        text = 'Outside campus';
        iconColor = Colors.white.withValues(alpha: 0.5);
      case LocationBannerStatus.unavailable:
        text = 'Location unavailable';
      case LocationBannerStatus.offline:
        // No connection: the last building saved, and nothing is sent to the back
        text = vm.lastBuildingName == null
            ? 'Sin conexión · ubicación no disponible'
            : 'Último edificio: ${vm.lastBuildingName} · ${vm.lastBuildingAgo}';
        icon = Icons.wifi_off_rounded;
        iconColor = AppColors.accent1.withValues(alpha: 0.7);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.subtitle().copyWith(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        ),
        if (vm.isRefreshing && !vm.isFirstLoad) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
            ),
          ),
        ],
      ],
    );
  }
}
