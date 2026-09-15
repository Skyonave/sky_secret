import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF10151C);
  static const surface = Color(0xFF181F29);
  static const accent = Color(0xFF79C9EB);
  static const muted = Color(0xFF9AA8B8);
  static const border = Color(0xFF2C3644);
}

ThemeData buildAppTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: 'Segoe UI',
  visualDensity: VisualDensity.standard,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 13, height: 1.4),
    bodyMedium: TextStyle(fontSize: 13, height: 1.35),
    bodySmall: TextStyle(fontSize: 12, height: 1.35),
    labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12),
    labelSmall: TextStyle(fontSize: 11),
    titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  ),
  inputDecorationTheme: InputDecorationThemeData(
    isDense: true,
    filled: true,
    fillColor: AppColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    hintStyle: const TextStyle(fontSize: 12, color: AppColors.muted),
    labelStyle: const TextStyle(fontSize: 12, color: AppColors.muted),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.accent),
    ),
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: AppColors.border),
    ),
    titleTextStyle: const TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFFE4F4FA),
    ),
  ),
  scrollbarTheme: const ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(6),
    radius: Radius.circular(3),
    thumbColor: WidgetStatePropertyAll(Color(0xFF506074)),
  ),
  scaffoldBackgroundColor: AppColors.background,
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: AppColors.accent.withValues(alpha: 0.06),
  hoverColor: AppColors.accent.withValues(alpha: 0.05),
  focusColor: AppColors.accent.withValues(alpha: 0.10),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: const Color(0xFF182B39),
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    textStyle: const TextStyle(color: Color(0xFFE4F4FA), fontSize: 12, height: 1.4),
    constraints: const BoxConstraints(maxWidth: 280),
    margin: EdgeInsets.zero,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    textAlign: TextAlign.left,
    verticalOffset: 16,
    waitDuration: const Duration(milliseconds: 600),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: const Color(0xFF182B39),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    textStyle: const TextStyle(fontFamily: 'Segoe UI', fontSize: 12, color: Color(0xFFE4F4FA)),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(32, 32),
      padding: const EdgeInsets.all(7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      hoverColor: AppColors.accent.withValues(alpha: 0.06),
      focusColor: AppColors.accent.withValues(alpha: 0.12),
      highlightColor: AppColors.accent.withValues(alpha: 0.10),
    ),
  ),
  colorScheme: const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF062633),
    primaryContainer: Color(0xFF174459),
    onPrimaryContainer: Color(0xFFB8EFFF),
    secondary: Color(0xFF84DBFF),
    onSecondary: Color(0xFF062633),
    secondaryContainer: Color(0xFF163E52),
    onSecondaryContainer: Color(0xFFA5EAFF),
    tertiary: Color(0xFFB1EFFF),
    onTertiary: Color(0xFF062633),
    surface: AppColors.surface,
    onSurface: Color(0xFFE4F4FA),
    onSurfaceVariant: AppColors.muted,
    surfaceContainer: Color(0xFF181F29),
    surfaceContainerHigh: Color(0xFF202A37),
    surfaceContainerHighest: Color(0xFF293747),
    surfaceTint: AppColors.accent,
    outline: Color(0xFF526F80),
    outlineVariant: AppColors.border,
  ),
  dividerColor: AppColors.border,
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(fontFamily: 'Segoe UI', fontSize: 12, fontWeight: FontWeight.w500),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(fontFamily: 'Segoe UI', fontSize: 12, fontWeight: FontWeight.w500),
    ),
  ),
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    side: const BorderSide(color: AppColors.muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(fontFamily: 'Segoe UI', fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ),
);
