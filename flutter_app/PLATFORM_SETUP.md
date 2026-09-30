# Platform setup (Flutter)

This repo ships the Dart source only. Generate the native host projects once, then
apply the permission entries below — BLE will silently fail to scan without them.

```bash
cd flutter_app
flutter create . --platforms=android,ios --project-name leakguard
flutter pub get
```

`flutter create .` will not overwrite `lib/`, `pubspec.yaml` or this file.

---

## Android

`android/app/src/main/AndroidManifest.xml` — inside `<manifest>`, above `<application>`:

```xml
<!-- Android 12+ (API 31+) -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11 and below -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />

<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

`android/app/build.gradle.kts` (or `.gradle`) — flutter_blue_plus needs a modern
min SDK:

```kotlin
android {
    compileSdk = 35
    defaultConfig {
        minSdk = 23
        targetSdk = 35
    }
}
```

`neverForLocation` on `BLUETOOTH_SCAN` is what lets the app skip the location
permission on Android 12+. If you drop that flag you must also request
`ACCESS_FINE_LOCATION` at runtime.

---

## iOS

`ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>LeakGuard connects to your HM-10 module to read live water flow.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>LeakGuard connects to your HM-10 module to read live water flow.</string>
```

`ios/Podfile` — platform floor for flutter_blue_plus:

```ruby
platform :ios, '13.0'
```

---

## Desktop (optional)

`sqflite` has no desktop implementation. To run the app on Windows, macOS or Linux
for development, add `sqflite_common_ffi` and initialise the factory before
`AppDatabase.open()`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
```

BLE on Windows/Linux via flutter_blue_plus is supported but less well tested than
mobile; the bundled simulator is the easier path for desktop UI work.

---

## Fonts

Typography comes from `google_fonts`, which fetches Inter and JetBrains Mono at
first run and caches them. For a fully offline build, download both families, drop
the `.ttf` files in `assets/fonts/`, declare them in `pubspec.yaml`, and swap the
`GoogleFonts.*` calls in `lib/core/theme/app_theme.dart` for `fontFamily` strings.
