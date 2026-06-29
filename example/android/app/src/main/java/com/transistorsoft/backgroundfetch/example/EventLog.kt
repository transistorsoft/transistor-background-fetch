package com.transistorsoft.backgroundfetch.example

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A tiny persistent event log backed by SharedPreferences.
 *
 * Shared between the foreground [MainActivity] and the cold-started [HeadlessTask] process,
 * so headless events that fire while the app is terminated are still visible the next time
 * the user launches the app. Entries survive until the user taps **Clear**.
 *
 * Note on processes: the SDK's `FetchJobService` runs in the app's default process, so the
 * headless task writes to the same SharedPreferences file MainActivity reads — and because a
 * terminated app is relaunched as a fresh process, that read always sees the latest entries.
 */
object EventLog {
    private const val PREFS = "tsbackgroundfetch_example"
    private const val KEY = "log"
    private const val MAX_LINES = 200
    const val TAG = "TSBackgroundFetch"

    @Synchronized
    fun append(context: Context, message: String) {
        Log.d(TAG, message)
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val timestamp = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        val line = "$timestamp  $message"
        val existing = prefs.getString(KEY, "").orEmpty()
        var combined = if (existing.isEmpty()) line else "$existing\n$line"
        // Keep the log bounded.
        val lines = combined.split("\n")
        if (lines.size > MAX_LINES) combined = lines.takeLast(MAX_LINES).joinToString("\n")
        prefs.edit().putString(KEY, combined).apply()
    }

    fun read(context: Context): String =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "").orEmpty()

    fun clear(context: Context) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY).apply()
    }
}
