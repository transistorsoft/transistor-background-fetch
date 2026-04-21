import SwiftUI

struct ContentView: View {
    var model: FetchModel

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // -- header --
            VStack(spacing: 4) {
                Text("BackgroundFetch Demo")
                    .font(.title2.bold())
                Text("Status: \(model.statusText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.yellow.opacity(0.25))

            // -- controls --
            HStack(spacing: 10) {
                Button("Start") { model.start() }
                Button("Stop") { model.stop() }
                Button("Status") { Task { await model.checkStatus() } }
            }
            .buttonStyle(.bordered)
            .padding(.top, 12)

            HStack(spacing: 10) {
                Button("Schedule Task") { model.scheduleTask() }
                Button("Clear") { model.clearLog() }
                    .tint(.secondary)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
            .disabled(!model.isConfigured)

            // -- event log --
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
            .padding(.top, 8)
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
