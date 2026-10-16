import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0A0E11);
  static const surface = Color(0xFF12181C);
  static const surface2 = Color(0xFF0D1215);
  static const line = Color(0xFF1A242B);
  static const track = Color(0xFF1A242B);
  static const text = Color(0xFFE9F2F3);
  static const textSoft = Color(0xFFB9C7CD);
  static const muted = Color(0xFF8C9DA6);
  static const faint = Color(0xFF6F8089);
  static const accent = Color(0xFF2DE1D3);
  static const accentDim = Color(0xFF0F2B2A);
  static const amber = Color(0xFFFFB54A);
  static const red = Color(0xFFFF7A6B);
}

const numFont = 'ChakraPetch';

TextStyle numStyle(double size, {Color color = C.text, FontWeight weight = FontWeight.w600}) =>
    TextStyle(fontFamily: numFont, fontSize: size, fontWeight: weight, color: color, height: 1.1);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: C.accent,
      onPrimary: C.bg,
      secondary: C.accent,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, foregroundColor: C.text, elevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface2,
      indicatorColor: C.accentDim,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? C.accent : C.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.accent : C.muted)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.bg : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.line),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.surface, contentTextStyle: TextStyle(color: C.text)),
  );
}
