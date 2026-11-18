import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/session_provider.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import 'pin_dialogs.dart';

/// Wraps the authenticated app and hides it behind a PIN after inactivity or
/// when the user chooses to lock. This is a privacy screen layered over an
/// already-encrypted archive, not a replacement for disk encryption.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _lastActive = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(settingsProvider).lockEnabled) {
        ref.read(sessionLockProvider.notifier).lock();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _checkIdle());
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _bump();
    return false;
  }

  void _bump() {
    _lastActive = DateTime.now();
  }

  void _checkIdle() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    if (!settings.lockEnabled) return;
    if (ref.read(sessionLockProvider)) return;
    final minutes = settings.autoLockMinutes;
    if (minutes <= 0) return;
    if (DateTime.now().difference(_lastActive).inMinutes >= minutes) {
      ref.read(sessionLockProvider.notifier).lock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final settings = ref.read(settingsProvider);
      final minutes = settings.autoLockMinutes;
      if (settings.lockEnabled &&
          minutes > 0 &&
          DateTime.now().difference(_lastActive).inMinutes >= minutes) {
        ref.read(sessionLockProvider.notifier).lock();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lastActive = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(sessionLockProvider);
    if (locked) {
      return LockScreen(
        onUnlocked: () {
          _bump();
          ref.read(sessionLockProvider.notifier).unlock();
        },
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _bump(),
      onPointerMove: (_) => _bump(),
      child: widget.child,
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(settingsProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _busy = false;
      _error = 'That PIN did not match.';
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: QuietCard(
              padding: const EdgeInsets.all(Insets.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: scheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: Insets.lg),
                  Text(
                    'Lifelog is locked',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    'Your archive remains encrypted on disk while the app is '
                    'hidden.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                  const SizedBox(height: Insets.xl),
                  PinField(
                    controller: _pin,
                    autofocus: true,
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Insets.md),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: Insets.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _unlock,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Unlock'),
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'There is no PIN recovery. The PIN protects this screen; '
                    'it does not change the archive encryption key. If you '
                    'forget it, you will need to remove the app’s local data.',
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
