package com.transistorsoft.tsbackgroundfetch;

import android.annotation.TargetApi;
import android.app.ActivityManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import java.util.Calendar;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * Created by chris on 2018-01-11.
 */

public class BackgroundFetch {
    public static final String TAG = "TSBackgroundFetch";

    public static final String ACTION_CONFIGURE = "configure";
    public static final String ACTION_START     = "start";
    public static final String ACTION_STOP      = "stop";
    public static final String ACTION_FINISH    = "finish";
    public static final String ACTION_STATUS    = "status";
    public static final String ACTION_FORCE_RELOAD = TAG + "-forceReload";

    public static final String EVENT_FETCH      = ".event.BACKGROUND_FETCH";

    public static final int STATUS_AVAILABLE = 2;

    private static BackgroundFetch mInstance = null;
    private static int FETCH_JOB_ID = 999;

    public static BackgroundFetch getInstance(Context context) {
        if (mInstance == null) {
            mInstance = getInstanceSynchronized(context.getApplicationContext());
        }
        return mInstance;
    }

    private static synchronized BackgroundFetch getInstanceSynchronized(Context context) {
        if (mInstance == null) mInstance = new BackgroundFetch(context.getApplicationContext());
        return mInstance;
    }

    private Context mContext;
    private BackgroundFetch.Callback mCallback;
    private BackgroundFetchConfig mConfig;
    private FetchJobService.CompletionHandler mCompletionHandler;

    private BackgroundFetch(Context context) {
        mContext = context;
    }

    public void configure(BackgroundFetchConfig config, BackgroundFetch.Callback callback) {
        Log.d(TAG, "- configure: " + config);
        mCallback = callback;
        config.save(mContext);
        mConfig = config;
        start();
    }

    public void onBoot() {
        mConfig = new BackgroundFetchConfig.Builder().load(mContext);
        if (mConfig.getStartOnBoot() && !mConfig.getStopOnTerminate()) {
            start();
        }
    }

    @TargetApi(21)
    public void start() {
        Log.d(TAG, "- start");
        if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            // API 21+ uses new JobScheduler API
            long fetchInterval = mConfig.getMinimumFetchInterval() * 60L * 1000L;
            JobScheduler jobScheduler = (JobScheduler) mContext.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            JobInfo.Builder builder = new JobInfo.Builder(FETCH_JOB_ID, new ComponentName(mContext, FetchJobService.class))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE)
                    .setRequiresDeviceIdle(false)
                    .setRequiresCharging(false)
                    .setPersisted(mConfig.getStartOnBoot() && !mConfig.getStopOnTerminate());
            if (android.os.Build.VERSION.SDK_INT >= 24) {
                builder.setPeriodic(fetchInterval, TimeUnit.MINUTES.toMillis(5));
            } else {
                builder.setPeriodic(fetchInterval);
            }
            if (jobScheduler != null) {
                jobScheduler.schedule(builder.build());
            }
        } else {
            // Everyone else get AlarmManager
            int fetchInterval = mConfig.getMinimumFetchInterval() * 60 * 1000;
            AlarmManager alarmManager = (AlarmManager) mContext.getSystemService(Context.ALARM_SERVICE);
            Calendar cal = Calendar.getInstance();
            cal.setTimeInMillis(System.currentTimeMillis());
            cal.add(Calendar.MINUTE, mConfig.getMinimumFetchInterval());
            if (alarmManager != null) {
                alarmManager.setRepeating(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), fetchInterval, getAlarmPI());
            }
        }
    }

    public void stop() {
        Log.d(TAG,"- stop");

        if (mCompletionHandler != null) {
            mCompletionHandler.finish();
        }
        if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            JobScheduler jobScheduler = (JobScheduler) mContext.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            if (jobScheduler != null) {
                jobScheduler.cancel(FETCH_JOB_ID);
            }
        } else {
            AlarmManager alarmManager = (AlarmManager) mContext.getSystemService(Context.ALARM_SERVICE);
            if (alarmManager != null) {
                alarmManager.cancel(getAlarmPI());
            }
        }
    }

    public void finish() {
        Log.d(TAG, "- finish");
        if (mCompletionHandler != null) {
            mCompletionHandler.finish();
            mCompletionHandler = null;
        }
    }

    public int status() {
        return STATUS_AVAILABLE;
    }

    /**
     * Used for Headless operation for registering completion-handler to execute #jobFinised on JobScheduler
     * @param completionHandler
     */
    public void registerCompletionHandler(FetchJobService.CompletionHandler completionHandler) {
        mCompletionHandler = completionHandler;
    }

    public void onFetch(FetchJobService.CompletionHandler completionHandler) {
        mCompletionHandler = completionHandler;
        onFetch();
    }

    public void onFetch() {
        Log.d(TAG, "- Background Fetch event received");
        if (mConfig == null) {
            mConfig = new BackgroundFetchConfig.Builder().load(mContext);
        }
        if (isMainActivityActive()) {
            if (mCallback != null) {
                mCallback.onFetch();
            }
        } else if (mConfig.getStopOnTerminate()) {
            Log.d(TAG, "- Stopping on terminate");
            stop();
        } else if (mConfig.getForceReload()) {
            Log.d(TAG, "- MainActivity is inactive");
            forceMainActivityReload();
        } else if (mConfig.getJobService() != null) {
            finish();
            // Fire a headless background-fetch event.
            if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                // API 21+ uses JobScheduler API to fire a Job to application's configured jobService class.
                JobScheduler jobScheduler = (JobScheduler) mContext.getSystemService(Context.JOB_SCHEDULER_SERVICE);
                try {
                    JobInfo.Builder builder = new JobInfo.Builder((FETCH_JOB_ID - 1), new ComponentName(mContext, Class.forName(mConfig.getJobService())))
                            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE)
                            .setRequiresDeviceIdle(false)
                            .setRequiresCharging(false)
                            .setOverrideDeadline(0L)
                            .setMinimumLatency(0L)
                            .setPersisted(false);
                    if (jobScheduler != null) {
                        jobScheduler.schedule(builder.build());
                    }
                } catch (ClassNotFoundException e) {
                    Log.e(TAG, e.getMessage());
                    e.printStackTrace();
                } catch (IllegalArgumentException e) {
                    Log.e(TAG, "- ERROR: Could not locate jobService: " + mConfig.getJobService() + ".  Did you forget to add it to your AndroidManifest.xml?");
                    Log.e(TAG, "<service android:name=\"" + mConfig.getJobService() + "\" android:permission=\"android.permission.BIND_JOB_SERVICE\" android:exported=\"true\" />");
                    e.printStackTrace();
                }
            } else {
                // API <21 uses old AlarmManager API.
                Intent intent = new Intent();
                String event = mContext.getPackageName() + EVENT_FETCH;
                intent.setAction(event);
                mContext.sendBroadcast(intent);
            }
        } else {
            // {stopOnTerminate: false, forceReload: false} with no Headless JobService??  Don't know what else to do here but stop
            Log.w(TAG, "- BackgroundFetch event has occurred while app is terminated but there's no jobService configured to handle the event.  BackgroundFetch will terminate.");
            stop();
        }
    }

    public void forceMainActivityReload() {
        Log.i(TAG,"- Forcing MainActivity reload");
        PackageManager pm = mContext.getPackageManager();
        Intent launchIntent = pm.getLaunchIntentForPackage(mContext.getPackageName());
        if (launchIntent == null) {
            Log.w(TAG, "- forceMainActivityReload failed to find launchIntent");
            return;
        }
        launchIntent.setAction(ACTION_FORCE_RELOAD);
        launchIntent.addFlags(Intent.FLAG_FROM_BACKGROUND);
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION);
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);

        mContext.startActivity(launchIntent);
    }

    public Boolean isMainActivityActive() {
        Boolean isActive = false;

        if (mContext == null || mCallback == null) {
            return false;
        }
        ActivityManager activityManager = (ActivityManager) mContext.getSystemService(Context.ACTIVITY_SERVICE);
        try {
            List<ActivityManager.RunningTaskInfo> tasks = activityManager.getRunningTasks(Integer.MAX_VALUE);
            for (ActivityManager.RunningTaskInfo task : tasks) {
                if (mContext.getPackageName().equalsIgnoreCase(task.baseActivity.getPackageName())) {
                    isActive = true;
                    break;
                }
            }
        } catch (java.lang.SecurityException e) {
            Log.w(TAG, "TSBackgroundFetch attempted to determine if MainActivity is active but was stopped due to a missing permission.  Please add the permission 'android.permission.GET_TASKS' to your AndroidManifest.  See Installation steps for more information");
            throw e;
        }
        return isActive;
    }

    private PendingIntent getAlarmPI() {
        Intent intent = new Intent(mContext, FetchAlarmReceiver.class);
        intent.setAction(TAG);
        return PendingIntent.getBroadcast(mContext, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /**
     * @interface BackgroundFetch.Callback
     */
    public interface Callback {
        void onFetch();
    }
}
