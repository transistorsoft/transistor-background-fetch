package com.transistorsoft.tsbackgroundfetch;

import android.content.Context;
import android.content.SharedPreferences;

import org.robolectric.RuntimeEnvironment;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class TSBackgroundFetchTest {

    private Context mContext;

    @Before
    public void setUp() throws Exception {
        mContext = RuntimeEnvironment.getApplication();
        BGTask.clear();
        // Reset singletons — static fields persist within a Robolectric test class.
        resetSingleton(BackgroundFetch.class, "mInstance");
        resetSingleton(LifecycleManager.class, "sInstance");
    }

    @After
    public void tearDown() throws Exception {
        BGTask.clear();
        resetSingleton(BackgroundFetch.class, "mInstance");
        resetSingleton(LifecycleManager.class, "sInstance");
    }

    private static void resetSingleton(Class<?> clazz, String fieldName) throws Exception {
        Field field = clazz.getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(null, null);
    }

    // =========================================================================
    //  BGTask — finish guard
    // =========================================================================

    @Test
    public void testFinishCallsCompletionHandlerOnce() {
        AtomicInteger finishCount = new AtomicInteger(0);
        FetchJobService.CompletionHandler handler = finishCount::incrementAndGet;

        BGTask task = new BGTask(mContext, "test.task", handler, 100);

        task.finish();
        task.finish();
        task.finish();

        assertEquals("CompletionHandler should fire exactly once", 1, finishCount.get());
    }

    @Test
    public void testFinishPreventsTimeoutCallback() {
        AtomicInteger finishCount = new AtomicInteger(0);
        FetchJobService.CompletionHandler handler = finishCount::incrementAndGet;

        BGTask task = new BGTask(mContext, "test.task", handler, 100);
        task.finish();

        // Fire the timeout directly — should be a no-op since already finished.
        task.onTimeout(mContext);

        assertFalse("Timed-out flag should remain false after finish", task.getTimedOut());
        assertEquals("CompletionHandler should fire exactly once", 1, finishCount.get());
    }

    @Test
    public void testTimeoutSetsFlag() {
        AtomicInteger finishCount = new AtomicInteger(0);
        FetchJobService.CompletionHandler handler = finishCount::incrementAndGet;

        BGTask task = new BGTask(mContext, "test.task", handler, 101);
        BGTask.addTask(task);

        // Fire timeout directly.
        task.onTimeout(mContext);
        assertTrue("Timed-out flag should be true", task.getTimedOut());
    }

    @Test
    public void testFinishAfterTimeoutStillFiresCompletionHandler() {
        AtomicInteger finishCount = new AtomicInteger(0);
        FetchJobService.CompletionHandler handler = finishCount::incrementAndGet;

        BGTask task = new BGTask(mContext, "test.task", handler, 101);
        BGTask.addTask(task);

        // Timeout first, then plugin calls finish (normal flow).
        task.onTimeout(mContext);
        assertTrue(task.getTimedOut());

        task.finish();
        assertEquals("CompletionHandler should fire exactly once from finish()", 1, finishCount.get());
    }

    @Test
    public void testDoubleTimeoutIsNoOp() {
        AtomicInteger finishCount = new AtomicInteger(0);
        FetchJobService.CompletionHandler handler = finishCount::incrementAndGet;

        BGTask task = new BGTask(mContext, "test.task", handler, 101);
        BGTask.addTask(task);

        task.onTimeout(mContext);
        // After timeout, plugin calls finish, which sets mFinished.
        task.finish();

        // Second timeout — should be blocked by mFinished.
        task.onTimeout(mContext);

        assertEquals("CompletionHandler should fire exactly once", 1, finishCount.get());
    }

    // =========================================================================
    //  BGTask — multiple completion handlers
    // =========================================================================

    @Test
    public void testMultipleCompletionHandlers() {
        AtomicInteger count1 = new AtomicInteger(0);
        AtomicInteger count2 = new AtomicInteger(0);

        FetchJobService.CompletionHandler handler1 = count1::incrementAndGet;
        FetchJobService.CompletionHandler handler2 = count2::incrementAndGet;

        BGTask task = new BGTask(mContext, "multi.handler", handler1, 200);
        task.setCompletionHandler(handler2);

        task.finish();

        assertEquals("Handler 1 should fire once", 1, count1.get());
        assertEquals("Handler 2 should fire once", 1, count2.get());
    }

    @Test
    public void testMultipleCompletionHandlersNotFiredTwice() {
        AtomicInteger count1 = new AtomicInteger(0);
        AtomicInteger count2 = new AtomicInteger(0);

        BGTask task = new BGTask(mContext, "multi.handler", count1::incrementAndGet, 200);
        task.setCompletionHandler(count2::incrementAndGet);

        task.finish();
        task.finish();

        assertEquals(1, count1.get());
        assertEquals(1, count2.get());
    }

    // =========================================================================
    //  BGTask — static task list management
    // =========================================================================

    @Test
    public void testAddAndGetTask() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "list.test", noop, 300);
        BGTask.addTask(task);

        BGTask found = BGTask.getTask("list.test");
        assertNotNull("Should find task by ID", found);
        assertEquals("list.test", found.getTaskId());
    }

    @Test
    public void testGetTaskReturnsNullForUnknown() {
        assertNull("Should return null for unknown taskId", BGTask.getTask("nonexistent"));
    }

    @Test
    public void testRemoveTask() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "remove.test", noop, 301);
        BGTask.addTask(task);

        BGTask.removeTask("remove.test");
        assertNull("Task should be removed", BGTask.getTask("remove.test"));
    }

    @Test
    public void testFinishRemovesTask() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "finish.remove", noop, 302);
        BGTask.addTask(task);

        task.finish();
        assertNull("finish() should remove task from list", BGTask.getTask("finish.remove"));
    }

    @Test
    public void testRemoveTaskIgnoresUnknown() {
        // Should not throw.
        BGTask.removeTask("nonexistent");
    }

    @Test
    public void testClear() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask.addTask(new BGTask(mContext, "clear.1", noop, 400));
        BGTask.addTask(new BGTask(mContext, "clear.2", noop, 401));

        BGTask.clear();

        assertNull(BGTask.getTask("clear.1"));
        assertNull(BGTask.getTask("clear.2"));
    }

    @Test
    public void testTaskIdMatchingIsCaseInsensitive() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "com.transistorsoft.Fetch", noop, 500);
        BGTask.addTask(task);

        assertNotNull(BGTask.getTask("com.transistorsoft.fetch"));
        assertNotNull(BGTask.getTask("COM.TRANSISTORSOFT.FETCH"));
    }

    // =========================================================================
    //  BackgroundFetchConfig — Builder
    // =========================================================================

    @Test
    public void testConfigBuilderDefaults() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("default.test")
                .setIsFetchTask(true)
                .build();

        assertEquals("default.test", config.getTaskId());
        assertEquals(15, config.getMinimumFetchInterval());
        assertTrue(config.getStopOnTerminate());
        assertFalse(config.getStartOnBoot());
        assertFalse(config.getRequiresCharging());
        assertFalse(config.getRequiresDeviceIdle());
        assertFalse(config.getRequiresBatteryNotLow());
        assertFalse(config.getRequiresStorageNotLow());
        assertFalse(config.getForceAlarmManager());
        assertTrue("Fetch task should be periodic", config.getPeriodic());
        assertTrue(config.isFetchTask());
    }

    @Test
    public void testConfigBuilderCustomValues() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("custom.test")
                .setIsFetchTask(false)
                .setMinimumFetchInterval(30)
                .setDelay(60000)
                .setPeriodic(true)
                .setStopOnTerminate(false)
                .setStartOnBoot(true)
                .setRequiresCharging(true)
                .setRequiresDeviceIdle(true)
                .setRequiresBatteryNotLow(true)
                .setRequiresStorageNotLow(true)
                .setForceAlarmManager(true)
                .setJobService("com.example.HeadlessTask")
                .build();

        assertEquals("custom.test", config.getTaskId());
        assertFalse(config.isFetchTask());
        assertEquals(30, config.getMinimumFetchInterval());
        assertEquals(60000, config.getDelay());
        assertTrue(config.getPeriodic());
        assertFalse(config.getStopOnTerminate());
        assertTrue(config.getStartOnBoot());
        assertTrue(config.getRequiresCharging());
        assertTrue(config.getRequiresDeviceIdle());
        assertTrue(config.getRequiresBatteryNotLow());
        assertTrue(config.getRequiresStorageNotLow());
        assertTrue(config.getForceAlarmManager());
        assertEquals("com.example.HeadlessTask", config.getJobService());
    }

    @Test
    public void testConfigValidationForcesStopOnTerminateWithoutJobService() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("validate.test")
                .setStopOnTerminate(false)
                .setStartOnBoot(true)
                .build();

        // Without a jobService, stopOnTerminate must be forced true and startOnBoot forced false.
        assertTrue("stopOnTerminate should be forced true without jobService", config.getStopOnTerminate());
        assertFalse("startOnBoot should be forced false without jobService", config.getStartOnBoot());
    }

    @Test
    public void testConfigValidationAllowsStopOnTerminateFalseWithJobService() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("validate.js.test")
                .setStopOnTerminate(false)
                .setStartOnBoot(true)
                .setJobService("com.example.HeadlessTask")
                .build();

        assertFalse(config.getStopOnTerminate());
        assertTrue(config.getStartOnBoot());
    }

    @Test
    public void testGetPeriodicTrueForFetchTask() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("periodic.fetch")
                .setIsFetchTask(true)
                .setPeriodic(false)
                .build();

        // Fetch tasks are always periodic regardless of setPeriodic value.
        assertTrue("Fetch tasks should always be periodic", config.getPeriodic());
    }

    @Test
    public void testGetJobIdUsesHashCodeForNonFetchTasks() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("com.example.task")
                .setIsFetchTask(false)
                .build();

        assertEquals("com.example.task".hashCode(), config.getJobId());
    }

    @Test
    public void testGetJobIdUsesFetchJobIdForFetchTasks() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("com.transistorsoft.fetch")
                .setIsFetchTask(true)
                .build();

        assertEquals(BackgroundFetchConfig.FETCH_JOB_ID, config.getJobId());
    }

    @Test
    public void testGetJobIdReturnsZeroForForceAlarmManager() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("alarm.test")
                .setForceAlarmManager(true)
                .build();

        assertEquals(0, config.getJobId());
    }

    // =========================================================================
    //  BackgroundFetchConfig — SharedPreferences persistence
    // =========================================================================

    @Test
    public void testConfigSaveAndLoad() {
        BackgroundFetchConfig original = new BackgroundFetchConfig.Builder()
                .setTaskId("persist.test")
                .setIsFetchTask(false)
                .setMinimumFetchInterval(30)
                .setDelay(5000)
                .setPeriodic(true)
                .setStopOnTerminate(false)
                .setStartOnBoot(true)
                .setRequiresCharging(true)
                .setForceAlarmManager(true)
                .setJobService("com.example.HeadlessTask")
                .build();

        original.save(mContext);

        // Load from SharedPreferences into a fresh Builder.
        BackgroundFetchConfig loaded = new BackgroundFetchConfig.Builder().load(mContext, "persist.test");

        assertEquals(original.getTaskId(), loaded.getTaskId());
        assertEquals(original.isFetchTask(), loaded.isFetchTask());
        assertEquals(original.getMinimumFetchInterval(), loaded.getMinimumFetchInterval());
        assertEquals(original.getDelay(), loaded.getDelay());
        assertEquals(original.getPeriodic(), loaded.getPeriodic());
        assertEquals(original.getStopOnTerminate(), loaded.getStopOnTerminate());
        assertEquals(original.getStartOnBoot(), loaded.getStartOnBoot());
        assertEquals(original.getRequiresCharging(), loaded.getRequiresCharging());
        assertEquals(original.getForceAlarmManager(), loaded.getForceAlarmManager());
        assertEquals(original.getJobService(), loaded.getJobService());
    }

    @Test
    public void testConfigDestroyRemovesTaskFromSet() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("destroy.test")
                .setIsFetchTask(false)
                .build();

        config.save(mContext);

        SharedPreferences prefs = mContext.getSharedPreferences(BackgroundFetch.TAG, 0);
        assertTrue(prefs.getStringSet("tasks", null).contains("destroy.test"));

        config.destroy(mContext);

        assertFalse(prefs.getStringSet("tasks", null).contains("destroy.test"));
    }

    @Test
    public void testConfigDestroyClearsPrefsForFetchTasks() {
        // This was Bug 4 — fetch task prefs were leaked on destroy.
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("fetch.destroy.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build();

        config.save(mContext);

        SharedPreferences taskPrefs = mContext.getSharedPreferences(
                BackgroundFetch.TAG + ":fetch.destroy.test", 0);
        assertTrue(taskPrefs.contains(BackgroundFetchConfig.FIELD_TASK_ID));

        config.destroy(mContext);

        assertFalse("Fetch task prefs should be cleared on destroy",
                taskPrefs.contains(BackgroundFetchConfig.FIELD_TASK_ID));
    }

    @Test
    public void testConfigDestroyClearsPrefsForScheduledTasks() {
        BackgroundFetchConfig config = new BackgroundFetchConfig.Builder()
                .setTaskId("scheduled.destroy.test")
                .setIsFetchTask(false)
                .setDelay(5000)
                .setJobService("com.example.HeadlessTask")
                .build();

        config.save(mContext);

        SharedPreferences taskPrefs = mContext.getSharedPreferences(
                BackgroundFetch.TAG + ":scheduled.destroy.test", 0);
        assertTrue(taskPrefs.contains(BackgroundFetchConfig.FIELD_TASK_ID));

        config.destroy(mContext);

        assertFalse("Scheduled task prefs should be cleared on destroy",
                taskPrefs.contains(BackgroundFetchConfig.FIELD_TASK_ID));
    }

    // =========================================================================
    //  BackgroundFetch — configure / stop
    //  Note: configure/start/stop are synchronous. Do NOT idle the looper —
    //  LifecycleManager's ProcessLifecycleOwner registration is not available
    //  in unit tests.
    // =========================================================================

    @Test
    public void testConfigureSetsCallback() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        BackgroundFetch.Callback callback = new BackgroundFetch.Callback() {
            @Override public void onFetch(String taskId) {}
            @Override public void onTimeout(String taskId) {}
        };

        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("cb.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            callback
        );

        assertSame(callback, adapter.getFetchCallback());
    }

    @Test
    public void testStopAllNullsCallback() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("stop.all.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            new BackgroundFetch.Callback() {
                @Override public void onFetch(String taskId) {}
                @Override public void onTimeout(String taskId) {}
            }
        );

        assertNotNull(adapter.getFetchCallback());

        adapter.stop(null);

        assertNull("stop(null) should clear the fetch callback", adapter.getFetchCallback());
    }

    @Test
    public void testStopSingleTaskLeavesCallback() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        BackgroundFetch.Callback callback = new BackgroundFetch.Callback() {
            @Override public void onFetch(String taskId) {}
            @Override public void onTimeout(String taskId) {}
        };

        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("stop.single.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            callback
        );

        adapter.stop("stop.single.test");

        assertSame("stop(taskId) should NOT clear the fetch callback", callback, adapter.getFetchCallback());
    }

    @Test
    public void testReconfigurePersistsNewConfig() {
        // Bug 5 — re-configure path didn't call config.save().
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        BackgroundFetch.Callback callback = new BackgroundFetch.Callback() {
            @Override public void onFetch(String taskId) {}
            @Override public void onTimeout(String taskId) {}
        };

        // First configure.
        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("reconfig.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            callback
        );

        // Re-configure with different interval.
        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("reconfig.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(30)
                .build(),
            callback
        );

        // Load from SharedPreferences — should reflect the updated value.
        BackgroundFetchConfig loaded = new BackgroundFetchConfig.Builder().load(mContext, "reconfig.test");
        assertEquals("Re-configured interval should be persisted", 30, loaded.getMinimumFetchInterval());
    }

    @Test
    public void testStopAllClearsMConfig() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        BackgroundFetch.Callback callback = new BackgroundFetch.Callback() {
            @Override public void onFetch(String taskId) {}
            @Override public void onTimeout(String taskId) {}
        };

        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("clear.config.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            callback
        );

        assertNotNull(adapter.getConfig("clear.config.test"));

        adapter.stop(null);

        assertNull("stop(null) should clear all configs", adapter.getConfig("clear.config.test"));
    }

    @Test
    public void testStopSingleTaskRemovesConfig() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        BackgroundFetch.Callback callback = new BackgroundFetch.Callback() {
            @Override public void onFetch(String taskId) {}
            @Override public void onTimeout(String taskId) {}
        };

        adapter.configure(
            new BackgroundFetchConfig.Builder()
                .setTaskId("remove.config.test")
                .setIsFetchTask(true)
                .setMinimumFetchInterval(15)
                .build(),
            callback
        );

        adapter.stop("remove.config.test");

        assertNull("stop(taskId) should remove that config", adapter.getConfig("remove.config.test"));
    }

    @Test
    public void testStatusAlwaysReturnsAvailable() {
        BackgroundFetch adapter = BackgroundFetch.getInstance(mContext);
        assertEquals(BackgroundFetch.STATUS_AVAILABLE, adapter.status());
    }

    // =========================================================================
    //  BGTask — toMap / toJson
    // =========================================================================

    @Test
    public void testToMap() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "map.test", noop, 600);

        java.util.Map<String, Object> map = task.toMap();
        assertEquals("map.test", map.get("taskId"));
        assertEquals(false, map.get("timeout"));
    }

    @Test
    public void testToJson() throws org.json.JSONException {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "json.test", noop, 601);

        org.json.JSONObject json = task.toJson();
        assertEquals("json.test", json.getString("taskId"));
        assertFalse(json.getBoolean("timeout"));
    }

    @Test
    public void testToMapAfterTimeout() {
        FetchJobService.CompletionHandler noop = () -> {};
        BGTask task = new BGTask(mContext, "map.timeout", noop, 602);
        BGTask.addTask(task);

        task.onTimeout(mContext);

        java.util.Map<String, Object> map = task.toMap();
        assertEquals(true, map.get("timeout"));
    }
}
