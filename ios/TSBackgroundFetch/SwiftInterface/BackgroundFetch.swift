//
//  BackgroundFetch.swift
//  TSBackgroundFetch
//
//  Created by Christopher Scott on 2026-04-14.
//  Copyright © 2026 Transistor Software. All rights reserved.
//
//  Swift convenience layer over the Objective-C TSBackgroundFetch API.
//
//  This file is NOT compiled into the TSBackgroundFetch XCFramework binary.
//  It imports TSBackgroundFetch as a framework and is included as source in
//  the host target (demo apps, test targets, etc.).
//
//  The Objective-C API (TSBackgroundFetch.h) is left 100% intact for existing
//  plugin bridges (React Native, Cordova, Capacitor, Flutter).
//

import Foundation
import UIKit
import TSBackgroundFetch

public final class BackgroundFetch {

    // MARK: - Singleton

    public static let shared = BackgroundFetch()
    private let manager = TSBackgroundFetch.sharedInstance()
    private init() {}

    // MARK: - Configure

    /// Configure background fetch scheduling and return the current authorisation status.
    ///
    /// Call this after ``didFinishLaunching()`` to set the fetch interval and begin scheduling.
    /// Register fetch listeners with ``onFetch(_:)`` before or immediately after calling this.
    ///
    /// - Parameter minimumFetchInterval: Minimum interval in seconds between fetch events.
    ///   Pass `0` (the default) for `UIApplicationBackgroundFetchIntervalMinimum`.
    /// - Returns: The `UIBackgroundRefreshStatus` at configuration time.
    ///   If the status is not `.available`, background fetch is not authorised.
    ///
    /// ```swift
    /// let status = await BackgroundFetch.shared.configure(minimumFetchInterval: 900)
    /// guard status == .available else { return }
    /// ```
    @discardableResult
    public func configure(minimumFetchInterval: TimeInterval = 0) async -> UIBackgroundRefreshStatus {
        await withCheckedContinuation { continuation in
            manager.configure(minimumFetchInterval) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Start / Stop

    /// Start background fetch scheduling (or resume a specific processing task).
    ///
    /// - Parameter identifier: Pass a specific task identifier to start a previously-
    ///   registered processing task. Pass `nil` (the default) to start the default
    ///   app-refresh fetch scheduling.
    /// - Throws: An `NSError` if the underlying scheduling call fails.
    public func start(identifier: String? = nil) throws {
        if let error = manager.start(identifier) { throw error }
    }

    /// Stop background fetch scheduling (or a specific processing task).
    ///
    /// - Parameter identifier: Pass a specific task identifier to stop only that task.
    ///   Pass `nil` (the default) to stop all task scheduling.
    public func stop(identifier: String? = nil) {
        manager.stop(identifier)
    }

    /// Signal that background work is complete for the given task.
    ///
    /// Always call this as soon as your background work finishes — including when
    /// `FetchEvent.timeout` is `true`. Failing to call `finish` may cause the OS to
    /// deprioritise future background launches.
    ///
    /// - Parameter taskId: The `FetchEvent.taskId` received in your fetch callback.
    public func finish(taskId: String) {
        manager.finish(taskId)
    }

    // MARK: - Status

    /// The current background-refresh authorisation status.
    ///
    /// ```swift
    /// let status = await BackgroundFetch.shared.refreshStatus
    /// ```
    public var refreshStatus: UIBackgroundRefreshStatus {
        get async {
            await withCheckedContinuation { continuation in
                manager.status { continuation.resume(returning: $0) }
            }
        }
    }

    // MARK: - App-Refresh Events

    /// Register a callback for background app-refresh events.
    ///
    /// The OS delivers a single `BGAppRefreshTask`; `BackgroundFetch` demultiplexes it
    /// to every registered listener. Each listener is identified by a unique string so
    /// that multiple components (plugins, modules) can independently subscribe. The
    /// `BGTask` is signalled complete only after **all** listeners have called `finish`.
    ///
    /// Both normal fetch events and timeout events are delivered as a `FetchEvent`.
    /// Check `event.timeout` to distinguish them.
    ///
    /// The returned `EventSubscription` automatically removes the listener when it
    /// is deallocated, so hold a strong reference for as long as you want events.
    ///
    /// - Parameters:
    ///   - identifier: A unique name for this listener (e.g. `"MyApp"`, `"Analytics"`).
    ///     Each identifier receives its own fetch/timeout callback and must independently
    ///     call ``finish(taskId:)``.
    ///   - callback: Invoked on the main queue when a fetch event fires or times out.
    ///
    /// ```swift
    /// let subscription = BackgroundFetch.shared.onFetch(identifier: "MyApp") { event in
    ///     if event.timeout {
    ///         BackgroundFetch.shared.finish(taskId: event.taskId)
    ///         return
    ///     }
    ///     // ... do background work ...
    ///     BackgroundFetch.shared.finish(taskId: event.taskId)
    /// }
    /// ```
    @discardableResult
    public func onFetch(
        identifier: String,
        _ callback: @escaping (FetchEvent) -> Void
    ) -> EventSubscription {
        let id = identifier
        manager.addListener(
            id,
            callback: { taskId in
                callback(FetchEvent(taskId: taskId, timeout: false))
            },
            timeout: { taskId in
                callback(FetchEvent(taskId: taskId, timeout: true))
            }
        )
        return EventSubscription { [weak self] in
            self?.manager.removeListener(id)
        }
    }

    // MARK: - Processing Tasks

    /// Schedule a `BGProcessingTask` and register a callback for its events.
    ///
    /// The task identifier must be listed in your app's `Info.plist` under
    /// `BGTaskSchedulerPermittedIdentifiers`.
    ///
    /// The returned `EventSubscription` stops and removes the task when deallocated.
    /// Hold a strong reference for as long as you want the task to remain active.
    ///
    /// ```swift
    /// var heartbeat: BackgroundFetch.EventSubscription?
    ///
    /// heartbeat = try BackgroundFetch.shared.scheduleTask(
    ///     identifier: "com.transistorsoft.task.heartbeat",
    ///     delay: 900,
    ///     periodic: true
    /// ) { event in
    ///     if event.timeout {
    ///         BackgroundFetch.shared.finish(taskId: event.taskId)
    ///         return
    ///     }
    ///     // ... do background work ...
    ///     BackgroundFetch.shared.finish(taskId: event.taskId)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - identifier: The `BGTaskSchedulerPermittedIdentifiers` task identifier.
    ///   - delay: Earliest begin delay in seconds.
    ///   - periodic: Reschedule automatically after each execution. Defaults to `false`.
    ///   - requiresExternalPower: Only run when the device is charging. Defaults to `false`.
    ///   - requiresNetworkConnectivity: Only run when a network is available. Defaults to `false`.
    ///   - callback: Invoked on the main queue when the task fires or times out.
    /// - Returns: An `EventSubscription` whose `deinit` calls `stop(identifier:)`.
    /// - Throws: An `NSError` if the BGTaskScheduler rejects the request (e.g., identifier
    ///   not registered in `Info.plist`, or iOS < 13).
    @discardableResult
    public func scheduleTask(
        identifier: String,
        delay: TimeInterval,
        periodic: Bool = false,
        requiresExternalPower: Bool = false,
        requiresNetworkConnectivity: Bool = false,
        callback: @escaping (FetchEvent) -> Void
    ) throws -> EventSubscription {
        let error = manager.scheduleProcessingTask(
            withIdentifier: identifier,
            type: 0,
            delay: delay,
            periodic: periodic,
            requiresExternalPower: requiresExternalPower,
            requiresNetworkConnectivity: requiresNetworkConnectivity,
            callback: { taskId, timeout in
                callback(FetchEvent(taskId: taskId, timeout: timeout))
            }
        )
        if let error { throw error }
        return EventSubscription { [weak self] in
            self?.manager.stop(identifier)
        }
    }
}
