import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_navigation.dart';
import 'db.dart';
import 'global_notice.dart';
import 'ota_daily_check.dart';
import 'ota_release.dart';
import 'plugin_operation.dart';
import 'theme.dart';
import 'transfer_progress.dart';
import 'ui_components.dart';

class OtaUpdate {
  static const _channel = MethodChannel('skytide.native.channel');
  static const _otaApi = 'https://skytide.asia/api/OTA';
  static const _releaseApi =
      'https://api.github.com/repos/yutan123/SkyTide/releases';
  static const _releaseApiFallbacks = <String>[
    'https://ghproxy.net/$_releaseApi',
    'https://mirror.ghproxy.com/$_releaseApi',
    'https://gh-proxy.com/$_releaseApi',
  ];

  static final _dailyCheck = OtaDailyCheck();

  static Future<void> checkOncePerDay() async {
    try {
      final db = DBManager();
      await _dailyCheck.run(
        date: DateTime.now().toIso8601String().substring(0, 10),
        readDate: () => db.getKV('ota_checked_date'),
        writeDate: (date) async {
          await db.setKV('ota_checked_date', date);
        },
        probe: _probe,
        onResult: (result) => _present(result, showWhenCurrent: false),
      );
    } catch (error) {
      debugPrint('[ota] check failed: $error');
    }
  }

  static bool _checkingNow = false;

  static Future<void> checkNow(BuildContext context) async {
    if (_checkingNow) return;
    _checkingNow = true;
    final operation = PluginOperation();
    try {
      final result = await TransferProgress.run(
        context,
        '正在检测新版本…',
        () => _cancellableProbe(operation),
        operation: operation,
        compact: true,
      );
      operation.check();
      if (!context.mounted) return;
      await _present(result, showWhenCurrent: true, context: context);
    } on PluginOperationCancelled {
      // A cancelled manual check must not show any result or error.
    } catch (error) {
      debugPrint('[ota] check failed: $error');
      if (context.mounted) {
        GlobalNotice.show(_errorMessage(error), color: const Color(0xFFE74C3C));
      }
    } finally {
      operation.dispose();
      _checkingNow = false;
    }
  }

  static Future<(OtaRelease?, PackageInfo)> _cancellableProbe(
    PluginOperation operation,
  ) async {
    operation.check();
    final cancelled = Completer<(OtaRelease?, PackageInfo)>();
    final unlisten = operation.listen(
      () => cancelled.completeError(const PluginOperationCancelled()),
    );
    try {
      return await Future.any([_probe(operation), cancelled.future]);
    } finally {
      unlisten();
    }
  }

  static Future<(OtaRelease?, PackageInfo)> _probe([
    PluginOperation? operation,
  ]) async {
    final release = await _latestRelease(operation);
    operation?.check();
    final installed = await PackageInfo.fromPlatform();
    operation?.check();
    return (release, installed);
  }

  static Future<void> _present(
    (OtaRelease?, PackageInfo) result, {
    required bool showWhenCurrent,
    BuildContext? context,
  }) async {
    final (release, installed) = result;
    if (release == null ||
        !release.isNewerThan(installed.version, installed.buildNumber)) {
      if (showWhenCurrent && context != null && context.mounted) {
        GlobalNotice.show(release == null ? '暂未发布可用更新' : '当前已是最新版本');
      }
      return;
    }
    if (!showWhenCurrent &&
        await DBManager().getKV('ota_ignored_version') == release.versionName) {
      return;
    }
    final target = context ?? appNavigatorKey.currentContext;
    if (target == null || !target.mounted) return;
    await _showUpdate(target, release);
  }

  static String _errorMessage(Object error) {
    if (error is SocketException) return '网络连接失败，请检查网络后重试';
    if (error is TimeoutException) return '检查更新超时，请稍后重试';
    if (error is HttpException) {
      if (error.message.contains('404')) return '更新源尚未发布可用版本';
      if (error.message.contains('403')) return '更新源访问受限，请稍后重试';
    }
    if (error is FormatException) return '更新信息格式无效';
    return '检查更新失败，请稍后重试';
  }

  static Future<OtaRelease?> _latestRelease(PluginOperation? operation) async {
    operation?.check();
    final client = http.Client();
    final unlisten = operation?.listen(client.close);
    try {
      final response = await client
          .get(
            Uri.parse(_otaApi),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw HttpException('OTA HTTP ${response.statusCode}');
      }
      return OtaRelease.fromManifest(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } catch (error) {
      operation?.check();
      debugPrint('[ota] primary source failed: $error');
    } finally {
      unlisten?.call();
      client.close();
    }
    return _latestGitHubRelease(operation);
  }

  static Future<OtaRelease> _latestGitHubRelease(
    PluginOperation? operation,
  ) async {
    final errors = <String>[];
    for (final endpoint in <String>[_releaseApi, ..._releaseApiFallbacks]) {
      operation?.check();
      final client = http.Client();
      final unlisten = operation?.listen(client.close);
      try {
        final response = await client
            .get(
              Uri.parse(endpoint),
              headers: const {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'SkyTide',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          errors.add('$endpoint HTTP ${response.statusCode}');
          continue;
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! List) {
          errors.add('$endpoint 响应不是 Release 列表');
          continue;
        }
        final picked = OtaReleasePicker.pickLatest(decoded);
        if (picked != null) {
          return OtaRelease(
            versionName: OtaReleasePicker.versionOf(picked),
            releaseNotes: picked['body']?.toString().trim() ?? '',
            downloadUrl: Uri.parse(OtaReleasePicker.apkUrls(picked).first),
          );
        }
        errors.add('$endpoint 未找到可用 Release');
      } on TimeoutException {
        errors.add('$endpoint 超时');
      } on SocketException {
        errors.add('$endpoint 网络不可达');
      } on FormatException {
        errors.add('$endpoint 返回非 JSON 数据');
      } catch (error) {
        errors.add('$endpoint $error');
      } finally {
        unlisten?.call();
        client.close();
      }
    }
    operation?.check();
    throw HttpException('所有更新源均不可用：${errors.join('；')}');
  }

  static Future<void> _showUpdate(
    BuildContext context,
    OtaRelease release,
  ) async {
    final version = release.versionName;
    final notes = release.releaseNotes.isEmpty
        ? '有新的 SkyTide 版本可用。'
        : release.releaseNotes;
    final action = await TideDialogs.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = TideTheme.of(ctx);
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: TideDialogs.glassContent(
              context: ctx,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '发现新版本 $version',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'TideFont',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  notes,
                  style: TextStyle(
                    color: theme.textWeak,
                    fontFamily: 'TideFont',
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TideDialogs.glassButton(
                        '忽略此版本',
                        color: theme.buttonSecondary,
                        textColor: theme.textStrong,
                        onTap: () => Navigator.pop(ctx, 'ignore'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TideDialogs.glassButton(
                        '下载',
                        onTap: () => Navigator.pop(ctx, 'update'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == 'ignore') {
      await DBManager().setKV('ota_ignored_version', version);
      return;
    }
    if (action != 'update' || !context.mounted) return;
    try {
      await TransferProgress.run(context, '正在获取安装包…', () async {
        if (!context.mounted) return;
        await _channel
            .invokeMethod<void>('openUpdateInBrowser', {
              'url': release.downloadUrl.toString(),
            })
            .timeout(const Duration(seconds: 8));
      });
    } catch (_) {
      if (context.mounted) {
        GlobalNotice.show('无法打开浏览器下载，请稍后重试', color: const Color(0xFFE74C3C));
      }
    }
  }
}
