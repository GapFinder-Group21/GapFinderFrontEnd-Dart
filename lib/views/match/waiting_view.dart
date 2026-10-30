import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/waiting_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Waits for the other person to accept or decline the match request you sent.
class WaitingView extends StatefulWidget {
  const WaitingView({super.key});

  @override
  State<WaitingView> createState() => _WaitingViewState();
}

class _WaitingViewState extends State<WaitingView> with WidgetsBindingObserver {
  StreamSubscription<WaitingEvent>? _eventsSub;

  @override
  // Listen to the polling result
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final vm = context.read<WaitingViewModel>();
    _eventsSub = vm.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case MatchAccepted(:final match):
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.itsAMatch,
            arguments: {
              'matchId': match.id,
              'candidateUser': vm.candidateUser,
            },
          );
        case MatchRejected():
          _showRejectedDialog();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  // The polling stops while the app is in the background and resumes when the user comes back
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vm = context.read<WaitingViewModel>();
    if (state == AppLifecycleState.paused) {
      vm.pausePolling();
    } else if (state == AppLifecycleState.resumed) {
      vm.resumePolling();
    }
  }

  // Dialog shown when the other person declines
  void _showRejectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Request Declined', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text('The other user declined your match request.', style: AppFonts.body()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Cancels the request in the back and goes back; if it could not be cancelled, says why and keeps waiting
  Future<void> _cancel() async {
    final message = await context.read<WaitingViewModel>().cancelRequest();
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Message of the last status we know, shown while there is no connection
  String _savedStatusMessage(WaitingViewModel vm) {
    switch (vm.lastKnownStatus) {
      case MatchStatusEnum.PENDING:
        return 'La última vez que revisamos, la otra persona todavía no respondía.';
      case MatchStatusEnum.ACCEPTED:
        return 'La última vez que revisamos, la otra persona ya había aceptado.';
      case MatchStatusEnum.REJECTED:
        return 'La última vez que revisamos, la otra persona había rechazado.';
      case MatchStatusEnum.COMPLETED:
        return 'La última vez que revisamos, este match ya estaba completado.';
      case null:
        return 'Todavía no tenemos un estado guardado de esta solicitud.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WaitingViewModel>();

    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
        child: Column(
          children: [
            // The polling is paused without connection
            if (vm.isOffline)
              OfflineBanner(
                message: 'Sin conexión · revisión en pausa',
                lastUpdated: vm.lastUpdated,
              ),
            Expanded(child: _buildBody(vm)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(WaitingViewModel vm) {
    return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // No spinner without connection: nothing is being checked
              if (vm.isOffline)
                const Icon(Icons.wifi_off_rounded, size: 72, color: AppColors.accent1)
              else
                const SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent2),
                  ),
                ),
              const SizedBox(height: 32),
              Text(
                vm.isOffline ? 'SIN CONEXIÓN' : 'WAITING FOR RESPONSE...',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 22,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                vm.isOffline
                    ? '${_savedStatusMessage(vm)} Volveremos a revisar cuando regrese la conexión.'
                    : 'We sent your connection request. Waiting for them to accept.',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: vm.isCancelling ? null : _cancel,
                  child: Text(
                    'Cancel Request',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
  }
}
