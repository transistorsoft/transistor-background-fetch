import SwiftUI
import UIKit

@Observable
final class FetchModel {
    var statusText = "Unknown"
    var events: [LogEntry] = []
    var isConfigured = false

    private var fetchSubscription: BackgroundFetch.EventSubscription?
    private var taskSubscription: BackgroundFetch.EventSubscription?

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: EntryType

        enum EntryType {
            case event, timeout, status, error
        }
    }

    // MARK: - Actions

    func configure() async {
        let status = await BackgroundFetch.shared.configure()
        statusText = statusLabel(status)
        isConfigured = true
        log("[configure] \(statusText)", type: .status)

        fetchSubscription = BackgroundFetch.shared.onFetch(identifier: "DemoApp") { [weak self] event in
            guard let self else { return }
            if event.timeout {
                self.log("[timeout] \(event.taskId)", type: .timeout)
                BackgroundFetch.shared.finish(taskId: event.taskId)
                return
            }
            self.log("[fetch] \(event.taskId)", type: .event)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                BackgroundFetch.shared.finish(taskId: event.taskId)
                self.log("[finish] \(event.taskId)", type: .event)
            }
        }
    }

    func start() {
        do {
            try BackgroundFetch.shared.start()
            log("[start] OK", type: .status)
        } catch {
            log("[start] \(error.localizedDescription)", type: .error)
        }
    }

    func stop() {
        BackgroundFetch.shared.stop()
        taskSubscription = nil
        log("[stop] OK", type: .status)
    }

    func checkStatus() async {
        let status = await BackgroundFetch.shared.refreshStatus
        statusText = statusLabel(status)
        log("[status] \(statusText)", type: .status)
    }

    func scheduleTask() {
        do {
            taskSubscription = try BackgroundFetch.shared.scheduleTask(
                identifier: "com.transistorsoft.demo.task",
                delay: 60,
                periodic: true
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
            log("[scheduleTask] OK", type: .status)
        } catch {
            log("[scheduleTask] \(error.localizedDescription)", type: .error)
        }
    }

    func clearLog() {
        events.removeAll()
    }

    // MARK: - Private

    private func log(_ message: String, type: LogEntry.EntryType) {
        events.insert(LogEntry(timestamp: Date(), message: message, type: type), at: 0)
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
