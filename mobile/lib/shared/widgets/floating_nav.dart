import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

class FloatingNavItem {
  const FloatingNavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Dark rounded bottom bar that floats above the content; the active tab opens into a light pill with its label.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onTap});

  final List<FloatingNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bar = AppTheme.dark ? const Color(0xFF232B28) : AppTheme.primaryDark;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bar,
          borderRadius: BorderRadius.circular(34),
          boxShadow: [BoxShadow(color: bar.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              flex: i == index ? 2 : 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != index) HapticFeedback.selectionClick();
                  onTap(i);
                },
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(horizontal: i == index ? 14 : 0, vertical: 10),
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i == index ? items[i].activeIcon : items[i].icon,
                          color: i == index ? AppTheme.primaryDark : Colors.white70, size: 24),
                      if (i == index) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
