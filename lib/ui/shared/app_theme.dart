import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0B131B);
  static const surface = Color(0xFF13212D);
  static const accent = Color(0xFF6CDEFF);
  static const muted = Color(0xFF8FA7B6);
  static const border = Color(0xFF263D4B);
}

ThemeData buildAppTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: 'Segoe UI',
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
      borderRadius: BorderRadius.circular(10),
    ),
    textStyle: const TextStyle(color: Color(0xFFE4F4FA), fontSize: 12, height: 1.4),
    constraints: const BoxConstraints(maxWidth: 280),
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    textAlign: TextAlign.center,
    verticalOffset: 16,
    waitDuration: const Duration(milliseconds: 600),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: const Color(0xFF182B39),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 40),
      padding: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
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
    surfaceContainer: Color(0xFF142532),
    surfaceContainerHigh: Color(0xFF182B39),
    surfaceContainerHighest: Color(0xFF1D3443),
    surfaceTint: AppColors.accent,
    outline: Color(0xFF526F80),
    outlineVariant: AppColors.border,
  ),
  dividerColor: AppColors.border,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),
);
