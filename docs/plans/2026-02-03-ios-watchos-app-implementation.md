# iOS + watchOS Hydration App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS app that polls a WaterH water bottle via BLE, tracks hydration progress toward a daily goal, and syncs state to Apple Watch.

**Architecture:** iPhone handles all BLE communication via brief polling connections. HydrationTracker manages goal progress and timer calculations. State syncs to Watch via WatchConnectivity. Both devices show halo ring UI and fire local notifications.

**Tech Stack:** Swift, SwiftUI, CoreBluetooth, WatchConnectivity, UserNotifications

---

## Task 1: Create DrinkEvent Model

**Files:**
- Create: `SmartWaterBottleCompanion/Models/DrinkEvent.swift`
- Test: `SmartWaterBottleCompanionTests/DrinkEventTests.swift`

**Step 1: Write the failing test**

In `SmartWaterBottleCompanionTests/DrinkEventTests.swift`:

```swift
import XCTest
@testable import SmartWaterBottleCompanion

final class DrinkEventTests: XCTestCase {

    func testParseDrinkEventFromValidData() {
        // Sample packet: record type 0x1A, Feb 2, 22:21:15, 16ml
        let data = Data([0x1A, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.month, 2)
        XCTAssertEqual(event?.day, 2)
        XCTAssertEqual(event?.hour, 22)
        XCTAssertEqual(event?.minute, 21)
        XCTAssertEqual(event?.second, 15)
        XCTAssertEqual(event?.amountMl, 16)
    }

    func testRejectInvalidRecordType() {
        // Wrong record type (not 0x1A)
        let data = Data([0x1B, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)

        XCTAssertNil(event)
    }

    func testRejectTooShortData() {
        let data = Data([0x1A, 0x02, 0x02])

        let event = DrinkEvent(data: data)

        XCTAssertNil(event)
    }

    func testTimestampGeneration() {
        let data = Data([0x1A, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)
        let timestamp = event?.timestamp

        XCTAssertNotNil(timestamp)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: timestamp!), 2)
        XCTAssertEqual(calendar.component(.day, from: timestamp!), 2)
        XCTAssertEqual(calendar.component(.hour, from: timestamp!), 22)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/DrinkEventTests 2>&1 | tail -20`

Expected: FAIL - "Cannot find 'DrinkEvent' in scope"

**Step 3: Write minimal implementation**

Create `SmartWaterBottleCompanion/Models/DrinkEvent.swift`:

```swift
import Foundation

struct DrinkEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let month: UInt8
    let day: UInt8
    let hour: UInt8
    let minute: UInt8
    let second: UInt8
    let amountMl: UInt8

    init?(data: Data) {
        guard data.count >= 13, data[0] == 0x1A else { return nil }

        self.id = UUID()
        self.month = data[1]
        self.day = data[2]
        self.hour = data[3]
        self.minute = data[4]
        self.second = data[5]
        // data[6] is separator
        self.amountMl = data[7]
    }

    var timestamp: Date? {
        var components = DateComponents()
        components.month = Int(month)
        components.day = Int(day)
        components.hour = Int(hour)
        components.minute = Int(minute)
        components.second = Int(second)
        components.year = Calendar.current.component(.year, from: Date())
        return Calendar.current.date(from: components)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/DrinkEventTests 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add SmartWaterBottleCompanion/Models/DrinkEvent.swift SmartWaterBottleCompanionTests/DrinkEventTests.swift
git commit -m "feat: add DrinkEvent model with BLE packet parsing"
```

---

## Task 2: Create HydrationState Model

**Files:**
- Create: `SmartWaterBottleCompanion/Models/HydrationState.swift`
- Test: `SmartWaterBottleCompanionTests/HydrationStateTests.swift`

**Step 1: Write the failing test**

In `SmartWaterBottleCompanionTests/HydrationStateTests.swift`:

```swift
import XCTest
@testable import SmartWaterBottleCompanion

final class HydrationStateTests: XCTestCase {

    func testProgressCalculation() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.todayTotalMl = 800

        XCTAssertEqual(state.progress, 0.5, accuracy: 0.01)
    }

    func testProgressCapsAt100Percent() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.todayTotalMl = 2000

        XCTAssertEqual(state.progress, 1.0, accuracy: 0.01)
    }

    func testGlassCount() {
        var state = HydrationState(dailyGoalMl: 1600, mlPerGlass: 200)
        state.todayTotalMl = 600

        XCTAssertEqual(state.glassesConsumed, 3)
        XCTAssertEqual(state.glassesGoal, 8)
    }

    func testTimeUntilNextDrink() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.wakeTime = DateComponents(hour: 8, minute: 0)
        state.sleepTime = DateComponents(hour: 20, minute: 0)
        state.todayTotalMl = 400  // 2 glasses of 8

        // 12 hours awake, need 8 glasses, already had 2, so 6 more in remaining time
        // This depends on current time, so just check it returns a positive value during waking hours
        let interval = state.timeUntilNextDrink(from: makeDate(hour: 10, minute: 0))

        XCTAssertNotNil(interval)
        XCTAssertGreaterThan(interval!, 0)
    }

    func testNoReminderDuringSleep() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.wakeTime = DateComponents(hour: 8, minute: 0)
        state.sleepTime = DateComponents(hour: 20, minute: 0)

        let interval = state.timeUntilNextDrink(from: makeDate(hour: 22, minute: 0))

        XCTAssertNil(interval)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/HydrationStateTests 2>&1 | tail -20`

Expected: FAIL - "Cannot find 'HydrationState' in scope"

**Step 3: Write minimal implementation**

Create `SmartWaterBottleCompanion/Models/HydrationState.swift`:

```swift
import Foundation

struct HydrationState: Codable, Equatable {
    var dailyGoalMl: Int
    var mlPerGlass: Int
    var todayTotalMl: Int
    var lastDrinkTime: Date?
    var wakeTime: DateComponents
    var sleepTime: DateComponents
    var drinkHistory: [DrinkEvent]

    init(
        dailyGoalMl: Int = 1600,
        mlPerGlass: Int = 200,
        todayTotalMl: Int = 0,
        lastDrinkTime: Date? = nil,
        wakeTime: DateComponents = DateComponents(hour: 8, minute: 0),
        sleepTime: DateComponents = DateComponents(hour: 20, minute: 0),
        drinkHistory: [DrinkEvent] = []
    ) {
        self.dailyGoalMl = dailyGoalMl
        self.mlPerGlass = mlPerGlass
        self.todayTotalMl = todayTotalMl
        self.lastDrinkTime = lastDrinkTime
        self.wakeTime = wakeTime
        self.sleepTime = sleepTime
        self.drinkHistory = drinkHistory
    }

    var progress: Double {
        min(1.0, Double(todayTotalMl) / Double(dailyGoalMl))
    }

    var glassesConsumed: Int {
        todayTotalMl / mlPerGlass
    }

    var glassesGoal: Int {
        dailyGoalMl / mlPerGlass
    }

    func timeUntilNextDrink(from now: Date = Date()) -> TimeInterval? {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        let wakeHour = wakeTime.hour ?? 8
        let wakeMinute = wakeTime.minute ?? 0
        let sleepHour = sleepTime.hour ?? 20
        let sleepMinute = sleepTime.minute ?? 0

        let currentMinutes = currentHour * 60 + currentMinute
        let wakeMinutes = wakeHour * 60 + wakeMinute
        let sleepMinutes = sleepHour * 60 + sleepMinute

        // Outside waking hours
        if currentMinutes < wakeMinutes || currentMinutes >= sleepMinutes {
            return nil
        }

        // Calculate remaining drinks needed
        let remainingMl = max(0, dailyGoalMl - todayTotalMl)
        let remainingGlasses = (remainingMl + mlPerGlass - 1) / mlPerGlass // Round up

        if remainingGlasses == 0 {
            return nil // Goal achieved
        }

        // Calculate remaining waking time
        let remainingMinutes = sleepMinutes - currentMinutes

        // Spread remaining drinks across remaining time
        let intervalMinutes = Double(remainingMinutes) / Double(remainingGlasses)

        return intervalMinutes * 60 // Convert to seconds
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/HydrationStateTests 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add SmartWaterBottleCompanion/Models/HydrationState.swift SmartWaterBottleCompanionTests/HydrationStateTests.swift
git commit -m "feat: add HydrationState model with goal and timer calculation"
```

---

## Task 3: Create BLE Manager

**Files:**
- Create: `SmartWaterBottleCompanion/Services/BLEManager.swift`
- Create: `SmartWaterBottleCompanion/Services/BLEConstants.swift`

**Note:** BLE code is hard to unit test without hardware mocking. We'll test this manually with the actual bottle.

**Step 1: Create BLE constants**

Create `SmartWaterBottleCompanion/Services/BLEConstants.swift`:

```swift
import CoreBluetooth

enum BLEConstants {
    // WaterH bottle uses custom 128-bit UUIDs
    // These need to be discovered from actual bottle - placeholder format
    static let bottleServiceUUID = CBUUID(string: "0000FF00-0000-1000-8000-00805F9B34FB")

    // Characteristic #1 - Write commands
    static let commandCharacteristicUUID = CBUUID(string: "0000FF01-0000-1000-8000-00805F9B34FB")

    // Characteristic #2 - Read responses
    static let responseCharacteristicUUID = CBUUID(string: "0000FF02-0000-1000-8000-00805F9B34FB")

    // Command to request drink history
    static let requestHistoryCommand = Data([0x01])

    // Drink packet header "PT" = 0x50 0x54
    static let drinkPacketHeader = Data([0x50, 0x54])

    // Connection timeout
    static let scanTimeout: TimeInterval = 10.0
    static let connectionTimeout: TimeInterval = 5.0
}
```

**Step 2: Create BLE Manager**

Create `SmartWaterBottleCompanion/Services/BLEManager.swift`:

```swift
import CoreBluetooth
import Combine

enum BLEConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case polling
    case error(String)
}

@MainActor
class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var lastError: String?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?

    private var scanTimer: Timer?
    private var onDrinksReceived: (([DrinkEvent]) -> Void)?

    override init() {
        super.init()
    }

    func startScanning() {
        connectionState = .scanning
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func poll(completion: @escaping ([DrinkEvent]) -> Void) {
        self.onDrinksReceived = completion
        startScanning()

        // Timeout for scan
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.scanTimeout, repeats: false) { [weak self] _ in
            self?.handleScanTimeout()
        }
    }

    func disconnect() {
        scanTimer?.invalidate()
        scanTimer = nil

        if let peripheral = peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        peripheral = nil
        commandCharacteristic = nil
        responseCharacteristic = nil
        connectionState = .disconnected
    }

    private func handleScanTimeout() {
        if case .scanning = connectionState {
            disconnect()
            connectionState = .error("Bottle not found")
            lastError = "Could not find bottle. Make sure it's nearby."
            onDrinksReceived?([])
        }
    }

    private func requestDrinkHistory() {
        guard let characteristic = commandCharacteristic else { return }
        connectionState = .polling
        peripheral?.writeValue(BLEConstants.requestHistoryCommand, for: characteristic, type: .withoutResponse)

        // Read response after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.readResponse()
        }
    }

    private func readResponse() {
        guard let characteristic = responseCharacteristic else {
            finishPolling(drinks: [])
            return
        }
        peripheral?.readValue(for: characteristic)
    }

    private func parseResponse(data: Data) -> [DrinkEvent] {
        var drinks: [DrinkEvent] = []

        // Check for "PT" header
        guard data.count >= 6,
              data.prefix(2) == BLEConstants.drinkPacketHeader else {
            return drinks
        }

        // Skip header (2) + length (2) + metadata (2) = 6 bytes
        var offset = 6

        // Parse drink records (13 bytes each)
        while offset + 13 <= data.count {
            let recordData = data.subdata(in: offset..<offset+13)
            if let event = DrinkEvent(data: recordData) {
                drinks.append(event)
            }
            offset += 13
        }

        return drinks
    }

    private func finishPolling(drinks: [DrinkEvent]) {
        onDrinksReceived?(drinks)
        onDrinksReceived = nil
        disconnect()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                central.scanForPeripherals(withServices: [BLEConstants.bottleServiceUUID], options: nil)
            case .poweredOff:
                connectionState = .error("Bluetooth is off")
            case .unauthorized:
                connectionState = .error("Bluetooth permission denied")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            scanTimer?.invalidate()
            central.stopScan()

            self.peripheral = peripheral
            peripheral.delegate = self
            connectionState = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .connected
            peripheral.discoverServices([BLEConstants.bottleServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .error("Failed to connect")
            lastError = error?.localizedDescription
            finishPolling(drinks: [])
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first else {
                finishPolling(drinks: [])
                return
            }
            peripheral.discoverCharacteristics([
                BLEConstants.commandCharacteristicUUID,
                BLEConstants.responseCharacteristicUUID
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == BLEConstants.commandCharacteristicUUID {
                    commandCharacteristic = characteristic
                } else if characteristic.uuid == BLEConstants.responseCharacteristicUUID {
                    responseCharacteristic = characteristic
                }
            }

            if commandCharacteristic != nil && responseCharacteristic != nil {
                requestDrinkHistory()
            } else {
                finishPolling(drinks: [])
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == BLEConstants.responseCharacteristicUUID,
                  let data = characteristic.value else {
                finishPolling(drinks: [])
                return
            }

            let drinks = parseResponse(data: data)
            finishPolling(drinks: drinks)
        }
    }
}
```

**Step 3: Commit**

```bash
git add SmartWaterBottleCompanion/Services/BLEConstants.swift SmartWaterBottleCompanion/Services/BLEManager.swift
git commit -m "feat: add BLEManager for polling water bottle"
```

---

## Task 4: Create HydrationTracker (Main ViewModel)

**Files:**
- Create: `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift`
- Test: `SmartWaterBottleCompanionTests/HydrationTrackerTests.swift`

**Step 1: Write the failing test**

In `SmartWaterBottleCompanionTests/HydrationTrackerTests.swift`:

```swift
import XCTest
@testable import SmartWaterBottleCompanion

final class HydrationTrackerTests: XCTestCase {

    func testProcessNewDrinks() {
        let tracker = HydrationTracker()
        tracker.state = HydrationState(dailyGoalMl: 1600, todayTotalMl: 0)

        let drink1Data = Data([0x1A, 0x02, 0x03, 0x10, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x01, 0x61, 0x00]) // 100ml
        let drink2Data = Data([0x1A, 0x02, 0x03, 0x11, 0x00, 0x00, 0x00, 0xC8, 0x00, 0x00, 0x01, 0x61, 0x00]) // 200ml (0xC8 = 200)

        let drinks = [DrinkEvent(data: drink1Data)!, DrinkEvent(data: drink2Data)!]

        tracker.processNewDrinks(drinks)

        XCTAssertEqual(tracker.state.todayTotalMl, 300)
        XCTAssertEqual(tracker.state.drinkHistory.count, 2)
    }

    func testFiltersTodayDrinksOnly() {
        let tracker = HydrationTracker()
        tracker.state = HydrationState(dailyGoalMl: 1600, todayTotalMl: 0)

        // Today's date components
        let today = Calendar.current.dateComponents([.month, .day], from: Date())
        let todayMonth = UInt8(today.month!)
        let todayDay = UInt8(today.day!)

        // Yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayComponents = Calendar.current.dateComponents([.month, .day], from: yesterday)
        let yesterdayMonth = UInt8(yesterdayComponents.month!)
        let yesterdayDay = UInt8(yesterdayComponents.day!)

        // Create drinks - one today, one yesterday
        let todayDrinkData = Data([0x1A, todayMonth, todayDay, 0x10, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x01, 0x61, 0x00])
        let yesterdayDrinkData = Data([0x1A, yesterdayMonth, yesterdayDay, 0x10, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x01, 0x61, 0x00])

        let drinks = [
            DrinkEvent(data: todayDrinkData)!,
            DrinkEvent(data: yesterdayDrinkData)!
        ]

        tracker.processNewDrinks(drinks)

        // Only today's drink should count
        XCTAssertEqual(tracker.state.todayTotalMl, 100)
    }

    func testPollIntervalAdaptive() {
        let tracker = HydrationTracker()

        // Far from reminder - long interval
        tracker.state.todayTotalMl = 0
        var interval = tracker.calculatePollInterval(timeUntilReminder: 20 * 60) // 20 min
        XCTAssertEqual(interval, 10 * 60) // 10 min

        // Getting close - medium interval
        interval = tracker.calculatePollInterval(timeUntilReminder: 7 * 60) // 7 min
        XCTAssertEqual(interval, 5 * 60) // 5 min

        // Very close - short interval
        interval = tracker.calculatePollInterval(timeUntilReminder: 3 * 60) // 3 min
        XCTAssertEqual(interval, 2 * 60) // 2 min

        // Alert firing - urgent interval
        interval = tracker.calculatePollInterval(timeUntilReminder: 0)
        XCTAssertEqual(interval, 1 * 60) // 1 min
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/HydrationTrackerTests 2>&1 | tail -20`

Expected: FAIL - "Cannot find 'HydrationTracker' in scope"

**Step 3: Write minimal implementation**

Create `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift`:

```swift
import Foundation
import Combine

@MainActor
class HydrationTracker: ObservableObject {
    @Published var state: HydrationState
    @Published var isPolling = false
    @Published var connectionError: String?

    private let bleManager = BLEManager()
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(state: HydrationState = HydrationState()) {
        self.state = state

        // Observe BLE errors
        bleManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionError)
    }

    func startPolling() {
        pollOnce()
        scheduleNextPoll()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        bleManager.disconnect()
    }

    func pollOnce() {
        isPolling = true
        bleManager.poll { [weak self] drinks in
            self?.isPolling = false
            self?.processNewDrinks(drinks)
        }
    }

    func processNewDrinks(_ drinks: [DrinkEvent]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Filter to today's drinks only
        let todayDrinks = drinks.filter { drink in
            guard let timestamp = drink.timestamp else { return false }
            return calendar.isDate(timestamp, inSameDayAs: today)
        }

        // Add new drinks not already in history
        let existingIds = Set(state.drinkHistory.map { $0.id })
        let newDrinks = todayDrinks.filter { !existingIds.contains($0.id) }

        if !newDrinks.isEmpty {
            state.drinkHistory.append(contentsOf: newDrinks)
            state.drinkHistory.sort { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

            // Recalculate total
            state.todayTotalMl = todayDrinks.reduce(0) { $0 + Int($1.amountMl) }
            state.lastDrinkTime = todayDrinks.last?.timestamp
        }
    }

    func calculatePollInterval(timeUntilReminder: TimeInterval) -> TimeInterval {
        switch timeUntilReminder {
        case _ where timeUntilReminder <= 0:
            return 1 * 60  // Alert firing: 1 minute
        case 0..<(5 * 60):
            return 2 * 60  // <5 min: 2 minutes
        case (5 * 60)..<(10 * 60):
            return 5 * 60  // 5-10 min: 5 minutes
        default:
            return 10 * 60 // >10 min: 10 minutes
        }
    }

    private func scheduleNextPoll() {
        let timeUntilReminder = state.timeUntilNextDrink() ?? (30 * 60)
        let interval = calculatePollInterval(timeUntilReminder: timeUntilReminder)

        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pollOnce()
                self?.scheduleNextPoll()
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartWaterBottleCompanionTests/HydrationTrackerTests 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift SmartWaterBottleCompanionTests/HydrationTrackerTests.swift
git commit -m "feat: add HydrationTracker with adaptive polling"
```

---

## Task 5: Create Halo Ring View

**Files:**
- Create: `SmartWaterBottleCompanion/Views/HaloRingView.swift`

**Step 1: Create the halo ring component**

Create `SmartWaterBottleCompanion/Views/HaloRingView.swift`:

```swift
import SwiftUI

struct HaloRingView: View {
    let progress: Double
    let glassesConsumed: Int
    let glassesGoal: Int
    let isAlerting: Bool

    @State private var animateRainbow = false

    private let ringWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: ringWidth)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isAlerting ? rainbowGradient : progressGradient,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                // Center content
                VStack(spacing: 4) {
                    Text("\(glassesConsumed)/\(glassesGoal)")
                        .font(.system(size: size * 0.15, weight: .bold, design: .rounded))

                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.08))
                        .foregroundColor(.blue)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: isAlerting) { _, alerting in
            if alerting {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    animateRainbow = true
                }
            } else {
                animateRainbow = false
            }
        }
    }

    private var progressGradient: AngularGradient {
        AngularGradient(
            colors: [.blue, .cyan, .blue],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    private var rainbowGradient: AngularGradient {
        AngularGradient(
            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
            center: .center,
            startAngle: .degrees(animateRainbow ? 360 : 0),
            endAngle: .degrees(animateRainbow ? 720 : 360)
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        HaloRingView(progress: 0.75, glassesConsumed: 6, glassesGoal: 8, isAlerting: false)
            .frame(width: 200, height: 200)

        HaloRingView(progress: 0.5, glassesConsumed: 4, glassesGoal: 8, isAlerting: true)
            .frame(width: 150, height: 150)
    }
    .padding()
}
```

**Step 2: Commit**

```bash
git add SmartWaterBottleCompanion/Views/HaloRingView.swift
git commit -m "feat: add HaloRingView with progress and rainbow alert animation"
```

---

## Task 6: Create Main Content View

**Files:**
- Modify: `SmartWaterBottleCompanion/ContentView.swift`

**Step 1: Update ContentView with full UI**

Replace `SmartWaterBottleCompanion/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = HydrationTracker()
    @State private var showSettings = false
    @State private var countdown: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Halo Ring
                HaloRingView(
                    progress: tracker.state.progress,
                    glassesConsumed: tracker.state.glassesConsumed,
                    glassesGoal: tracker.state.glassesGoal,
                    isAlerting: countdown <= 0 && tracker.state.timeUntilNextDrink() != nil
                )
                .frame(height: 250)
                .padding(.top, 20)

                // Countdown
                if let _ = tracker.state.timeUntilNextDrink() {
                    VStack(spacing: 4) {
                        Text(formatTime(countdown))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("until next drink")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Outside drinking hours")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.horizontal)

                // Today's drinks
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.headline)
                        .padding(.horizontal)

                    if tracker.state.drinkHistory.isEmpty {
                        Text("No drinks recorded yet")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tracker.state.drinkHistory.reversed()) { drink in
                                    DrinkRowView(drink: drink)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Spacer()

                // Connection status
                if tracker.isPolling {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking bottle...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = tracker.connectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Hydration")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(state: $tracker.state)
            }
        }
        .onAppear {
            tracker.startPolling()
            updateCountdown()
        }
        .onDisappear {
            tracker.stopPolling()
        }
        .onReceive(timer) { _ in
            updateCountdown()
        }
    }

    private func updateCountdown() {
        countdown = max(0, tracker.state.timeUntilNextDrink() ?? 0)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct DrinkRowView: View {
    let drink: DrinkEvent

    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundColor(.blue)

            if let time = drink.timestamp {
                Text(time, style: .time)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(drink.amountMl) ml")
                .fontWeight(.medium)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Commit**

```bash
git add SmartWaterBottleCompanion/ContentView.swift
git commit -m "feat: update ContentView with halo ring, countdown, and drink history"
```

---

## Task 7: Create Settings View

**Files:**
- Create: `SmartWaterBottleCompanion/Views/SettingsView.swift`

**Step 1: Create settings view**

Create `SmartWaterBottleCompanion/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Binding var state: HydrationState
    @Environment(\.dismiss) private var dismiss

    @State private var wakeHour: Int = 8
    @State private var wakeMinute: Int = 0
    @State private var sleepHour: Int = 20
    @State private var sleepMinute: Int = 0
    @State private var goalGlasses: Int = 8

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper("\(goalGlasses) glasses", value: $goalGlasses, in: 4...16)

                    Text("\(goalGlasses * state.mlPerGlass) ml total")
                        .foregroundColor(.secondary)
                }

                Section("Wake Time") {
                    HStack {
                        Picker("Hour", selection: $wakeHour) {
                            ForEach(4..<12, id: \.self) { hour in
                                Text("\(hour):00").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)

                        Picker("Minute", selection: $wakeMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: ":%02d", minute)).tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                    }
                    .frame(height: 100)
                }

                Section("Sleep Time") {
                    HStack {
                        Picker("Hour", selection: $sleepHour) {
                            ForEach(18..<24, id: \.self) { hour in
                                Text("\(hour):00").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)

                        Picker("Minute", selection: $sleepMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: ":%02d", minute)).tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                    }
                    .frame(height: 100)
                }

                Section("About") {
                    HStack {
                        Text("Glass size")
                        Spacer()
                        Text("\(state.mlPerGlass) ml")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private func loadSettings() {
        wakeHour = state.wakeTime.hour ?? 8
        wakeMinute = state.wakeTime.minute ?? 0
        sleepHour = state.sleepTime.hour ?? 20
        sleepMinute = state.sleepTime.minute ?? 0
        goalGlasses = state.dailyGoalMl / state.mlPerGlass
    }

    private func saveSettings() {
        state.wakeTime = DateComponents(hour: wakeHour, minute: wakeMinute)
        state.sleepTime = DateComponents(hour: sleepHour, minute: sleepMinute)
        state.dailyGoalMl = goalGlasses * state.mlPerGlass
    }
}

#Preview {
    SettingsView(state: .constant(HydrationState()))
}
```

**Step 2: Commit**

```bash
git add SmartWaterBottleCompanion/Views/SettingsView.swift
git commit -m "feat: add SettingsView for goal and schedule configuration"
```

---

## Task 8: Add Info.plist for Bluetooth Permission

**Files:**
- Modify: `SmartWaterBottleCompanion/Info.plist` (create if needed via Xcode, or add keys programmatically)

**Note:** Modern Xcode projects use build settings for Info.plist keys. We need to add the Bluetooth usage description.

**Step 1: Create Info.plist with Bluetooth permission**

Create `SmartWaterBottleCompanion/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>This app connects to your WaterH water bottle to track your hydration.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>This app connects to your WaterH water bottle to track your hydration.</string>
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
    </array>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add SmartWaterBottleCompanion/Info.plist
git commit -m "feat: add Info.plist with Bluetooth permissions"
```

---

## Task 9: Add watchOS Target (Manual Step)

**This task requires Xcode UI:**

1. Open `SmartWaterBottleCompanion.xcodeproj` in Xcode
2. File → New → Target
3. Select "watchOS" → "App"
4. Name: "SmartWaterBottleCompanion Watch App"
5. Interface: SwiftUI
6. Language: Swift
7. Ensure "Include Notification Scene" is checked
8. Click Finish

After adding the target, continue to Task 10.

---

## Task 10: Create Watch App Views

**Files (after watchOS target exists):**
- Create: `SmartWaterBottleCompanion Watch App/ContentView.swift`
- Create: `SmartWaterBottleCompanion Watch App/HaloRingView.swift`

**Step 1: Create Watch ContentView**

Create `SmartWaterBottleCompanion Watch App/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var connector = WatchConnector()

    var body: some View {
        ZStack {
            // Halo ring as background
            WatchHaloRingView(
                progress: connector.state.progress,
                isAlerting: connector.isAlerting
            )

            // Center content
            VStack(spacing: 4) {
                Text("\(connector.state.glassesConsumed)/\(connector.state.glassesGoal)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Image(systemName: "drop.fill")
                    .foregroundColor(.blue)

                if let time = connector.timeUntilNext {
                    Text(formatTime(time))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct WatchHaloRingView: View {
    let progress: Double
    let isAlerting: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isAlerting ?
                        LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.9, height: size * 0.9)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Create WatchConnector**

Create `SmartWaterBottleCompanion Watch App/WatchConnector.swift`:

```swift
import WatchConnectivity
import SwiftUI

class WatchConnector: NSObject, ObservableObject {
    @Published var state = HydrationState()
    @Published var isAlerting = false
    @Published var timeUntilNext: TimeInterval?

    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
}

extension WatchConnector: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Activation complete
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let data = applicationContext["state"] as? Data,
               let state = try? JSONDecoder().decode(HydrationState.self, from: data) {
                self.state = state
            }

            if let alerting = applicationContext["isAlerting"] as? Bool {
                self.isAlerting = alerting
            }

            if let time = applicationContext["timeUntilNext"] as? TimeInterval {
                self.timeUntilNext = time
            }
        }
    }
}
```

**Step 3: Commit**

```bash
git add "SmartWaterBottleCompanion Watch App/"
git commit -m "feat: add Watch app with halo ring UI"
```

---

## Task 11: Add WatchConnectivity to iOS App

**Files:**
- Create: `SmartWaterBottleCompanion/Services/PhoneConnector.swift`
- Modify: `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift`

**Step 1: Create PhoneConnector**

Create `SmartWaterBottleCompanion/Services/PhoneConnector.swift`:

```swift
import WatchConnectivity

class PhoneConnector: NSObject, ObservableObject {
    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    func sendState(_ state: HydrationState, isAlerting: Bool, timeUntilNext: TimeInterval?) {
        guard let session = session, session.isPaired, session.isWatchAppInstalled else { return }

        var context: [String: Any] = [
            "isAlerting": isAlerting
        ]

        if let data = try? JSONEncoder().encode(state) {
            context["state"] = data
        }

        if let time = timeUntilNext {
            context["timeUntilNext"] = time
        }

        try? session.updateApplicationContext(context)
    }
}

extension PhoneConnector: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
```

**Step 2: Update HydrationTracker to sync with Watch**

Add to `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift`, inside the class:

```swift
// Add property
private let phoneConnector = PhoneConnector()

// Add method
private func syncWithWatch() {
    let timeUntilNext = state.timeUntilNextDrink()
    let isAlerting = (timeUntilNext ?? 1) <= 0
    phoneConnector.sendState(state, isAlerting: isAlerting, timeUntilNext: timeUntilNext)
}

// Call syncWithWatch() at end of processNewDrinks() and in scheduleNextPoll()
```

**Step 3: Commit**

```bash
git add SmartWaterBottleCompanion/Services/PhoneConnector.swift SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift
git commit -m "feat: add WatchConnectivity to sync state with Watch"
```

---

## Task 12: Add Local Notifications

**Files:**
- Create: `SmartWaterBottleCompanion/Services/NotificationManager.swift`
- Modify: `SmartWaterBottleCompanion/SmartWaterBottleCompanionApp.swift`

**Step 1: Create NotificationManager**

Create `SmartWaterBottleCompanion/Services/NotificationManager.swift`:

```swift
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func scheduleReminder(in seconds: TimeInterval) {
        // Remove existing reminders
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["hydration-reminder"])

        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to Drink!"
        content.body = "Stay hydrated - grab your water bottle."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "hydration-reminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["hydration-reminder"])
    }
}
```

**Step 2: Update App entry point**

Replace `SmartWaterBottleCompanion/SmartWaterBottleCompanionApp.swift`:

```swift
import SwiftUI

@main
struct SmartWaterBottleCompanionApp: App {

    init() {
        NotificationManager.shared.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Step 3: Commit**

```bash
git add SmartWaterBottleCompanion/Services/NotificationManager.swift SmartWaterBottleCompanion/SmartWaterBottleCompanionApp.swift
git commit -m "feat: add NotificationManager for hydration reminders"
```

---

## Task 13: Wire Up Notifications in HydrationTracker

**Files:**
- Modify: `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift`

**Step 1: Update HydrationTracker to schedule notifications**

Add to `scheduleNextPoll()` method:

```swift
// After calculating interval, schedule notification
if let timeUntilReminder = state.timeUntilNextDrink(), timeUntilReminder > 0 {
    NotificationManager.shared.scheduleReminder(in: timeUntilReminder)
}
```

Add to `processNewDrinks()` when new drinks are detected:

```swift
// Cancel and reschedule notification when drink detected
if !newDrinks.isEmpty {
    NotificationManager.shared.cancelReminder()
    if let newTime = state.timeUntilNextDrink(), newTime > 0 {
        NotificationManager.shared.scheduleReminder(in: newTime)
    }
}
```

**Step 2: Commit**

```bash
git add SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift
git commit -m "feat: wire notifications to HydrationTracker"
```

---

## Task 14: Final Integration Test

**Step 1: Build and run on simulator**

```bash
xcodebuild build -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

**Step 2: Run all tests**

```bash
xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -50
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup and integration"
```

---

## Summary

This plan implements:
1. **DrinkEvent model** - Parses BLE drink packets
2. **HydrationState model** - Tracks goal, progress, and timer calculations
3. **BLEManager** - Handles polling connections to the bottle
4. **HydrationTracker** - Main ViewModel with adaptive polling
5. **HaloRingView** - Visual progress indicator with rainbow alerts
6. **ContentView** - Main iPhone UI
7. **SettingsView** - Configuration for goals and schedule
8. **Watch App** - Simplified UI synced via WatchConnectivity
9. **Notifications** - Local reminders when timer expires

**Next steps after implementation:**
- Discover actual BLE UUIDs from the bottle and update `BLEConstants.swift`
- Test with real hardware
- Add Watch complication
