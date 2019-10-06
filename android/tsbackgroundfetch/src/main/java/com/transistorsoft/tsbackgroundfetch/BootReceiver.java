package com.transistorsoft.tsbackgroundfetch;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * Created by chris on 2018-01-15.
 */

public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(final Context context, Intent intent) {
        // Android SDK >= LOLLIPOP_MR1 use JobScheduler which automatically persists Jobs on BOOT
        String action = intent.getAction();
        if (android.os.Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) {
            Log.d(BackgroundFetch.TAG,  "BootReceiver: " + action);
            BackgroundFetch.getThreadPool().execute(new Runnable() {
                @Override public void run() {
                    BackgroundFetch.getInstance(context.getApplicationContext()).onBoot();
                }
            });
        }
    }
}
