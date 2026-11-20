import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_services.dart';
import 'app/lifelog_app.dart';
import 'app/providers/providers.dart';
import 'app/theme/app_theme.dart';
import 'app/widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch framework, platform and async errors so a transient failure cannot
  // leave the user with a silent blank screen. Errors are only logged locally;
  // nothing is uploaded or written into the encrypted archive.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _reportError(error, stack);
    return true;
  };

  runZonedGuarded(
    () => runApp(const BootstrapApp()),
    _reportError,
  );
}

void _reportError(Object error, StackTrace? stack) {
  debugPrint('Lifelog error: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// Boots storage and cryptography before any provider or screen exists. The
/// failure state is a real screen showing the actual error, because hiding a
/// failed bootstrap behind a blank window would be dishonest.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<AppServices> _future = AppServices.bootstrap();

  void _retry() {
    setState(() => _future = AppServices.bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'Lifelog',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const _StartupSplash(),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            title: 'Lifelog',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: _StartupFailure(
              error: snapshot.error!,
              onRetry: _retry,
            ),
          );
        }
        final services = snapshot.requireData;
        return ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: const LifelogApp(),
        );
      },
    );
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LifelogMark(size: 64),
            const SizedBox(height: Insets.lg),
            Text(
              'Opening your archive',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Decrypting locally. Nothing is uploaded.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
            ),
            const SizedBox(height: Insets.xl),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              padding: const EdgeInsets.all(Insets.xxl),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: scheme.error,
                    size: 30,
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'Lifelog could not open its encrypted archive',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    'The local data folder could not be prepared, the key '
                    'could not be loaded, or the archive file could not be '
                    'decrypted. Your existing files have been left in place; '
                    'retry before deleting or replacing anything.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                  const SizedBox(height: Insets.lg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Insets.md),
                    decoration: BoxDecoration(
                      color: palette.subtle,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: palette.border),
                    ),
                    child: SelectableText(
                      '$error',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: Insets.lg),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('Try again'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '$error'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error details copied.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined, size: 17),
                        label: const Text('Copy details'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'If this repeats, check that the application data folder '
                    'is writable. Do not delete the archive file before '
                    'copying it somewhere safe.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.dimText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
