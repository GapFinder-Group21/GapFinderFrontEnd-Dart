import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/my_matches_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';
import 'package:gapfinderfrontend_dart/views/widgets/open_tables/cached_avatar.dart';

/// "Mis matches": the history of the user's matches, the ratings and the button to rate.
class MyMatchesView extends StatefulWidget {
  const MyMatchesView({super.key});

  @override
  State<MyMatchesView> createState() => _MyMatchesViewState();
}

class _MyMatchesViewState extends State<MyMatchesView> {
  late final MyMatchesViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<MyMatchesViewModel>();
    // Notices can arrive with nobody tapping (a queued rating sent or refused): shown as SnackBar
    _vm.addListener(_showNotice);
  }

  @override
  void dispose() {
    _vm.removeListener(_showNotice);
    super.dispose();
  }

  void _showNotice() {
    final notice = _vm.takeNotice();
    if (notice == null || !mounted) return;
    final ok = notice == MyMatchesViewModel.sentNotice || notice == MyMatchesViewModel.queuedNotice;
    _snack(notice, ok: ok);
  }

  void _snack(String text, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: AppFonts.body().copyWith(fontSize: 13, color: Colors.white)),
      backgroundColor: ok ? AppColors.accent2 : AppColors.accent1,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyMatchesViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: const CustomTopBar(title: 'Mis matches', showBack: true),
      body: Column(
        children: [
          // Read-only history saved in SQLite because there is no connection
          if (vm.isOffline && !vm.isEmpty)
            OfflineBanner(
              message: 'Sin conexión · mostrando tus matches guardados',
              lastUpdated: vm.lastUpdated,
            ),
          Expanded(
            child: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: vm.pullToRefresh,
                    child: vm.error != null
                        ? _buildErrorState(vm)
                        : vm.isEmpty
                            ? _buildEmptyState('Aún no tienes matches. ¡Busca uno en tu próximo GAP!')
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  _buildSummary(vm),
                                  const SizedBox(height: 16),
                                  _buildChips(vm),
                                  const SizedBox(height: 16),
                                  if (vm.items.isEmpty)
                                    _buildFilterEmpty(vm.filter)
                                  else
                                    ...vm.items.map((item) => _buildMatchCard(vm, item)),
                                ],
                              ),
                  ),
          ),
        ],
      ),
    );
  }

  // Average of the stars received and how many are left to rate
  Widget _buildSummary(MyMatchesViewModel vm) {
    final average = vm.averageReceived;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _buildStat(
              label: 'PROMEDIO RECIBIDO',
              value: average == null ? '—' : average.toStringAsFixed(1),
              color: AppColors.accent2,
              icon: average == null ? null : Icons.star_rounded,
            ),
          ),
          Container(width: 1, height: 44, color: context.palette.contrast.withValues(alpha: 0.08)),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStat(
              label: 'POR CALIFICAR',
              value: '${vm.pendingToRate}',
              color: vm.pendingToRate > 0 ? AppColors.accent1 : context.palette.contrast,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({required String label, required String value, required Color color, IconData? icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
            fontSize: 11,
            letterSpacing: 1,
            color: context.palette.contrast.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              value,
              style: AppFonts.display(weight: FontWeight.w900).copyWith(fontSize: 24, color: color),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, color: color, size: 22),
            ],
          ],
        ),
      ],
    );
  }

  // Chips Por calificar / Calificados / Todos (same look as the match mode selector)
  Widget _buildChips(MyMatchesViewModel vm) {
    const labels = {
      MatchHistoryFilter.toRate: 'Por calificar',
      MatchHistoryFilter.rated: 'Calificados',
      MatchHistoryFilter.all: 'Todos',
    };
    return Row(
      children: labels.entries.map((entry) {
        final selected = vm.filter == entry.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: entry.key == MatchHistoryFilter.all ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => vm.selectFilter(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent1 : context.palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.accent1 : context.palette.contrast.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  entry.value,
                  style: AppFonts.body(weight: selected ? FontWeight.w900 : FontWeight.w600).copyWith(
                    fontSize: 13,
                    color: selected ? Colors.white : context.palette.contrast,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  // Card of one match: who, when, status and the ratings (or the button to rate)
  Widget _buildMatchCard(MyMatchesViewModel vm, MatchHistoryItem item) {
    final other = item.otherUser;
    final pending = vm.isPending(item.matchId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CachedAvatar(url: other?.avatarUrl, name: other?.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      other?.name ?? 'Estudiante',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.display(weight: FontWeight.w800).copyWith(
                        fontSize: 15,
                        color: context.palette.contrast,
                      ),
                    ),
                    if ((other?.career ?? '').isNotEmpty)
                      Text(
                        other!.career,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.body().copyWith(
                          fontSize: 12,
                          color: context.palette.contrast.withValues(alpha: 0.5),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 13, color: AppColors.accent2),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _dateText(item),
                            style: AppFonts.body().copyWith(
                              fontSize: 12,
                              color: context.palette.contrast.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(item.status),
            ],
          ),
          // Not completed: only the status, nothing to rate yet
          if (item.isCompleted) ...[
            const SizedBox(height: 14),
            if (vm.canRateNow(item))
              CustomButton(
                label: 'Calificar',
                small: true,
                onClick: vm.isSubmitting ? null : () => _openRatingSheet(vm, item),
              )
            else if (item.myRating != null)
              _buildRatings(item, pending: pending),
          ],
        ],
      ),
    );
  }

  // My stars, and the stars of the other student (or that they have not rated yet)
  Widget _buildRatings(MatchHistoryItem item, {required bool pending}) {
    final mine = item.myRating!;
    final theirs = item.otherRating;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionLabel('TU CALIFICACIÓN'),
              const Spacer(),
              _stars(mine.stars, AppColors.accent1),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.accent1),
                const SizedBox(width: 4),
                Text(
                  'Pendiente de enviar',
                  style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 12, color: AppColors.accent1),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (theirs != null) ...[
            Row(
              children: [
                _sectionLabel('SU CALIFICACIÓN'),
                const Spacer(),
                _stars(theirs.stars, AppColors.accent2),
              ],
            ),
            if ((theirs.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '"${theirs.comment}"',
                style: AppFonts.body().copyWith(
                  fontSize: 13,
                  color: context.palette.contrast.withValues(alpha: 0.65),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ] else
            Text(
              'Aún no te califica',
              style: AppFonts.body().copyWith(
                fontSize: 12,
                color: context.palette.contrast.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
          fontSize: 10,
          letterSpacing: 1,
          color: context.palette.contrast.withValues(alpha: 0.4),
        ),
      );

  Widget _stars(int stars, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: i < stars ? color : context.palette.contrast.withValues(alpha: 0.2),
          ),
        ),
      );

  // Status of the match in Spanish
  Widget _buildStatusBadge(MatchStatusEnum status) {
    final (text, color) = switch (status) {
      MatchStatusEnum.COMPLETED => ('COMPLETADO', AppColors.accent2),
      MatchStatusEnum.ACCEPTED => ('ACEPTADO', AppColors.accent3),
      MatchStatusEnum.PENDING => ('PENDIENTE', Colors.grey),
      MatchStatusEnum.REJECTED => ('RECHAZADO', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(fontSize: 9, color: color),
      ),
    );
  }

  // "Lun 16 nov · 9:30 – 10:30"
  String _dateText(MatchHistoryItem item) {
    const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final start = item.startTime;
    return '${weekdays[start.weekday - 1]} ${start.day} ${months[start.month - 1]} · '
        '${DisplayFormatters.time(start)} – ${DisplayFormatters.time(item.endTime)}';
  }

  // Shown when the history could not be loaded, with a Retry button
  Widget _buildErrorState(MyMatchesViewModel vm) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(vm.isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                color: AppColors.accent1, size: 48),
            const SizedBox(height: 16),
            Text(
              vm.isOffline ? 'Sin conexión' : 'No pudimos cargar tus matches',
              textAlign: TextAlign.center,
              style: AppFonts.display(weight: FontWeight.w700).copyWith(
                fontSize: 16,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 8),
            Text(vm.error!, textAlign: TextAlign.center, style: AppFonts.body().copyWith(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: vm.pullToRefresh, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  // Shown when the user has no matches at all
  Widget _buildEmptyState(String text) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: context.palette.contrast.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }

  // The selected chip has nothing to show
  Widget _buildFilterEmpty(MatchHistoryFilter filter) {
    final text = switch (filter) {
      MatchHistoryFilter.toRate => 'No tienes matches por calificar.',
      MatchHistoryFilter.rated => 'Aún no has calificado ningún match.',
      MatchHistoryFilter.all => 'Aún no tienes matches.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.star_outline_rounded, size: 56, color: context.palette.contrast.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  // Bottom sheet to rate: 5 stars (required) + optional comment. The draft is kept in Hive.
  Future<void> _openRatingSheet(MyMatchesViewModel vm, MatchHistoryItem item) async {
    final draft = await vm.loadDraft(item.matchId);
    if (!mounted) return;

    final result = await showModalBottomSheet<_RatingInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _RatingSheet(
        name: item.otherUser?.name ?? 'tu match',
        initialStars: draft?.stars ?? 0,
        initialComment: draft?.comment ?? '',
        isOffline: vm.isOffline || !vm.hasConnection,
        onChanged: (stars, comment) => vm.saveDraft(item.matchId, stars, comment),
      ),
    );
    if (result == null || !mounted) return;

    final error = await vm.rate(item.matchId, result.stars, result.comment);
    if (error != null && mounted) _snack(error, ok: false);
  }
}

class _RatingInput {
  final int stars;
  final String comment;
  const _RatingInput(this.stars, this.comment);
}

class _RatingSheet extends StatefulWidget {
  final String name;
  final int initialStars;
  final String initialComment;
  final bool isOffline;
  final void Function(int stars, String comment) onChanged;

  const _RatingSheet({
    required this.name,
    required this.initialStars,
    required this.initialComment,
    required this.isOffline,
    required this.onChanged,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late int _stars = widget.initialStars;
  late final TextEditingController _comment = TextEditingController(text: widget.initialComment);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _setStars(int stars) {
    setState(() => _stars = stars);
    widget.onChanged(_stars, _comment.text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: palette.contrast.withValues(alpha: 0.1), width: 1.5),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.contrast.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Califica tu match con ${widget.name}',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 18, color: palette.contrast),
            ),
            const SizedBox(height: 4),
            Text(
              '¿Cómo te fue en este GAP?',
              style: AppFonts.body().copyWith(fontSize: 13, color: palette.contrast.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return IconButton(
                  onPressed: () => _setStars(i + 1),
                  iconSize: 40,
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? AppColors.accent1 : palette.contrast.withValues(alpha: 0.25),
                  ),
                );
              }),
            ),
            if (_stars == 0)
              Center(
                child: Text(
                  'Elige de 1 a 5 estrellas',
                  style: AppFonts.body(weight: FontWeight.w700).copyWith(
                    fontSize: 12,
                    color: palette.contrast.withValues(alpha: 0.45),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              maxLength: MyMatchesViewModel.maxComment,
              maxLines: 3,
              minLines: 2,
              onChanged: (text) => widget.onChanged(_stars, text),
              style: AppFonts.body().copyWith(fontSize: 14, color: palette.contrast),
              decoration: InputDecoration(
                hintText: 'Comentario (opcional)',
                hintStyle: AppFonts.body().copyWith(color: palette.contrast.withValues(alpha: 0.4)),
                filled: true,
                fillColor: palette.background,
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.accent2, width: 1.5)),
                counterStyle: AppFonts.body().copyWith(fontSize: 11, color: palette.contrast.withValues(alpha: 0.45)),
              ),
            ),
            if (widget.isOffline) ...[
              const SizedBox(height: 6),
              Text(
                'Sin conexión: tu calificación se enviará cuando vuelva el internet',
                style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 12, color: AppColors.accent1),
              ),
            ],
            const SizedBox(height: 14),
            CustomButton(
              label: 'Enviar calificación',
              onClick: _stars == 0 ? null : () => Navigator.pop(context, _RatingInput(_stars, _comment.text)),
            ),
          ],
        ),
      ),
    );
  }
}
