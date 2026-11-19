import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../domain/models/settings.dart';
import '../security/pin_dialogs.dart';
import '../settings/cloudflare_sync_actions.dart';

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
                    eyebrow: 'Account required',
                    title: 'Sign in to continue',
                    body:
                        'A Cloudflare sync account is required to use Lifelog. '
                        'Sign in or create an account to continue. Your journal stays on this device and encrypted; cloud sync stores encrypted backups only.',
                    children: [
                      if (settings.cloudflareConnected)
                        QuietCard(
                          padding: const EdgeInsets.all(Insets.md),
                          child: Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: Insets.sm),
                              Expanded(
                                child: Text(
                                  'Signed in as ${settings.cloudflareUsername ?? 'your account'}. You can continue setup.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: LifelogPalette.of(context)
                                            .mutedText,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _SignInChoiceCard(
                          icon: Icons.login_rounded,
                          title: 'Sign in',
                          subtitle:
                              'Use your existing Cloudflare sync account',
                          primary: true,
                          onTap: () async {
                            await connectCloudflareSync(context, ref);
                            if (!context.mounted) return;
                            if (ref.read(settingsProvider).cloudflareConnected) {
                              _pages.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: Insets.md),
                        _SignInChoiceCard(
                          icon: Icons.person_add_alt_1_rounded,
                          title: 'Create account',
                          subtitle:
                              'First-time setup for your personal Cloudflare Worker (built-in URL preconfigured)',
                          onTap: () async {
                            await connectCloudflareSync(
                              context,
                              ref,
                              initialCreateAccount: true,
                            );
                            if (!context.mounted) return;
                            if (ref.read(settingsProvider).cloudflareConnected) {
                              _pages.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                        ),
                      ],
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
                    eyebrow: 'Privacy',
                    title: 'Private by design',
                    body:
                        'Your data is encrypted on this device. You choose what to connect and what to share.',
                    children: const [
                      _FactRow(
                        icon: Icons.enhanced_encryption_outlined,
                        text: 'Your journal and records are encrypted on this device.',
                      ),
                      _FactRow(
                        icon: Icons.touch_app_outlined,
                        text: 'Nothing is added unless you choose to add it.',
                      ),
                      _FactRow(
                        icon: Icons.cloud_outlined,
                        text:
                            'Cloudflare sync, Last.fm, and Health connections are optional and only used when you enable them.',
                      ),
                      _FactRow(
                        icon: Icons.location_on_outlined,
                        text: 'Location is only used when you save a place. Screen Time data is not available on iPhone without special Apple approval.',
                      ),
                    ],
                  ),
                  _PageFrame(
                    wide: wide,
                    illustration: const _SetupArt(),
                    eyebrow: 'Permissions',
                    title: 'Allow access you want to use',
                    body:
                        'You can allow these now or later in Settings. If you skip them, the app still works and saves everything locally.',
                    children: [
                      _PermissionCard(
                        icon: Icons.location_on_outlined,
                        title: 'Location',
                        subtitle: _locationPermission == LocationPermission.always
                            ? 'Always access is enabled for saving places and visits.'
                            : _locationPermission == LocationPermission.whileInUse
                                ? 'Currently While Using. You can change this to Always in Settings.'
                                : 'Allow Always so location features work reliably when saving places and visits.',
                        actionLabel: _requestingLocation ? '...' : _locationStatusLabel(),
                        onTap: _requestingLocation
                            ? () {}
                            : () => _requestLocationPermission(context),
                      ),
                      const SizedBox(height: Insets.md),
                      _PermissionCard(
                        icon: Icons.favorite_border_rounded,
                        title: 'Health, sleep & steps',
                        subtitle: _healthGranted == true
                            ? 'Access requested. Apple may not confirm read access; allow Steps and Sleep for Lifelog in Health if syncing does not work.'
                            : 'Read-only access to automatically sync sleep and steps from Apple Health / Health Connect.',
                        actionLabel: _requestingHealth ? '...' : _healthStatusLabel(),
                        onTap: _requestingHealth
                            ? () {}
                            : () => _requestHealthPermission(context),
                      ),
                      const SizedBox(height: Insets.md),
                      QuietCard(
                        padding: const EdgeInsets.all(Insets.md),
                        color: LifelogPalette.of(context).subtle.withValues(alpha: 0.7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.hourglass_top_rounded, size: 17, color: LifelogPalette.of(context).mutedText),
                            const SizedBox(width: Insets.sm),
                            Expanded(
                              child: Text(
                                'Screen Time/app usage data is not accessible to regular iPhone apps. It requires Apple Family Controls entitlement and approval (Screen Time API: Family Controls, ManagedSettings, DeviceActivity), so Lifelog cannot retrieve it automatically. See Settings > Permissions > Screen Time (advanced) for details.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LifelogPalette.of(context).mutedText),
                              ),
                            ),
                          ],
                        ),
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
                    if (_page == 0)
                      FilledButton.icon(
                        onPressed: settings.cloudflareConnected
                            ? () => _pages.nextPage(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                )
                            : null,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('Continue'),
                      )
                    else
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

  static const _pagesInitialised = 6;

  LocationPermission? _locationPermission;
  bool? _healthGranted;
  bool _requestingLocation = false;
  bool _requestingHealth = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatuses();
  }

  Future<void> _refreshPermissionStatuses() async {
    LocationPermission? location;
    try {
      location = await Geolocator.checkPermission();
    } catch (_) {}
    final services = ref.read(appServicesProvider);
    bool? health;
    try {
      health = await services.healthSteps.hasPermission();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _locationPermission = location;
      _healthGranted = health;
    });
  }

  String _locationStatusLabel() {
    final p = _locationPermission;
    if (p == null) return 'Check access';
    if (p == LocationPermission.always) return 'Always allowed';
    if (p == LocationPermission.whileInUse) return 'Set to Always';
    if (p == LocationPermission.deniedForever) return 'Open Settings';
    if (p == LocationPermission.denied) return 'Allow Always';
    return 'Allow Always';
  }

  String _healthStatusLabel() {
    if (_healthGranted == true) return 'Requested';
    if (_healthGranted == false) return 'Allow';
    return 'Allow';
  }

  Future<void> _requestLocationPermission(BuildContext context) async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      var permission = _locationPermission ?? await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          showSnack(context, 'Location is turned off. Open Settings and set Lifelog location to Always.');
        }
        await Geolocator.openAppSettings();
      } else {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled && context.mounted) {
          showSnack(context, 'Turn on Location Services, then set Lifelog location access to Always.');
        }
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        // Request/upgrade to Always where the platform allows.
        if (permission == LocationPermission.whileInUse) {
          permission = await Geolocator.requestPermission();
        }
        if (!context.mounted) return;
        setState(() => _locationPermission = permission);
        if (permission == LocationPermission.always) {
          showSnack(context, 'Location access set to Always.');
        } else if (permission == LocationPermission.whileInUse) {
          showSnack(context, 'Location is While Using. Open Settings > Lifelog > Location and choose Always.');
          await Geolocator.openAppSettings();
        } else if (permission == LocationPermission.deniedForever) {
          showSnack(context, 'Location permission is off. Open Settings and set Lifelog location to Always.');
          await Geolocator.openAppSettings();
        } else {
          showSnack(context, 'Location access was not granted. You can allow Always in Settings.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Could not request location access: $e');
      }
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
      await _refreshPermissionStatuses();
    }
  }

  Future<void> _requestHealthPermission(BuildContext context) async {
    if (_requestingHealth) return;
    setState(() => _requestingHealth = true);
    try {
      final services = ref.read(appServicesProvider);
      if (!services.healthSteps.isSupported) {
        if (context.mounted) {
          showSnack(context, 'Health access is available on supported devices (iPhone/Apple Health or Android/Health Connect).');
        }
        return;
      }
      final ok = await services.healthSteps.requestPermission();
      final status = await services.healthSteps.hasPermission();
      if (!context.mounted) return;
      setState(() => _healthGranted = status ?? ok);
      if (ok || status == true) {
        showSnack(context, 'Health access requested. If sleep or steps do not sync, allow Steps and Sleep for Lifelog in the Health app or device Settings.');
      } else {
        final isApple = Theme.of(context).platform == TargetPlatform.iOS ||
            Theme.of(context).platform == TargetPlatform.macOS;
        if (isApple) {
          showSnack(context, 'Could not enable Health access. Open iPhone Settings > Privacy & Security > Health (or Health app > Apps > Lifelog) and allow Steps and Sleep.');
        } else {
          showSnack(context, 'Could not enable Health access. Open Health Connect and allow Lifelog to read Steps and Sleep.');
        }
        await Geolocator.openAppSettings();
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Could not request Health access: $e');
      }
    } finally {
      if (mounted) setState(() => _requestingHealth = false);
      await _refreshPermissionStatuses();
    }
  }

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
    final bg = primary
        ? scheme.primary.withValues(alpha: palette.isDark ? 0.18 : 0.10)
        : palette.card;
    final border = primary ? scheme.primary.withValues(alpha: 0.28) : palette.border;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Insets.lg),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: border),
          boxShadow: palette.isDark
              ? null
              : [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: primary ? 0.08 : 0.03),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          children: [
            IconBadge(icon: icon, size: 44, iconSize: 22, color: primary ? scheme.primary : null),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, size: 18, color: primary ? scheme.primary : palette.dimText),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return QuietCard(
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          IconBadge(icon: icon, size: 40, iconSize: 20),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.mutedText)),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          FilledButton.tonal(
            onPressed: onTap,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

