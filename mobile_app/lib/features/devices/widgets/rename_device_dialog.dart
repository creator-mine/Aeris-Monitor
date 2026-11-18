import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../models/device.dart';
import '../../../shared/widgets/tr_text.dart';

/// Asks for a new device name. Returns null when the dialog is cancelled or
/// the name is left empty.
Future<String?> showRenameDeviceDialog(
  BuildContext context,
  Device device,
) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDeviceDialog(initialName: device.name),
  );
}

class _RenameDeviceDialog extends StatefulWidget {
  final String initialName;

  const _RenameDeviceDialog({required this.initialName});

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const TrText('Переименовать устройство'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: L10n.of(context, 'Название'),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const TrText('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const TrText('Сохранить'),
        ),
      ],
    );
  }
}
