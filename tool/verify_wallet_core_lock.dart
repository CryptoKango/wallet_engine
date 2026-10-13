import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart' show QuickCrypto;
import 'package:wallet_engine/src/native_bridge/wallet_core_bridge_manifest.dart';

const _expectedRepository = 'https://github.com/trustwallet/wallet-core.git';
const _sha256Pattern = r'^[a-f0-9]{64}$';
const _commitPattern = r'^[a-f0-9]{40}$';
const _releaseTargets = <String>{
  'android-arm64-v8a',
  'ios-arm64',
  'ios-simulator-universal',
};

void main(List<String> arguments) {
  final releaseMode = arguments.contains('--release');
  final file = File('native/wallet-core.lock.json');
  if (!file.existsSync()) {
    _fail('Missing native/wallet-core.lock.json.');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    _fail('Invalid native lock JSON: ${error.message}');
  }
  if (decoded is! Map<String, Object?>) {
    _fail('Native lock must be a JSON object.');
  }

  final lock = decoded;
  if (lock['schemaVersion'] != 1) {
    _fail('Unsupported native lock schemaVersion.');
  }
  final source = _object(lock, 'source');
  if (source['repository'] != _expectedRepository) {
    _fail('Wallet Core source must use the canonical repository.');
  }
  final tag = _nonEmptyString(source, 'tag');
  final commit = _nonEmptyString(source, 'commit');
  if (!RegExp(_commitPattern).hasMatch(commit)) {
    _fail('Wallet Core commit must be a full lowercase Git SHA.');
  }
  if (source['license'] != 'Apache-2.0') {
    _fail('Wallet Core source license must be reviewed as Apache-2.0.');
  }

  final archive = _object(lock, 'officialReleaseArchive');
  final url = _nonEmptyString(archive, 'url');
  if (!url.startsWith(
    'https://github.com/trustwallet/wallet-core/releases/download/$tag/',
  )) {
    _fail('Release archive must be hosted by the canonical repository.');
  }
  if (!RegExp(_sha256Pattern).hasMatch(_nonEmptyString(archive, 'sha256'))) {
    _fail('Release archive requires a lowercase SHA-256 digest.');
  }
  final appleArtifact = _object(lock, 'officialAppleArtifact');
  final appleUrl = _nonEmptyString(appleArtifact, 'url');
  if (appleUrl !=
      'https://github.com/trustwallet/wallet-core/releases/download/'
          '$tag/WalletCore.xcframework.zip') {
    _fail('Apple artifact must use the canonical release asset.');
  }
  if (!RegExp(
    _sha256Pattern,
  ).hasMatch(_nonEmptyString(appleArtifact, 'sha256'))) {
    _fail('Apple artifact requires a lowercase SHA-256 digest.');
  }

  final bridge = _object(lock, 'bridge');
  if (bridge['abiVersion'] is! int || (bridge['abiVersion'] as int) <= 0) {
    _fail('Bridge abiVersion must be a positive integer.');
  }
  if (bridge['libraryName'] != 'wallet_engine_core') {
    _fail('Unexpected bridge libraryName.');
  }
  if (tag != walletCoreProductionManifest.upstreamVersion ||
      commit != walletCoreProductionManifest.upstreamCommit ||
      source['repository'] != walletCoreProductionManifest.sourceRepository ||
      source['license'] != walletCoreProductionManifest.license ||
      bridge['abiVersion'] != walletCoreProductionManifest.abiVersion) {
    _fail('Native lock and Dart production manifest are out of sync.');
  }

  final artifacts = lock['artifacts'];
  if (artifacts is! List<Object?>) {
    _fail('Native artifacts must be a JSON array.');
  }
  final targets = <String>{};
  final files = <String>{};
  for (final artifact in artifacts) {
    if (artifact is! Map<String, Object?>) {
      _fail('Every native artifact must be an object.');
    }
    final target = _nonEmptyString(artifact, 'target');
    final path = _nonEmptyString(artifact, 'file');
    final expectedHash = _nonEmptyString(artifact, 'sha256');
    if (!targets.add(target)) _fail('Duplicate native artifact target.');
    if (!files.add(path)) _fail('Duplicate native artifact file.');
    final isNativeArtifact = path.startsWith('native/artifacts/');
    final isDarwinArtifact = path.startsWith(
      'darwin/wallet_engine/WalletEngineCore.xcframework/',
    );
    final isAndroidArtifact = path.startsWith('android/src/main/jniLibs/');
    if ((!isNativeArtifact && !isDarwinArtifact && !isAndroidArtifact) ||
        path.split('/').contains('..') ||
        path.contains(r'\')) {
      _fail('Native artifact file is outside an approved package directory.');
    }
    if (!RegExp(_sha256Pattern).hasMatch(expectedHash)) {
      _fail('Every native artifact requires a SHA-256 digest.');
    }
    final artifactFile = File(path);
    if (!artifactFile.existsSync()) {
      _fail('Locked native artifact is missing: $path.');
    }
    final actualHash = _hex(
      QuickCrypto.sha256Hash(artifactFile.readAsBytesSync()),
    );
    if (actualHash != expectedHash) {
      _fail('Native artifact SHA-256 mismatch: $path.');
    }
  }
  final androidArtifacts = Directory('android/src/main/jniLibs');
  if (androidArtifacts.existsSync()) {
    final untracked =
        androidArtifacts
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((entry) => entry.path.replaceAll('\\', '/'))
            .where((path) => path.endsWith('.so') && !files.contains(path))
            .toList()
          ..sort();
    if (untracked.isNotEmpty) {
      _fail('Untracked Android native artifact: ${untracked.first}.');
    }
  }
  if (releaseMode) {
    final missing = _releaseTargets.difference(targets).toList()..sort();
    if (missing.isNotEmpty) {
      _fail('Release mode is missing native targets: ${missing.join(', ')}.');
    }
  }

  stdout.writeln(
    'Wallet Core lock verified: $tag@$commit '
    '(${artifacts.length} artifacts).',
  );
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> _object(Map<String, Object?> parent, String key) {
  final value = parent[key];
  if (value is! Map<String, Object?>) {
    _fail('$key must be a JSON object.');
  }
  return value;
}

String _nonEmptyString(Map<String, Object?> parent, String key) {
  final value = parent[key];
  if (value is! String || value.trim().isEmpty) {
    _fail('$key must be a non-empty string.');
  }
  return value;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
