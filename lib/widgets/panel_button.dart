import 'package:flutter/material.dart';

class PanelBtnCompact extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  final Color color;
  final String? tooltip;
  final bool isHighContrast;

  const PanelBtnCompact({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.color,
    this.tooltip,
    this.isHighContrast = false,
  });

  @override
  State<PanelBtnCompact> createState() => _PanelBtnCompactState();
}

class _PanelBtnCompactState extends State<PanelBtnCompact> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Colores base
    final Color textColor = widget.isHighContrast 
        ? (isEnabled ? Colors.black : Colors.grey.shade500) 
        : (isEnabled ? widget.color : (isDark ? Colors.white24 : Colors.grey.shade400));
    
    final Color borderColor = widget.isHighContrast 
        ? (isEnabled ? Colors.black : Colors.grey.shade300)
        : (isEnabled 
            ? widget.color.withValues(alpha: _isHovered ? 0.6 : 0.3) 
            : (isDark ? Colors.white10 : Colors.grey.shade200));

    final Color bgColor = widget.isHighContrast 
        ? Colors.white 
        : (isEnabled 
            ? widget.color.withValues(alpha: _isHovered ? 0.15 : 0.08)
            : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isEnabled ? 1.0 : 0.5,
        child: Tooltip(
          message: widget.tooltip ?? '',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: _isHovered && isEnabled
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(10),
                splashColor: widget.color.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 14, color: textColor),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700, 
                          fontSize: 10,
                          color: textColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
