# --- TSBackgroundFetch: keep Android components referenced from the manifest ---
-keep class com.transistorsoft.tsbackgroundfetch.FetchJobService
-keep class com.transistorsoft.tsbackgroundfetch.FetchAlarmReceiver
-keep class com.transistorsoft.tsbackgroundfetch.BootReceiver

# (Optional but harmless) Quiet any lifecycle warnings in consumer builds
-dontwarn androidx.lifecycle.**
