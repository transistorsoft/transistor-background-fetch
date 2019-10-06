package com.transistorsoft.tsbackgroundfetch;

import android.annotation.TargetApi;
import android.app.job.JobParameters;
import android.app.job.JobService;
import android.util.Log;

/**
 * Created by chris on 2018-01-11.
 */
@TargetApi(21)
public class FetchJobService extends JobService {
    @Override
    public boolean onStartJob(final JobParameters params) {
        CompletionHandler completionHandler = new CompletionHandler() {
            @Override
            public void finish() {
                Log.d(BackgroundFetch.TAG, "- jobFinished");
                jobFinished(params, false);
            }
        };

        BackgroundFetch.getInstance(getApplicationContext()).onFetch(completionHandler);

        return true;
    }

    @Override
    public boolean onStopJob(final JobParameters params) {
        Log.d(BackgroundFetch.TAG, "- onStopJob");
        jobFinished(params, false);
        return true;
    }

    public interface CompletionHandler {
        void finish();
    }
}
