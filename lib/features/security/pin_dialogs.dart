import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';

bool _validPin(String pin) =>
    pin.length >= 4 && pin.length <= 12 && RegExp(r'^\d+$').hasMatch(pin);

/// Creates a numeric PIN and returns it only after a matching confirmation.
Future<String?> askCreatePin(
  BuildContext context, {
  String title = 'Set a PIN',
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _CreatePinDialog(title: title),
  );
}

/// Asks for the current PIN and verifies it against stored settings.
Future<bool> confirmCurrentPin(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Confirm your PIN',
}) async {
  final controller = ref.read(settingsProvider.notifier);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _VerifyPinDialog(
      title: title,
      confirmLabel: 'Confirm',
      verify: controller.verifyPin,
    ),
  );
  return result ?? false;
}

/// A reusable PIN entry dialog that stays open until the PIN verifies or the
/// user cancels. No attempt counter is stored, so this is a privacy screen and
/// not a defence against an attacker with the encrypted files.
Future<bool> showPinPrompt(
  BuildContext context, {
  required Future<bool> Function(String pin) verify,
  String title = 'Unlock Lifelog',
  String subtitle =
      'Enter your PIN. The archive stays encrypted on disk while locked.',
  String confirmLabel = 'Unlock',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VerifyPinDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      verify: verify,
      autofocus: true,
    ),
  );
  return result ?? false;
}

class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.label = 'PIN',
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String label;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ],
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.pin_outlined, size: 19),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show PIN' : 'Hide PIN',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _CreatePinDialog extends StatefulWidget {
  const _CreatePinDialog({required this.title});
  final String title;

  @override
  State<_CreatePinDialog> createState() => _CreatePinDialogState();
}

class _CreatePinDialogState extends State<_CreatePinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text.trim();
    if (!_validPin(pin)) {
      setState(() => _error = 'Use 4 to 12 digits.');
      return;
    }
    if (pin != _confirm.text.trim()) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The PIN locks the app. It does not replace the archive '
              'encryption key, which is stored separately.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
            ),
            const SizedBox(height: Insets.md),
            PinField(controller: _pin, autofocus: true, label: 'New PIN'),
            const SizedBox(height: Insets.md),
            PinField(
              controller: _confirm,
              label: 'Confirm PIN',
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Set PIN')),
      ],
    );
  }
}

class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({
    required this.title,
    required this.verify,
    required this.confirmLabel,
    this.subtitle,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final Future<bool> Function(String pin) verify;
  final bool autofocus;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter your PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.verify(pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
              const SizedBox(height: Insets.md),
            ],
            PinField(
              controller: _pin,
              autofocus: widget.autofocus,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
