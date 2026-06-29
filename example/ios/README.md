# TSBackgroundFetch — iOS Swift Example

A minimal SwiftUI app that uses `TSBackgroundFetch` through its modern Swift API,
`BackgroundFetch.shared`.

## Requirements

- Xcode 16 or newer
- iOS 17+ device or simulator (the app target deploys to iOS 17; the SDK's Swift
  overlay itself requires iOS 13+)

## How the SDK is linked

This example consumes the SDK as a **local Swift package** so it builds straight
from this repository. The reference is declared in the Xcode project as:

```
XCLocalSwiftPackageReference  relativePath = "../../.."   →  native/background-fetch/Package.swift
```

It uses the `BackgroundFetch` product (the Swift overlay), so a single
`import BackgroundFetch` exposes `BackgroundFetch.shared`. The binary
`TSBackgroundFetch.xcframework` is still downloaded from the GitHub release by SPM.

### Using it in your own app

Add the package by URL instead of the local path:

> File ▸ Add Package Dependencies… ▸
> `https://github.com/transistorsoft/transistor-background-fetch`

Then add the **BackgroundFetch** library product to your target.

## Run

1. Open `BackgroundFetchExample.xcodeproj`.
2. Select your team under **Signing & Capabilities** (the bundle id is
   `com.transistorsoft.backgroundfetch.example` — change it to your own).
3. Build & run on a device or simulator.

## Background configuration

`Info.plist` already declares everything required:

- `UIBackgroundModes` → `fetch`, `processing`
- `BGTaskSchedulerPermittedIdentifiers` → `com.transistorsoft.fetch`,
  `com.transistorsoft.customtask`

Custom `scheduleTask` identifiers must be prefixed with `com.transistorsoft.` and
listed in `BGTaskSchedulerPermittedIdentifiers`.

## Triggering an event manually

Background fetch normally fires on the OS's own schedule. To force one while paused
at a breakpoint, run in the Xcode debugger console (LLDB):

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.transistorsoft.fetch"]
```

For the scheduled processing task use `@"com.transistorsoft.customtask"`.
