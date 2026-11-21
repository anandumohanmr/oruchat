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
    'ACCESS_FINE_LOCATION',
    'ACCESS_COARSE_LOCATION',
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
  const intents =
      '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n'
      '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="upi"/></intent>\n'
      '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="geo"/></intent>\n';
  if (!t.contains('android:scheme="upi"')) {
    if (t.contains('</queries>')) {
      t = t.replaceFirst('</queries>', '$intents    </queries>');
    } else {
      t = t.replaceFirst(
        '<application',
        '    <queries>\n$intents    </queries>\n    <application',
      );
    }
  }
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
}
