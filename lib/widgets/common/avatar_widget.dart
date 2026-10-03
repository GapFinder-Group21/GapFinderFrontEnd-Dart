import 'package:flutter/material.dart';
import '../../core/api_config.dart';
import '../../core/app_colors.dart';

class AvatarWidget extends StatelessWidget {
  final String? url;
  // Si no hay foto (o no carga) se muestra la inicial de este nombre
  final String? name;
  final double size;
  final BoxBorder? border;

  const AvatarWidget({
    super.key,
    this.url,
    this.name,
    this.size = 48,
    this.border,
  });

  static const _initialColors = [
    AppColors.accent1,
    AppColors.accent2,
    AppColors.accent3,
    AppColors.contrast,
  ];

  // Acepta URLs completas (https://...) y rutas del back (/uploads/foto.jpg)
  static String? resolveUrl(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty || value == 'null') return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return '${ApiConfig.baseUrl}${value.startsWith('/') ? '' : '/'}$value';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveUrl(url);
    final fallback = _buildFallback();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border ?? Border.all(color: AppColors.contrast.withOpacity(0.12), width: 2),
        color: AppColors.background,
      ),
      clipBehavior: Clip.antiAlias,
      child: resolved == null
          ? fallback
          : Image.network(
              resolved,
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Si la URL no carga (404, sin internet), se muestra la inicial en vez de un círculo vacío
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
            ),
    );
  }

  // Inicial del nombre sobre un color fijo por persona; sin nombre, el ícono de persona
  Widget _buildFallback() {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      return Icon(
        Icons.person_rounded,
        size: size * 0.6,
        color: AppColors.contrast.withOpacity(0.3),
      );
    }

    // Suma de los caracteres: la misma persona siempre queda con el mismo color
    final seed = trimmed.codeUnits.fold<int>(0, (sum, c) => sum + c);
    final color = _initialColors[seed % _initialColors.length];
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        trimmed.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
