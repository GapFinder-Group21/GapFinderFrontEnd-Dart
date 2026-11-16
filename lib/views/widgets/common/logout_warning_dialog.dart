import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';

// Logout confirm: lists what is removed from the phone, unsent actions first. Returns true to log out.
Future<bool> showLogoutWarningDialog(BuildContext context, LogoutWarning warning) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Cerrar sesión?', style: AppFonts.display(weight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning.hasUnsent)
              _Box(
                color: Colors.red,
                title: 'Sin enviar (se perderá)',
                items: warning.unsent,
                note: warning.isOffline ? 'Estás sin conexión, así que no alcanzará a enviarse.' : null,
              ),
            if (warning.hasUnsent) const SizedBox(height: 12),
            _Box(
              color: AppColors.accent2,
              title: 'Datos guardados para usar sin internet',
              items: warning.savedData,
              note: 'Estos datos vuelven a cargarse cuando inicies sesión con internet.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            warning.hasUnsent ? 'Salir y borrar' : 'Cerrar sesión',
            style: const TextStyle(color: AppColors.accent1),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}

// A colored box with a title, a bullet list and an optional note
class _Box extends StatelessWidget {
  final Color color;
  final String title;
  final List<String> items;
  final String? note;

  const _Box({required this.color, required this.title, required this.items, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 14)),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $item', style: AppFonts.body().copyWith(fontSize: 13)),
            ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: AppFonts.body().copyWith(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
