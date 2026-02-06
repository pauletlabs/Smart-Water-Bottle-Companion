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

- **Single connection only** - Bottle supports one BLE connection at a time
- **Command**: Write `01` to characteristic #1 to request drink history
- **Response**: Read from characteristic #2, `PT` header = drink data

### Drink Record Format (13 bytes)
```
Byte 0: Record type (0x1A = drink)
Byte 1: Month
Byte 2: Day
Byte 3: Hour (24h)
Byte 4: Minute
Byte 5: Second
Byte 6: Separator (0x00)
Byte 7: Amount in ml
Bytes 8-12: Flags/checksum (TBD)
```

## Project Status

### Phase 1: BLE Reverse Engineering - COMPLETE
### Phase 2: iOS + watchOS App - CURRENT

**Implementation plan:** `docs/plans/2026-02-03-ios-watchos-app-implementation.md`

**Progress (updated 2026-02-06 evening):**
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
