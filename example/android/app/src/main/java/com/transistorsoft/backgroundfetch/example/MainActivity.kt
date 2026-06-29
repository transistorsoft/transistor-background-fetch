package com.transistorsoft.backgroundfetch.example

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.transistorsoft.backgroundfetch.example.databinding.ActivityMainBinding
import com.transistorsoft.tsbackgroundfetch.BackgroundFetch
import com.transistorsoft.tsbackgroundfetch.BackgroundFetchConfig

/**
 * Minimal example of the TSBackgroundFetch Android SDK (`com.transistorsoft:tsbackgroundfetch`).
 *
 * Demonstrates:
 *  - configuring the periodic background-fetch task and registering a [BackgroundFetch.Callback]
 *  - start / stop (the header toggle) and scheduling a one-off task
 *  - a persistent event log ([EventLog]) shared with the [HeadlessTask] process, so headless
 *    events that fire while the app is terminated appear (prefixed 💀) on the next launch
 *
 * Every event MUST be acknowledged with [BackgroundFetch.finish] — including timeouts.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        // The periodic fetch task. Any stable string works as the task id.
        private const val FETCH_TASK_ID = "com.transistorsoft.fetch"

        // A one-off custom task scheduled on demand.
        private const val CUSTOM_TASK_ID = "com.transistorsoft.customtask"
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var fetch: BackgroundFetch

    // A single callback receives every task's events; discriminate by taskId.
    private val callback = object : BackgroundFetch.Callback {
        override fun onFetch(taskId: String) {
            log("[fetch] $taskId")
            // ... perform your background work here (network sync, etc.) ...
            fetch.finish(taskId)
            log("[finish] $taskId")
        }

        override fun onTimeout(taskId: String) {
            // The OS is reclaiming the background slot — wrap up immediately.
            log("[timeout] $taskId")
            fetch.finish(taskId)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Apps targeting Android 15+ (SDK 35+) are edge-to-edge: content draws behind the
        // status & navigation bars. Inset the root so the header sits below the status bar
        // and the bottom toolbar above the navigation bar.
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        fetch = BackgroundFetch.getInstance(applicationContext)
        configure()
        updateStatus()

        // Header toggle: ON = (re)configure & start, OFF = stop everything.
        // Set the initial checked state BEFORE attaching the listener so it doesn't re-fire.
        binding.switchToggle.isChecked = true
        binding.switchToggle.setOnCheckedChangeListener { _, isOn ->
            if (isOn) {
                // configure() re-registers the callback + config and auto-starts.
                // stop(null) cleared them, so configure() — not start() — is what restores them.
                configure()
            } else {
                fetch.stop(null) // null → stop every registered task
                log("[stop] all tasks")
            }
        }
        binding.btnSchedule.setOnClickListener { scheduleTask() }
        binding.btnClear.setOnClickListener {
            EventLog.clear(this)
            renderLog()
        }

        // Show entries persisted earlier — including 💀 headless events that fired while
        // the app was terminated.
        renderLog()
    }

    override fun onResume() {
        super.onResume()
        renderLog()
    }

    /** Android has no per-app background-refresh switch — status() is always AVAILABLE. */
    private fun updateStatus() {
        val available = fetch.status() == BackgroundFetch.STATUS_AVAILABLE
        binding.txtStatus.text = "Status: ${if (available) "Available" else fetch.status().toString()}"
    }

    /** Configure the periodic background-fetch task and register the event callback. */
    private fun configure() {
        val config = BackgroundFetchConfig.Builder()
            .setTaskId(FETCH_TASK_ID)
            .setIsFetchTask(true)
            .setMinimumFetchInterval(15)   // minutes — the OS enforces a 15-minute floor
            .setStopOnTerminate(false)     // keep firing after the app is terminated …
            .setStartOnBoot(true)          // … and re-register after a reboot
            // Headless events (app terminated / post-boot) are delivered to HeadlessTask.
            // The foreground `callback` above still handles events while the app is running.
            .setJobService(HeadlessTask::class.java.name)
            .build()
        fetch.configure(config, callback)
        log("[configure] headless: stopOnTerminate=false, startOnBoot=true")
    }

    /** Schedule a one-off custom task ~60s out (uses the callback above, keyed by taskId). */
    private fun scheduleTask() {
        val config = BackgroundFetchConfig.Builder()
            .setTaskId(CUSTOM_TASK_ID)
            .setDelay(60_000L)   // milliseconds
            .setPeriodic(false)
            .build()
        fetch.scheduleTask(config)
        log("[scheduleTask] $CUSTOM_TASK_ID delay=60s")
    }

    /** Append to the persistent log, then re-render. */
    private fun log(msg: String) {
        EventLog.append(this, msg)
        runOnUiThread { renderLog() }
    }

    /** Render the persisted event log and scroll to the newest entry. */
    private fun renderLog() {
        binding.txtLog.text = EventLog.read(this)
        binding.scrollLog.post { binding.scrollLog.fullScroll(View.FOCUS_DOWN) }
    }
}
