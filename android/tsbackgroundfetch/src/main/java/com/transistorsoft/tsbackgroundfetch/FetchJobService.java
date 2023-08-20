package com.transistorsoft.tsbackgroundfetch;

import android.annotation.TargetApi;
import android.app.job.JobParameters;
import android.app.job.JobService;
import android.os.PersistableBundle;
import android.util.Log;

/**
 * Created by chris on 2018-01-11.
 */
@TargetApi(21)
public class FetchJobService extends JobService {

    private static final LastJob sLastJob = new LastJob();

    @Override
    public boolean onStartJob(final JobParameters params) {
        PersistableBundle extras = params.getExtras();
        long scheduleAt = extras.getLong("scheduled_at");
        long dt = System.currentTimeMillis() - scheduleAt;
        // Scheduled < 1s ago?  Ignore.
        if (dt < 1000) {
            // JobScheduler always immediately fires an initial event on Periodic jobs -- We IGNORE these.
            jobFinished(params, false);
            return true;
        }

        final String taskId = extras.getString(BackgroundFetchConfig.FIELD_TASK_ID);

        // Is this a duplicate event?
        // JobScheduler has a bug in Android N that causes duplicate Jobs to fire within a few milliseconds.
        synchronized (sLastJob) {
            if (sLastJob.isDuplicate(taskId)) {
                Log.d(BackgroundFetch.TAG, "- Caught duplicate Job " + taskId + ": [IGNORED]");
                jobFinished(params, false);
                return true;
            } else {
                sLastJob.update(taskId);
            }
        }

        CompletionHandler completionHandler = () -> {
            Log.d(BackgroundFetch.TAG, "- jobFinished");
            jobFinished(params, false);
        };
        BGTask task = new BGTask(this, taskId, completionHandler, params.getJobId());
        BackgroundFetch.getInstance(getApplicationContext()).onFetch(task);

        return true;
    }

    @Override
    public boolean onStopJob(final JobParameters params) {
        Log.d(BackgroundFetch.TAG, "- onStopJob");

        PersistableBundle extras = params.getExtras();
        final String taskId = extras.getString(BackgroundFetchConfig.FIELD_TASK_ID);

        BGTask task = BGTask.getTask(taskId);
        if (task != null) {
            task.onTimeout(getApplicationContext());
        }
        jobFinished(params, false);
        return true;
    }

    public interface CompletionHandler {
        void finish();
    }

    private static class LastJob {
        private static final long OFFSET_TIME = 2000L;

        private String mTaskId = "";
        private long mTimestamp = 0;
        void update(String taskId) {
            mTaskId = taskId;
            mTimestamp = System.currentTimeMillis();
        }

        boolean isDuplicate(String taskId) {
            if ((mTimestamp == 0) || (!taskId.equalsIgnoreCase(mTaskId))) {
                return false;
            }
            long dt = System.currentTimeMillis() - mTimestamp;
            return (dt < OFFSET_TIME);
        }

        @Override
        public String toString() {
            return "[LastJob taskId: " + mTaskId + ", timestamp: " + mTimestamp + "]";
        }
    }
}
