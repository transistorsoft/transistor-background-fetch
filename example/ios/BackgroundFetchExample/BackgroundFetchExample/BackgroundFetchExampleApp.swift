//
//  BackgroundFetchExampleApp.swift
//  BackgroundFetchExample
//
//  A minimal SwiftUI app demonstrating the TSBackgroundFetch SDK consumed via
//  Swift Package Manager (the `BackgroundFetch` product, i.e. BackgroundFetch.shared).
//

import SwiftUI

@main
struct BackgroundFetchExampleApp: App {
    @State private var model = FetchModel()

    // No launch-time setup is required: TSBackgroundFetch automatically registers its
    // BGTaskScheduler handlers (from `BGTaskSchedulerPermittedIdentifiers` in Info.plist)
    // before the app finishes launching.

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.configure() }
        }
    }
}
