package com.transistorsoft.tsbackgroundfetch;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Created by chris on 2018-01-11.
 */

public class FetchAlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        BackgroundFetch.getInstance(context.getApplicationContext()).onFetch();
    }
}
