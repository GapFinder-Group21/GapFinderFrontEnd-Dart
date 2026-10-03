import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../services/google_service.dart';

/// Opens the Google sign-in page in the browser so the user can link their Google Calendar.
class GoogleConnectScreen extends StatefulWidget {
  const GoogleConnectScreen({super.key});

  @override
  State<GoogleConnectScreen> createState() => _GoogleConnectScreenState();
}

class _GoogleConnectScreenState extends State<GoogleConnectScreen> {
  final _googleService = GoogleService();
  bool _loading = false;
  bool _opened = false;
  String? _error;

  // Gets the Google sign-in URL from the backend and opens it in the browser - GET /google/auth-url
  Future<void> _openGoogleAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authUrl = await _googleService.getAuthUrl();
      final uri = Uri.parse(authUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('No se pudo abrir el navegador');
      }

      setState(() {
        _opened = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // After signing in with Google, go to the import screen
  void _continueToImport() {
    Navigator.pushReplacementNamed(context, '/google-calendar');
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
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.accent3,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Connect Google Calendar',
                textAlign: TextAlign.center,
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 20,
                  color: AppColors.contrast,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _opened
                    ? 'Finish signing in with your Google account in the browser, then come back and tap Continue.'
                    : 'You\'ll be taken to Google to sign in and authorize access to your calendar.',
                textAlign: TextAlign.center,
                style: AppFonts.body(weight: FontWeight.w400).copyWith(
                  fontSize: 14,
                  color: AppColors.contrast.withOpacity(0.55),
                ),
              ),
              // Error message, if opening Google failed
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 13,
                    color: AppColors.accent1,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              // Button: open Google first, then continue to the import
              if (_loading)
                const CircularProgressIndicator()
              else if (!_opened)
                CustomButton(
                  label: 'Continue with Google',
                  color: AppColors.accent3,
                  onClick: _openGoogleAuth,
                )
              else ...[
                  CustomButton(
                    label: 'Continue',
                    color: AppColors.accent3,
                    onClick: _continueToImport,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openGoogleAuth,
                    child: Text(
                      'Open Google sign-in again',
                      style: AppFonts.body(weight: FontWeight.w400).copyWith(
                        fontSize: 13,
                        color: AppColors.contrast.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}