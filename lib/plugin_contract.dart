import 'dart:convert';
import 'plugin_config_ui.dart';

/// The supported, deliberately small JSON Schema subset shared by settings and SDK.
class PluginContract {
  static const capabilities = {
    'network.sockets',
    'network.websocket',
    'network.stream',
    'network.binary',
    'network.endpoints',
    'crypto',
    'auth.pkce',
    'auth.oauth',
    'credentials',
    'background.send',
    'background.generate',
    'context.inject',
    'context.prompts',

    'chat.read',
    'chat.send',
    'media.download',
    'invocation.context',
    'modules.commonjs',
    'resources.read',
    'ui.web',
    'events.chat',
    'tasks',
    'notifications',
    'network.transfer',
    'chat.files',
    'media.requestHeaders',
    'network.originPatterns',
    'files',
    'network.files',
    'media.process',
    'schema.nested',
    'config.ui',
    'storage.large',
    'tasks.recurring',
    'workers',
    'runtime.sleep',
    'database',
    'database.vector',
    'commands',
    'events.priority',
    'appearance.launchAnimation',
    'ai',
  };
  static const hooks = {
    'context.build',
    'tool.before',
    'tool.after',
    'app.ready',
    'chat.message',
    'chat.sent',
    'task.trigger',
  };
  static final identifier = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  static void layout(Map root) {
    var count = 0;
    final ids = <String>{};
    void visit(Map node, int depth) {
      if (++count > 300 || depth > 16) throw const FormatException('界面层级或节点过多');
      final type = node['type'];
      if (!{
        'text',
        'column',
        'row',
        'card',
        'divider',
        'input',
        'toggle',
        'button',
        'progress',
        'badge',
        'spacer',
      }.contains(type)) {
        throw const FormatException('不支持的界面组件');
      }
      if (type == 'progress' && node['value'] != null) {
        final value = node['value'];
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw const FormatException('progress value 必须为 0～1 的数值');
        }
      }
      if (type == 'spacer' && node['height'] != null) {
        final height = node['height'];
        if (height is! num || !height.isFinite || height < 0 || height > 200) {
          throw const FormatException('spacer height 必须为 0～200 的数值');
        }
      }
      for (final field in ['label', 'text', 'style', 'action', 'id']) {
        if (node[field] != null && node[field] is! String)
          throw FormatException('UI $field 必须是文本');
      }
      if (type == 'input' || type == 'toggle') {
        final id = node['id'];
        if (id is! String || !identifier.hasMatch(id) || !ids.add(id))
          throw const FormatException('表单 id 无效或重复');
        if (node['value'] != null &&
            (type == 'input'
                ? node['value'] is! String
                : node['value'] is! bool)) {
          throw const FormatException('表单默认值类型无效');
        }
      }
      if (type == 'button' &&
          (node['action'] is! String ||
              !identifier.hasMatch(node['action'] as String))) {
        throw const FormatException('按钮 action 无效');
      }
      if (node['secret'] != null && node['secret'] is! bool)
        throw const FormatException('secret 必须为布尔值');
      final children = node['children'] ?? [];
      if (children is! List || children.any((child) => child is! Map))
        throw const FormatException('children 必须是组件数组');
      if (children.isNotEmpty && !{'column', 'row', 'card'}.contains(type))
        throw const FormatException('只有布局容器可包含 children');
      for (final child in children) {
        visit(child as Map, depth + 1);
      }
    }

    visit(root, 0);
  }

  /// Keeps only active form fields, preserving compatible values by ID.
  static Map<String, dynamic> formValues(
    Map root,
    Map<String, dynamic> current,
  ) {
    layout(root);
    final values = <String, dynamic>{};
    void visit(Map node) {
      final type = node['type'];
      if (type == 'input' || type == 'toggle') {
        final id = node['id'] as String;
        final old = current[id];
        values[id] = type == 'input'
            ? (old is String ? old : node['value'] ?? '')
            : (old is bool ? old : node['value'] ?? false);
      }
      for (final child in node['children'] as List? ?? []) {
        visit(child as Map);
      }
    }

    visit(root);
    return values;
  }

  static void schema(Map schema) {
    if (schema['type'] != 'object' || schema['properties'] is! Map) {
      throw const FormatException('配置/工具参数必须声明 object 和 properties');
    }
    var nodes = 0;
    void visit(Map field, int depth) {
      if (depth > 16 || ++nodes > 1000)
        throw const FormatException('Schema 层级或节点过多');
      if (!{
        'string',
        'boolean',
        'integer',
        'number',
        'object',
        'array',
      }.contains(field['type'])) {
        throw const FormatException('字段类型不支持');
      }
      for (final key in ['title', 'description', 'format']) {
        if (field[key] != null && field[key] is! String)
          throw FormatException('$key 必须为文本');
      }
      for (final key in ['minimum', 'maximum']) {
        if (field[key] != null &&
            (field[key] is! num || !(field[key] as num).isFinite))
          throw FormatException('$key 必须为有限数字');
      }
      if (field['minimum'] != null &&
          field['maximum'] != null &&
          field['minimum'] > field['maximum'])
        throw const FormatException('minimum 不能大于 maximum');
      for (final key in ['minLength', 'maxLength', 'minItems', 'maxItems']) {
        if (field[key] != null && (field[key] is! int || field[key] < 0))
          throw FormatException('$key 必须为非负整数');
      }
      for (final pair in [
        ['minLength', 'maxLength'],
        ['minItems', 'maxItems'],
      ]) {
        if (field[pair[0]] != null &&
            field[pair[1]] != null &&
            field[pair[0]] > field[pair[1]])
          throw const FormatException('最小值不能超过最大值');
      }
      if (field['type'] == 'object') {
        if (field['properties'] is! Map)
          throw const FormatException('object 必须声明 properties');
        if (field['additionalProperties'] != null &&
            field['additionalProperties'] is! bool)
          throw const FormatException('additionalProperties 必须为布尔值');
        final properties = field['properties'] as Map;
        for (final entry in properties.entries) {
          if (entry.key is! String || entry.value is! Map)
            throw const FormatException('Schema 属性无效');
          visit(entry.value as Map, depth + 1);
        }
        final required = field['required'];
        if (required != null &&
            (required is! List ||
                required.any((key) => !properties.containsKey(key))))
          throw const FormatException('required 必须引用已声明的属性');
      }
      if (field['type'] == 'array') {
        if (field['items'] is! Map)
          throw const FormatException('array 必须声明 items');
        visit(field['items'] as Map, depth + 1);
      }
      if (field['enum'] != null) {
        if (field['enum'] is! List || (field['enum'] as List).isEmpty)
          throw const FormatException('enum 必须为非空数组');
        final seen = <String>{};
        for (final option in field['enum'] as List) {
          _field('enum', option, {...field}..remove('enum'), depth);
          if (!seen.add(jsonEncode(option)))
            throw const FormatException('enum 不允许重复值');
        }
      }
      PluginConfigUi.validate(field);
      if (field.containsKey('default'))
        _field('default', field['default'], field, depth);
    }

    visit(schema, 0);
  }

  static Map<String, dynamic> values(Map schema, Map<String, dynamic> input) {
    schemaCheck(schema);
    if (utf8.encode(jsonEncode(input)).length > 1024 * 1024)
      throw const FormatException('参数超过 1 MiB');
    return Map<String, dynamic>.from(_field('参数', input, schema, 0) as Map);
  }

  static void schemaCheck(Map value) => schema(value);
  static dynamic _field(Object key, dynamic value, Map field, int depth) {
    if (depth > 16) throw FormatException('$key 层级过深');
    final valid = switch (field['type']) {
      'string' => value is String,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num && value.isFinite,
      'object' => value is Map,
      'array' => value is List,
      _ => false,
    };
    if (!valid) throw FormatException('$key 的类型不符合 ${field['type']}');
    if (field['enum'] is List &&
        !(field['enum'] as List).any((v) => jsonEncode(v) == jsonEncode(value)))
      throw FormatException('$key 必须选择声明的枚举值');
    PluginConfigUi.validateValue(key, value, field);
    if (value is num) {
      if (field['minimum'] is num && value < field['minimum'])
        throw FormatException('$key 小于最小值');
      if (field['maximum'] is num && value > field['maximum'])
        throw FormatException('$key 大于最大值');
    }
    if (value is String) {
      if (field['maxLength'] is int && value.length > field['maxLength'])
        throw FormatException('$key 超出长度限制');
      if (field['minLength'] is int && value.length < field['minLength'])
        throw FormatException('$key 长度不足');
      if (value.length > 65536) throw FormatException('$key 内容过长');
    }
    if (value is List) {
      if (value.length > (field['maxItems'] as int? ?? 10000) ||
          value.length < (field['minItems'] as int? ?? 0))
        throw FormatException('$key 数组长度超限');
      return [
        for (var i = 0; i < value.length; i++)
          _field('$key[$i]', value[i], field['items'] as Map, depth + 1),
      ];
    }
    if (value is Map) {
      final props = field['properties'] as Map;
      if (value.keys.any(
        (k) =>
            k is! String ||
            (!props.containsKey(k) && field['additionalProperties'] != true),
      ))
        throw FormatException('$key 包含未声明的配置/参数');
      final effective = <String, dynamic>{
        for (final entry in props.entries)
          entry.key as String: value.containsKey(entry.key)
              ? value[entry.key]
              : (entry.value as Map)['default'],
      };
      final result = <String, dynamic>{};
      if (field['additionalProperties'] == true)
        result.addAll(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map),
        );
      for (final entry in props.entries) {
        final child = entry.value as Map;
        final present = value.containsKey(entry.key);
        final next = present ? value[entry.key] : child['default'];
        if (next == null) {
          if ((field['required'] as List? ?? []).contains(entry.key) &&
              PluginConfigUi.visible(child, effective))
            throw FormatException('${entry.key} 为必填项');
          continue;
        }
        result[entry.key as String] = _field(
          '$key.${entry.key}',
          next,
          child,
          depth + 1,
        );
      }
      return result;
    }
    return value;
  }
}
