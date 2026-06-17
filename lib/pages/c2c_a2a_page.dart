import 'dart:io';
import 'package:flutter/material.dart';
import '../core/localization.dart';

class C2CA2APage extends StatelessWidget {
  final AppLocale loc;
  final bool isDarkMode;

  const C2CA2APage({super.key, required this.loc, required this.isDarkMode});

  Future<void> _launchUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.run('powershell', [
          '-Command',
          'Start-Process',
          '"$url"',
        ]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode;
    final accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;
    final cardBgColor = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.blue.withValues(alpha: 0.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.swap_horizontal_circle_outlined,
              color: accentColor,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              loc.t('C2C / A2A'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          loc.t(
            'Enlaces rápidos y recursos de integración para comercios (C2C) y aplicaciones (A2A).',
          ),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card 1: Web Portal Documentation
            Expanded(
              child: _buildLinkCard(
                context: context,
                icon: Icons.language,
                title: loc.t('Simulador Cloud to Cloud'),
                description: loc.t(
                  'Herramienta web para realizar pruebas y validaciones de integraciones Cloud to Cloud (C2C). Permite enviar y recibir transacciones de manera simulada para facilitar el desarrollo y debugging.',
                ),
                url: 'https://front-isv.pages.dev/simulator',
                accentColor: accentColor,
                bgColor: cardBgColor,
                borderColor: borderColor,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 20),
            // Card 2: Google Drive Resources
            Expanded(
              child: _buildLinkCard(
                context: context,
                icon: Icons.cloud_download_outlined,
                title: loc.t('Simulador App to App'),
                description: loc.t(
                  'Simulador que permite realizar pruebas y validaciones de integraciones App to App (A2A). Facilita el envío y recepción de transacciones de manera simulada para el desarrollo y debugging de aplicaciones.',
                ),
                url:
                    'https://drive.google.com/file/d/16855x0iysgDKpDgOiNdWjnEnR4mCEnbG/view?usp=sharing',
                accentColor: accentColor,
                bgColor: cardBgColor,
                borderColor: borderColor,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required String url,
    required Color accentColor,
    required Color bgColor,
    required Color borderColor,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 220,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
