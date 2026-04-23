import 'package:flutter/material.dart';
import '../core/localization.dart';
import '../services/sdk_service.dart';

class SettingsPage extends StatelessWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final String currentLang;
  final VoidCallback onThemeToggle;
  final Function(String) onLangChange;
  final SDKService sdk;

  const SettingsPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.currentLang,
    required this.onThemeToggle,
    required this.onLangChange,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.settings,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.cyanAccent : Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsSection(loc.language, [
            DropdownButton<String>(
              value: currentLang,
              dropdownColor: isDark ? Colors.grey[900] : Colors.white,
              items: [
                DropdownMenuItem(value: 'es', child: Text(loc.t('Español'))),
                DropdownMenuItem(value: 'en', child: Text(loc.t('English'))),
                DropdownMenuItem(value: 'pt', child: Text(loc.t('Português'))),
              ],
              onChanged: (v) {
                if (v != null) onLangChange(v);
              },
            ),
          ]),
          _buildSettingsSection(loc.theme, [
            Row(
              children: [
                Text(isDarkMode ? loc.darkMode : loc.lightMode),
                const SizedBox(width: 8),
                Switch(
                  activeThumbColor: isDarkMode
                      ? Colors.cyanAccent
                      : Colors.blueAccent,
                  activeTrackColor:
                      (isDarkMode ? Colors.cyanAccent : Colors.blueAccent)
                          .withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
                  value: isDarkMode,
                  onChanged: (_) => onThemeToggle(),
                ),
              ],
            ),
          ]),
          _buildSettingsSection(loc.t("Herramientas de Terminal"), [
            Row(
              children: [
                Tooltip(
                  message: loc.t("Reiniciar Terminal"),
                  child: InkWell(
                    onTap: () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(loc.t('Confirmar Reinicio')),
                          content: Text(
                            loc.t(
                              '¿Estás seguro de que deseas reiniciar el POS vinculado por ADB?',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(loc.t('CANCELAR')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                loc.t('REINICIAR'),
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        final code = await sdk.reboot();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                code == 0
                                    ? loc.t("Comando de reinicio enviado")
                                    : loc.t(
                                        "Error al intentar reiniciar el terminal",
                                      ),
                              ),
                              backgroundColor: code == 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.cyanAccent : Colors.blueAccent)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              (isDark ? Colors.cyanAccent : Colors.blueAccent)
                                  .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  loc.t("Reiniciar POS conectado por ADB"),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          Text(
            loc.about,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildAboutContent(),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAboutContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ISV TOOLKIT',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text('${loc.version} 1.0.1'),
        const SizedBox(height: 8),
        Text(loc.developedBy),
        const SizedBox(height: 16),
        const Text(''),
      ],
    );
  }
}
