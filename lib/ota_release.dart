class OtaRelease {
  const OtaRelease({
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
    this.versionCode,
  });

  final String versionName;
  final String releaseNotes;
  final Uri downloadUrl;
  final int? versionCode;

  static OtaRelease? fromManifest(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('无效的 OTA 清单');
    }
    final code = data['versionCode'];
    final name = data['versionName'];
    final url = data['downloadUrl'];
    final notes = data['releaseNotes'];
    if (code == null && name == null && url == null && notes == '') {
      return null;
    }
    final uri = url is String ? httpsUrl(url) : null;
    if (code is! int ||
        code < 1 ||
        name is! String ||
        name.trim().isEmpty ||
        uri == null ||
        notes is! String) {
      throw const FormatException('无效的 OTA 版本信息');
    }
    return OtaRelease(
      versionName: name.trim(),
      versionCode: code,
      downloadUrl: uri,
      releaseNotes: notes.trim(),
    );
  }

  static Uri? httpsUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  bool isNewerThan(String installedVersion, String installedBuild) {
    final code = versionCode;
    final installedCode = int.tryParse(installedBuild);
    if (code != null && installedCode != null) return code > installedCode;
    return OtaReleasePicker.compareVersions(versionName, installedVersion) > 0;
  }
}

class OtaReleasePicker {
  static String versionOf(Map<String, dynamic> release) {
    final raw = (release['tag_name'] ?? release['name'] ?? '')
        .toString()
        .trim();
    return raw.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
  }

  static List<String> apkUrls(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return const [];
    final urls = <String>[];
    for (final raw in assets.whereType<Map>()) {
      final name = raw['name']?.toString() ?? '';
      final url = raw['browser_download_url']?.toString() ?? '';
      if (name.toLowerCase() == 'skytide.apk' &&
          OtaRelease.httpsUrl(url) != null) {
        urls.add(url.trim());
      }
    }
    return urls;
  }

  static int compareVersions(String a, String b) {
    final aa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < (aa.length > bb.length ? aa.length : bb.length); i++) {
      final x = i < aa.length ? aa[i] : 0;
      final y = i < bb.length ? bb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Map<String, dynamic>? pickLatest(Iterable<dynamic> releases) {
    Map<String, dynamic>? best;
    var bestVersion = '';
    for (final raw in releases) {
      if (raw is! Map) continue;
      final release = Map<String, dynamic>.from(raw);
      if (release['draft'] == true) continue;
      if (release['prerelease'] == true) continue;
      if (apkUrls(release).isEmpty) continue;
      final version = versionOf(release);
      if (version.isEmpty) continue;
      if (best == null || compareVersions(version, bestVersion) > 0) {
        best = release;
        bestVersion = version;
      }
    }
    return best;
  }
}
