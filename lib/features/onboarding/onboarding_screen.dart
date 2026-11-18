import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../domain/models/settings.dart';
import '../security/pin_dialogs.dart';
import '../settings/google_drive_actions.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.lg,
                Insets.xl,
                0,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Text(
                    'Lifelog',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_page + 1} / $_pagesInitialised',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: LifelogPalette.of(context).mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _page = index),
                children: [
                  _PageFrame(
                    wide: wide,
                    illustration: const _SignInArt(),
                    eyebrow: 'Welcome',
                    title: 'Sign up, log in, or continue',
                    body:
                        'Create or connect your Google account to sync and restore your data across devices, '
                        'or continue without an account to keep everything saved locally on this device.',
                    children: [
                      _SignInChoiceCard(
                        icon: Icons.account_circle_outlined,
                        title: 'Sign up / Log in with Google',
                        subtitle: 'Securely sync and retrieve your encrypted backup with Google Drive',
                        primary: true,
                        onTap: () async {
                          await connectGoogleDrive(context, ref);
                          if (!context.mounted) return;
                          _pages.nextPage(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                      const SizedBox(height: Insets.md),
                      _SignInChoiceCard(
                        icon: Icons.phone_iphone_rounded,
                        title: 'Continue without signing in',
                        subtitle: 'No account needed. Everything is saved locally on this device (you can connect Google later).',
                        onTap: () => _pages.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ],
                  ),
                  _PageFrame(
                    wide: wide,
                    illustration: _WelcomeArt(),
                    eyebrow: 'Private by default',
                    title: 'A quiet place for your life',
                    body:
                        'Lifelog is a local-first journal, tracker, timeline '
                        'and memory archive. Everything you write or record is '
                        'encrypted on this device.',
                    children: [
                      const _FactRow(
                        icon: Icons.lock_outline_rounded,
                        text:
                            'Your archive is encrypted at rest with AES-256-GCM.',
                      ),
                      const _FactRow(
                        icon: Icons.cloud_off_outlined,
                        text: 'No account, no analytics, no cloud sync.',
                      ),
                      const _FactRow(
                        icon: Icons.touch_app_outlined,
                        text:
                            'Nothing is recorded unless you explicitly add it.',
                      ),
                    ],
                  ),
                  _PageFrame(
                    wide: wide,
                    illustration: const _FeaturesArt(),
                    eyebrow: 'What you can keep',
                    title: 'Small records, a longer story',
                    body:
                        'Each feature is independent. Use one, use all, or '
                        'leave the rest quiet.',
                    children: const [
                      _FeatureGrid(),
                    ],
                  ),
                  _PageFrame(
                    wide: wide,
                    illustration: const _PrivacyArt(),
                    eyebrow: 'The honest privacy model',
                    title: 'Protected, with limits stated',
                    body:
                        'Lifelog can make strong claims about what it stores '
                        'and what it sends. It cannot make claims it cannot '
                        'keep.',
                    children: const [
                      _FactRow(
                        icon: Icons.enhanced_encryption_outlined,
                        text:
                            'The whole structured archive is encrypted, not '
                            'only individual fields.',
                      ),
                      _FactRow(
                        icon: Icons.key_outlined,
                        text:
                            'The key lives in platform secure storage, with a '
                            'documented local-file fallback.',
                      ),
                      _FactRow(
                        icon: Icons.gps_off_rounded,
                        text:
                            'No background location tracking. Visits are '
                            'manual.',
                      ),
                      _FactRow(
                        icon: Icons.travel_explore_outlined,
                        text:
                            'The map is schematic: no tiles, no coordinates '
                            'sent to a provider.',
                      ),
                      _FactRow(
                        icon: Icons.graphic_eq_rounded,
                        text:
                            'Last.fm is optional, read-only and uses your own '
                            'API key.',
                      ),
                    ],
                  ),
                  _PageFrame(
                    wide: wide,
                    illustration: const _SetupArt(),
                    eyebrow: 'Make it yours',
                    title: 'A few choices before you begin',
                    body:
                        'You can change all of this later in Settings. None of '
                        'it sends anything anywhere.',
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: Insets.sm),
                      ChoicePills<AppThemeMode>(
                        values: AppThemeMode.values,
                        selected: settings.themeMode,
                        labelFor: (value) => value.label,
                        onChanged: (value) => guard(
                          context,
                          ref
                              .read(settingsProvider.notifier)
                              .setThemeMode(value),
                          errorPrefix: 'Could not save theme',
                        ),
                      ),
                      const SizedBox(height: Insets.lg),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.weekStartsMonday,
                        onChanged: (value) => guard(
                          context,
                          ref
                              .read(settingsProvider.notifier)
                              .setWeekStartsMonday(value),
                          errorPrefix: 'Could not save calendar preference',
                        ),
                        title: const Text('Week starts on Monday'),
                        subtitle: const Text(
                          'Used by the calendar and weekday labels.',
                        ),
                      ),
                      const Divider(height: Insets.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settings.lockEnabled
                                      ? 'PIN lock is on'
                                      : 'Optional PIN lock',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  settings.lockEnabled
                                      ? 'You can change or remove it in Settings.'
                                      : 'Add a privacy screen for when you step '
                                            'away. The archive is encrypted '
                                            'either way.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: LifelogPalette.of(
                                          context,
                                        ).mutedText,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Insets.md),
                          OutlinedButton(
                            onPressed: settings.lockEnabled
                                ? null
                                : () => _setPin(context),
                            child: Text(
                              settings.lockEnabled ? 'PIN set' : 'Set PIN',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Insets.lg),
                      QuietCard(
                        padding: const EdgeInsets.all(Insets.md),
                        color: LifelogPalette.of(
                          context,
                        ).subtle.withValues(alpha: 0.7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 17,
                              color: LifelogPalette.of(context).mutedText,
                            ),
                            const SizedBox(width: Insets.sm),
                            Expanded(
                              child: Text(
                                'You can import a Last.fm history or restore a '
                                'backup later. Lifelog starts empty and stays '
                                'empty until you add something.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: LifelogPalette.of(
                                        context,
                                      ).mutedText,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Row(
                  children: [
                    if (_page > 0)
                      TextButton.icon(
                        onPressed: _page == 0
                            ? null
                            : () => _pages.previousPage(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                              ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        label: const Text('Back'),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        for (var index = 0; index < _pagesInitialised; index++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 6),
                            width: index == _page ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: index == _page
                                  ? Theme.of(context).colorScheme.primary
                                  : LifelogPalette.of(context).border,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: Insets.xl),
                    if (_page != 0)
                      FilledButton.icon(
                        onPressed: _finishing ? null : _advance,
                        icon: Icon(
                          _page == _pagesInitialised - 1
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 17,
                        ),
                        label: Text(
                          _page == _pagesInitialised - 1 ? 'Begin' : 'Continue',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _pagesInitialised = 5;

  Future<void> _advance() async {
    if (_page < _pagesInitialised - 1) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _finishing = true);
    await guard(
      context,
      ref.read(settingsProvider.notifier).completeOnboarding(),
      errorPrefix: 'Could not finish onboarding',
    );
    if (mounted) setState(() => _finishing = false);
  }

  Future<void> _setPin(BuildContext context) async {
    final pin = await askCreatePin(context);
    if (pin == null) return;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).setPin(pin),
      errorPrefix: 'Could not set the PIN',
    );
    if (context.mounted) showSnack(context, 'PIN set.');
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.wide,
    required this.illustration,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.children,
  });

  final bool wide;
  final Widget illustration;
  final String eyebrow;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.xl,
        Insets.xl,
        Insets.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.mutedText,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Text(title, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: Insets.md),
            Text(
              body,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: palette.mutedText),
            ),
            const SizedBox(height: Insets.xl),
            ...children,
          ],
        ),
      ),
    );

    if (!wide) {
      return Column(
        children: [
          Expanded(child: content),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 5, child: content),
        Expanded(flex: 4, child: Center(child: illustration)),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 32, iconSize: 16),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.mutedText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const _features = <({IconData icon, String title, String body})>[
    (
      icon: Icons.menu_book_outlined,
      title: 'Journal',
      body: 'Free-form entries, moods, tags and encrypted attachments.',
    ),
    (
      icon: Icons.tune_rounded,
      title: 'Trackers',
      body: 'Yes/no, counts, numbers, duration, ratings and notes.',
    ),
    (
      icon: Icons.timeline_rounded,
      title: 'Timeline',
      body: 'Journal, tracker, place, music and photo records in order.',
    ),
    (
      icon: Icons.photo_library_outlined,
      title: 'Photos',
      body: 'Encrypted originals and thumbnails with captions and tags.',
    ),
    (
      icon: Icons.place_outlined,
      title: 'Places',
      body: 'Manual visits and saved places on a private schematic map.',
    ),
    (
      icon: Icons.graphic_eq_rounded,
      title: 'Music',
      body: 'Optional Last.fm import or manual listening records.',
    ),
    (
      icon: Icons.calendar_month_outlined,
      title: 'Memories',
      body: 'A calendar with real activity and on-this-day records.',
    ),
    (
      icon: Icons.insights_outlined,
      title: 'Insights',
      body: 'Counts and trends derived only from stored records.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 480 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * Insets.md) /
            columns;
        return Wrap(
          spacing: Insets.md,
          runSpacing: Insets.md,
          children: [
            for (final feature in _features)
              SizedBox(
                width: width,
                child: QuietCard(
                  padding: const EdgeInsets.all(Insets.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(
                        icon: feature.icon,
                        size: 32,
                        iconSize: 16,
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feature.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              feature.body,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: LifelogPalette.of(
                                      context,
                                    ).mutedText,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IllustrationFrame extends StatelessWidget {
  const _IllustrationFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Center(child: child),
    );
  }
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _IllustrationFrame(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.07),
            ),
          ),
          Icon(
            Icons.auto_stories_outlined,
            size: 92,
            color: scheme.primary.withValues(alpha: 0.7),
          ),
          Positioned(
            bottom: 52,
            right: 56,
            child: Icon(
              Icons.lock_outline_rounded,
              size: 30,
              color: scheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesArt extends StatelessWidget {
  const _FeaturesArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const icons = [
      Icons.menu_book_outlined,
      Icons.tune_rounded,
      Icons.photo_outlined,
      Icons.place_outlined,
      Icons.graphic_eq_rounded,
      Icons.calendar_month_outlined,
      Icons.insights_outlined,
      Icons.timeline_rounded,
      Icons.search_rounded,
    ];
    return _IllustrationFrame(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          for (final icon in icons)
            IconBadge(icon: icon, size: 52, iconSize: 23, color: scheme.primary),
        ],
      ),
    );
  }
}

class _PrivacyArt extends StatelessWidget {
  const _PrivacyArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _IllustrationFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 96,
            color: scheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(height: Insets.md),
          Text(
            'AES-256-GCM',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Argon2id backups',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.secondary),
          ),
        ],
      ),
    );
  }
}

class _SetupArt extends StatelessWidget {
  const _SetupArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _IllustrationFrame(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.tune_rounded,
            size: 92,
            color: scheme.primary.withValues(alpha: 0.7),
          ),
          Positioned(
            top: 58,
            right: 66,
            child: Icon(Icons.pin_outlined, size: 28, color: scheme.secondary),
          ),
          Positioned(
            bottom: 58,
            left: 66,
            child: Icon(
              Icons.dark_mode_outlined,
              size: 26,
              color: scheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInArt extends StatelessWidget {
  const _SignInArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _IllustrationFrame(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.07),
            ),
          ),
          Icon(
            Icons.cloud_sync_outlined,
            size: 88,
            color: scheme.primary.withValues(alpha: 0.75),
          ),
          Positioned(
            bottom: 54,
            right: 58,
            child: Icon(
              Icons.account_circle_rounded,
              size: 34,
              color: scheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInChoiceCard extends StatelessWidget {
  const _SignInChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bg = primary ? scheme.primary.withValues(alpha: 0.08) : palette.subtle.withValues(alpha: 0.5);
    final border = primary ? scheme.primary.withValues(alpha: 0.25) : palette.border;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Insets.lg),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            IconBadge(icon: icon, size: 40, iconSize: 20, color: primary ? scheme.primary : null),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.dimText),
          ],
        ),
      ),
    );
  }
}
