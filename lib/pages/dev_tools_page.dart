import 'package:flutter/material.dart';
import '../core/localization.dart';
import '../services/sdk_service.dart';
import '../widgets/panel_button.dart';

class DevToolsPage extends StatelessWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final SDKService sdk;

  const DevToolsPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.devTools, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.cyanAccent : Colors.blueAccent)),
        const SizedBox(height: 20),
        Row(
          children: [
            PanelBtnCompact(
              onPressed: () => sdk.runCommand(sdk.flutterPath, ['run', '-d', 'windows']),
              label: loc.debugRun, icon: Icons.play_arrow, color: Colors.greenAccent,
            ),
            const SizedBox(width: 12),
            PanelBtnCompact(
              onPressed: () => sdk.runCommand(sdk.flutterPath, ['build', 'windows', '--release']),
              label: loc.releaseBuild, icon: Icons.rocket_launch, color: Colors.cyanAccent,
            ),
          ],
        ),
      ],
    );
  }
}
