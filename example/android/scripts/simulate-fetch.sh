#!/bin/sh
#
# Simulate a background-fetch event on a connected Android device/emulator by
# force-running the SDK's periodic fetch job (job id 999 = FETCH_JOB_ID).
#
# Usage: ./scripts/simulate-fetch.sh
#
adb shell cmd jobscheduler run -f com.transistorsoft.backgroundfetch.example 999
