import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../services/google_service.dart';

/// Imports the user's class schedule from Google Calendar.
/// Shows three states: importing, success or error.
class GoogleCalendarScreen extends StatefulWidget {
  const GoogleCalendarScreen({super.key});

  @override
  State<GoogleCalendarScreen> createState() => _GoogleCalendarScreenState();
}

class _GoogleCalendarScreenState extends State<GoogleCalendarScreen> {
  final _googleService = GoogleService();
  String _phase = 'connecting'; // 'connecting' | 'success' | 'error'
  String? _errorMessage;

  @override
  // Start the import as soon as the screen opens
  void initState() {
    super.initState();
    _importSchedule();
  }

  // Asks the backend to import the schedule - POST /google/import-schedule
  Future<void> _importSchedule() async {
    setState(() {
      _phase = 'connecting';
      _errorMessage = null;
    });

    try {
      debugPrint('🚀 IMPORT: Starting Google Calendar import...');
      await _googleService.importSchedule();
      debugPrint('✅ IMPORT: Success (Standard)');
      if (!mounted) return;
      setState(() => _phase = 'success');
    } catch (e) {
      debugPrint('⚠️ IMPORT ERROR/CONFLICT: $e');
      if (!mounted) return;

      // A 409 means the classes were already imported, so it counts as success
      if (e.toString().contains('409')) {
        debugPrint('ℹ️ IMPORT: Conflict 409 detected, but data persists. Marking as success.');
        setState(() => _phase = 'success');
        return;
      }

      setState(() {
        _phase = 'error';
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomTopBar(
        title: 'Google Calendar',
        showBack: true,
      ),
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // State 1: importing (spinner)
              if (_phase == 'connecting') ...[
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent3),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Connecting to Google...',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Importing your calendar events',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.5),
                  ),
                ),
              // State 2: import finished
              ] else if (_phase == 'success') ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.accent3,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Calendar connected!',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your Google Calendar events have been imported successfully.',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.55),
                  ),
                ),
              // State 3: import failed
              ] else ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.accent1,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage ?? 'We couldn\'t import your calendar. Try again.',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.55),
                  ),
                ),
              ],
              const Spacer(),
              // Success: go to the home screen
              if (_phase == 'success')
                CustomButton(
                  label: 'Continue',
                  color: AppColors.accent3,
                  onClick: () {
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                  },
                ),
              // Error: let the user try again
              if (_phase == 'error')
                CustomButton(
                  label: 'Try Again',
                  color: AppColors.accent1,
                  onClick: _importSchedule,
                ),
            ],
          ),
        ),
      ),
    );
  }
}