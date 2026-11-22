import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import 'daily_launch_animation.dart';
import 'legal_pages.dart';
import 'main.dart' show TideMainScaffold;
import 'plugin_launch_animation.dart';
import 'plugin_system.dart';

Future<({bool resolved, TidePluginPackage? package})> _resolveLaunch() async {
  try {
    final package = await PluginSystem.instance
        .launchAnimationPackage()
        .timeout(const Duration(milliseconds: 600));
    return (resolved: true, package: package);
  } catch (_) {
    return (resolved: false, package: null);
  }
}

const _agreementKey = 'legal_agreement_accepted';
const _ageKey = 'legal_age_confirmed';
const _animationDateKey = 'launch_animation_moon_v1_date';

typedef _StartupSettings = ({
  bool accepted,
  String? animationDate,
  Future<void> Function(String) saveAnimationDate,
});

Future<_StartupSettings> _readStartupSettings() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Use the file and key prefix already used by consent writes and cold restore.
    const prefix = 'flutter.';
    final prefs = SharedPreferencesAsync(
      options: const SharedPreferencesAsyncAndroidOptions(
        backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
        originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
          fileName: 'FlutterSharedPreferences',
        ),
      ),
    );
    final values = await prefs.getAll(
      allowList: const {
        '$prefix$_agreementKey',
        '$prefix$_ageKey',
        '$prefix$_animationDateKey',
      },
    );
    final date = values['$prefix$_animationDateKey'];
    return (
      accepted:
          values['$prefix$_agreementKey'] == true &&
          values['$prefix$_ageKey'] == true,
      animationDate: date is String ? date : null,
      saveAnimationDate: (date) =>
          prefs.setString('$prefix$_animationDateKey', date),
    );
  }

  final prefs = await SharedPreferences.getInstance();
  return (
    accepted: prefs.get(_agreementKey) == true && prefs.get(_ageKey) == true,
    animationDate: switch (prefs.get(_animationDateKey)) {
      final String date => date,
      _ => null,
    },
    saveAnimationDate: (date) async {
      await prefs.setString(_animationDateKey, date);
    },
  );
}

/// Reads consent before mounting the destination and its launch decoration.
class FirstLaunchFlow extends StatefulWidget {
  const FirstLaunchFlow({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  State<FirstLaunchFlow> createState() => _FirstLaunchFlowState();
}

class _FirstLaunchFlowState extends State<FirstLaunchFlow> {
  _StartupSettings? _settings;
  Object? _error;
  bool _accepted = false;
  bool _launchResolved = false;
  TidePluginPackage? _launchPackage;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    final elapsed = Stopwatch()..start();
    final launchLookup = _resolveLaunch();
    try {
      final settings = await _readStartupSettings().timeout(
        const Duration(seconds: 3),
      );
      debugPrint('[startup] settings read in ${elapsed.elapsedMilliseconds}ms');
      final launch = await launchLookup;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _accepted = settings.accepted;
        _launchResolved = launch.resolved;
        _launchPackage = launch.package;
      });
    } catch (error) {
      debugPrint(
        '[startup] settings read failed after '
        '${elapsed.elapsedMilliseconds}ms (${error.runtimeType})',
      );
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : TextButton(onPressed: _load, child: const Text('重新读取启动设置')),
        ),
      );
    }
    final destination = _accepted
        ? _ReadyHome(onReady: widget.onReady)
        : LegalAgreementPage(
            requiredAcceptance: true,
            onAccepted: () => setState(() => _accepted = true),
          );
    final package = _launchPackage;
    if (package != null) {
      return PluginLaunchAnimation(package: package, child: destination);
    }
    if (!_launchResolved) return destination;
    return DailyLaunchAnimation(
      lastPlayedDate: settings.animationDate,
      savePlayedDate: settings.saveAnimationDate,
      force: !_accepted,
      child: destination,
    );
  }
}

class _ReadyHome extends StatefulWidget {
  const _ReadyHome({required this.onReady});
  final VoidCallback onReady;
  @override
  State<_ReadyHome> createState() => _ReadyHomeState();
}

class _ReadyHomeState extends State<_ReadyHome> {
  final _elapsed = Stopwatch()..start();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      if (!_elapsed.isRunning) return;
      _elapsed.stop();
      debugPrint(
        '[startup] first home pointer at ${_elapsed.elapsedMilliseconds}ms after mount',
      );
    },
    child: const TideMainScaffold(),
  );
}
