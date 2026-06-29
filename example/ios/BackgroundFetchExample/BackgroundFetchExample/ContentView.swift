//
//  ContentView.swift
//  BackgroundFetchExample
//

import SwiftUI

struct ContentView: View {
    var model: FetchModel

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Toggling the header switch starts (re-configures) or stops the SDK.
    private var runningBinding: Binding<Bool> {
        Binding(
            get: { model.isRunning },
            set: { isOn in
                if isOn { Task { await model.start() } } else { model.stop() }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // -- header: title + start/stop toggle --
            HStack {
                Text("BackgroundFetch")
                    .font(.title2.bold())
                Spacer()
                Toggle("Running", isOn: runningBinding)
                    .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.yellow.opacity(0.25))

            // -- body: event log --
            List(model.events) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.timeFmt.string(from: entry.timestamp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color(for: entry.type))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)

            // -- bottom toolbar: Clear | Status | Schedule Task --
            HStack {
                Button("Clear") { model.clearLog() }
                    .tint(.secondary)
                Spacer()
                Text("Status: \(model.statusText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Schedule Task") { model.scheduleTask() }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func color(for type: FetchModel.LogEntry.EntryType) -> Color {
        switch type {
        case .event:   .green
        case .timeout: .red
        case .status:  .blue
        case .error:   .red
        }
    }
}
