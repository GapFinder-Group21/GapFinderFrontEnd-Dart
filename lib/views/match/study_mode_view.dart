import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_mode_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Study mode (settings of the match): while it is on, the user does not appear as a match candidate nor as
/// a nearby friend. It is turned on for a while, for a gap of the week, and the periods can be removed.
class StudyModeView extends StatefulWidget {
  const StudyModeView({super.key});

  @override
  State<StudyModeView> createState() => _StudyModeViewState();
}

class _StudyModeViewState extends State<StudyModeView> {
  late final StudyModeViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<StudyModeViewModel>();
    // Notices can arrive with nobody tapping (a queued period refused by the back): shown as SnackBar
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
    _snack(notice, ok: notice == StudyModeViewModel.queuedNotice);
  }

  void _snack(String text, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: AppFonts.body().copyWith(fontSize: 13, color: Colors.white)),
      backgroundColor: ok ? AppColors.accent2 : AppColors.accent1,
      duration: const Duration(seconds: 4),
    ));
  }

  // Runs an action of the ViewModel and shows its error, if it has one
  Future<void> _run(Future<String?> Function() action) async {
    final error = await action();
    if (error != null && mounted) _snack(error, ok: false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyModeViewModel>();
    final today = vm.todayGaps;
    final later = vm.laterGaps;
    final periods = vm.periods;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: const CustomTopBar(title: 'Modo estudio', showBack: true),
      body: Column(
        children: [
          // What is on screen is what the phone has saved, and the changes wait to be sent
          if (vm.isOffline)
            OfflineBanner(
              message: 'Sin conexión · tus cambios se enviarán cuando vuelva',
              lastUpdated: vm.lastUpdated,
            ),
          Expanded(
            child: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: vm.pullToRefresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (vm.error != null) ...[
                          _buildErrorCard(vm),
                          const SizedBox(height: 16),
                        ],
                        _buildNowCard(vm),
                        const SizedBox(height: 24),
                        _sectionLabel('TUS GAPS DE HOY'),
                        const SizedBox(height: 10),
                        if (today.isEmpty)
                          _emptyText('No tienes más gaps hoy.')
                        else
                          ...today.map((gap) => _buildGapCard(vm, gap)),
                        const SizedBox(height: 14),
                        _sectionLabel('ESTA SEMANA'),
                        const SizedBox(height: 10),
                        if (later.isEmpty)
                          _emptyText('No tienes gaps próximos esta semana.')
                        else
                          ...later.map((gap) => _buildGapCard(vm, gap)),
                        const SizedBox(height: 14),
                        _sectionLabel('PERIODOS DE ESTUDIO'),
                        const SizedBox(height: 10),
                        if (periods.isEmpty)
                          _emptyText('No tienes periodos de estudio activos.')
                        else
                          ...periods.map((period) => _buildPeriodCard(vm, period)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
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

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
          fontSize: 11,
          letterSpacing: 1,
          color: context.palette.contrast.withValues(alpha: 0.4),
        ),
      );

  Widget _emptyText(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: AppFonts.body().copyWith(fontSize: 13, color: context.palette.contrast.withValues(alpha: 0.45)),
        ),
      );

  // The back could not be reached or answered with an error: the saved data stays below
  Widget _buildErrorCard(StudyModeViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent1.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent1.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.accent1, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vm.error!,
              style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 13, color: context.palette.contrast),
            ),
          ),
          TextButton(onPressed: vm.pullToRefresh, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  // The main switch and the duration chips
  Widget _buildNowCard(StudyModeViewModel vm) {
    final studying = vm.isStudyingNow;
    final until = vm.activeUntil;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: AppColors.accent2, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estoy estudiando ahora',
                      style: AppFonts.display(weight: FontWeight.w800).copyWith(
                        fontSize: 16,
                        color: context.palette.contrast,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No apareces en matches ni como amigo cercano mientras estudias',
                      style: AppFonts.body().copyWith(
                        fontSize: 12,
                        color: context.palette.contrast.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: studying,
                activeThumbColor: AppColors.accent2,
                onChanged: (on) => _run(on ? vm.startStudying : vm.stopStudying),
              ),
            ],
          ),
          if (studying && until != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent2.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.accent2, size: 18),
                  const SizedBox(width: 8),
                  // Wrap: on a narrow screen (or with a big system font) "hasta HH:mm" goes to the next
                  // line instead of overflowing
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Termina en ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.body(weight: FontWeight.w700).copyWith(
                                  fontSize: 13,
                                  color: AppColors.accent2,
                                ),
                              ),
                            ),
                            _Countdown(
                              end: until,
                              onEnded: vm.refreshIfExpired,
                              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                fontSize: 14,
                                color: AppColors.accent2,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'hasta ${_hhmm(until)}',
                          style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.accent2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionLabel('DURACIÓN'),
          const SizedBox(height: 8),
          _buildChips(vm),
          if (!vm.canUseGapDuration) ...[
            const SizedBox(height: 6),
            Text(
              '"Hasta que termine el gap" se activa cuando estás en un gap',
              style: AppFonts.body().copyWith(fontSize: 11, color: context.palette.contrast.withValues(alpha: 0.45)),
            ),
          ],
        ],
      ),
    );
  }

  // Chips 30 min / 1 h / Hasta que termine el gap (same look as the chips of "Mis matches", in accent2)
  Widget _buildChips(StudyModeViewModel vm) {
    const flex = {
      StudyDuration.thirtyMinutes: 2,
      StudyDuration.oneHour: 2,
      StudyDuration.untilGapEnds: 4,
    };

    return Row(
      children: StudyDuration.values.map((duration) {
        final selected = vm.selectedDuration == duration;
        final enabled = duration != StudyDuration.untilGapEnds || vm.canUseGapDuration;
        // A chip that cannot be used is faded with the alpha of its colors (no Opacity widget: it would
        // paint the chip in an extra layer)
        final fade = enabled ? 1.0 : 0.4;

        return Expanded(
          flex: flex[duration]!,
          child: Padding(
            padding: EdgeInsets.only(right: duration == StudyDuration.untilGapEnds ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => vm.selectDuration(duration) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent2 : context.palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent2
                        : context.palette.contrast.withValues(alpha: 0.1 * fade),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  duration.label,
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: selected ? FontWeight.w900 : FontWeight.w600).copyWith(
                    fontSize: 13,
                    color: selected ? Colors.white : context.palette.contrast.withValues(alpha: fade),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // A gap of the week with its "Ocultar" switch
  Widget _buildGapCard(StudyModeViewModel vm, Gap gap) {
    final until = vm.hiddenUntil(gap);
    final hidden = until != null;
    final own = vm.hasOwnPeriod(gap);
    // A gap hidden by the study mode of "now" is shown again with the main switch, not with its own
    final canToggle = !hidden || own;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateText(gap),
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 14,
                    color: context.palette.contrast,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 13, color: AppColors.accent2),
                    const SizedBox(width: 4),
                    Text(
                      _minutesText(gap.durationMinutes),
                      style: AppFonts.body().copyWith(
                        fontSize: 12,
                        color: context.palette.contrast.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                if (hidden) ...[
                  const SizedBox(height: 4),
                  Text(
                    own ? 'Oculto hasta ${_hhmm(until)}' : 'Oculto por tu modo estudio activo',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 12, color: AppColors.accent2),
                  ),
                ],
              ],
            ),
          ),
          Text(
            'Ocultar',
            style: AppFonts.body(weight: FontWeight.w700).copyWith(
              fontSize: 12,
              color: context.palette.contrast.withValues(alpha: 0.6),
            ),
          ),
          Switch(
            value: hidden,
            activeThumbColor: AppColors.accent2,
            onChanged: canToggle ? (on) => _run(() => on ? vm.hideGap(gap) : vm.showGap(gap)) : null,
          ),
        ],
      ),
    );
  }

  // A study period (going on now, or later) with its "Quitar" button
  Widget _buildPeriodCard(StudyModeViewModel vm, StudyPeriod period) {
    final now = DateTime.now();
    final active = period.isActiveAt(now);
    final pending = vm.isPending(period);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap: the "Pendiente de enviar" tag goes to the next line if there is no room for it
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statusBadge(active ? 'AHORA' : 'PROGRAMADO', active ? AppColors.accent2 : AppColors.accent3),
              if (pending)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 14, color: AppColors.accent1),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Pendiente de enviar',
                        style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 12, color: AppColors.accent1),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _periodText(period, now),
            style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 15, color: context.palette.contrast),
          ),
          if (active) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Termina en ',
                  style: AppFonts.body().copyWith(
                    fontSize: 12,
                    color: context.palette.contrast.withValues(alpha: 0.5),
                  ),
                ),
                _Countdown(
                  end: period.endTime,
                  onEnded: vm.refreshIfExpired,
                  style: AppFonts.body(weight: FontWeight.w800).copyWith(fontSize: 12, color: AppColors.accent2),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          CustomButton(
            label: 'Quitar',
            small: true,
            outline: true,
            onClick: () => _run(() => vm.removePeriod(period)),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
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

  // HH:mm (24 hours, the same format as the banner of the Match tab)
  String _hhmm(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  // "Lun 23 nov · 09:30 – 10:30"
  String _dateText(Gap gap) {
    return '${_dayText(gap.startTime)} · ${_hhmm(gap.startTime)} – ${_hhmm(gap.endTime)}';
  }

  // "Lun 23 nov"
  String _dayText(DateTime date) {
    const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  // "09:30 – 10:30" (with the day when it is not today)
  String _periodText(StudyPeriod period, DateTime now) {
    final sameDay = period.startTime.year == now.year &&
        period.startTime.month == now.month &&
        period.startTime.day == now.day;
    final range = '${_hhmm(period.startTime)} – ${_hhmm(period.endTime)}';
    return sameDay ? range : '${_dayText(period.startTime)} · $range';
  }

  // "1 h 30 min" / "45 min"
  String _minutesText(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }
}

/// Countdown to the end of a study period (for example "24:10"). It is only UI: a Timer that repaints this
/// text every second, not a multithreading strategy. When it reaches zero it tells the ViewModel, which
/// reads the periods again (the real expiry comes from the cache, see StudyPeriodsCache).
class _Countdown extends StatefulWidget {
  final DateTime end;
  final TextStyle style;
  final Future<void> Function() onEnded;

  const _Countdown({required this.end, required this.style, required this.onEnded});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  late Duration _left = _remaining();

  Duration _remaining() {
    final left = widget.end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(_Countdown old) {
    super.didUpdateWidget(old);
    if (old.end != widget.end) _left = _remaining();
  }

  void _tick() {
    if (!mounted) return;
    final left = _remaining();
    setState(() => _left = left);
    if (left == Duration.zero) {
      _timer?.cancel();
      widget.onEnded();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _left.inHours;
    final m = (_left.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return Text(h > 0 ? '$h:$m:$s' : '$m:$s', style: widget.style);
  }
}
