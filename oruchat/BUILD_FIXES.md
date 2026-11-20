# Android build fixes

This revision fixes the GitHub Actions errors shown in the supplied build log:

1. `chat_page.dart` and `stories_tab.dart` now import `supabase_flutter`, which exposes the `FileOptions` type used by Supabase Storage uploads.
2. `tool/patch_android.dart` now sets Android NDK to `27.0.12077973` in the generated Android app Gradle file, matching the highest NDK requirement reported by the installed Flutter plugins.

## Re-run the APK build

Commit/push the project to GitHub, then open **Actions** and run **Build OruChat Android APK** again. The workflow regenerates the Android folder and runs `dart run tool/patch_android.dart`, so the NDK setting is applied automatically.

If a later build fails, share the first Dart/Gradle `Error:` line and the surrounding log (not only the final `BUILD FAILED` line).
