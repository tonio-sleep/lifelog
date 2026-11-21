import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Surfaces archive failures that used to be stored but never shown. A failed
/// disk write still updates memory, so the person must be told that changes are
/// not durable until the problem is fixed.
class AppStatusBanner extends ConsumerStatefulWidget {
  const AppStatusBanner({super.key});

  @override
  ConsumerState<AppStatusBanner> createState() => _AppStatusBannerState();
}

class _AppStatusBannerState extends ConsumerState<AppStatusBanner> {
  final Set<String> _dismissed = <String>{};

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);
    final saveStatus = ref.watch(archiveSaveStatusProvider);
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;

    final messages = <({String key, String text, Color color})>[
      if (saveStatus.error != null &&
          saveStatus.error!.trim().isNotEmpty &&
          !_dismissed.contains('save'))
        (
          key: 'save',
          text: 'Changes are not saved to disk: ${saveStatus.error}',
          color: scheme.error,
        ),
      for (final warning in services.startupWarnings)
        if (warning.trim().isNotEmpty && !_dismissed.contains(warning))
          (
            key: warning,
            text: warning,
            color: Colors.amber.shade800,
          ),
    ];

    if (messages.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in messages)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
            decoration: BoxDecoration(
              color: message.color.withValues(alpha: 0.14),
              border: Border(
                bottom: BorderSide(color: message.color.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  size: 17,
                  color: message.color,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.mutedText,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _dismissed.add(message.key)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
