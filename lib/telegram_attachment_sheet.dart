import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_permissions.dart';
import 'global_notice.dart';
import 'telegram_theme_widgets.dart';
import 'theme.dart';

class TelegramAttachmentResult {
  const TelegramAttachmentResult(this.kind, [this.paths = const []]);
  final String kind;
  final List<String> paths;
}

class TelegramAttachmentSheet extends StatefulWidget {
  const TelegramAttachmentSheet({super.key});
  @override
  State<TelegramAttachmentSheet> createState() =>
      _TelegramAttachmentSheetState();
}

class _Attachment {
  _Attachment(Map map)
    : id = map['id'].toString(),
      name = map['name']?.toString() ?? '附件',
      size = (map['size'] as num?)?.toInt() ?? 0,
      duration = (map['duration'] as num?)?.toInt() ?? 0,
      thumbnail = (map['thumbnail'] as String? ?? '').isEmpty
          ? null
          : base64Decode(map['thumbnail'] as String);
  final String id, name;
  final int size, duration;
  final Uint8List? thumbnail;
}

class _TelegramAttachmentSheetState extends State<TelegramAttachmentSheet>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('skytide.native.channel');
  static const _tabs = [
    (Icons.camera_alt_outlined, '相机', 'camera'),
    (Icons.photo_library_outlined, '相册', 'img'),
    (Icons.videocam_outlined, '视频', 'video'),
    (Icons.insert_drive_file_outlined, '文件', 'file'),
  ];
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );
  final _items = <_Attachment>[];
  final _selected = <String>{};
  int _tab = 1;
  int _generation = 0;
  bool _busy = false, _loading = false, _hasMore = true, _allowed = false;
  String? _error;
  String get _kind => _tabs[_tab].$3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || _tab == 0 || _loading || !_hasMore) return;
    final generation = _generation;
    final kind = _kind;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_allowed) {
        final allowed = await AppPermissions.attachments(context, kind);
        if (!mounted || generation != _generation) return;
        _allowed = allowed;
        if (!allowed) {
          setState(() => _error = '允许访问后可在这里浏览，也可使用系统选择');
          return;
        }
      }
      final page =
          await _channel.invokeListMethod<dynamic>('listChatGallery', {
            'offset': _items.length,
            'kind': kind,
          }) ??
          [];
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.map((item) => _Attachment(item as Map)));
        _hasMore = page.length == 36;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '读取失败，请重试或使用系统选择');
      }
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  void _reset() {
    _generation++;
    _items.clear();
    _selected.clear();
    _loading = false;
    _hasMore = true;
    _allowed = false;
    _error = null;
  }

  Future<void> _reload() async {
    if (_loading || _busy) return;
    setState(_reset);
    await _load();
  }

  Future<void> _switch(int tab) async {
    if (tab == _tab || _busy || _motion.isAnimating) return;
    await _motion.forward();
    if (!mounted) return;
    setState(() {
      _tab = tab;
      _reset();
    });
    _load();
    await _motion.reverse();
  }

  Future<void> _confirm() async {
    if (_busy || _selected.isEmpty) return;
    final kind = _kind;
    setState(() => _busy = true);
    try {
      final paths =
          await _channel.invokeListMethod<String>('importChatGallery', {
            'ids': _selected.toList(),
            'kind': kind,
          }) ??
          [];
      if (mounted && paths.isNotEmpty) {
        Navigator.pop(context, TelegramAttachmentResult(kind, paths));
      }
    } on PlatformException catch (error) {
      GlobalNotice.show(error.message ?? '附件读取失败，请重新选择');
    } catch (_) {
      GlobalNotice.show('附件读取失败，请重新选择');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _systemPicker() =>
      Navigator.pop(context, TelegramAttachmentResult(_kind));

  void _toggle(_Attachment item) {
    if (_busy) return;
    if (!_selected.contains(item.id) && _selected.length >= 36) {
      GlobalNotice.show('一次最多选择36个附件');
      return;
    }
    if (item.size > 256 * 1024 * 1024) {
      GlobalNotice.show('单个附件不能超过256 MiB');
      return;
    }
    setState(() {
      if (!_selected.remove(item.id)) _selected.add(item.id);
    });
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';
  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _check(bool selected, TideTheme theme) => Container(
    width: 23,
    height: 23,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? telegramGreen : theme.surfaceVariant,
      border: Border.all(
        color: selected ? telegramGreen : theme.textFaint,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(Icons.check, size: 16, color: Colors.white)
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final height = (MediaQuery.sizeOf(context).height * .53).clamp(
      260.0,
      560.0,
    );
    return AnimatedBuilder(
      animation: _motion,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          height * .12 * Curves.easeInOut.transform(_motion.value),
        ),
        child: child,
      ),
      child: TelegramGlass(
        radius: 30,
        appearanceTarget: 'dialog.sheet',
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            height: height,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 9),
                  Container(
                    width: 35,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.textWeak.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              _tabs[_tab].$2,
                              style: TextStyle(
                                color: theme.textStrong,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_tab != 0)
                          TextButton(
                            onPressed: _busy || _selected.isEmpty
                                ? null
                                : _confirm,
                            child: Text(
                              _busy
                                  ? '导入中…'
                                  : '添加${_selected.isEmpty ? '' : ' (${_selected.length})'}',
                            ),
                          )
                        else
                          const SizedBox(width: 64),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _tab == 0
                        ? Center(
                            child: TextButton.icon(
                              onPressed: _systemPicker,
                              icon: Icon(
                                Icons.camera_alt_outlined,
                                color: theme.primary,
                              ),
                              label: const Text('打开相机'),
                            ),
                          )
                        : _browser(theme),
                  ),
                  if (_tab != 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _systemPicker,
                        child: Text(
                          _tab == 1
                              ? '打开系统相册'
                              : _tab == 2
                              ? '打开系统视频选择'
                              : '浏览其他文件',
                        ),
                      ),
                    ),
                  Row(
                    children: List.generate(
                      _tabs.length,
                      (i) => Expanded(
                        child: InkWell(
                          onTap: () => _switch(i),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _tabs[i].$1,
                                  color: i == _tab
                                      ? telegramGreen
                                      : theme.textWeak,
                                  size: 25,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _tabs[i].$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: i == _tab
                                        ? telegramGreen
                                        : theme.textWeak,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }

  Widget _browser(TideTheme theme) {
    if (_items.isEmpty) {
      if (_loading)
        return Center(child: CircularProgressIndicator(color: theme.primary));
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ??
                  (_tab == 3 ? '暂无可访问的最近文件，可浏览其他文件' : '暂无${_tabs[_tab].$2}内容'),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textWeak),
            ),
            TextButton(onPressed: _reload, child: const Text('重新加载')),
          ],
        ),
      );
    }
    Widget item(BuildContext context, int index) {
      if (index == _items.length) {
        return Center(
          child: _error != null
              ? IconButton(
                  tooltip: '重新加载',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: theme.primary),
                ),
        );
      }
      final entry = _items[index];
      final selected = _selected.contains(entry.id);
      if (_tab == 3) {
        final extension = entry.name.contains('.')
            ? entry.name.split('.').last.toUpperCase()
            : '文件';
        return Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            onTap: _busy ? null : () => _toggle(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      color: theme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textStrong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$extension · ${_size(entry.size)}',
                          style: TextStyle(fontSize: 12, color: theme.textWeak),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _check(selected, theme),
                ],
              ),
            ),
          ),
        );
      }
      return Semantics(
        label: '${_tabs[_tab].$2} ${index + 1}',
        selected: selected,
        button: true,
        child: InkWell(
          onTap: _busy ? null : () => _toggle(entry),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (entry.thumbnail != null)
                Image.memory(
                  entry.thumbnail!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                ColoredBox(
                  color: theme.surfaceVariant,
                  child: Icon(_tabs[_tab].$1, color: theme.textWeak),
                ),
              if (selected)
                ColoredBox(color: telegramGreen.withValues(alpha: .2)),
              if (_tab == 2)
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        Text(
                          _duration(entry.duration),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(top: 6, right: 6, child: _check(selected, theme)),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (event) {
        if (event.metrics.extentAfter < 300 && _error == null) _load();
        return false;
      },
      child: _tab == 3
          ? ListView.builder(
              key: ValueKey(_tab),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              itemBuilder: item,
            )
          : GridView.builder(
              key: ValueKey(_tab),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              itemBuilder: item,
            ),
    );
  }
}
