# GinLo — notes for Claude

- **Keep `DEVLOG.md` up to date.** After every iteration (each committed change the user asked for), add a
  section: goal, files created/changed, what was measured or verified on the phone, and what broke and how it
  was fixed. The user reads it to follow the project's progress.
- Small, incremental commits; the user follows along and learns from the code. Comment the *why*.
- Build/run (needs Java 17 + Android SDK on PATH):
  `export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=/opt/homebrew/share/android-commandlinetools; export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"`
  then `flutter build apk --profile --flavor dev` (profile: debug mode is ~10x slower for the pixel loops).
- Flavors: `dev` = GinLo Dev (boxes, scores, Lab tab), `prod` = GinLo (shop app, smoothed output).
- New `.tflite` models: run `tools/inline_buffers.py` first (the bundled LiteRT 1.4.0 can't read external weights).
- Camera rotation has one source of truth: the screen angle from `MainActivity.kt`; picture and frames both use it.
