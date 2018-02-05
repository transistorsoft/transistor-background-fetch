package com.transistorsoft.tsbackgroundfetch;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Created by chris on 2018-01-11.
 */

public class BackgroundFetchConfig {
    private Builder config;

    private static final int MINIMUM_FETCH_INTERVAL = 15;

    public static class Builder {
        private int minimumFetchInterval           = MINIMUM_FETCH_INTERVAL;
        private boolean stopOnTerminate     = true;
        private boolean startOnBoot         = false;
        private boolean forceReload         = false;
        private String jobService           = null;

        public Builder setMinimumFetchInterval(int fetchInterval) {
            if (fetchInterval >= MINIMUM_FETCH_INTERVAL) {
                this.minimumFetchInterval = fetchInterval;
            }
            return this;
        }

        public Builder setStopOnTerminate(boolean stopOnTerminate) {
            this.stopOnTerminate = stopOnTerminate;
            return this;
        }

        public Builder setForceReload(boolean forceReload) {
            this.forceReload = forceReload;
            return this;
        }

        public Builder setStartOnBoot(boolean startOnBoot) {
            this.startOnBoot = startOnBoot;
            return this;
        }

        public Builder setJobService(String className) {
            this.jobService = className;
            return this;
        }

        public BackgroundFetchConfig build() {
            return new BackgroundFetchConfig(this);
        }

        public BackgroundFetchConfig load(Context context) {
            SharedPreferences preferences = context.getSharedPreferences(BackgroundFetch.TAG, 0);
            if (preferences.contains("fetchInterval")) {
                setMinimumFetchInterval(preferences.getInt("fetchInterval", minimumFetchInterval));
            }
            if (preferences.contains("stopOnTerminate")) {
                setStopOnTerminate(preferences.getBoolean("stopOnTerminate", stopOnTerminate));
            }
            if (preferences.contains("startOnBoot")) {
                setStartOnBoot(preferences.getBoolean("startOnBoot", startOnBoot));
            }
            if (preferences.contains("forceReload")) {
                setForceReload(preferences.getBoolean("forceReload", forceReload));
            }
            if (preferences.contains("jobService")) {
                setJobService(preferences.getString("jobService", null));
            }
            return new BackgroundFetchConfig(this);
        }
    }

    private BackgroundFetchConfig(Builder builder) {
        config = builder;
        // Validate config
        if (config.jobService != null) {
            if (config.forceReload) {
                Log.w(BackgroundFetch.TAG, "- Configuration error:  Headless jobService is incompatible with forceReload.  Enforcing forceReload: false.");
                config.setForceReload(false);
            }
        } else if (!config.forceReload) {
            if (!config.stopOnTerminate) {
                Log.w(BackgroundFetch.TAG, "- Configuration error:  {forceReload: false, jobService: null} is incompatible with stopOnTerminate: false:  Enforcing stopOnTerminate: true.");
                config.setStopOnTerminate(true);
            }
            if (config.startOnBoot) {
                Log.w(BackgroundFetch.TAG, "- Configuration error:  {forceReload: false, jobService: null} is incompatible with startOnBoot: true:  Enforcing startOnBoot: false.");
                config.setStartOnBoot(false);
            }
        }
    }

    public void save(Context context) {
        SharedPreferences preferences = context.getSharedPreferences(BackgroundFetch.TAG, 0);
        SharedPreferences.Editor editor = preferences.edit();
        editor.putInt("minimumFetchInterval", config.minimumFetchInterval);
        editor.putBoolean("stopOnTerminate", config.stopOnTerminate);
        editor.putBoolean("startOnBoot", config.startOnBoot);
        editor.putBoolean("forceReload", config.forceReload);
        editor.putString("jobService", config.jobService);
        editor.apply();
    }

    public int getMinimumFetchInterval() {
        return config.minimumFetchInterval;
    }

    public boolean getStopOnTerminate() {
        return config.stopOnTerminate;
    }

    public boolean getStartOnBoot() {
        return config.startOnBoot;
    }

    public boolean getForceReload() {
        return config.forceReload;
    }

    public String getJobService() { return config.jobService; }

    public String toString() {
        JSONObject output = new JSONObject();
        try {
            output.put("minimumFetchInterval", config.minimumFetchInterval);
            output.put("stopOnTerminate", config.stopOnTerminate);
            output.put("startOnBoot", config.startOnBoot);
            output.put("forceReload", config.forceReload);
            output.put("jobService", config.jobService);
            return output.toString(2);
        } catch (JSONException e) {
            e.printStackTrace();
            return output.toString();
        }
    }
}
