part of 'ui_chat_room.dart';

extension _TelegramChat on _ChatRoomPageState {
  Widget _telegramHeader() {
    final theme = TideTheme.of(context);
    Widget button(IconData icon, String label, VoidCallback action) =>
        TelegramGlass(
          fillOpacity: theme.isDark ? .48 : .52,
          child: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: label,
              onPressed: action,
              icon: Icon(icon, color: theme.textStrong),
            ),
          ),
        );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 12),
        child: Row(
          children: [
            button(
              Icons.arrow_back_rounded,
              '返回',
              () => Navigator.pop(context),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: TelegramGlass(
                fillOpacity: theme.isDark ? .48 : .52,
                child: tideAppearanceSurface(
                  context,
                  'chat.header',
                  SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          left: 3,
                          child: SkyTideAvatar(
                            name: _bot['name']?.toString() ?? '',
                            path: _bot['avatar']?.toString(),
                            size: 42,
                            radius: 21,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                alignment: _typing
                                    ? const Alignment(0, -.55)
                                    : Alignment.center,
                                child: Text(
                                  _bot['name']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textStrong,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: const Alignment(0, .72),
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  opacity: _typing ? 1 : 0,
                                  child: Text(
                                    '正在输入中…',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: theme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  material: 'frosted',
                  radius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(width: 7),
            TelegramChatMenuIsland(onPressed: _telegramChatMenu),
          ],
        ),
      ),
    );
  }

  bool _telegramStartsDay(int index) => telegramStartsNewDay(
    (_msgs[index]['timestamp'] as num?)?.toInt() ?? 0,
    index == 0 ? null : (_msgs[index - 1]['timestamp'] as num?)?.toInt() ?? 0,
  );

  String _telegramDayLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    return '${date.year == now.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
  }

  Widget _telegramMessageRow(int index, Widget child) {
    final message = _msgs[index];
    final theme = TideTheme.of(context);
    return GestureDetector(
      key: _messageKeys.putIfAbsent(
        message['id']?.toString() ?? 'telegram_$index',
        GlobalKey.new,
      ),
      onLongPress: () => _telegramMessageMenu(message),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_telegramStartsDay(index))
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.isDark
                      ? const Color(0xFF303830)
                      : const Color(0xFF587850),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _telegramDayLabel(
                    (message['timestamp'] as num?)?.toInt() ?? 0,
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }

  Future<void> _telegramChatMenu(
    BuildContext anchor,
    VoidCallback onClosed,
  ) async {
    _inputFocus.unfocus();
    final action = await showTelegramMenu<int>(
      context: anchor,
      duration: const Duration(milliseconds: 180),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in [
            (Icons.call_outlined, '语音通话'),
            (Icons.history_rounded, '聊天记录管理'),
            (Icons.tune_rounded, '模型设置'),
            (Icons.person_outline_rounded, '机器人信息'),
          ].indexed)
            TelegramMenuItem(
              icon: item.$2.$1,
              label: item.$2.$2,
              onTap: () => Navigator.pop(ctx, item.$1),
            ),
        ],
      ),
    );
    if (!mounted) return;
    onClosed();
    if (action == 0) await _openCallPreparation();
    if (action == 1) _showDeleteOptions();
    if (action == 2) _showModelSettings();
    if (action == 3) _showBotInfo();
  }

  Future<void> _telegramMessageMenu(
    Map<String, dynamic> msg, {
    String? anchorMessageId,
  }) async {
    final anchor =
        _messageKeys[anchorMessageId ?? msg['id']?.toString()]?.currentContext;
    if (anchor == null) return;
    final actions = await _pluginMessageActions(msg);
    if (!mounted || !anchor.mounted) return;
    final action = await showTelegramMenu<String>(
      context: anchor,
      preferAbove: true,
      width: 205,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TelegramMenuItem(
            icon: Icons.copy_outlined,
            label: '复制',
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          if (actions.isNotEmpty)
            TelegramMenuItem(
              icon: Icons.extension_outlined,
              label: '插件操作',
              onTap: () => Navigator.pop(ctx, 'plugin'),
            ),
          TelegramMenuItem(
            icon: Icons.delete_outline_rounded,
            label: '删除',
            destructive: true,
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'copy')
      await Clipboard.setData(
        ClipboardData(text: msg['content']?.toString() ?? ''),
      );
    if (action == 'plugin') await _choosePluginMessageAction(msg, actions);
    if (action == 'delete') {
      try {
        await DBManager().deleteMessage(msg['id'].toString());
        if (mounted)
          _updateTelegram(() {
            _messagesRevision++;
            _msgs.removeWhere((m) => m['id'] == msg['id']);
            _messageKeys.remove(msg['id']?.toString());
          });
      } catch (_) {
        if (mounted) GlobalNotice.show('删除失败，请重试');
      }
    }
  }

  Widget _telegramInputBar() {
    final theme = TideTheme.of(context);
    final hasContent =
        _hasText ||
        _pendingImages.isNotEmpty ||
        _pendingDocuments.isNotEmpty ||
        _pendingExpression != null;
    return SafeArea(
      top: false,
      bottom: !_emojiPanelMounted,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
        child: TelegramGlass(
          radius: 32,
          child: tideAppearanceSurface(
            context,
            'chat.input',
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImages.isNotEmpty || _pendingDocuments.isNotEmpty)
                  _attachmentPreview(theme),
                if (_pendingExpression != null)
                  _pendingExpressionPreview(theme),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: _showEmojiPanel ? '键盘' : '表情',
                      icon: Icon(
                        _showEmojiPanel
                            ? Icons.keyboard_outlined
                            : Icons.sentiment_satisfied_alt_outlined,
                        size: 27,
                        color: theme.textWeak,
                      ),
                      onPressed: () {
                        if (_showEmojiPanel) {
                          _setEmojiPanel(false);
                          _inputFocus.requestFocus();
                        } else {
                          _toggleEmojiPanel();
                        }
                      },
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 136),
                        child: TextField(
                          controller: _msgC,
                          focusNode: _inputFocus,
                          contextMenuBuilder: androidTextContextMenu,
                          minLines: 1,
                          maxLines: 5,
                          style: TextStyle(
                            fontFamily: 'TideFont',
                            fontSize: 16,
                            color: theme.textStrong,
                          ),
                          decoration: InputDecoration(
                            hintText: _isRecording
                                ? '录音中 $_recSecs 秒…'
                                : '输入消息',
                            hintStyle: TextStyle(color: theme.textWeak),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                          ),
                          onSubmitted: (_) => _sendFromComposer(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '添加附件',
                      onPressed: _telegramAttachments,
                      icon: Icon(
                        Icons.attach_file_rounded,
                        size: 27,
                        color: theme.textWeak,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Material(
                          color: telegramGreen,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: hasContent
                                ? (_loading ? null : _sendFromComposer)
                                : ((!_isRecording &&
                                          _sendVoiceCooldown.isBlocked)
                                      ? null
                                      : _toggleRec),
                            child: Icon(
                              hasContent
                                  ? Icons.arrow_upward_rounded
                                  : (_isRecording
                                        ? Icons.stop_rounded
                                        : Icons.mic_none_rounded),
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            material: 'frosted',
            radius: BorderRadius.circular(32),
          ),
        ),
      ),
    );
  }

  Future<void> _telegramAttachments() async {
    _inputFocus.unfocus();
    _setEmojiPanel(false);
    final result = await showModalBottomSheet<TelegramAttachmentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .18),
      useSafeArea: true,
      builder: (_) => const TelegramAttachmentSheet(),
    );
    if (!mounted || result == null) return;
    if (result.paths.isNotEmpty) {
      _updateTelegram(() {
        if (result.kind == 'img') {
          _pendingImages.addAll(result.paths);
        } else {
          _pendingDocuments.addAll(result.paths);
        }
      });
    } else if (result.kind == 'img') {
      // The system photo picker grants access to the selected images itself.
      try {
        final images = await ImagePicker().pickMultiImage(limit: 36);
        if (!mounted || images.isEmpty) return;
        _updateTelegram(() {
          _pendingImages.addAll(images.map((image) => image.path));
        });
      } catch (_) {
        if (mounted) GlobalNotice.show('添加图片失败，请重试');
      }
    } else {
      await _pickMediaSource(result.kind);
    }
  }

  Widget _telegramEmojiPicker(TideTheme theme) {
    final query = _telegramEmojiSearch;
    final entries = _emojiCatalog
        .where(
          (emoji) => query.isEmpty
              ? emoji.category == _emojiCategory
              : emoji.name.contains(query) || emoji.glyph.contains(query),
        )
        .toList(growable: false);
    return TelegramGlass(
      radius: 26,
      child: SizedBox(
        height: _ChatRoomPageState._emojiPanelHeight,
        child: Column(
          children: [
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final category in _emojiCategoryIcons.entries)
                    IconButton(
                      tooltip: category.value.$2,
                      icon: Icon(
                        category.value.$1,
                        size: 22,
                        color: _emojiCategory == category.key
                            ? theme.primary
                            : theme.textWeak,
                      ),
                      onPressed: () => _updateTelegram(() {
                        _emojiCategory = category.key;
                        _telegramEmojiSearch = '';
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 34,
                child: TextField(
                  contextMenuBuilder: androidTextContextMenu,
                  onChanged: (value) =>
                      _updateTelegram(() => _telegramEmojiSearch = value),
                  style: TextStyle(fontSize: 14, color: theme.textStrong),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.textWeak,
                    ),
                    hintText: '搜索表情',
                    filled: true,
                    fillColor: theme.textWeak.withValues(alpha: .08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _emojiTab == 1
                  ? !_stickersLoaded
                        ? Center(
                            child: CircularProgressIndicator(
                              color: theme.primary,
                            ),
                          )
                        : _stickers.isEmpty
                        ? Center(
                            child: Text(
                              '暂无我的表情',
                              style: TextStyle(color: theme.textWeak),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                ),
                            itemCount: _stickers.length,
                            itemBuilder: (_, i) {
                              final sticker = _stickers[i];
                              return InkWell(
                                onTap: () => _selectSticker(sticker),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _localStickerPreview(
                                    sticker['file_path']?.toString() ?? '',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              );
                            },
                          )
                  : _emojiCatalogLoading
                  ? Center(
                      child: CircularProgressIndicator(color: theme.primary),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 45,
                          ),
                      key: ValueKey((_emojiCategory, query.isNotEmpty)),
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final emoji = entries[i];
                        return InkWell(
                          onTap: () => _insertWechatEmoji(emoji),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Image.asset(emoji.asset),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final tab in ['表情符号', '贴纸'].indexed)
                    TextButton(
                      onPressed: () {
                        _updateTelegram(() => _emojiTab = tab.$1);
                        if (tab.$1 == 1) _loadStickers();
                      },
                      child: Text(
                        tab.$2,
                        style: TextStyle(
                          color: _emojiTab == tab.$1
                              ? theme.primary
                              : theme.textWeak,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: _deleteWechatEmoji,
                    icon: Icon(Icons.backspace_outlined, color: theme.textWeak),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _telegramJoinsMessages(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    if (first == null || second == null || first['role'] != second['role'])
      return false;
    bool textBubble(Map<String, dynamic> message) =>
        !{
          'document',
          'file',
          'image',
          'video',
          'audio',
          'voice',
          'sticker',
          'emoji',
          'voice_call_card',
          'inner_thought',
        }.contains(message['type']) &&
        ![
          'image',
          'audio',
          'video',
          'image_path',
          'video_path',
          'audio_path',
          'file_path',
        ].any((key) => message[key]?.toString().isNotEmpty == true);
    return textBubble(first) &&
        textBubble(second) &&
        !telegramStartsNewDay(
          (second['timestamp'] as num?)?.toInt() ?? 0,
          (first['timestamp'] as num?)?.toInt() ?? 0,
        );
  }

  Widget _telegramContent(
    Map<String, dynamic> message,
    bool visible,
    Widget child, {
    required int index,
    bool attachment = false,
    bool voice = false,
    bool inlineStamp = false,
    Widget? photoText,
  }) {
    if (!TideTheme.of(context).isTelegram || !visible) return child;
    final streaming = message['id'].toString().startsWith('stream_');
    final stamp = !streaming && !inlineStamp
        ? _telegramMessageStamp(message)
        : null;
    if (photoText != null) {
      final isUser = message['role'] == 'user';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 8),
          TelegramBubble(
            isUser: isUser,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [photoText, if (stamp != null) stamp],
            ),
          ),
        ],
      );
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [child, if (stamp != null) stamp],
    );
    if (voice) {
      bool joinsVoice(Map<String, dynamic>? other) =>
          other != null &&
          other['role'] == message['role'] &&
          (other['type'] == 'audio' || other['type'] == 'voice') &&
          !telegramStartsNewDay(
            (other['timestamp'] as num?)?.toInt() ?? 0,
            (message['timestamp'] as num?)?.toInt() ?? 0,
          );
      return SizedBox(
        width: 228,
        child: TelegramBubble(
          isUser: message['role'] == 'user',
          joinsPrevious: joinsVoice(index > 0 ? _msgs[index - 1] : null),
          showTail: !joinsVoice(
            index + 1 < _msgs.length ? _msgs[index + 1] : null,
          ),
          child: content,
        ),
      );
    }
    if (attachment) return content;
    final previous = index > 0 ? _msgs[index - 1] : null;
    final next = index + 1 < _msgs.length ? _msgs[index + 1] : null;
    final joinsPrevious = _telegramJoinsMessages(previous, message);
    final showTail = !_telegramJoinsMessages(message, next);
    return TelegramBubble(
      isUser: message['role'] == 'user',
      showTail: showTail,
      joinsPrevious: joinsPrevious,
      child: content,
    );
  }

  Widget _telegramMessageStamp(Map<String, dynamic> message) {
    final theme = TideTheme.of(context);
    final user = message['role'] == 'user';
    final delivery = telegramDeliveryState(message);
    final sending = delivery == TelegramDeliveryState.sending;
    final failed = delivery == TelegramDeliveryState.failed;
    return Padding(
      padding: const EdgeInsets.only(top: 2, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            telegramMessageTime((message['timestamp'] as num?)?.toInt() ?? 0),
            style: TextStyle(fontSize: 10, color: theme.textWeak),
          ),
          if (user) ...[
            const SizedBox(width: 4),
            Icon(
              sending
                  ? Icons.schedule_rounded
                  : failed
                  ? Icons.error_outline_rounded
                  : Icons.done_all_rounded,
              size: 16,
              color: failed ? Colors.redAccent : theme.primary,
            ),
          ],
        ],
      ),
    );
  }
}
