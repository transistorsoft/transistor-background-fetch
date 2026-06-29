//
//  FetchModel.swift
//  BackgroundFetchExample
//
//  Drives the TSBackgroundFetch SDK and records a persistent in-app event log.
//

import SwiftUI
import UIKit
import BackgroundFetch

// Note: `@Observable` requires iOS 17, which is why the example app targets iOS 17.
// The SDK itself supports iOS 13 — on an older target use `ObservableObject` / `@Published`.
@Observable
final class FetchModel {
    var statusText = "Unknown"
    var events: [LogEntry] = []
    var isRunning = false

    // Hold the subscriptions: each `EventSubscription` removes its listener / stops
    // its task when it is deallocated, so keep a strong reference while you want events.
    private var fetchSubscription: BackgroundFetch.EventSubscription?
    private var taskSubscription: BackgroundFetch.EventSubscription?

    // The event log is persisted to UserDefaults so it survives relaunch — iOS has no
    // headless mechanism, but foreground/background-launch events are kept until Clear.
    private let storeKey = "BackgroundFetchExample.eventLog"

    struct LogEntry: Identifiable, Codable {
        var id = UUID()
        let timestamp: Date
        let message: String
        let type: EntryType

        enum EntryType: String, Codable { case event, timeout, status, error }
    }

    init() {
        // Restore the persisted log so events recorded on a previous launch are still shown.
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            events = saved
        }
    }

    // MARK: - Actions

    /// Configure background fetch and subscribe to periodic app-refresh events.
    func configure() async {
        isRunning = true   // reflect the header toggle immediately (before the await)
        // 15-minute minimum interval (the OS treats this as a lower bound only).
        let status = await BackgroundFetch.shared.configure(minimumFetchInterval: 15 * 60)
        statusText = statusLabel(status)
        log("[configure] \(statusText)", type: .status)

        // Drop any prior listener before re-subscribing (so calling configure() again
        // after stop() re-arms cleanly rather than stacking listeners on the same id).
        fetchSubscription = nil
        fetchSubscription = BackgroundFetch.shared.onFetch(identifier: "BackgroundFetchExample") { [weak self] event in
            guard let self else { return }
            if event.timeout {
                // The OS is about to suspend us — wrap up immediately.
                self.log("[timeout] \(event.taskId)", type: .timeout)
                BackgroundFetch.shared.finish(taskId: event.taskId)
                return
            }
            self.log("[fetch] \(event.taskId)", type: .event)
            // ... perform your background work here (network sync, etc.) ...
            BackgroundFetch.shared.finish(taskId: event.taskId)
            self.log("[finish] \(event.taskId)", type: .event)
        }
    }

    /// (Re)start after a `stop()`.
    ///
    /// On iOS the only way to resume app-refresh once you've released the listener is to
    /// re-configure: `configure()` re-registers the `onFetch` listener and re-schedules.
    func start() async {
        await configure()
    }

    /// Stop everything.
    ///
    /// `BackgroundFetch.shared.stop()` cancels the scheduled `BGProcessingTask`(s); releasing
    /// the subscriptions removes the app-refresh listener, which cancels the scheduled
    /// `BGAppRefresh` once the last listener is gone.
    func stop() {
        BackgroundFetch.shared.stop()
        fetchSubscription = nil
        taskSubscription = nil
        isRunning = false
        log("[stop] OK", type: .status)
    }

    /// Schedule a one-off `BGProcessingTask` ~60s out.
    func scheduleTask() {
        do {
            taskSubscription = try BackgroundFetch.shared.scheduleTask(
                identifier: "com.transistorsoft.customtask",
                delay: 60,
                periodic: false
            ) { [weak self] event in
                guard let self else { return }
                if event.timeout {
                    self.log("[task timeout] \(event.taskId)", type: .timeout)
                    BackgroundFetch.shared.finish(taskId: event.taskId)
                    return
                }
                self.log("[task] \(event.taskId)", type: .event)
                BackgroundFetch.shared.finish(taskId: event.taskId)
            }
            log("[scheduleTask] com.transistorsoft.customtask", type: .status)
        } catch {
            log("[scheduleTask] \(error.localizedDescription)", type: .error)
        }
    }

    func clearLog() {
        events.removeAll()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    // MARK: - Private

    private func log(_ message: String, type: LogEntry.EntryType) {
        events.insert(LogEntry(timestamp: Date(), message: message, type: type), at: 0)
        if events.count > 200 { events = Array(events.prefix(200)) }
        persist()
    }

    /// Persist the log so it survives relaunch; cleared only via `clearLog()`.
    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func statusLabel(_ status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: "Available"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }
}
