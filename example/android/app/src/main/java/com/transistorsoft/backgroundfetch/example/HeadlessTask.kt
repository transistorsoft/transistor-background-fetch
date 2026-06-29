package com.transistorsoft.backgroundfetch.example

import android.content.Context
import androidx.annotation.Keep
import com.transistorsoft.tsbackgroundfetch.BGTask
import com.transistorsoft.tsbackgroundfetch.BackgroundFetch

/**
 * Headless background-fetch handler — runs when a fetch event fires while the app is
 * **terminated** (`stopOnTerminate = false`) and after a **reboot** (`startOnBoot = true`).
 *
 * The SDK instantiates this class by **reflection** (see `BGTask.fireHeadlessEvent`), so:
 *  - it must expose a public `HeadlessTask(Context, BGTask)` constructor — the same shape
 *    the React Native and Flutter plugins use, and
 *  - it must survive R8/ProGuard (`@Keep`), since nothing references it directly.
 *
 * Wired up in [MainActivity.configure] via
 * `BackgroundFetchConfig.Builder().setJobService(HeadlessTask::class.java.name)`.
 *
 * Events are written to the shared persistent [EventLog] (prefixed with 💀) so they appear
 * in the UI the next time the user launches the app. You MUST call
 * `BackgroundFetch.getInstance(context).finish(taskId)` when the work is done (including on
 * timeout) — `BGTask.finish()` itself is not public — or the OS will stop scheduling fetch.
 */
@Keep
class HeadlessTask(context: Context, task: BGTask) {

    init {
        val appContext = context.applicationContext
        val taskId = task.taskId

        if (task.timedOut) {
            // The OS reclaimed the slot before we finished — wrap up immediately.
            EventLog.append(appContext, "💀 [HeadlessTask] timeout: $taskId")
            BackgroundFetch.getInstance(appContext).finish(taskId)
        } else {
            EventLog.append(appContext, "💀 [HeadlessTask] event: $taskId")
            // The constructor runs on the main thread — offload real work onto a background
            // thread. The try/finally guarantees finish() runs even if the work body throws,
            // so a failure can't leave the JobScheduler job hanging until the 60s timeout.
            Thread {
                try {
                    // ... perform your background work here (network sync, etc.) ...
                    EventLog.append(appContext, "💀 [HeadlessTask] finish: $taskId")
                } finally {
                    BackgroundFetch.getInstance(appContext).finish(taskId)
                }
            }.start()
        }
    }
}
