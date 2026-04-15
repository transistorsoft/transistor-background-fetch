# CHANGELOG

## Unreleased
* [iOS] Add iOS DemoApp scaffolding, workspace, and shared schemes
* [Android] Upgrade build/publish pipeline, Sonatype Central Portal
* [iOS] Upgrade build/publish pipeline, add versioning and SwiftInterface
* [iOS] Bug in publish/build scripts
* [iOS] Remove obsolete TSBackgroundFetch.framework.  harden publish script
* [iOS] Hardending to publish script
* [iOS] Remove PrivacyInfo from podspec.  not required.  it's already in teh .xcframework
* [iOS] Implement Android sonatype publishing:  No more custom maven url for consumers
* [iOS] Implementing publishing for iOS/Android with cocoapods, SPM, sontatype
* [iOS] Update build commands with logging
* [iOS] Update to Gradle 8
* [iOS] codesign TSBackgroundFetch.xcframework
* [iOS] add Task type and PrivacyInfo
* [iOS] Only allow registration of BGProcessingTasks which are prefixed with com.transistorsoft
* [iOS] JobService will keep a queue of the last 5 executed Jobs to analyze for duplicates
* [iOS] Detect and dispose of duplicate events fired within 2000ms of each other
* [Android] Android 14 (SDK 34) support
* [iOS] Log JobScheduler jobId to facilitate simulating scheduleTask events with adb shell
* [iOS] Refactor headless-detection to use LifecycleManager
* [iOS] Android 12 compatibility
* [iOS] Modify build output dirs for cordova, react
* [Android] Allow reconfigure of fetch-task.  [Android] Ignore initial fetch-task scheduled immediately from JobScheduler.  Add new logic to isMainActivityActive based upon launchIntent
* [iOS] Add capacitor build-script
* [iOS] Modify build-script to Flattent .framework for MacCatalyst
* [iOS] Migrate instance vars to property
* [iOS] Set iOS min version 9.0
* [iOS] Build success for Catalyst
* [iOS] Update to reccommended settings
* [iOS] Update build-script
* [iOS] Implement task timeout warning callback
* [iOS] reconfigure build scripts to build maven repo format.  local aar dependencies no longer allowed with gradle tool 4.0.0
* [iOS] onBoot must take into account forceAlarmManager and auto-start those tasks
* [iOS] Migrate project to AndroidX.  [Android] check wakeLock.isHeld() before wakeLock.release().

## 4.1.0 &mdash; 2026-04-15
- Bug in publish/build scripts
- Release 4.1.0

## 4.0.6 &mdash; 2026-04-15
- Bug in publish/build scripts
- chore: TSBackgroundFetch 4.0.6 (url + checksum)
- Remove obsolete TSBackgroundFetch.framework.  harden publish script
- chore: TSBackgroundFetch 4.0.5 (url + checksum)
- chore: TSBackgroundFetch 4.0.4 (url + checksum)
- Hardending to publish script
- chore: TSBackgroundFetch 4.0.3 (url + checksum)
- chore: TSBackgroundFetch 4.0.3 (url + checksum)
- Remove PrivacyInfo from podspec.  not required.  it's already in teh .xcframework
- chore: TSBackgroundFetch 4.0.2 (url + checksum)
- chore: TSBackgroundFetch 4.0.2 (url + checksum)
- Add PrivacyInfo ref to .podspec
- Implement Android sonatype publishing:  No more custom maven url for consumers
- chore: TSBackgroundFetch 4.0.1 (url + checksum)
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- Update build script
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- Implementing publishing for iOS/Android with cocoapods, SPM, sontatype
- chore: TSBackgroundFetch 4.0.0 (url + checksum)
- Update build commands with logging
- Update to Gradle 8
- codesign TSBackgroundFetch.xcframework
- [iOS] add Task type and PrivacyInfo
- Only allow registration of BGProcessingTasks which are prefixed with com.transistorsoft
- JobService will keep a queue of the last 5 executed Jobs to analyze for duplicates
- Detect and dispose of duplicate events fired within 2000ms of each other
- [Android] Android 14 (SDK 34) support
- Log JobScheduler jobId to facilitate simulating scheduleTask events with adb shell
- Refactor headless-detection to use LifecycleManager
- Android 12 compatibility
- Modify build output dirs for cordova, react
- [Android] Allow reconfigure of fetch-task.  [Android] Ignore initial fetch-task scheduled immediately from JobScheduler.  Add new logic to isMainActivityActive based upon launchIntent
- Add capacitor build-script
- Modify build-script to Flattent .framework for MacCatalyst
- Migrate instance vars to property
- Set iOS min version 9.0
- Build success for Catalyst
- Update to reccommended settings
- Update build-script
- Implement task timeout warning callback
- reconfigure build scripts to build maven repo format.  local aar dependencies no longer allowed with gradle tool 4.0.0
- onBoot must take into account forceAlarmManager and auto-start those tasks
- Migrate project to AndroidX.  [Android] check wakeLock.isHeld() before wakeLock.release().
* Hardening ios publishing script for guaranteed, oneshot release success for SPM and Cocoapods.
* Remove obsolete files

## 4.0.5 &mdash; 2025-11-08
* Re-build, testing SPM releases and refresh in consumer app.

## 4.0.4 &mdash; 2025-11-08
* Re-build, testing SPM releases and refresh in consumer app.

## 4.0.3 &mdash; 2025-11-08
* Re-build.  Invalid checksum.

## 4.0.2 &mdash; 2025-11-07
* Implmement Sonatype publishing for Android.  flutter background_fetch react-native-background-fetch, cordova-background-fetch and capacitor-background-fetch can now all import tsbackgroundfetch dependency as a first-class android dependency rather than requiring a custom maven url in the consumer app!
* Add `PrivacyInfo` to iOS podspec

## 4.0.1 &mdash; 2025-11-06
* Implement Cocoapod / Swift Package Manager publishing for TSBackgroundFetch.  No more holding TSBackgroundFetch.xcframework in the plugin repo.
