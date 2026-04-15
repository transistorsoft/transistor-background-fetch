//
//  FetchEvent.swift
//  TSBackgroundFetch
//
//  Created by Christopher Scott on 2026-04-14.
//  Copyright © 2026 Transistor Software. All rights reserved.
//
//  Delivered to callbacks registered with BackgroundFetch.onFetch and
//  BackgroundFetch.scheduleTask.
//

import Foundation

extension BackgroundFetch {
    public struct FetchEvent {
        /// The listener identifier that was passed to ``BackgroundFetch/onFetch(identifier:_:)``.
        /// Pass this back to ``BackgroundFetch/finish(taskId:)`` to signal that *this*
        /// subscriber's work is complete. The OS task is only marked finished once every
        /// registered subscriber has called `finish`.
        public let taskId: String

        /// `true` when the OS fired the task's expiration handler before
        /// `finish(taskId:)` was called. Perform minimal cleanup when this is
        /// `true` and call `finish(taskId:)` immediately.
        public let timeout: Bool
    }
}
