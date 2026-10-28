import 'package:flutter/material.dart';

/// Stance's `StanceColorTokens` (the ones the app uses).
abstract final class AppColors {
  static const primary = Color(0xFF792EFF);
  static const primaryLight = Color(0xFF9357FF);
  static const primaryVariant = Color(0xFF498AEE);
  static const secondaryPrime = Color(0xFFB557FF);
  static const secondary = Color(0xFF363536);
  static const background = Color(0xFF2C3450);
  static const error = Color(0xFFE85252);
  static const success = Color(0xFF5EBA5C);
  static const amber = Color(0xFFFF9900);
  static const subtitleGray = Color(0xFF8E8E93);
  static const pink = Color(0xFFF415C3);
  static const purple1 = Color(0xFF915EEB);
  static const purple2 = Color(0xFF782EFD);
  static const fourgroundSolid = Color(0xFF201B28);

  /// The near-black `StanceBackground` behind Stance's RPE and edit sheets.
  static const sheetBackground = Color(0xFF101010);

  /// Compose's `Color.Gray`, which Stance uses for secondary labels.
  static const gray = Color(0xFF888888);

  /// Home's `IosCardBackground`: white at 4 %.
  static const cardFill = Color(0x0AFFFFFF);

  /// `cardStroke`: white at 12 %.
  static const cardStroke = Color(0x1FFFFFFF);

  /// `SmallDeviceStatusButton` status dot.
  static const connected = Color(0xFF34C759);
  static const disconnected = Color(0xFFFF3B30);
}

/// Stance's `stanceDarkColorScheme()`. Stance's MainActivity always uses
/// the dark scheme without dynamic colour, so there is no light theme.
const _scheme = ColorScheme(
  brightness: Brightness.dark,
  primary: AppColors.primary,
  onPrimary: Colors.white,
  primaryContainer: AppColors.primaryLight,
  onPrimaryContainer: Color(0xFFE8DDFF),
  inversePrimary: Color(0xFFC4A8FF),
  secondary: AppColors.secondaryPrime,
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFF4A2A5C),
  onSecondaryContainer: Color(0xFFF8E0FF),
  tertiary: AppColors.primaryVariant,
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFF1E3A5C),
  onTertiaryContainer: Color(0xFFD6E8FF),
  surface: Color(0xFF323A56),
  onSurface: Colors.white,
  onSurfaceVariant: Color(0xFFC4C8D4),
  surfaceTint: Color(0x1F792EFF),
  inverseSurface: Color(0xFFE5E7EB),
  onInverseSurface: Color(0xFF1A1C1E),
  error: AppColors.error,
  onError: Colors.white,
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  outline: Color(0xFF9AA0B0),
  outlineVariant: Color(0xFF5C6378),
  scrim: Colors.black,
  surfaceBright: Color(0xFF3F4A6C),
  surfaceDim: Color(0xFF2E3652),
  surfaceContainerLowest: AppColors.background,
  surfaceContainerLow: Color(0xFF2E3652),
  surfaceContainer: Color(0xFF353E5C),
  surfaceContainerHigh: Color(0xFF3A4464),
  surfaceContainerHighest: Color(0xFF3F4A6C),
);

TextStyle _poppins(double size, FontWeight weight, double lineHeight,
        [double letterSpacing = 0]) =>
    TextStyle(
      fontFamily: 'Poppins',
      fontSize: size,
      fontWeight: weight,
      height: lineHeight / size,
      letterSpacing: letterSpacing,
    );

/// Stance's `StanceTypography` (Poppins).
final _textTheme = TextTheme(
  displayLarge: _poppins(64, FontWeight.w600, 72, -0.25),
  displayMedium: _poppins(52, FontWeight.w600, 60),
  displaySmall: _poppins(44, FontWeight.w700, 52),
  headlineLarge: _poppins(40, FontWeight.w700, 48),
  headlineMedium: _poppins(28, FontWeight.w700, 36),
  headlineSmall: _poppins(24, FontWeight.w700, 32),
  titleLarge: _poppins(22, FontWeight.w700, 28),
  titleMedium: _poppins(20, FontWeight.w600, 26),
  titleSmall: _poppins(18, FontWeight.w500, 24),
  bodyLarge: _poppins(16, FontWeight.w500, 24),
  bodyMedium: _poppins(14, FontWeight.w500, 20),
  bodySmall: _poppins(12, FontWeight.w400, 16),
  labelLarge: _poppins(14, FontWeight.w500, 20),
  labelMedium: _poppins(12, FontWeight.w500, 16),
  labelSmall: _poppins(11, FontWeight.w700, 16),
).apply(bodyColor: Colors.white, displayColor: Colors.white);

/// Stance's `StanceShapes`: 4 / 8 / 12 / 16 / 28 dp.
RoundedRectangleBorder _rounded(double r) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

ThemeData appTheme() => ThemeData(
      colorScheme: _scheme,
      fontFamily: 'Poppins',
      textTheme: _textTheme,
      // Compose's Scaffold paints colorScheme.background.
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardFill,
        elevation: 0,
        shape: _rounded(16),
      ),
      dialogTheme: DialogThemeData(shape: _rounded(28)),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _scheme.surfaceContainer,
        shape: _rounded(4),
      ),
      listTileTheme: ListTileThemeData(
        subtitleTextStyle:
            _textTheme.bodyMedium?.copyWith(color: AppColors.subtitleGray),
      ),
    );
