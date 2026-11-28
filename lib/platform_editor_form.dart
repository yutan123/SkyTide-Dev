import 'dart:async';

import 'package:flutter/material.dart';

import 'app_navigation.dart';

bool get platformEditorInForeground =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
    appNavigatorKey.currentState?.overlay?.context.mounted == true;

typedef EditorForm =
    Future<Map<String, Object?>?> Function(
      String source,
      String title,
      String message,
      List<EditorField> fields,
    );

class EditorField {
  const EditorField(
    this.id,
    this.label,
    this.type, {
    this.options = const [],
    this.required = false,
  });
  final String id, label, type;
  final List<String> options;
  final bool required;
}

Future<Map<String, Object?>?> showPlatformEditorForm(
  String source,
  String title,
  String message,
  List<EditorField> fields,
) async {
  if (!platformEditorInForeground) return null;
  final navigator = appNavigatorKey.currentState!;
  final route = DialogRoute<Map<String, Object?>>(
    context: navigator.overlay!.context,
    barrierDismissible: false,
    builder: (_) => _EditorDialog(source, title, message, fields),
  );
  void cancel() {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }

  final listener = AppLifecycleListener(onHide: cancel);
  final timer = Timer(const Duration(minutes: 2), cancel);
  try {
    return await navigator.push(route);
  } finally {
    timer.cancel();
    listener.dispose();
  }
}

class _EditorDialog extends StatefulWidget {
  const _EditorDialog(this.source, this.title, this.message, this.fields);
  final String source, title, message;
  final List<EditorField> fields;

  @override
  State<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends State<_EditorDialog> {
  final form = GlobalKey<FormState>();
  final values = <String, Object?>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('SkyTide 平台编辑器'),
    scrollable: true,
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('请求来源：${widget.source}'),
          const SizedBox(height: 8),
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          Text(widget.message, textDirection: TextDirection.ltr),
          for (final field in widget.fields) ...[
            const SizedBox(height: 12),
            if (field.type == 'single')
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: InputDecoration(labelText: field.label),
                items: [
                  for (final option in field.options)
                    DropdownMenuItem(value: option, child: Text(option)),
                ],
                onChanged: (value) => values[field.id] = value,
                validator: (value) =>
                    field.required && value == null ? '请选择一项' : null,
              )
            else if (field.type == 'multi')
              FormField<List<String>>(
                initialValue: const [],
                validator: (selection) =>
                    field.required && selection!.isEmpty ? '请至少选择一项' : null,
                builder: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field.label),
                    for (final option in field.options)
                      CheckboxListTile(
                        title: Text(option),
                        value: state.value!.contains(option),
                        onChanged: (checked) {
                          final selection = [...state.value!];
                          if (checked == true) {
                            selection.add(option);
                          } else {
                            selection.remove(option);
                          }
                          state.didChange(selection);
                          values[field.id] = selection;
                        },
                      ),
                    if (state.hasError) Text(state.errorText!),
                  ],
                ),
              )
            else if (field.type == 'toggle')
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: Text(field.label),
                  value: values[field.id] == true,
                  onChanged: (value) =>
                      setState(() => values[field.id] = value),
                ),
              )
            else
              TextFormField(
                decoration: InputDecoration(labelText: field.label),
                obscureText: field.type == 'secret',
                autocorrect: field.type != 'secret',
                enableSuggestions: field.type != 'secret',
                maxLines: field.type == 'multiline' ? 4 : 1,
                maxLength: field.type == 'secret' ? 4096 : 2000,
                keyboardType: field.type == 'number'
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : field.type == 'multiline'
                    ? TextInputType.multiline
                    : TextInputType.text,
                onSaved: (raw) {
                  final value = raw?.trim() ?? '';
                  if (value.isEmpty) return;
                  values[field.id] = field.type == 'number'
                      ? num.parse(value)
                      : value;
                },
                validator: (raw) {
                  final value = raw?.trim() ?? '';
                  if (value.isEmpty) return field.required ? '请填写此项' : null;
                  if (field.type == 'number' &&
                      num.tryParse(value)?.isFinite != true) {
                    return '请输入有效数字';
                  }
                  return null;
                },
              ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          form.currentState!.save();
          for (final field in widget.fields) {
            if (field.type == 'toggle')
              values.putIfAbsent(field.id, () => false);
            if (field.type == 'multi')
              values.putIfAbsent(field.id, () => <String>[]);
          }
          Navigator.pop(context, values);
        },
        child: Text(widget.fields.isEmpty ? '允许此操作' : '确认'),
      ),
    ],
  );
}
