//
//  EventSubscription.swift
//  TSBackgroundFetch
//
//  Created by Christopher Scott on 2026-04-14.
//  Copyright © 2026 Transistor Software. All rights reserved.
//
//  A subscription handle returned by BackgroundFetch event-listener methods.
//  The underlying listener is automatically removed when the subscription is
//  deallocated, so callers only need to retain it for as long as they want events.
//
//  Store in a property or a Set<BackgroundFetch.EventSubscription>:
//
//      private var fetchSubscription: BackgroundFetch.EventSubscription?
//
//      fetchSubscription = BackgroundFetch.shared.onFetch { event in
//          BackgroundFetch.shared.finish(taskId: event.taskId)
//      }
//
//      // Cancels immediately:
//      fetchSubscription = nil
//

import Foundation

extension BackgroundFetch {
    public final class EventSubscription: Hashable {
        private let cancel: () -> Void

        init(_ cancel: @escaping () -> Void) {
            self.cancel = cancel
        }

        deinit {
            cancel()
        }

        /// Convenience: store in a set to manage multiple subscriptions together.
        public func store(in set: inout Set<EventSubscription>) {
            set.insert(self)
        }

        public static func == (lhs: EventSubscription, rhs: EventSubscription) -> Bool {
            lhs === rhs
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}
