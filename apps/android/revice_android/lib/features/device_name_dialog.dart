import 'package:flutter/material.dart';

import '../core/formatters.dart';

Future<void> editDeviceName(
  BuildContext context, {
  required String initial,
  required Future<void> Function(String) save,
  String title = 'Rename Device',
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _NameDialog(initial: initial, save: save, title: title),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initial,
    required this.save,
    required this.title,
  });
  final String initial, title;
  final Future<void> Function(String) save;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final text = TextEditingController(text: widget.initial);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => error = deviceNameError(text.text));
    if (error != null) return;
    setState(() => busy = true);
    try {
      await widget.save(text.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Device name saved.')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save. Check your connection and account, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: text,
            enabled: !busy,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Device Name',
              helperText: 'Up to 40 characters',
              errorText: error,
            ),
            onSubmitted: (_) {
              if (!busy) submit();
            },
          ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
