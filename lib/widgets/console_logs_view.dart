import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/localization.dart';
import '../services/terminal_sdk_service.dart';

// Optimized separate log console widget to improve performance
class ConsoleLogsView extends StatefulWidget {
  final TerminalSDKService terminalSdk;
  final bool isDarkMode;
  final Color cardBgColor;
  final Color borderColor;
  final Color primaryColor;
  final AppLocale loc;
  final bool embedMode;

  const ConsoleLogsView({
    super.key,
    required this.terminalSdk,
    required this.isDarkMode,
    required this.cardBgColor,
    required this.borderColor,
    required this.primaryColor,
    required this.loc,
    this.embedMode = false,
  });

  @override
  State<ConsoleLogsView> createState() => _ConsoleLogsViewState();
}

class _ConsoleLogsViewState extends State<ConsoleLogsView> {
  final List<String> _logLines = [];
  StreamSubscription? _logSubscription;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _logLines.addAll(widget.terminalSdk.recentLogs);
    _logSubscription = widget.terminalSdk.logs.listen((line) {
      if (mounted) {
        setState(() {
          if (line == '--- LOGS LIMPIADOS ---') {
            _logLines.clear();
          } else {
            _logLines.add(line);
          }
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLogs() {
    widget.terminalSdk.clearLogs();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.terminal, color: widget.primaryColor, size: 14),
            const SizedBox(width: 6),
            Text(
              widget.loc.t('Logs de Eventos'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _logLines.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      widget.loc.t('Logs copiados al portapapeles'),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 12),
              label: Text(
                widget.loc.t('Copiar logs'),
                style: const TextStyle(fontSize: 10),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_outline, size: 12),
              label: Text(
                widget.loc.t('Limpiar'),
                style: const TextStyle(fontSize: 10),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? const Color(0xFF020617)
                  : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: _logLines.length,
              itemBuilder: (context, index) {
                final line = _logLines[index];
                Color textColor = Colors.white.withValues(alpha: 0.9);

                if (line.contains('[ERROR]')) {
                  textColor = const Color(0xFFEF9A9A); // Soft Red
                } else if (line.contains('[SUCCESS]')) {
                  textColor = const Color(0xFFA5D6A7); // Soft Green
                } else if (line.contains('[TX]')) {
                  textColor = const Color(0xFF90CAF9); // Soft Blue
                } else if (line.contains('[RX]')) {
                  textColor = const Color(0xFFCE93D8); // Soft Purple
                } else if (line.contains('[DEBUG]')) {
                  textColor = const Color(0xFFEEEEEE); // Soft Grey
                } else if (line.contains('[INFO]')) {
                  textColor = const Color(
                    0xFFA5D6A7,
                  ); // Soft Green (or same as POLL info)
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    if (widget.embedMode) {
      return body;
    }

    return Card(
      color: widget.cardBgColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.borderColor, width: 1),
      ),
      child: Padding(padding: const EdgeInsets.all(12.0), child: body),
    );
  }
}
