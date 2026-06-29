//
//  Reexports.swift
//  BackgroundFetch (Swift overlay)
//
//  Created by Christopher Scott on 2026-06-25.
//  Copyright © 2026 Transistor Software. All rights reserved.
//
//  Re-exports the Objective-C TSBackgroundFetch module so that a single
//  `import BackgroundFetch` exposes both the Swift convenience API
//  (`BackgroundFetch.shared`) and the underlying Objective-C API when needed —
//  most importantly `TSBackgroundFetch.sharedInstance().didFinishLaunching()`,
//  which must be called at app launch to register the BGTaskScheduler handlers.
//
//  This file is only compiled into the `BackgroundFetch` Swift Package target.
//  It is NOT symlinked into the DemoApp (which links the framework directly).
//

@_exported import TSBackgroundFetch
