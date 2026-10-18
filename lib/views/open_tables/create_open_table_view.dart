import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/models/open_table_abandonment.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/create_open_table_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';

/// Form to create an open table: activity, description, max participants and building.
/// If the user leaves without publishing, it reports in which step they quit (abandonment).
class CreateOpenTableView extends StatefulWidget {
  const CreateOpenTableView({super.key});

  @override
  State<CreateOpenTableView> createState() => _CreateOpenTableViewState();
}

class _CreateOpenTableViewState extends State<CreateOpenTableView> {
  final _descController = TextEditingController();

  // ViewModel for callbacks and helper builders (build() watches it)
  CreateOpenTableViewModel get _vm => context.read<CreateOpenTableViewModel>();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  // Bottom sheet to pick the activity (it also sets the duration)
  void _showActivityPicker() {
    _vm.setStep(OpenTableCreationStep.activity);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SELECT ACTIVITY',
                style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                  fontSize: 14,
                  letterSpacing: 1.2,
                  color: AppColors.contrast.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              if (_vm.activities.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No activities found in catalog',
                    style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _vm.activities.length,
                    itemBuilder: (context, index) {
                      final a = _vm.activities[index];
                      final bool isSelected = a.id == _vm.selectedActivity?.id;

                      return ListTile(
                        onTap: () {
                          _vm.selectActivity(a);
                          Navigator.pop(context);
                        },
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? AppColors.accent3 : AppColors.contrast.withValues(alpha: 0.2),
                        ),
                        title: Text(
                          a.name,
                          style: AppFonts.body(
                            weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ).copyWith(
                            color: isSelected ? AppColors.accent3 : AppColors.contrast,
                          ),
                        ),
                        subtitle: Text(
                          '${a.durationMinutes} minutes · ${a.effortType.name.toLowerCase()}',
                          style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.contrast.withValues(alpha: 0.45)),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Bottom sheet to pick the building where the table will be
  void _showBuildingPicker() {
    _vm.setStep(OpenTableCreationStep.location);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SELECT LOCATION',
                style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                  fontSize: 14,
                  letterSpacing: 1.2,
                  color: AppColors.contrast.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              if (_vm.buildings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No buildings found in system',
                    style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _vm.buildings.length,
                    itemBuilder: (context, index) {
                      final b = _vm.buildings[index];
                      final bool isSelected = b.id == _vm.selectedBuilding?.id;

                      return ListTile(
                        onTap: () {
                          _vm.selectBuilding(b);
                          Navigator.pop(context);
                        },
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? AppColors.accent2 : AppColors.contrast.withValues(alpha: 0.2),
                        ),
                        title: Text(
                          b.name,
                          style: AppFonts.body(
                            weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ).copyWith(
                            color: isSelected ? AppColors.accent2 : AppColors.contrast,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Creates the open table and closes the screen
  Future<void> _publish() async {
    final result = await _vm.publish(_descController.text.trim());
    if (!mounted) return;

    switch (result) {
      case PublishResult.published:
        Navigator.pop(context, true);
      case PublishResult.missingFields:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an activity and location')),
        );
      case PublishResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_vm.publishError ?? '')),
        );
      case PublishResult.noSession:
        break;
    }
  }

  // Reports the step where the user quit and closes the screen
  Future<void> _onCancel() async {
    final shouldClose = await _vm.reportAbandonment();
    if (shouldClose && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateOpenTableViewModel>();

    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (vm.errorMessage != null) {
      return Scaffold(
        appBar: const CustomTopBar(title: 'Create Open Table', showBack: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.accent1, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  vm.errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 24),
                CustomButton(label: 'Retry', onClick: vm.loadData),
              ],
            ),
          ),
        ),
      );
    }

    // The back arrow and the back gesture also count as quitting
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onCancel();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomTopBar(
        title: 'Create Open Table',
        showBack: true,
        onBack: _onCancel,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Activity selector
            _buildSelectableField(
              title: 'Activity',
              value: vm.selectedActivity?.name ?? 'Select an activity',
              subtitle: vm.selectedActivity != null ? '${vm.selectedActivity!.durationMinutes} min' : null,
              onTap: _showActivityPicker,
            ),

            const SizedBox(height: 12),

            // Description
            _buildSection(
              title: 'What do you propose?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _descController,
                    maxLength: 160,
                    maxLines: 4,
                    onTap: () => vm.setStep(OpenTableCreationStep.description),
                    onChanged: (_) => setState(() {}),
                    style: AppFonts.body().copyWith(fontSize: 13, color: AppColors.contrast),
                    decoration: InputDecoration(
                      hintText: "Describe what you want to do, where exactly you'll be...",
                      hintStyle: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: AppColors.background,
                      counterText: '',
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_descController.text.length}/160',
                    style: AppFonts.body().copyWith(fontSize: 11, color: AppColors.contrast.withValues(alpha: 0.3)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Max participants (+ / - buttons)
            _buildSection(
              title: 'Max participants',
              child: Row(
                children: [
                  IconButton(
                    onPressed: vm.canDecrementParticipants ? vm.decrementParticipants : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '${vm.maxParticipants}',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 16, color: AppColors.contrast),
                  ),
                  IconButton(
                    onPressed: vm.canIncrementParticipants ? vm.incrementParticipants : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Building selector
            _buildSelectableField(
              title: 'Location',
              value: vm.selectedBuilding?.name ?? 'Select a building',
              onTap: _showBuildingPicker,
            ),

            const SizedBox(height: 32),

            vm.isPublishing
                ? const Center(child: CircularProgressIndicator())
                : Column(
              children: [
                CustomButton(
                  label: 'Publish Open Table',
                  color: AppColors.accent3,
                  onClick: _publish,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _onCancel,
                    child: Text(
                      'Cancel',
                      style: AppFonts.body(weight: FontWeight.w700).copyWith(
                        fontSize: 14,
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
    );
  }

  // Tappable field that shows the current value and opens a picker
  Widget _buildSelectableField({required String title, required String value, String? subtitle, required VoidCallback onTap}) {
    return _buildSection(
      title: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.contrast.withValues(alpha: 0.12), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(
                      fontSize: 14,
                      color: AppColors.contrast,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.accent3, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              Icon(Icons.unfold_more_rounded, color: AppColors.contrast.withValues(alpha: 0.4), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // White card with a title, used for each part of the form
  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.contrast.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
