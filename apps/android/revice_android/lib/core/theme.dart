import 'package:flutter/material.dart';

const lime = Color(0xFFB9F35A);
const cyan = Color(0xFF4EDFC3);
const muted = Color(0xFF93A28C);

ThemeData reviceTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF050807),
  colorScheme: const ColorScheme.dark(
    primary: lime,
    secondary: cyan,
    surface: Color(0xFF111914),
    onSurface: Color(0xFFF4F8EE),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF111914),
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFF29372D)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF050807),
    centerTitle: false,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Color(0xFF111914),
    indicatorColor: const Color(0xFF293C20),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? lime : muted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected) ? lime : muted,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
      ),
    ),
  ),
);
