import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';

/// What the app needs from Android to update itself (docs/app-updates.md). Tests use a fake.
abstract interface class AppInstaller {
  /// The installed app's versionCode (the CI run number).
  Future<int> installedVersionCode();

  /// Where the downloaded APK goes (the app's cache, shared with the installer through a FileProvider).
  Future<String> downloadPath();

  /// Opens Android's install screen for the APK at [path]. The user confirms with "Instalovat".
  Future<void> install(String path);
}

class AndroidAppInstaller implements AppInstaller {
  const AndroidAppInstaller();

  static const _system = MethodChannel('cz.jbohacek.quizly/system');

  @override
  Future<int> installedVersionCode() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  @override
  Future<String> downloadPath() async => (await _system.invokeMethod<String>('updateApkPath'))!;

  @override
  Future<void> install(String path) => _system.invokeMethod<void>('installApk', {'path': path});
}

final appInstallerProvider = Provider<AppInstaller>((ref) => const AndroidAppInstaller());

/// The versionCode hidden with "Později": the card comes back when the app starts again.
class UpdateLater extends Notifier<int?> {
  @override
  int? build() => null;

  void hide(int versionCode) => state = versionCode;
}

final updateLaterProvider = NotifierProvider<UpdateLater, int?>(UpdateLater.new);

/// A newer version the server has, or null. Checked on Domů and when the app comes back to the front.
/// Updates are extra: a failed check just shows nothing.
final availableUpdateProvider = FutureProvider.autoDispose<AppLatest?>((ref) async {
  final later = ref.watch(updateLaterProvider);
  final client = ref.watch(apiClientProvider);
  final installer = ref.watch(appInstallerProvider);
  try {
    final latest = await client.latestApp();
    if (latest == null || latest.versionCode == later) return null;
    return latest.versionCode > await installer.installedVersionCode() ? latest : null;
  } on Object {
    return null;
  }
});
