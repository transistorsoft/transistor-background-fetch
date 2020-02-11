package com.transistorsoft.tsbackgroundfetch;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.PowerManager;
import android.util.Log;

import static android.content.Context.POWER_SERVICE;

/**
 * Created by chris on 2018-01-11.
 */

public class FetchAlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {

        PowerManager powerManager = (PowerManager) context.getSystemService(POWER_SERVICE);
        final PowerManager.WakeLock wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, BackgroundFetch.TAG + "::" + intent.getAction());
        wakeLock.acquire(60000);

        FetchJobService.CompletionHandler completionHandler = new FetchJobService.CompletionHandler() {
            @Override
            public void finish() {
                wakeLock.release();
                Log.d(BackgroundFetch.TAG, "- FetchAlarmReceiver finish");
            }
        };

        BGTask task = new BGTask(intent.getAction(), completionHandler);
        BackgroundFetch.getInstance(context.getApplicationContext()).onFetch(task);
    }
}
