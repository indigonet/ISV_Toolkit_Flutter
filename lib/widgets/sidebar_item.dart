import 'package:flutter/material.dart';

class SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isDark ? Colors.cyanAccent : Colors.blueAccent;
    final baseColor = widget.isDark ? Colors.white24 : Colors.black26;
    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.6);

    return InkWell(
      onTap: widget.onTap,
      onHover: (hovering) => setState(() => _isHovered = hovering),
      hoverColor: Colors.transparent, // Disable default InkWell hover
      splashColor: primaryColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? primaryColor.withValues(alpha: 0.08)
              : (_isHovered
                    ? primaryColor.withValues(alpha: 0.02)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? primaryColor.withValues(alpha: 0.15)
                : (_isHovered
                      ? primaryColor.withValues(alpha: 0.05)
                      : Colors.transparent),
          ),
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: widget.isSelected
                  ? primaryColor
                  : (_isHovered ? hoverColor : baseColor),
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                color: widget.isSelected
                    ? primaryColor
                    : (_isHovered ? hoverColor : baseColor),
                fontWeight: widget.isSelected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
