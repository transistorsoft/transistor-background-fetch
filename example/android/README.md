# TSBackgroundFetch — Android Kotlin Example

A minimal single-Activity Kotlin app that uses the `tsbackgroundfetch` library.

## Requirements

- JDK 17
- Android Studio (or the Gradle command line)
- A device or emulator running API 26+

## How the SDK is linked

The SDK is pulled from **Maven Central**:

```kotlin
dependencies {
    implementation("com.transistorsoft:tsbackgroundfetch:4.1.1")
}
```

The library AAR contributes its own manifest entries — `FetchJobService`,
`BootReceiver`, `FetchAlarmReceiver` and the `RECEIVE_BOOT_COMPLETED`,
`WAKE_LOCK` and `SCHEDULE_EXACT_ALARM` permissions (the last merged with
`android:maxSdkVersion="33"`) — so this app's `AndroidManifest.xml` declares
none of them.

## Run

```bash
./gradlew :app:installDebug
```

…or open the `android/` folder in Android Studio and Run.

## Triggering an event manually

Background fetch normally fires on the OS's own schedule (≈15-minute minimum). To
force the periodic fetch job immediately, run the helper script:

```bash
./scripts/simulate-fetch.sh
```

…which force-runs the fetch job (job id `999` = `FETCH_JOB_ID`) via `adb`:

```bash
adb shell cmd jobscheduler run -f com.transistorsoft.backgroundfetch.example 999
```

Watch the events with:

```bash
adb logcat -s TSBackgroundFetch
```

## Headless (terminated / after reboot)

This example configures `stopOnTerminate = false` and `startOnBoot = true`, and registers
a [`HeadlessTask`](app/src/main/java/com/transistorsoft/backgroundfetch/example/HeadlessTask.kt)
via `setJobService(...)`. The periodic fetch job is therefore **persisted** by the OS, so it
keeps firing after the app is terminated and survives a reboot (on API 26+ JobScheduler
re-arms the persisted job itself; the `BootReceiver` only re-schedules in the AlarmManager
fallback). Headless events go to `HeadlessTask` instead of the in-app `Callback`.

The on-screen event log is **persisted** (see
[`EventLog`](app/src/main/java/com/transistorsoft/backgroundfetch/example/EventLog.kt)), so
headless events that fired while the app was terminated appear — prefixed with 💀 — the next
time you launch it. The log is cleared only by the **Clear** button.

To see it:

```bash
# 1. Launch the app once so it registers + persists the config.
# 2. Reliably terminate it (swipe-away is OEM-dependent):
adb shell am force-stop com.transistorsoft.backgroundfetch.example
# 3. Trigger the persisted fetch job (bypasses the 15-min schedule) and watch the 💀 logs:
./scripts/simulate-fetch.sh
adb logcat -s TSBackgroundFetch
# 4. Re-launch the app — the 💀 entries are waiting in the on-screen log.
```

> Routing depends on lifecycle state when the event fires: while a started Activity exists the
> event goes to the in-app `Callback` (`[fetch]` logs); once the process is terminated (or
> running post-boot) it goes to `HeadlessTask` (💀 logs). `simulate-fetch.sh` only drives the
> headless path because the job is persisted — a result of `stopOnTerminate=false` +
> `startOnBoot=true`.
