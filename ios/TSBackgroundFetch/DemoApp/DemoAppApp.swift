import SwiftUI

@main
struct DemoAppApp: App {
    @State private var model = FetchModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.configure() }
        }
    }
}
