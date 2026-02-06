import Foundation
import Combine

/// Protocol for BLE management - allows swapping real/mock implementations
@MainActor
protocol BLEManaging: ObservableObject {
    var connectionState: BLEConnectionState { get }
    var lastError: String? { get }

    func poll(completion: @escaping ([DrinkEvent]) -> Void)
    func disconnect()
}

// Make BLEManager conform to the protocol
extension BLEManager: BLEManaging {}
