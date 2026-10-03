import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/match.dart';
import '../../models/user.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../services/match_service.dart';
import '../../core/token_storage.dart';
import '../../core/widgets/custom_button.dart';

/// Shown when someone sends you a match request: accept or decline it.
class MatchInvitationScreen extends StatefulWidget {
  final int matchId;

  const MatchInvitationScreen({
    super.key,
    required this.matchId,
  });

  @override
  State<MatchInvitationScreen> createState() => _MatchInvitationScreenState();
}

class _MatchInvitationScreenState extends State<MatchInvitationScreen> {
  final _matchService = MatchService();
  Match? _match;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  // Load the match details when the screen opens
  void initState() {
    super.initState();
    _loadMatchDetails();
  }

  // Gets the match and the user who sent it - GET /matches/{id}
  Future<void> _loadMatchDetails() async {
    try {
      final match = await _matchService.getById(widget.matchId);
      
      setState(() {
        _match = match;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading match invitation: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  // Accepts the match and shows the "It's a match" screen - PATCH /matches/{id}/accept
  Future<void> _accept() async {
    if (_match == null) return;
    setState(() => _isProcessing = true);
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;
      final updatedMatch = await _matchService.accept(_match!.id, userId);

      if (!mounted) return;
      
      Navigator.pushReplacementNamed(
        context,
        '/its-a-match',
        arguments: {
          'matchId': updatedMatch.id,
          'candidateUser': updatedMatch.proposerGap?.user,
        },
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accepting match: $e')),
      );
    }
  }

  // Declines the match and closes the screen - PATCH /matches/{id}/reject
  Future<void> _decline() async {
    if (_match == null) return;
    setState(() => _isProcessing = true);
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;
      await _matchService.reject(_match!.id, userId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error declining match: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = _match!.proposerGap?.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Match user not found')));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.accent3, // Azul para invitaciones
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Text(
                "Match Invitation!",
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOMEONE WANTS TO CONNECT',
                      style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: AppColors.contrast.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildUserCard(user),
                    const SizedBox(height: 32),
                    
                    Text(
                      'PROPOSAL',
                      style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: AppColors.contrast.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accent3.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        "${user.name} found an overlap in your schedules and wants to meet up!",
                        style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.7)),
                      ),
                    ),

                    const SizedBox(height: 48),
                    
                    _isProcessing 
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            CustomButton(
                              label: 'Accept Invitation',
                              color: AppColors.accent2,
                              onClick: _accept,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: _decline,
                                child: Text(
                                  'Decline',
                                  style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                                    fontSize: 15,
                                    color: AppColors.contrast.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card with the photo, name and career of the user who sent the match
  Widget _buildUserCard(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          AvatarWidget(
            url: user.avatarUrl,
            name: user.name,
            size: 70,
            border: Border.all(color: AppColors.accent3.withValues(alpha: 0.2), width: 3),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: AppFonts.display(weight: FontWeight.w900).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.career,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.subtitle(weight: FontWeight.w600).copyWith(
                    fontSize: 13,
                    color: AppColors.contrast.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
