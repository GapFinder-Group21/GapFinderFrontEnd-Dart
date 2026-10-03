import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../core/widgets/match_mode_selector.dart';
import '../../core/widgets/animated_match_button.dart';
import '../../models/gap.dart';
import '../../models/match.dart';
import '../../services/match_service.dart';
import '../../models/match_mode_enum.dart';
import '../../models/match_status_enum.dart';
import '../../services/gap_service.dart';

/// Match tab: shows your current free gap and the button to start looking for a match.
/// The button is disabled if you have no gap now or you already have an active match.
class MatchMainScreen extends StatefulWidget {
  final bool isActive;
  const MatchMainScreen({super.key, this.isActive = false});

  @override
  State<MatchMainScreen> createState() => _MatchMainScreenState();
}

class _MatchMainScreenState extends State<MatchMainScreen> {
  final _gapService = GapService();
  final _matchService = MatchService();
  MatchModeEnum _selectedMode = MatchModeEnum.career;
  late Future<Gap?> _activeGapFuture;
  late Future<Match?> _activeMatchFuture;
  int? _userId;
  DateTime? _lastCheckTime;

  @override
  // Load the current gap and the active match
  void initState() {
    super.initState();
    _loadData();
  }

  // Starts loading the current gap and the active match
  void _loadData() {
    _activeGapFuture = _loadActiveGap();
    _activeMatchFuture = _loadActiveMatch();
  }

  // Reload everything (pull to refresh)
  Future<void> _refresh() async {
    setState(() {
      _loadData();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchMainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload the data every time the user comes back to this tab
    if (widget.isActive && !oldWidget.isActive) {
      setState(() {
        _loadData();
      });
    }
  }

  // Finds an accepted match of this user - GET /matches
  Future<Match?> _loadActiveMatch() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    try {
      final all = await _matchService.getAll();
      final active = all.where((m) => 
        (m.proposerGap?.user?.id == userId || m.acceptorGap?.user?.id == userId) &&
        m.status == MatchStatusEnum.ACCEPTED
      ).firstOrNull;

      if (active != null) {
        debugPrint('🔒 [MatchMainScreen] Active match found! ID=${active.id} blocking match button.');
      } else {
        debugPrint('🔓 [MatchMainScreen] No active ACCEPTED match found for userId=$userId.');
      }
      return active;
    } catch (e) {
      debugPrint('❌ [MatchMainScreen] Error loading active match: $e');
      return null;
    }
  }

  // Finds the gap the user is in right now - GET /gaps/user/{userId}
  Future<Gap?> _loadActiveGap() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    _userId = userId;

    final now = DateTime.now();
    setState(() {
      _lastCheckTime = now;
    });

    try {
      final gaps = await _gapService.getUserGaps(userId);
      return gaps.where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime)).firstOrNull;
    } catch (e) {
      debugPrint("Advertencia: No se pudieron cargar los GAPs en Match: $e");
      return null;
    }
  }

  // Date and time of the last check, e.g. "Mon, Oct 6 - 9:30"
  String _getFullDateTimeLabel(DateTime dt) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final day = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    final time = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    
    return "$day, $month ${dt.day} - $time";
  }

  // DateTime -> "9:30" (12h format without AM/PM)
  String _formatTime(DateTime time) {
    final localTime = TimeOfDay.fromDateTime(time);
    final hour = localTime.hourOfPeriod == 0 ? 12 : localTime.hourOfPeriod;
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Minutes -> "1h 30m free" / "45m free"
  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m free';
    if (h > 0) return '${h}h free';
    return '${m}m free';
  }

  // Opens the searching screen with the selected match mode
  Future<void> _startMatch() async {
    if (_userId == null) return;
    Navigator.pushNamed(
      context,
      '/searching-match',
      arguments: {'userId': _userId, 'mode': _selectedMode},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              width: double.infinity,
              color: AppColors.contrast,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Text(
                'MATCH',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: FutureBuilder<List<dynamic>>(
                    future: Future.wait([_activeGapFuture, _activeMatchFuture]),
                    builder: (context, snapshot) {
                      final isLoading = snapshot.connectionState == ConnectionState.waiting;
                      final gap = isLoading ? null : snapshot.data![0] as Gap?;
                      final activeMatch = isLoading ? null : snapshot.data![1] as Match?;

                      final bool canMatch = gap != null && activeMatch == null;

                      return Column(
                        children: [
                          // "Current GAP" card
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(),
                            )
                          else if (gap != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                              margin: const EdgeInsets.only(bottom: 32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(width: 4, color: AppColors.accent2),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CURRENT GAP',
                                          style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                                            fontSize: 12,
                                            letterSpacing: 1,
                                            color: AppColors.accent2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${_formatTime(gap.startTime)} – ${_formatTime(gap.endTime)}',
                                          style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                            fontSize: 18,
                                            color: AppColors.contrast,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time, size: 13, color: AppColors.accent2),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatDuration(gap.durationMinutes),
                                              style: AppFonts.body().copyWith(
                                                fontSize: 13,
                                                color: AppColors.contrast.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              margin: const EdgeInsets.only(bottom: 32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.contrast.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'You have no active GAP right now.',
                                    textAlign: TextAlign.center,
                                    style: AppFonts.body().copyWith(
                                      fontSize: 14,
                                      color: AppColors.contrast.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  if (_lastCheckTime != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Last check: ${_getFullDateTimeLabel(_lastCheckTime!)}',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.body().copyWith(
                                        fontSize: 12,
                                        color: AppColors.contrast.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                          if (activeMatch != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: AppColors.accent2.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.accent2.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.bolt_rounded, color: AppColors.accent2, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "YOU HAVE AN ACTIVE MATCH HAPPENING NOW!",
                                      style: AppFonts.body(weight: FontWeight.w800).copyWith(
                                        fontSize: 12,
                                        color: AppColors.accent2,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Main animated MATCH button
                          AnimatedMatchButton(
                            isEnabled: canMatch,
                            onTap: _startMatch,
                          ),

                          const SizedBox(height: 28),

                          // Match mode selector (career, interests or effort)
                          MatchModeSelector(
                            selected: _selectedMode,
                            onChanged: (mode) => setState(() => _selectedMode = mode),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
