import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Asks for a folder with the system's own picker: the GTK or desktop
/// portal dialog on Linux, the shell dialog on Windows, the open panel on
/// macOS. Where there is none (Android), it asks for a path instead.
/// Returns null when cancelled.
Future<String?> pickDirectory(BuildContext context, {String? initial, String confirm = '选择', String title = '选择文件夹'}) async {
  final start = initial != null && initial.isNotEmpty && Directory(initial).existsSync() ? initial : null;
  // Android's picker answers with content:// addresses, not paths lookd
  // could use.
  if (Platform.isAndroid) return _askPath(context, initial ?? '', confirm, title);
  try {
    return await getDirectoryPath(initialDirectory: start, confirmButtonText: confirm);
  } on UnimplementedError {
    // No native picker on this platform.
  } on MissingPluginException {
    // Same, in tests and on unsupported embedders.
  } on PlatformException {
    // The picker failed to open (e.g. no portal); ask instead.
  }
  if (!context.mounted) return null;
  return _askPath(context, initial ?? '', confirm, title);
}

/// Asks where to save a file with the system's save dialog; where there is
/// none (Android), it asks for a folder and keeps [suggestedName]. The
/// returned path ends in one of [type]'s extensions.
Future<String?> pickSavePath(BuildContext context, {required String suggestedName, required XTypeGroup type, String confirm = '保存'}) async {
  String? path;
  var native = false;
  try {
    path = (await getSaveLocation(suggestedName: suggestedName, acceptedTypeGroups: [type], confirmButtonText: confirm))?.path;
    native = true;
  } on UnimplementedError {
    // No native dialog.
  } on MissingPluginException {
    // Same, in tests.
  } on PlatformException {
    // The dialog failed to open.
  }
  if (!native) {
    if (!context.mounted) return null;
    final dir = await pickDirectory(context, title: '保存到哪个文件夹', confirm: confirm);
    if (dir != null) path = p.join(dir, suggestedName);
  }
  if (path == null || path.isEmpty) return null;
  final exts = type.extensions ?? const [];
  if (exts.isNotEmpty && !exts.any((e) => path!.toLowerCase().endsWith('.${e.toLowerCase()}'))) path = '$path.${exts.first}';
  return path;
}

Future<String?> _askPath(BuildContext context, String initial, String confirm, String title) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文件夹路径', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(c, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim().isEmpty ? null : ctl.text.trim()), child: Text(confirm)),
      ],
    ),
  );
}

/// A path text field with a button that opens [pickDirectory].
class FolderField extends StatelessWidget {
  const FolderField({super.key, required this.controller, required this.label, this.hint, this.helper, this.onPicked, this.onSubmitted, this.autofocus = false});
  final TextEditingController controller;
  final String label;
  final String? hint, helper;
  final ValueChanged<String>? onPicked, onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          border: const OutlineInputBorder(),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: '选择文件夹',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () async {
                final dir = await pickDirectory(context, initial: controller.text.trim(), title: label);
                if (dir == null) return;
                controller.text = dir;
                onPicked?.call(dir);
              },
            ),
          ),
        ),
      );
}
