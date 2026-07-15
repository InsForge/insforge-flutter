// tool/set_version.dart
//
// Single source of truth for the SDK version. Keeps `insforge` and
// `insforge_flutter` in lockstep and regenerates the runtime version constant
// used for the `User-Agent` header.
//
// Usage (run from the repo root):
//   dart run tool/set_version.dart 0.2.0   # set the version everywhere
//   dart run tool/set_version.dart --check # verify everything is in sync (CI)
//
// "Set" updates, all to the same version:
//   * packages/insforge/pubspec.yaml            version:
//   * packages/insforge_flutter/pubspec.yaml    version: and  insforge: ^<v>
//   * packages/insforge/lib/src/core/version.dart  insforgeSdkVersion
import 'dart:io';

const String _insforgePubspec = 'packages/insforge/pubspec.yaml';
const String _flutterPubspec = 'packages/insforge_flutter/pubspec.yaml';
const String _versionDart = 'packages/insforge/lib/src/core/version.dart';

final RegExp _semver = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');
final RegExp _versionLine = RegExp(r'^version:.*$', multiLine: true);
final RegExp _depLine = RegExp(r'^(\s+insforge:\s*\^).*$', multiLine: true);
final RegExp _dartConst = RegExp(r"const String insforgeSdkVersion = '.*';");

void main(List<String> args) {
  _ensureRepoRoot();
  if (args.isEmpty) {
    _usageAndExit();
  }
  if (args.first == '--check') {
    exit(_check() ? 0 : 1);
  }
  final version = args.first;
  if (!_semver.hasMatch(version)) {
    stderr
        .writeln('Invalid version "$version" (expected X.Y.Z[-pre][+build]).');
    exit(64);
  }
  _set(version);
}

void _set(String version) {
  _replaceFirst(_insforgePubspec, _versionLine, 'version: $version');
  _replaceFirst(_flutterPubspec, _versionLine, 'version: $version');
  _replaceFirstMapped(
    _flutterPubspec,
    _depLine,
    (Match m) => '${m.group(1)}$version',
  );
  _replaceFirst(
    _versionDart,
    _dartConst,
    "const String insforgeSdkVersion = '$version';",
  );
  stdout.writeln('Set insforge + insforge_flutter to $version '
      '(and insforge_flutter -> insforge: ^$version).');
  stdout.writeln('Regenerated $_versionDart.');
  stdout.writeln('Next: update each package CHANGELOG.md and commit.');
  stdout.writeln('Then push insforge-v$version, wait for it on pub.dev, and '
      'push insforge_flutter-v$version from the same commit.');
}

bool _check() {
  final core = _pubspecVersion(_insforgePubspec);
  final flutter = _pubspecVersion(_flutterPubspec);
  final dart = _dartVersion();
  final dep = _depConstraint();

  final problems = <String>[
    if (flutter != core)
      'insforge_flutter version ($flutter) != insforge version ($core)',
    if (dart != core)
      'version.dart insforgeSdkVersion ($dart) != insforge version ($core)',
    if (dep != core) 'insforge_flutter dep "insforge: ^$dep" != ^$core',
  ];

  if (problems.isEmpty) {
    stdout.writeln(
      'Version $core is in sync across both packages + version.dart.',
    );
    return true;
  }
  stderr.writeln('Version drift detected:');
  for (final p in problems) {
    stderr.writeln('  - $p');
  }
  stderr.writeln('Fix with: dart run tool/set_version.dart $core');
  return false;
}

// --- file helpers ---

void _replaceFirst(String path, RegExp re, String replacement) {
  final file = File(path);
  final content = file.readAsStringSync();
  if (!re.hasMatch(content)) {
    stderr.writeln('Pattern ${re.pattern} not found in $path');
    exit(70);
  }
  file.writeAsStringSync(content.replaceFirst(re, replacement));
}

void _replaceFirstMapped(
  String path,
  RegExp re,
  String Function(Match) replace,
) {
  final file = File(path);
  final content = file.readAsStringSync();
  if (!re.hasMatch(content)) {
    stderr.writeln('Pattern ${re.pattern} not found in $path');
    exit(70);
  }
  file.writeAsStringSync(content.replaceFirstMapped(re, replace));
}

String _pubspecVersion(String path) =>
    _firstGroup(path, RegExp(r'^version:\s*(.+?)\s*$', multiLine: true));

String _dartVersion() =>
    _firstGroup(_versionDart, RegExp(r"insforgeSdkVersion = '(.+?)'"));

String _depConstraint() => _firstGroup(
      _flutterPubspec,
      RegExp(r'^\s+insforge:\s*\^(.+?)\s*$', multiLine: true),
    );

String _firstGroup(String path, RegExp re) {
  final m = re.firstMatch(File(path).readAsStringSync());
  if (m == null) {
    stderr.writeln('Could not read ${re.pattern} from $path');
    exit(70);
  }
  return m.group(1)!;
}

void _ensureRepoRoot() {
  if (!File(_insforgePubspec).existsSync()) {
    stderr.writeln('Run this from the repository root '
        '(could not find $_insforgePubspec).');
    exit(66);
  }
}

void _usageAndExit() {
  stdout.writeln('Usage:');
  stdout.writeln('  dart run tool/set_version.dart <X.Y.Z>   set the version');
  stdout.writeln('  dart run tool/set_version.dart --check   verify sync (CI)');
  exit(64);
}
