import 'dart:async';
import 'package:flutter/material.dart';
import 'core/preferences_service.dart';
import 'core/localization.dart';
import 'pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await PreferencesService.load();
  runApp(ISVToolkitApp(prefs: prefs));
}

class ISVToolkitApp extends StatefulWidget {
  final PreferencesService prefs;
  const ISVToolkitApp({super.key, required this.prefs});

  @override
  State<ISVToolkitApp> createState() => _ISVToolkitAppState();
}

class _ISVToolkitAppState extends State<ISVToolkitApp> {
  late String _currentLang;
  late bool _isDarkMode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Restore saved preferences
    _isDarkMode = widget.prefs.isDarkMode;
    _currentLang = widget.prefs.language;
    // Simular carga del sistema
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _toggleTheme() {
    setState(() => _isDarkMode = !_isDarkMode);
    widget.prefs.setDarkMode(_isDarkMode);
  }

  void _changeLang(String lang) {
    setState(() => _currentLang = lang);
    widget.prefs.setLanguage(lang);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ISV Toolkit',
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F9FF),
        colorScheme: ColorScheme.light(
          primary: Colors.blueAccent,
          secondary: Colors.cyan,
          surface: Colors.white,
          onSurface: Colors.blueGrey[900]!,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212), // Anthracite
        colorScheme: ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
          surface: const Color(0xFF1E1E1E), // Slightly lighter surface
          onSurface: Colors.white,
          onPrimary: Colors.black,
          surfaceContainerHighest: const Color(0xFF2C2C2C),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      ),
      home: _isLoading
          ? SplashScreen(isDarkMode: _isDarkMode, currentLang: _currentLang)
          : DashboardPage(
              currentLang: _currentLang,
              isDarkMode: _isDarkMode,
              onThemeToggle: _toggleTheme,
              onLangChange: _changeLang,
            ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  final bool isDarkMode;
  final String currentLang;
  const SplashScreen({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocale.get(currentLang);
    final bgColor = isDarkMode
        ? const Color(0xFF0F0F0F)
        : const Color(0xFFF4F9FF);
    final accentColor = isDarkMode ? Colors.cyanAccent : Colors.blueAccent;

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Container
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 48),
            // Title
            Text(
              'ISV TOOLKIT',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.analysisInitialDesc,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 60),
            // Loading Indicator
            SizedBox(
              width: 200,
              child: Column(
                children: [
                  LinearProgressIndicator(
                    backgroundColor: accentColor.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    borderRadius: BorderRadius.circular(10),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.splashLoading.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
