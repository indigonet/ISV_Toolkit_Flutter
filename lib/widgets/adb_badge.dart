import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/localization.dart';

class AdbBadge extends StatelessWidget {
  final String status;
  final bool isDark;
  final AppLocale loc;
  final VoidCallback onRefresh;

  const AdbBadge({
    super.key,
    required this.status,
    required this.isDark,
    required this.loc,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    bool isConnected = status.contains(loc.statusConnected);
    return Tooltip(
      message: isConnected ? loc.copySn : loc.connectionStatus,
      child: InkWell(
        onTap: isConnected ? () {
          final sn = status.split(':').last.trim();
          Clipboard.setData(ClipboardData(text: sn));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('S/N $sn ${loc.copySuccess}'),
            behavior: SnackBarBehavior.floating, 
            width: 220
          ));
        } : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark 
                ? (isConnected ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.2)) 
                : (isConnected ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5)),
              width: 1,
            ),
            boxShadow: isDark ? [] : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isConnected ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle, 
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                status, 
                style: TextStyle(
                  fontSize: 11, 
                  fontWeight: FontWeight.w600, 
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                )
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: InkWell(
                  onTap: onRefresh, 
                  child: Icon(
                    Icons.refresh, 
                    size: 14, 
                    color: isDark ? Colors.cyanAccent : Colors.blueAccent
                  )
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
