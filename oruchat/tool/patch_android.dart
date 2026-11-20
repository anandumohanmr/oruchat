// Flutter create undaakkiya android folder-il OruChat-inu vendiya maattangal varuthunnu:
// permissions (camera, mic, internet), app name, minSdk 24.
// Run: dart run tool/patch_android.dart
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln(
      'android/app/src/main/AndroidManifest.xml kandilla. Aadyam "flutter create" cheyyanam.',
    );
    exit(1);
  }
  var t = manifest.readAsStringSync();

  const perms = [
    'INTERNET',
    'ACCESS_NETWORK_STATE',
    'CAMERA',
    'RECORD_AUDIO',
    'MODIFY_AUDIO_SETTINGS',
    'BLUETOOTH',
    'BLUETOOTH_CONNECT',
    'VIBRATE',
    'USE_BIOMETRIC',
    'USE_FINGERPRINT',
  ];
  final add = StringBuffer();
  for (final p in perms) {
    if (!t.contains('android.permission.$p"')) {
      add.writeln(
        '    <uses-permission android:name="android.permission.$p"/>',
      );
    }
  }
  if (!t.contains('android.hardware.camera')) {
    add.writeln(
      '    <uses-feature android:name="android.hardware.camera" android:required="false"/>',
    );
    add.writeln(
      '    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>',
    );
  }
  if (add.isNotEmpty) {
    t = t.replaceFirst('<application', '$add    <application');
  }
  t = t.replaceFirst(
    RegExp(r'android:label="[^"]*"'),
    'android:label="OruChat"',
  );
  manifest.writeAsStringSync(t);
  stdout.writeln('Manifest patched.');

  for (final name in ['build.gradle.kts', 'build.gradle']) {
    final f = File('android/app/$name');
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    final kts = name.endsWith('.kts');
    final re = RegExp(r'minSdk(Version)?(\s*=\s*|\s+)flutter\.minSdkVersion');
    if (re.hasMatch(s)) {
      s = s.replaceAll(re, kts ? 'minSdk = 24' : 'minSdkVersion 24');
      f.writeAsStringSync(s);
      stdout.writeln('$name patched (minSdk 24).');
    } else {
      stdout.writeln('WARNING: minSdk line kandilla in $name');
    }
  }

  // local_auth requires a FragmentActivity on Android.
  final kotlinRoot = Directory('android/app/src/main/kotlin');
  if (kotlinRoot.existsSync()) {
    for (final entity in kotlinRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('MainActivity.kt')) continue;
      var source = entity.readAsStringSync();
      source = source.replaceAll('import io.flutter.embedding.android.FlutterActivity',
          'import io.flutter.embedding.android.FlutterFragmentActivity');
      source = source.replaceAll('extends FlutterActivity', 'extends FlutterFragmentActivity');
      source = source.replaceAll(': FlutterActivity()', ': FlutterFragmentActivity()');
      entity.writeAsStringSync(source);
      stdout.writeln('MainActivity configured for biometric authentication.');
    }
  }

}
