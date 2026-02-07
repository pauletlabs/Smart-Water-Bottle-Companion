//
//  WatchSessionManager.swift
//  SmartWaterBottleWatch Watch App
//
//  Manages WatchConnectivity session on the Watch side
//

import Foundation
import Combine
import WatchConnectivity

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var hydrationData: WatchHydrationData = .empty
    @Published var isReachable: Bool = false
    @Published var lastSyncTime: Date?

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Request fresh data from iPhone
    func requestUpdate() {
        guard let session = session, session.isReachable else {
            print("📱 iPhone not reachable")
            return
        }

        session.sendMessage(["request": "hydrationData"], replyHandler: { [weak self] response in
            Task { @MainActor in
                if let data = WatchHydrationData(from: response) {
                    self?.hydrationData = data
                    self?.lastSyncTime = Date()
                    print("✅ Received hydration data from iPhone")
                }
            }
        }, errorHandler: { error in
            print("❌ Failed to request data: \(error.localizedDescription)")
        })
    }
}

// MARK: - WCSessionDelegate
extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("❌ Watch session activation failed: \(error.localizedDescription)")
            } else {
                print("✅ Watch session activated: \(activationState.rawValue)")
                isReachable = session.isReachable
                // Request initial data
                requestUpdate()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            print("📱 iPhone reachability: \(session.isReachable)")
            if session.isReachable {
                requestUpdate()
            }
        }
    }

    /// Receive application context (background updates)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            if let data = WatchHydrationData(from: applicationContext) {
                hydrationData = data
                lastSyncTime = Date()
                print("📥 Received application context update")
            }
        }
    }

    /// Receive direct messages
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            if let data = WatchHydrationData(from: message) {
                hydrationData = data
                lastSyncTime = Date()
                print("📥 Received direct message update")
            }
        }
    }

    /// Receive user info transfers
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        Task { @MainActor in
            if let data = WatchHydrationData(from: userInfo) {
                hydrationData = data
                lastSyncTime = Date()
                print("📥 Received user info update")
            }
        }
    }
}
