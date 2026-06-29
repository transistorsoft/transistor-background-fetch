# TSBackgroundFetch — Native Example Apps

Minimal, self-contained example apps showing how to use **TSBackgroundFetch**
directly in a native app, without a cross-platform framework (React Native,
Flutter, Capacitor or Cordova).

| Platform | Language | SDK artifact | Dependency manager |
|---|---|---|---|
| [iOS](ios/) | Swift (SwiftUI) | `TSBackgroundFetch.xcframework` | Swift Package Manager |
| [Android](android/) | Kotlin | `com.transistorsoft:tsbackgroundfetch` | Gradle / Maven Central |

Both apps demonstrate the same flow:

1. **Register** the `BGTaskScheduler` handlers at launch (iOS) — Android registers lazily.
2. **Configure** the periodic background-fetch task and subscribe to events.
3. **Start / Stop / Status** controls.
4. **Schedule** a one-off custom task.
5. **Finish** every event (including timeouts) — required so the OS keeps scheduling you.

See each platform's `README.md` for build & run instructions, including how to
manually trigger a background event from the debugger.
