import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../models/interest.dart';
import '../../services/interest_service.dart';
import '../../services/user_service.dart';

/// Onboarding step where the user picks their interests (used to find better matches).
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  final _interestService = InterestService();
  final _userService = UserService();
  
  late Future<List<Interest>> _interestsFuture;
  final Set<int> _selectedInterestIds = {};
  bool _isSaving = false;

  @override
  // Load the list of interests from the backend
  void initState() {
    super.initState();
    _interestsFuture = _interestService.getInterests();
  }

  // Select or unselect an interest
  void _toggleInterest(int id) {
    setState(() {
      if (_selectedInterestIds.contains(id)) {
        _selectedInterestIds.remove(id);
      } else {
        _selectedInterestIds.add(id);
      }
    });
  }

  // Saves the selected interests and moves to the schedule setup
  Future<void> _handleContinue() async {
    if (_selectedInterestIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one interest')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) throw Exception('User session not found');

      // Save each selected interest one by one - POST /users/{userId}/interests/{interestId}
      for (final interestId in _selectedInterestIds) {
        await _userService.addInterest(userId, interestId);
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/schedule-setup');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving interests: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomTopBar(
        title: 'GAP FINDER',
        subtitle: 'Profile Setup',
      ),
      body: FutureBuilder<List<Interest>>(
        future: _interestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Error loading interests: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: AppFonts.body().copyWith(color: AppColors.contrast.withOpacity(0.6)),
                ),
              ),
            );
          }

          final interests = snapshot.data ?? [];

          return Column(
            children: [
              // List of interests the user can tap
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What are you into?',
                        style: AppFonts.display(weight: FontWeight.w800).copyWith(
                          fontSize: 22,
                          color: AppColors.contrast,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Select all that apply — we'll use this for matching",
                        style: AppFonts.subtitle().copyWith(
                          fontSize: 14,
                          color: AppColors.contrast.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // One chip per interest; selected ones are highlighted
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: interests.map((interest) {
                          final bool isSelected = _selectedInterestIds.contains(interest.id);

                          return GestureDetector(
                            onTap: () => _toggleInterest(interest.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.accent1 : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 1.5,
                                  color: isSelected ? AppColors.accent1 : AppColors.contrast.withOpacity(0.18),
                                ),
                              ),
                              child: Text(
                                interest.name,
                                style: AppFonts.body(
                                  weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                ).copyWith(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : AppColors.contrast,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : CustomButton(
                        label: 'Continue',
                        onClick: _handleContinue,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
