import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers/providers.dart';
import '../app/providers/settings_provider.dart';
import '../domain/models/settings.dart';
import '../features/cloudflare/cloudflare_required_auth_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/security/lock_screen.dart';
import '../integrations/cloudflare/cloudflare_sync.dart';
import '../integrations/lastfm/lastfm_sync.dart';
import '../integrations/location/location_tracking_controller.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

class LifelogApp extends ConsumerWidget {
  const LifelogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Lifelog',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: const LifelogScrollBehavior(),
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeMode: switch (settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      // Account setup is asked for once. After that, signing out or an expired
      // session never blocks the journal: the data is local, and the sync card
      // in Settings says what to do.
      home: !settings.onboardingComplete
          ? const OnboardingScreen()
          : !settings.cloudflareConnected && !settings.cloudflareSetupDone
          ? const CloudflareRequiredAuthScreen()
          : const LockGate(
              child: LocationTrackingHost(
                child: _StartupSync(child: AppShell()),
              ),
            ),
    );
  }
}

class _StartupSync extends ConsumerStatefulWidget {
  const _StartupSync({required this.child});
  final Widget child;

  @override
  ConsumerState<_StartupSync> createState() => _StartupSyncState();
}

class _StartupSyncState extends ConsumerState<_StartupSync> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: fetch new Last.fm scrobbles and check Cloudflare restore on start.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      syncLastfmIfConnected(ref);
      await maybePromptCloudflareRestore(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Initialize cloud sync early so media reads can use the online cache
    // fallback before any screen opens an attachment.
    ref.watch(cloudAutoSyncProvider);
    return widget.child;
  }
}
