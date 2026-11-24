import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'plugin_config_ui.dart';
import 'plugin_config_resources.dart';
import 'package:flutter/material.dart';

import 'plugin_contract.dart';
import 'theme.dart';
import 'ui_components.dart';

class PluginConfigDialog extends StatefulWidget {
  final Future<dynamic> Function(Map<String, dynamic>)? onTest;
  final Future<String> Function(String)? importFile;
  final Future<List<PluginConfigOption>> Function()? loadDirectories;
  final Future<String> Function(String)? createDirectory;
  final String title;
  final Map schema;
  final Map<String, dynamic> values;
  const PluginConfigDialog({
    super.key,
    this.onTest,
    this.importFile,
    this.loadDirectories,
    this.createDirectory,
    required this.title,
    required this.schema,
    required this.values,
  });
  @override
  State<PluginConfigDialog> createState() => _PluginConfigDialogState();
}

class _PluginConfigDialogState extends State<PluginConfigDialog> {
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  String? _error;
  bool _saving = false;
  bool _testing = false;
  bool _picking = false;
  String? _testMessage;
  final _revealed = <String>{};
  final _catalog = <String, List<PluginConfigOption>>{};

  @override
  void initState() {
    super.initState();
    if (tz.timeZoneDatabase.locations.isEmpty) tzdata.initializeTimeZones();
    final properties = widget.schema['properties'] as Map;
    for (final key in properties.keys.cast<String>()) {
      final field = properties[key] as Map;
      final value = widget.values[key] ?? field['default'];
      if ({
        'provider',
        'bot',
        'slider',
      }.contains(PluginConfigUi.ui(field)['widget'])) {
        if (value != null) _values[key] = value;
      } else if (field['type'] == 'boolean' && field['enum'] is! List) {
        _values[key] = value ?? false;
      } else if (field['enum'] is List &&
          !{'object', 'array'}.contains(field['type'])) {
        if (value != null) _values[key] = value;
      } else {
        _controllers[key] = TextEditingController(
          text: value == null
              ? ''
              : ({'object', 'array'}.contains(field['type'])
                    ? const JsonEncoder.withIndent('  ').convert(value)
                    : value.toString()),
        );
      }
    }
    _loadCatalogs();
  }

  Future<void> _save() async {
    try {
      if (_saving || _testing || _picking) return;
      setState(() => _saving = true);
      final values = await _validated();
      if (mounted) Navigator.pop(context, values);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final materialTheme = Theme.of(context);
    return Theme(
      data: materialTheme.copyWith(
        colorScheme: materialTheme.colorScheme.copyWith(
          primary: theme.primary,
          onPrimary: Colors.white,
          surface: theme.surface,
          onSurface: theme.textStrong,
        ),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: TideDialogSurface(
          kind: TideDialogKind.form,
          title: Text(
            widget.title,
            style: TextStyle(
              color: theme.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'TideFont',
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AbsorbPointer(
                    absorbing: _testing || _saving || _picking,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _formFields(),
                    ),
                  ),
                  if (_testMessage != null)
                    Text(
                      _testMessage!,
                      style: TextStyle(color: theme.textWeak),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: materialTheme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (widget.onTest != null)
                    TextButton(
                      onPressed: _testing || _saving || _picking ? null : _test,
                      child: Text(
                        _testing
                            ? '测试中…'
                            : PluginConfigUi.ui(widget.schema)['testLabel']
                                      as String? ??
                                  '测试连接',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: _testing || _saving || _picking
                            ? null
                            : _save,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String title, Map field) {
    final theme = TideTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: theme.textFaint.withValues(alpha: .25)),
    );
    return InputDecoration(
      labelText: title,
      labelStyle: TextStyle(color: theme.textWeak),
      helperText: field['description']?.toString(),
      helperStyle: TextStyle(color: theme.textWeak, fontSize: 12),
      helperMaxLines: 8,
      suffixText: PluginConfigUi.ui(field)['unit'] as String?,
      filled: true,
      fillColor: theme.surfaceVariant.withValues(alpha: .45),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.primary, width: 1.5),
      ),
    );
  }

  Future<void> _selectOption(String key, String title, List options) async {
    FocusScope.of(context).unfocus();
    final theme = TideTheme.of(context);
    final selected = options.indexWhere(
      (option) => jsonEncode(option) == jsonEncode(_values[key]),
    );
    final index = await TideDialogs.show<int>(
      context: context,
      builder: (ctx) => TideDialogSurface(
        kind: TideDialogKind.notice,
        title: Text(
          title,
          style: TextStyle(
            color: theme.textStrong,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'TideFont',
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: i == selected
                          ? theme.primary.withValues(alpha: .12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  options[i].toString(),
                                  style: TextStyle(
                                    color: i == selected
                                        ? theme.primary
                                        : theme.textStrong,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                i == selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: i == selected
                                    ? theme.primary
                                    : theme.textFaint,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: theme.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted || index == null) return;
    setState(() => _values[key] = options[index]);
  }

  Widget _field(String key, Map field) {
    final theme = TideTheme.of(context);
    final title = field['title']?.toString() ?? key;
    final ui = PluginConfigUi.ui(field);
    final kind = ui['widget'];
    if (kind == 'provider' || kind == 'bot') {
      final value = _values[key];
      final ids = value is List
          ? value
          : [if (value != null && value != '') value];
      final catalog = _catalog[key];
      final names = {
        for (final o in catalog ?? <PluginConfigOption>[]) o.id: o.label,
      };
      final display = ids
          .map((id) => names[id] ?? (catalog == null ? '加载中…' : '已失效，请重新选择'))
          .join('、');
      return _picker(key, field, display, () => _resource(key, field));
    }
    if ({'file', 'directory', 'date', 'time', 'timezone'}.contains(kind)) {
      return _picker(
        key,
        field,
        _controllers[key]!.text,
        () => _specialPicker(key, field),
      );
    }
    if (kind == 'slider') {
      final min = (field['minimum'] as num).toDouble();
      final max = (field['maximum'] as num).toDouble();
      final value = (_values[key] as num? ?? min).toDouble().clamp(min, max);
      final step =
          ui['step'] as num? ?? (field['type'] == 'integer' ? 1 : null);
      final divisions = step == null ? null : ((max - min) / step).round();
      return InputDecorator(
        decoration: _decoration(title, field),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_values[key] ?? '未设置'}${ui['unit'] ?? ''}'),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => setState(() {
                _values[key] = field['type'] == 'integer'
                    ? v.round()
                    : double.parse(v.toStringAsFixed(8));
              }),
            ),
          ],
        ),
      );
    }
    if (field['enum'] is List && !{'object', 'array'}.contains(field['type'])) {
      final options = field['enum'] as List;
      // Compare encoded values to preserve distinct integer and decimal entries.
      final selected = options.indexWhere(
        (option) => jsonEncode(option) == jsonEncode(_values[key]),
      );
      return Semantics(
        button: true,
        label: title,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _selectOption(key, title, options),
          child: InputDecorator(
            decoration: _decoration(title, field),
            isEmpty: selected < 0,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected < 0 ? '' : options[selected].toString(),
                    style: TextStyle(color: theme.textStrong, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.expand_more_rounded,
                  color: theme.textWeak,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (field['type'] == 'boolean') {
      final enabled = _values[key] as bool? ?? false;
      return Semantics(
        label: title,
        toggled: enabled,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _values[key] = !enabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: theme.textStrong, fontSize: 14),
                      ),
                      if (field['description'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          field['description'].toString(),
                          style: TextStyle(color: theme.textWeak, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 48,
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 23,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: enabled ? theme.primary : theme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: enabled
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: enabled ? Colors.white : theme.textWeak,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return TextField(
      controller: _controllers[key],
      style: TextStyle(color: theme.textStrong, fontSize: 14),
      cursorColor: theme.primary,
      onChanged: (_) => setState(() {}),
      obscureText:
          field['type'] == 'string' &&
          field['format'] == 'password' &&
          !_revealed.contains(key),
      minLines: kind == 'multiline'
          ? ui['rows'] as int? ?? 4
          : ({'object', 'array'}.contains(field['type']) ? 3 : 1),
      maxLines: kind == 'multiline'
          ? 20
          : ({'object', 'array'}.contains(field['type']) ? 8 : 1),
      keyboardType: {'number', 'integer'}.contains(field['type'])
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      enableSuggestions: field['format'] != 'password',
      autocorrect: field['format'] != 'password',
      decoration: _decoration(title, field).copyWith(
        suffixIcon: field['format'] == 'password'
            ? IconButton(
                tooltip: _revealed.contains(key) ? '隐藏密码' : '显示密码',
                icon: Icon(
                  _revealed.contains(key)
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() {
                  if (!_revealed.add(key)) _revealed.remove(key);
                }),
              )
            : null,
      ),
    );
  }

  Map<String, dynamic> _draft({bool strict = false}) {
    final properties = widget.schema['properties'] as Map;
    final result = <String, dynamic>{
      if (widget.schema['additionalProperties'] == true)
        for (final entry in widget.values.entries)
          if (!properties.containsKey(entry.key)) entry.key: entry.value,
      ..._values,
    };
    for (final entry in _controllers.entries) {
      final field = properties[entry.key] as Map;
      final text = entry.value.text;
      try {
        if (text.isEmpty && field['type'] != 'string') continue;
        result[entry.key] = switch (field['type']) {
          'integer' => int.parse(text),
          'number' => double.parse(text),
          'object' || 'array' => jsonDecode(text),
          _ => text,
        };
      } catch (_) {
        if (strict && PluginConfigUi.visible(field, _draft())) {
          throw FormatException(
            '${field['title'] ?? entry.key}：请输入有效的${field['type']}值',
          );
        }
      }
    }
    return result;
  }

  Future<void> _test() async {
    if (_testing || _saving || _picking) return;
    setState(() => _testing = true);
    try {
      final values = await _validated();
      if (!mounted) return;
      setState(() {
        _testing = true;
        _testMessage = null;
        _error = null;
      });
      final result = await widget.onTest!(values).timeout(
        const Duration(seconds: 30),
      );
      if (!mounted) return;
      if (result is! Map || result['ok'] is! bool) {
        throw const FormatException(
          '测试处理器必须返回 {ok: boolean, message?: string}',
        );
      }
      setState(() {
        _testMessage = result['ok'] == true ? '连接测试成功' : '连接测试失败';
        // Detailed remote errors can contain credentials; plugins should log safe details themselves.
      });
    } catch (_) {
      if (mounted) setState(() => _error = '测试未通过，请检查配置、插件启用状态及连接情况');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<Map<String, dynamic>> _validated() async {
    final draft = _draft(strict: true);
    final properties = widget.schema['properties'] as Map;
    for (final entry in properties.entries) {
      final field = entry.value as Map;
      if (!PluginConfigUi.visible(field, draft)) continue;
      final ui = PluginConfigUi.ui(field);
      final kind = ui['widget'];
      final value = draft[entry.key];
      if (kind == 'provider' || kind == 'bot') {
        final options = await PluginConfigResources.options(
          kind,
          ui['providerTypes'] as List? ?? const ['chat', 'stt', 'tts'],
        );
        final ids = options.map((o) => o.id).toSet();
        final selected = value is List
            ? value
            : [if (value != null && value != '') value];
        if (selected.toSet().length != selected.length ||
            selected.any((id) => !ids.contains(id))) {
          throw FormatException(
            '${field['title'] ?? entry.key}：存在已失效或重复选项，请重新选择',
          );
        }
        if (field['type'] == 'string' && value == '') draft.remove(entry.key);
      }
      if (value is String && value.isNotEmpty) {
        if (kind == 'date') {
          final date = DateTime.tryParse(value);
          if (date == null ||
              date.toIso8601String().substring(0, 10) != value) {
            throw FormatException('${field['title'] ?? entry.key}：日期无效');
          }
        }
        if (kind == 'time' &&
            !RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
          throw const FormatException('时间必须为 HH:mm');
        }
        if (kind == 'timezone' &&
            !tz.timeZoneDatabase.locations.containsKey(value)) {
          throw const FormatException('请选择有效时区');
        }
      }
    }
    return PluginContract.values(widget.schema, draft);
  }

  List<Widget> _formFields() {
    final properties = widget.schema['properties'] as Map;
    final draft = _draft();
    final groups = <String, List<String>>{};
    for (final key in properties.keys.cast<String>()) {
      final field = properties[key] as Map;
      if (!PluginConfigUi.visible(field, draft)) continue;
      final group = PluginConfigUi.ui(field)['group'] as String? ?? '';
      (groups[group] ??= []).add(key);
    }
    Widget item(String key) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: _field(key, properties[key] as Map),
    );
    return [
      for (final group in groups.entries)
        if (group.key.isEmpty)
          ...group.value.map(item)
        else
          _PluginConfigSection(
            key: ValueKey((group.key,)),
            title: group.key,
            initiallyExpanded: !group.value.any(
              (key) =>
                  PluginConfigUi.ui(properties[key] as Map)['collapsed'] ==
                  true,
            ),
            children: group.value.map(item).toList(),
          ),
    ];
  }

  Future<List<String>?> _choose(
    String title,
    List<PluginConfigOption> options,
    List<String> initial, {
    bool multiple = false,
    int? maxItems,
  }) async {
    FocusScope.of(context).unfocus();
    options = [
      ...options,
      for (final id in initial)
        if (!options.any((o) => o.id == id))
          PluginConfigOption(id, '已失效选项', '请取消选择'),
    ];
    final selected = initial.toSet();
    var search = '';
    final theme = TideTheme.of(context);
    return TideDialogs.show<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final filtered = options
              .where(
                (o) => '${o.label} ${o.detail} ${o.id}'.toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .toList();
          return TideDialogSurface(
            kind: TideDialogKind.choice,
            title: Text(multiple ? '$title（已选 ${selected.length}）' : title),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => refresh(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * .4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.isEmpty ? 1 : filtered.length,
                        itemBuilder: (ctx, index) {
                          if (filtered.isEmpty)
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('没有可选项，请先添加或调整搜索内容'),
                            );
                          final option = filtered[index];
                          final active = selected.contains(option.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: option.isBot
                                ? SkyTideAvatar(
                                    name: option.label,
                                    path: option.avatar,
                                    size: 40,
                                  )
                                : null,
                            title: Text(option.label),
                            subtitle: option.detail.isEmpty
                                ? null
                                : Text(option.detail),
                            trailing: Icon(
                              active
                                  ? (multiple
                                        ? Icons.check_box_rounded
                                        : Icons.radio_button_checked)
                                  : (multiple
                                        ? Icons.check_box_outline_blank_rounded
                                        : Icons.radio_button_unchecked),
                              color: active ? theme.primary : theme.textWeak,
                            ),
                            onTap: () {
                              if (!multiple) {
                                Navigator.pop(ctx, [option.id]);
                                return;
                              }
                              if (!active &&
                                  maxItems != null &&
                                  selected.length >= maxItems)
                                return;
                              refresh(() {
                                if (active) {
                                  selected.remove(option.id);
                                } else {
                                  selected.add(option.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (multiple) {
                    refresh(selected.clear);
                  } else {
                    Navigator.pop(ctx, <String>[]);
                  }
                },
                child: const Text('清空'),
              ),
              if (multiple)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected.toList()),
                  child: const Text('确定'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _picker(
    String key,
    Map field,
    String display,
    VoidCallback onTap, {
    bool clearable = true,
  }) {
    final theme = TideTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _testing ? null : onTap,
      child: InputDecorator(
        decoration: _decoration(field['title']?.toString() ?? key, field),
        isEmpty: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                display.isEmpty ? '请选择' : display,
                style: TextStyle(
                  color: display.isEmpty ? theme.textWeak : theme.textStrong,
                  fontSize: 14,
                ),
              ),
            ),
            if (clearable && display.isNotEmpty)
              IconButton(
                tooltip: '清空',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: _testing
                    ? null
                    : () => setState(() {
                        _controllers[key]?.clear();
                        if (_values.containsKey(key))
                          _values[key] = field['type'] == 'array'
                              ? <String>[]
                              : '';
                      }),
              ),
            Icon(Icons.expand_more_rounded, color: theme.textWeak, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _resource(String key, Map field) async {
    try {
      final ui = PluginConfigUi.ui(field);
      final kind = ui['widget'] as String;
      final options = await PluginConfigResources.options(
        kind,
        ui['providerTypes'] as List? ?? const ['chat', 'stt', 'tts'],
      );
      if (!mounted) return;
      final current = _values[key];
      final multiple = field['type'] == 'array';
      final result = await _choose(
        field['title']?.toString() ?? key,
        options,
        current is List
            ? current.cast<String>()
            : [if (current is String && current.isNotEmpty) current],
        multiple: multiple,
        maxItems: field['maxItems'] as int?,
      );
      if (result == null || !mounted) return;
      setState(() {
        _catalog[key] = options;
        _values[key] = multiple ? result : (result.isEmpty ? '' : result.first);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法加载选项，请重试');
    }
  }

  Future<void> _loadCatalogs() async {
    final properties = widget.schema['properties'] as Map;
    try {
      await Future.wait([
        for (final key in properties.keys.cast<String>())
          () async {
            final ui = PluginConfigUi.ui(properties[key] as Map);
            if (!{'provider', 'bot'}.contains(ui['widget'])) return;
            final list = await PluginConfigResources.options(
              ui['widget'],
              ui['providerTypes'] as List? ?? const ['chat', 'stt', 'tts'],
            );
            if (mounted) setState(() => _catalog[key] = list);
          }(),
      ]);
    } catch (_) {
      if (mounted) setState(() => _error = '无法加载提供商或机器人列表，请重试');
    }
  }

  Future<void> _specialPicker(String key, Map field) async {
    final ui = PluginConfigUi.ui(field);
    final kind = ui['widget'];
    final controller = _controllers[key]!;
    if (_picking || _saving || _testing) return;
    setState(() => _picking = true);
    FocusScope.of(context).unfocus();
    try {
      String? value;
      if (kind == 'file') {
        if (widget.importFile == null) throw StateError('插件未声明 files 权限');
        final extensions = (ui['extensions'] as List?)?.cast<String>();
        final result = await FilePicker.platform.pickFiles(
          type: extensions == null ? FileType.any : FileType.custom,
          allowedExtensions: extensions,
        );
        final path = result?.files.single.path;
        if (path != null) value = await widget.importFile!(path);
      } else if (kind == 'directory') {
        if (widget.loadDirectories == null) throw StateError('插件未声明 files 权限');
        final options = await widget.loadDirectories!();
        if (!mounted) return;
        final result = await _choose(
          '选择插件目录',
          [const PluginConfigOption('@new', '新建目录'), ...options],
          [if (controller.text.isNotEmpty) controller.text],
        );
        if (result == null) return;
        if (result.contains('@new')) {
          if (!mounted) return;
          final input = TextEditingController();
          try {
            final name = await TideDialogs.show<String>(
              context: context,
              builder: (ctx) => TideDialogSurface(
                kind: TideDialogKind.form,
                title: const Text('新建插件目录'),
                content: TextField(
                  controller: input,
                  decoration: const InputDecoration(
                    hintText: '例如 attachments/mail',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, input.text.trim()),
                    child: const Text('创建'),
                  ),
                ],
              ),
            );
            if (name != null && name.isNotEmpty)
              value = await widget.createDirectory!(name);
          } finally {
            input.dispose();
          }
        } else {
          value = result.isEmpty ? '' : result.first;
        }
      } else if (kind == 'timezone') {
        final options =
            tz.timeZoneDatabase.locations.keys
                .map((name) => PluginConfigOption(name, name))
                .toList()
              ..sort((a, b) => a.label.compareTo(b.label));
        final result = await _choose('选择时区', options, [
          if (controller.text.isNotEmpty) controller.text,
        ]);
        if (result != null) value = result.isEmpty ? '' : result.first;
      } else if (kind == 'date') {
        var date = DateTime.tryParse(controller.text) ?? DateTime.now();
        final first = DateTime(1900), last = DateTime(2200, 12, 31);
        if (date.isBefore(first) || date.isAfter(last)) date = DateTime.now();
        value = await TideDialogs.show<String>(
          context: context,
          builder: (ctx) => TideDialogSurface(
            kind: TideDialogKind.choice,
            title: Text(field['title']?.toString() ?? key),
            content: SizedBox(
              width: 320,
              height: 320,
              child: CalendarDatePicker(
                initialDate: date,
                firstDate: first,
                lastDate: last,
                onDateChanged: (d) => date = d,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, date.toIso8601String().substring(0, 10)),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else if (kind == 'time') {
        final parts = controller.text.split(':');
        var hour = parts.length == 2 ? int.tryParse(parts[0]) ?? 0 : 0;
        var minute = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
        hour = hour.clamp(0, 23);
        minute = minute.clamp(0, 59);
        value = await TideDialogs.show<String>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => TideDialogSurface(
              kind: TideDialogKind.choice,
              title: Text(field['title']?.toString() ?? key),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text('小时'),
                  Slider(
                    value: hour.toDouble(),
                    min: 0,
                    max: 23,
                    divisions: 23,
                    onChanged: (v) => refresh(() => hour = v.round()),
                  ),
                  const Text('分钟'),
                  Slider(
                    value: minute.toDouble(),
                    min: 0,
                    max: 59,
                    divisions: 59,
                    onChanged: (v) => refresh(() => minute = v.round()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
        );
      }
      if (mounted && value != null) setState(() => controller.text = value!);
    } catch (_) {
      if (mounted) setState(() => _error = '选择失败，请检查文件权限、路径或插件权限后重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}

class _PluginConfigSection extends StatefulWidget {
  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _PluginConfigSection({
    super.key,
    required this.title,
    required this.initiallyExpanded,
    required this.children,
  });

  @override
  State<_PluginConfigSection> createState() => _PluginConfigSectionState();
}

class _PluginConfigSectionState extends State<_PluginConfigSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _expanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: theme.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Keep editors mounted and give the open section its natural height.
        Visibility(
          visible: _expanded,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}
