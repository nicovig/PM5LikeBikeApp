import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pm5_bike/features/home_shell.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class Pm5App extends StatelessWidget {
  const Pm5App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PM5 Bike',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Pm5Colors.background,
        colorScheme: const ColorScheme.dark(
          surface: Pm5Colors.background,
          primary: Pm5Colors.text,
          onPrimary: Pm5Colors.background,
          secondary: Pm5Colors.muted,
          error: Pm5Colors.warning,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF0C0C0C),
          indicatorColor: Color(0xFF2C2C2C),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1C1C1C),
          contentTextStyle: TextStyle(color: Pm5Colors.text),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Pm5Colors.panel,
          labelStyle: TextStyle(color: Pm5Colors.muted),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Pm5Colors.line),
          ),
        ),
        dividerColor: Pm5Colors.line,
      ),
      home: const HomeShell(),
    );
  }
}
