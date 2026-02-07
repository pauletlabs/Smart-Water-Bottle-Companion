//
//  SmartWaterBottleWatchApp.swift
//  SmartWaterBottleWatch Watch App
//
//  Created by Charlie Normand on 07/02/2026.
//

import SwiftUI
import UserNotifications
import WatchKit

@main
struct SmartWaterBottleWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// App delegate to handle notification presentation in foreground
class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner, play sound, and update badge even in foreground
        completionHandler([.banner, .sound])
    }
}
