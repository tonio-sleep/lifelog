import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';

/// A quiet card with an always-visible header and a body that expands in
/// place. Shared by the finished-day page so every kind of record reads the
/// same way and can be collapsed independently.
class CollapsibleDaySection extends StatelessWidget {
  const CollapsibleDaySection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.subtitle,
    this.count,
    this.action,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final IconData icon;
  final Color color;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final countLabel = count == null || count == 0
        ? null
        : '$count ${count == 1 ? 'item' : 'items'}';
    return QuietCard(
      padding: const EdgeInsets.all(Insets.md),
      child: Semantics(
        button: true,
        expanded: expanded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(Radii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    IconBadge(icon: icon, color: color, size: 36, iconSize: 18),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.titleSmall),
                          if (subtitle != null || countLabel != null)
                            Text(
                              [subtitle, countLabel]
                                  .whereType<String>()
                                  .join(' · '),
                              style: text.bodySmall?.copyWith(
                                color: palette.mutedText,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?action,
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: context.reduceMotion
                          ? Duration.zero
                          : Motion.base,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: palette.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration:
                  context.reduceMotion ? Duration.zero : Motion.base,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: Insets.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}
