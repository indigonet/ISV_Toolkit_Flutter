import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/preferences_service.dart';
import 'core/localization.dart';
import 'pages/dashboard_page.dart';

const String appVersion = '1.0.4';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1280, 720));
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
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate Navy
        colorScheme: ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
          surface: const Color(0xFF1E293B), // Elevated Slate
          onSurface: Colors.white,
          onPrimary: Colors.black,
          surfaceContainerHighest: const Color(0xFF334155), // Slate border
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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

class SplashScreen extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;
  const SplashScreen({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  int _messageIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final loc = AppLocale.get(widget.currentLang);
    _timer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (mounted) {
        setState(() {
          _messageIndex = (timer.tick) % loc.splashMessages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocale.get(widget.currentLang);
    final bgColor = widget.isDarkMode
        ? const Color(0xFF0F172A)
        : const Color(0xFFF4F9FF);
    final accentColor = widget.isDarkMode
        ? Colors.cyanAccent
        : Colors.blueAccent;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Container
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.05),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                // Title
                Text(
                  'ISV TOOLKIT',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: widget.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loc.appTitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: accentColor.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 70),
                // Loading Indicator & Dynamic Text
                SizedBox(
                  width: 240,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          backgroundColor: accentColor.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor,
                          ),
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          loc.splashMessages[_messageIndex],
                          key: ValueKey<int>(_messageIndex),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            color: widget.isDarkMode
                                ? Colors.white54
                                : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Version at bottom
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'v$appVersion | 2026 iOnetech',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: widget.isDarkMode ? Colors.white12 : Colors.black12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
