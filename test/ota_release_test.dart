import 'package:flutter_test/flutter_test.dart';
import 'package:skytide/ota_release.dart';

void main() {
  Map<String, dynamic> release({
    required String tag,
    bool draft = false,
    bool prerelease = false,
    List<Map<String, String>> assets = const [
      {
        'name': 'SkyTide.apk',
        'browser_download_url': 'https://example.com/SkyTide.apk',
      },
    ],
  }) {
    return {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'assets': assets,
    };
  }

  group('OTA manifest', () {
    final manifest = <String, dynamic>{
      'versionCode': 7,
      'versionName': '1.2.0',
      'downloadUrl': 'https://example.com/share/123',
      'releaseNotes': '更新说明',
    };

    test('compares build codes and accepts an HTTPS share page', () {
      final release = OtaRelease.fromManifest(manifest)!;
      expect(release.isNewerThan('1.2.0', '6'), isTrue);
      expect(release.isNewerThan('1.0.0', '7'), isFalse);
      expect(release.downloadUrl.path, '/share/123');
      expect(release.releaseNotes, '更新说明');
    });

    test('recognizes no release without treating it as an error', () {
      expect(
        OtaRelease.fromManifest(<String, dynamic>{
          'versionCode': null,
          'versionName': null,
          'downloadUrl': null,
          'releaseNotes': '',
        }),
        isNull,
      );
    });

    test('rejects invalid update links', () {
      expect(
        () => OtaRelease.fromManifest({
          ...manifest,
          'downloadUrl': 'file:///app.apk',
        }),
        throwsFormatException,
      );
    });
  });

  group('OtaReleasePicker', () {
    test('strips v prefixes and build metadata', () {
      expect(OtaReleasePicker.versionOf({'tag_name': 'v1.0.2+3'}), '1.0.2');
    });

    test('only accepts the SkyTide APK name regardless of case', () {
      final urls = OtaReleasePicker.apkUrls({
        'assets': [
          {
            'name': 'other.apk',
            'browser_download_url': 'https://example.com/other.apk',
          },
          {
            'name': 'SKYTIDE.APK',
            'browser_download_url': 'https://example.com/SkyTide.apk',
          },
        ],
      });
      expect(urls, ['https://example.com/SkyTide.apk']);
      expect(
        OtaReleasePicker.apkUrls(
          release(
            tag: 'v1.1.0',
            assets: const [
              {
                'name': 'TideBot.apk',
                'browser_download_url': 'https://example.com/TideBot.apk',
              },
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('skips drafts, prereleases and releases without apk', () {
      final picked = OtaReleasePicker.pickLatest([
        release(tag: 'v1.2.0', draft: true),
        release(tag: 'v1.1.0', prerelease: true),
        release(tag: 'v1.0.9', assets: const []),
        release(tag: 'v1.0.3'),
        release(tag: 'v1.0.1'),
      ]);
      expect(picked?['tag_name'], 'v1.0.3');
    });

    test('returns null when no published apk exists', () {
      expect(
        OtaReleasePicker.pickLatest([
          release(tag: 'v2.0.0', draft: true),
          release(tag: 'v2.0.0-beta', prerelease: true),
        ]),
        isNull,
      );
    });
  });
}
