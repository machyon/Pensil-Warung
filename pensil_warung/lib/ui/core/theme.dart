import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppColors {
  static const ink = Color(0xFF1B1B19);
  static const paper = Color(0xFFF3F2F1);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3E3E1);
  static const fieldBorder = Color(0xFFD1D1D0);
  static const muted = Color(0xFF626260);
  static const label = Color(0xFF4F4F4D);
  static const faint = Color(0xFF8C8B89);
  static const chip = Color(0xFFEAE9E8);
  static const disabled = Color(0xFFDEDEDD);
  static const onDisabled = Color(0xFF7C7B79);
  static const avatar = Color(0xFF3A3A38);
  static const accent = Color(0xFFFFC727);
  static const onAccent = Color(0xFF2A2000);
  static const error = Color(0xFFB63325);
  static const errorBg = Color(0xFFF6E7E5);
}

TextStyle appText(double size, {FontWeight weight = FontWeight.w500, Color color = AppColors.ink, double? letterSpacing}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing);

TextStyle monoText(double size, {Color color = AppColors.ink}) =>
    GoogleFonts.robotoMono(fontSize: size, color: color);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.paper,
  );
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    dividerColor: AppColors.border,
  );
}
