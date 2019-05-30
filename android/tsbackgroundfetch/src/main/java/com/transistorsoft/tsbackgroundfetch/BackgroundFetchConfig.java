package com.transistorsoft.tsbackgroundfetch;

import android.app.job.JobInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Created by chris on 2018-01-11.
 */

public class BackgroundFetchConfig {
    private Builder config;

    private static final int MINIMUM_FETCH_INTERVAL = 15;

    public static final String FIELD_MINIMUM_FETCH_INTERVAL = "minimumFetchInterval";
    public static final String FIELD_START_ON_BOOT = "startOnBoot";
    public static final String FIELD_FORCE_RELOAD = "forceReload";
    public static final String FIELD_REQUIRED_NETWORK_TYPE = "requiredNetworkType";
    public static final String FIELD_REQUIRES_BATTERY_NOT_LOW = "requiresBatteryNotLow";
    public static final String FIELD_REQUIRES_CHARGING = "requiresCharging";
    public static final String FIELD_REQUIRES_DEVICE_IDLE = "requiresDeviceIdle";
    public static final String FIELD_REQUIRES_STORAGE_NOT_LOW = "requiresStorageNotLow";
    public static final String FIELD_STOP_ON_TERMINATE = "stopOnTerminate";
    public static final String FIELD_JOB_SERVICE = "jobService";

    public static class Builder {
        private int minimumFetchInterval           = MINIMUM_FETCH_INTERVAL;
        private boolean stopOnTerminate     = true;
        private boolean startOnBoot         = false;
        private boolean forceReload         = false;
        private int requiredNetworkType     = 0;
        private boolean requiresBatteryNotLow   = false;
        private boolean requiresCharging    = false;
        private boolean requiresDeviceIdle  = false;
        private boolean requiresStorageNotLow = false;

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

        public Builder setRequiredNetworkType(int networkType) {

            if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                if (
                    (networkType != JobInfo.NETWORK_TYPE_ANY) &&
                    (networkType != JobInfo.NETWORK_TYPE_CELLULAR) &&
                    (networkType != JobInfo.NETWORK_TYPE_NONE) &&
                    (networkType != JobInfo.NETWORK_TYPE_NOT_ROAMING) &&
                    (networkType != JobInfo.NETWORK_TYPE_UNMETERED)
                ) {
                    Log.e(BackgroundFetch.TAG, "[ERROR] Invalid " + FIELD_REQUIRED_NETWORK_TYPE + ": " + networkType + "; Defaulting to NETWORK_TYPE_NONE");
                    networkType = JobInfo.NETWORK_TYPE_NONE;
                }
                this.requiredNetworkType = networkType;
            }
            return this;
        }

        public Builder setRequiresBatteryNotLow(boolean value) {
            this.requiresBatteryNotLow = value;
            return this;
        }

        public Builder setRequiresCharging(boolean value) {
            this.requiresCharging = value;
            return this;
        }

        public Builder setRequiresDeviceIdle(boolean value) {
            this.requiresDeviceIdle = value;
            return this;
        }

        public Builder setRequiresStorageNotLow(boolean value) {
            this.requiresStorageNotLow = value;
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
            if (preferences.contains(FIELD_MINIMUM_FETCH_INTERVAL)) {
                setMinimumFetchInterval(preferences.getInt(FIELD_MINIMUM_FETCH_INTERVAL, minimumFetchInterval));
            }
            if (preferences.contains(FIELD_STOP_ON_TERMINATE)) {
                setStopOnTerminate(preferences.getBoolean(FIELD_STOP_ON_TERMINATE, stopOnTerminate));
            }
            if (preferences.contains(FIELD_REQUIRED_NETWORK_TYPE)) {
                setRequiredNetworkType(preferences.getInt(FIELD_REQUIRED_NETWORK_TYPE, requiredNetworkType));
            }
            if (preferences.contains(FIELD_REQUIRES_BATTERY_NOT_LOW)) {
                setRequiresBatteryNotLow(preferences.getBoolean(FIELD_REQUIRES_BATTERY_NOT_LOW, requiresBatteryNotLow));
            }
            if (preferences.contains(FIELD_REQUIRES_CHARGING)) {
                setRequiresCharging(preferences.getBoolean(FIELD_REQUIRES_CHARGING, requiresCharging));
            }
            if (preferences.contains(FIELD_REQUIRES_DEVICE_IDLE)) {
                setRequiresDeviceIdle(preferences.getBoolean(FIELD_REQUIRES_DEVICE_IDLE, requiresDeviceIdle));
            }
            if (preferences.contains(FIELD_REQUIRES_STORAGE_NOT_LOW)) {
                setRequiresStorageNotLow(preferences.getBoolean(FIELD_REQUIRES_STORAGE_NOT_LOW, requiresStorageNotLow));
            }
            if (preferences.contains(FIELD_START_ON_BOOT)) {
                setStartOnBoot(preferences.getBoolean(FIELD_START_ON_BOOT, startOnBoot));
            }
            if (preferences.contains(FIELD_FORCE_RELOAD)) {
                setForceReload(preferences.getBoolean(FIELD_FORCE_RELOAD, forceReload));
            }
            if (preferences.contains(FIELD_JOB_SERVICE)) {
                setJobService(preferences.getString(FIELD_JOB_SERVICE, null));
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
        editor.putInt(FIELD_MINIMUM_FETCH_INTERVAL, config.minimumFetchInterval);
        editor.putBoolean(FIELD_STOP_ON_TERMINATE, config.stopOnTerminate);
        editor.putBoolean(FIELD_START_ON_BOOT, config.startOnBoot);
        editor.putBoolean(FIELD_FORCE_RELOAD, config.forceReload);
        editor.putInt(FIELD_REQUIRED_NETWORK_TYPE, config.requiredNetworkType);
        editor.putBoolean(FIELD_REQUIRES_BATTERY_NOT_LOW, config.requiresBatteryNotLow);
        editor.putBoolean(FIELD_REQUIRES_CHARGING, config.requiresCharging);
        editor.putBoolean(FIELD_REQUIRES_DEVICE_IDLE, config.requiresDeviceIdle);
        editor.putBoolean(FIELD_REQUIRES_STORAGE_NOT_LOW, config.requiresStorageNotLow);
        editor.putString(FIELD_JOB_SERVICE, config.jobService);
        editor.apply();
    }

    public int getMinimumFetchInterval() {
        return config.minimumFetchInterval;
    }

    public int getRequiredNetworkType() { return config.requiredNetworkType; }
    public boolean getRequiresBatteryNotLow() { return config.requiresBatteryNotLow; }
    public boolean getRequiresCharging() { return config.requiresCharging; }
    public boolean getRequiresDeviceIdle() { return config.requiresDeviceIdle; }
    public boolean getRequiresStorageNotLow() { return config.requiresStorageNotLow; }
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
            output.put(FIELD_MINIMUM_FETCH_INTERVAL, config.minimumFetchInterval);
            output.put(FIELD_STOP_ON_TERMINATE, config.stopOnTerminate);
            output.put(FIELD_REQUIRED_NETWORK_TYPE, config.requiredNetworkType);
            output.put(FIELD_REQUIRES_BATTERY_NOT_LOW, config.requiresBatteryNotLow);
            output.put(FIELD_REQUIRES_CHARGING, config.requiresCharging);
            output.put(FIELD_REQUIRES_DEVICE_IDLE, config.requiresDeviceIdle);
            output.put(FIELD_REQUIRES_STORAGE_NOT_LOW, config.requiresStorageNotLow);
            output.put(FIELD_START_ON_BOOT, config.startOnBoot);
            output.put(FIELD_FORCE_RELOAD, config.forceReload);
            output.put(FIELD_JOB_SERVICE, config.jobService);
            return output.toString(2);
        } catch (JSONException e) {
            e.printStackTrace();
            return output.toString();
        }
    }
}
