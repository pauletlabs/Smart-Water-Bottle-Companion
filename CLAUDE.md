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

**Progress (paused 2026-02-05, files created but tests not yet verified):**
- [x] Task 1: DrinkEvent model (committed)
- [~] Task 2: HydrationState model (code + tests created, needs verification)
- [~] Task 3: BLE Manager (code created, needs tests + verification)
- [ ] Task 4: HydrationTracker (checkpoint)
- [~] Task 5: HaloRingView (code created, needs tests + verification)
- [ ] Task 6-7: Remaining iPhone UI (MainDashboardView, SettingsView)
- [~] Task 8: Info.plist Bluetooth permissions (created, needs verification)
- [ ] Task 9: watchOS target (manual Xcode step)
- [ ] Task 10-13: Watch app + notifications
- [ ] Task 14: Final integration

**Next session TODO:**
1. Run all tests to verify Tasks 1-3, 5: `xcodebuild test -project SmartWaterBottleCompanion.xcodeproj -scheme SmartWaterBottleCompanion -destination 'platform=iOS Simulator,name=iPhone 16'`
2. Fix any failing tests
3. Commit working code to feature branch
4. Continue with Task 4 (HydrationTracker) and remaining UI tasks

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
- `SmartWaterBottleCompanion/Views/HaloRingView.swift` - Circular progress ring UI

### Test Files
- `SmartWaterBottleCompanionTests/DrinkEventTests.swift`
- `SmartWaterBottleCompanionTests/HydrationStateTests.swift`

## Tech Stack

- **iOS/watchOS**: Swift, SwiftUI, CoreBluetooth, WatchConnectivity
- **ESP32** (later): Arduino, NimBLE-Arduino, TFT_eSPI, WiFiManager
