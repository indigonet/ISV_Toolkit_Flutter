import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/localization.dart';

class AdbBadge extends StatelessWidget {
  final String status;
  final bool isDark;
  final AppLocale loc;
  final VoidCallback onRefresh;
  final List<String> devices;
  final String? currentSerial;
  final Function(String)? onDeviceSelected;

  const AdbBadge({
    super.key,
    required this.status,
    required this.isDark,
    required this.loc,
    required this.onRefresh,
    this.devices = const [],
    this.currentSerial,
    this.onDeviceSelected,
  });

  @override
  Widget build(BuildContext context) {
    bool isConnected = status.contains(loc.statusConnected);
    bool isLoading = status == loc.loading;

    final colorDot = isConnected
        ? Colors.greenAccent
        : (isLoading ? Colors.orangeAccent : Colors.redAccent);

    final colorBorder = isDark
        ? (isConnected
            ? Colors.greenAccent.withValues(alpha: 0.3)
            : (isLoading
                ? Colors.orangeAccent.withValues(alpha: 0.2)
                : Colors.redAccent.withValues(alpha: 0.2)))
        : (isConnected
            ? Colors.green.withValues(alpha: 0.5)
            : (isLoading
                ? Colors.orange.withValues(alpha: 0.5)
                : Colors.red.withValues(alpha: 0.5)));

    return Tooltip(
      message: isConnected ? loc.copySn : loc.connectionStatus,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorBorder, width: 1.5),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: colorDot.withValues(alpha: 0.08),
                    blurRadius: 6,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Part 1: Status & Copy
              InkWell(
                onTap: isConnected
                    ? () {
                        final sn = currentSerial ?? status.split(':').last.trim();
                        Clipboard.setData(ClipboardData(text: sn));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('S/N $sn ${loc.copySuccess}'),
                            behavior: SnackBarBehavior.floating,
                            width: 220,
                          ),
                        );
                      }
                    : null,
                borderRadius: BorderRadius.horizontal(
                  left: const Radius.circular(20),
                  right: Radius.circular(devices.length > 1 ? 0 : 20),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colorDot,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorDot.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isConnected
                            ? "${loc.statusConnected}: ${currentSerial ?? status.split(':').last.trim()}"
                            : status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Part 2: Dropdown Trigger (if multiple devices)
              if (isConnected && devices.length > 1) ...[
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 10,
                  endIndent: 10,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => onDeviceSelected?.call(v),
                  tooltip: loc.selectTerminalTooltip,
                  offset: const Offset(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                    ),
                  ),
                  itemBuilder: (context) {
                    return devices.map((String serial) {
                      bool isSelected = serial == currentSerial;
                      return PopupMenuItem<String>(
                        value: serial,
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone_android_rounded,
                              size: 16,
                              color: isSelected
                                  ? (isDark ? Colors.cyanAccent : Colors.blueAccent)
                                  : (isDark ? Colors.white54 : Colors.black54),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              serial,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (isSelected) ...[
                              const Spacer(),
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
