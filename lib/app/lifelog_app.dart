import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers/settings_provider.dart';
import '../domain/models/settings.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/security/lock_screen.dart';
import '../integrations/lastfm/lastfm_sync.dart';
import '../integrations/google_drive/google_drive_sync.dart';
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
      home: settings.onboardingComplete
          ? const LockGate(child: _StartupSync(child: AppShell()))
          : const OnboardingScreen(),
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
    // Fire-and-forget: fetch new Last.fm scrobbles and check Google Drive restore on start.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      syncLastfmIfConnected(ref);
      await maybePromptGoogleDriveRestore(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
