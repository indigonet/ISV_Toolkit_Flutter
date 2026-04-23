import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../core/localization.dart';

import '../services/sdk_service.dart';
import '../widgets/sidebar_item.dart';
import '../widgets/adb_badge.dart';
import 'analysis_page.dart';
import 'signing_page.dart';
import 'adb_page.dart';
import 'settings_page.dart';

class DashboardPage extends StatefulWidget {
  final String currentLang;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final Function(String) onLangChange;

  const DashboardPage({
    super.key,
    required this.currentLang,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.onLangChange,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  final SDKService _sdk = SDKService();
  final ValueNotifier<String> _adbStatus = ValueNotifier<String>(
    "Disconnected",
  );
  Timer? _adbTimer;

  AppLocale get _loc => AppLocale.languages[widget.currentLang]!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshAdb();
    _adbTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshAdb(),
    );
    _sdk.autoSearchAllTools();
  }

  @override
  void dispose() {
    _adbTimer?.cancel();
    _adbStatus.dispose();
    _tabController.dispose();
    _sdk.stopProcess();
    super.dispose();
  }

  void _refreshAdb() async {
    final status = await _sdk.getAdbDevices(
      _loc.statusConnected,
      _loc.statusDisconnected,
      _loc.statusError,
    );
    _adbStatus.value = status;
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
      _tabController.index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(isDark),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(isDark),
                Expanded(
                  child: Row(
                    children: [
                      _buildSidebar(isDark),
                      VerticalDivider(
                        width: 1,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      Expanded(child: _buildMainContent()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F7FA),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            width: 36,
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 16),
          Text(
            _loc.appTitle,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _showToolsConfigDialog,
            icon: Icon(
              Icons.handyman_outlined,
              size: 20,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            tooltip: _loc.t('Configuración de Rutas'),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<String>(
            valueListenable: _adbStatus,
            builder: (context, status, _) {
              return AdbBadge(
                status: status,
                isDark: isDark,
                loc: _loc,
                onRefresh: _refreshAdb,
              );
            },
          ),
        ],
      ),
    );
  }

  void _showToolsConfigDialog() {
    final isDark = widget.isDarkMode;
    bool isAutoDetecting = false;
    String? successMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            title: Row(
              children: [
                Text(_loc.configSdk),
                const Spacer(),
                if (isAutoDetecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        isAutoDetecting = true;
                        successMessage = null;
                      });
                      _sdk.autoSearchAllTools().then((_) {
                        if (context.mounted) {
                          setDialogState(() {
                            isAutoDetecting = false;
                            successMessage = _loc.t("Herramientas cargadas");
                          });
                        }
                      });
                    },
                    icon: const Icon(Icons.travel_explore, size: 14),
                    label: Text(
                      _loc.t('AUTO-DETECCIÓN'),
                      style: const TextStyle(fontSize: 10),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    try { await windowManager.focus(); } catch(_) {}
                    String? path = await FilePicker.platform.getDirectoryPath();

                    if (path != null) {
                      _sdk.autoDetectSDK(path);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 14),
                  label: Text(
                    _loc.t('BUSCAR SDK'),
                    style: const TextStyle(fontSize: 10),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (successMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        successMessage!,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  _buildPathField(
                    _loc.t('ADB Path'),
                    _sdk.adbPath,
                    (v) => setState(() => _sdk.adbPath = v),
                  ),
                  _buildPathField(
                    'AAPT Path',
                    _sdk.aaptPath,
                    (v) => setState(() => _sdk.aaptPath = v),
                  ),
                  _buildPathField(
                    'APK Signer Path',
                    _sdk.apksignerPath,
                    (v) => setState(() => _sdk.apksignerPath = v),
                  ),
                  _buildPathField(
                    'Keytool Path',
                    _sdk.keytoolPath,
                    (v) => setState(() => _sdk.keytoolPath = v),
                  ),
                  _buildPathField(
                    'Jarsigner Path',
                    _sdk.jarsignerPath,
                    (v) => setState(() => _sdk.jarsignerPath = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_loc.close),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPathField(
    String label,
    String current,
    Function(String) onSave,
  ) {
    TextEditingController c = TextEditingController(text: current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              try { await windowManager.focus(); } catch(_) {}
              FilePickerResult? r = await FilePicker.platform.pickFiles();

              if (r != null) {
                c.text = r.files.single.path!;
                onSave(c.text);
              }
            },
          ),
        ),
        onSubmitted: onSave,
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SidebarItem(
            icon: Icons.search,
            label: _loc.analyzeApk,
            isSelected: _selectedIndex == 0,
            onTap: () => _onTabSelected(0),
            isDark: isDark,
          ),
          SidebarItem(
            icon: Icons.key_sharp,
            label: _loc.signerSuite,
            isSelected: _selectedIndex == 1,
            onTap: () => _onTabSelected(1),
            isDark: isDark,
          ),
          SidebarItem(
            icon: Icons.pets,
            label: _loc.t('Logcat'),
            isSelected: _selectedIndex == 2,
            onTap: () => _onTabSelected(2),
            isDark: isDark,
          ),
          const Spacer(),
          SidebarItem(
            icon: Icons.settings,
            label: _loc.settings,
            isSelected: _selectedIndex == 3,
            onTap: () => _onTabSelected(3),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ValueListenableBuilder<String>(
        valueListenable: _adbStatus,
        builder: (context, status, _) {
          return IndexedStack(
            index: _selectedIndex,
            children: [
              AnalysisPage(
                loc: _loc,
                isDarkMode: widget.isDarkMode,
                sdk: _sdk,
                adbStatus: status,
              ),
              SigningPage(loc: _loc, isDarkMode: widget.isDarkMode, sdk: _sdk),
              AdbPage(
                loc: _loc,
                isDarkMode: widget.isDarkMode,
                sdk: _sdk,
                adbStatus: status,
              ),
              SettingsPage(
                loc: _loc,
                isDarkMode: widget.isDarkMode,
                currentLang: widget.currentLang,
                onThemeToggle: widget.onThemeToggle,
                onLangChange: widget.onLangChange,
                sdk: _sdk,
              ),
            ],
          );
        },
      ),
    );
  }
}
