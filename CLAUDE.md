# Smart Water Bottle Companion

## User Preferences

- **Always address the user as "Wise Jedi"**

## Workflow

- **Use feature branches** for new work, not direct commits to main
- **Create PRs** to get GitHub Copilot reviews before merging
- Branch naming: `feature/<description>` or `task/<task-number>-<description>`

## Project Overview

A hydration reminder system for a child that monitors a WaterH Bluetooth water bottle. Two implementation chapters:

1. **Chapter 1: iOS + watchOS App** (CURRENT) - iPhone handles BLE polling, syncs state to Apple Watch
2. **Chapter 2: ESP32 Desk Display** - Standalone desk device with LCD, no phone dependency

Both can coexist - ESP32 could receive state from iPhone instead of connecting to bottle directly.

## Goals

- Remind child to drink water based on daily goal spread across waking hours
- Detect drinks via BLE polling (brief connections to coexist with WaterH app)
- Display progress with halo ring UI (inspired by bottle's rainbow LED)
- Notifications on iPhone and Apple Watch

## Key Design Decisions

- **Background polling** - Brief BLE connections so WaterH app can still be used
- **Goal-based reminders** - User sets daily goal, app calculates intervals across waking hours
- **Halo ring UI** - Fills with progress, pulses rainbow when time to drink
- **Watch-first design** - UI fits Apple Watch, expanded for iPhone
- **Adaptive polling** - More frequent when timer is running low

## BLE Protocol (Decoded)

### Connection
- **Single connection only** - Bottle supports one BLE connection at a time
- **Services discovered:**
  - `0000FFE0-0000-1000-8000-00805F9B34FB` - Response service (FFE4 characteristic: Read, Notify)
  - `0000FFE5-0000-1000-8000-00805F9B34FB` - Command service (FFE9 characteristic: WriteNoResp)
  - `00010203-0405-0607-0809-0A0B0C0D1912` - Unknown service

### Data Flow
- **Subscribe to notifications** on FFE4 - bottle sends data automatically
- **Packet types:**
  - `RT` (0x52 0x54) - Real-time status, sent periodically
  - `RP` (0x52 0x50) - Response/acknowledgment
  - `PT` (0x50 0x54) - Drink history (original format)
  - Other packets contain drink records starting with metadata bytes

### Drink Record Format (13 bytes)
```
Example: 1A 02 07 0E 2E 20 00 11 00 00 01 47 00
         ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^^^^^^^^^^
         |  |  |  |  |  |  |  |  └─ Flags/checksum
         |  |  |  |  |  |  |  └──── Amount: 17ml (0x11)
         |  |  |  |  |  |  └─────── Separator (0x00)
         |  |  |  |  |  └────────── Second: 32 (0x20)
         |  |  |  |  └───────────── Minute: 46 (0x2E)
         |  |  |  └──────────────── Hour: 14 (0x0E = 2PM)
         |  |  └─────────────────── Day: 7 (0x07)
         |  └────────────────────── Month: 2 (February)
         └───────────────────────── Record type: 0x1A = drink event
```

### Packet Structure
Drink history packets typically start with 2 metadata bytes, followed by multiple 13-byte drink records:
```
[len] [meta] [drink1: 13 bytes] [drink2: 13 bytes] ...
```

## Project Status

### Phase 1: BLE Reverse Engineering - COMPLETE
### Phase 2: iOS + watchOS App - CURRENT

**Implementation plan:** `docs/plans/2026-02-03-ios-watchos-app-implementation.md`

**Progress (updated 2026-02-07 morning):**
- [x] Task 1: DrinkEvent model (committed, tests pass)
- [x] Task 2: HydrationState model (committed, tests pass)
- [x] Task 3: BLE Manager (committed)
- [x] Task 4: HydrationTracker (committed, tests need Swift 6 fix)
- [x] Task 5: HaloRingView (committed)
- [x] Task 6: ContentView - full UI (committed)
- [x] Task 7: SettingsView (committed)
- [x] Task 8: Info.plist removed (using Xcode build settings)
- [x] BLE Simulator for testing (committed)
- [x] Demo mode with 10s countdown + 60s alert (committed)
- [x] Rainbow border glow + alert banner UI (committed)
- [x] **Real countdown timer** - counts down from last drink, 45min max cap
- [x] **BLE connection persistence** - stays connected when leaving discovery
- [x] **Auto-reconnect** - reconnects when bottle disconnects
- [x] **Drink data parsing** - parses drink records from bottle notifications
- [x] **Connection status UI** - shows connected/disconnected on main screen
- [ ] Task 9: watchOS target (manual Xcode step)
- [ ] Task 10-13: Watch app + notifications
- [ ] Task 14: Final integration

**Branch:** `feature/ios-app-core-implementation` (PR #1 open)

**Current TODO (next session):**
1. Test demo countdown fix - user reported timer getting stuck, refactored to DemoCountdownManager
2. Fix HydrationTrackerTests Swift 6 concurrency issue
3. watchOS target and app
4. Notifications

### Phase 2.5: BLE Simulator - COMPLETE

**Goal:** Enable end-to-end testing of the app without the physical water bottle.

**Components:**
- `MockBLEManager` - Simulates drink events for testing
- Simulator controls in toolbar (ant icon 🐜) - Add 200ml, Add 150ml, 10s Demo, Clear All
- `DemoCountdownManager` - Manages 10s countdown + 60s alert phase independently of view lifecycle
- `RainbowBorderView` - Siri-style animated border glow when alerting (20px)
- `AlertBannerView` - "Time to Drink!" banner with bouncing drop and pulsing bell

**Usage:** In simulator, tap the ant icon (🐜) menu to add drinks or trigger the demo.

### Phase 3: Testing & Refinement
### Phase 4: ESP32 Desk Display (Chapter 2)
### Phase 5: Integration

## Key Files

- `docs/plans/2026-02-02-hydration-reminder-system-design.md` - Full design document
- `docs/plans/2026-02-03-ios-watchos-app-implementation.md` - Task-by-task implementation plan
- `SmartWaterBottleCompanion/` - iOS app source
- `SmartWaterBottleCompanion.xcodeproj` - Xcode project

### Source Files (created)
- `SmartWaterBottleCompanion/Models/DrinkEvent.swift` - BLE packet parser
- `SmartWaterBottleCompanion/Models/HydrationState.swift` - Daily hydration tracking state
- `SmartWaterBottleCompanion/Services/BLEConstants.swift` - Bluetooth UUIDs
- `SmartWaterBottleCompanion/Services/BLEManager.swift` - CoreBluetooth integration
- `SmartWaterBottleCompanion/Services/MockBLEManager.swift` - Mock BLE for simulator testing
- `SmartWaterBottleCompanion/ViewModels/HydrationTracker.swift` - Main state coordinator
- `SmartWaterBottleCompanion/ViewModels/DemoCountdownManager.swift` - Demo mode timer logic
- `SmartWaterBottleCompanion/Views/HaloRingView.swift` - Circular progress ring UI
- `SmartWaterBottleCompanion/Views/RainbowBorderView.swift` - Animated glow border
- `SmartWaterBottleCompanion/Views/AlertBannerView.swift` - "Time to Drink!" banner
- `SmartWaterBottleCompanion/Views/SettingsView.swift` - Settings screen
- `SmartWaterBottleCompanion/ContentView.swift` - Main app UI

### Test Files
- `SmartWaterBottleCompanionTests/DrinkEventTests.swift`
- `SmartWaterBottleCompanionTests/HydrationStateTests.swift`
- `SmartWaterBottleCompanionTests/DemoCountdownTests.swift` - Demo logic tests (all pass)
- `SmartWaterBottleCompanionTests/DemoCountdownManagerTests.swift` - Manager tests

## Tech Stack

- **iOS/watchOS**: Swift, SwiftUI, CoreBluetooth, WatchConnectivity
- **ESP32** (later): Arduino, NimBLE-Arduino, TFT_eSPI, WiFiManager
