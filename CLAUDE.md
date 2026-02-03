# Smart Water Bottle Companion

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

**Progress (paused at Task 1):**
- [x] Task 1: DrinkEvent model (created, tests written, needs test run)
- [ ] Task 2: HydrationState model
- [ ] Task 3: BLE Manager
- [ ] Task 4: HydrationTracker (checkpoint)
- [ ] Task 5-7: iPhone UI
- [ ] Task 8: Bluetooth permissions
- [ ] Task 9: watchOS target (manual Xcode step)
- [ ] Task 10-13: Watch app + notifications
- [ ] Task 14: Final integration

### Phase 3: Testing & Refinement
### Phase 4: ESP32 Desk Display (Chapter 2)
### Phase 5: Integration

## Key Files

- `docs/plans/2026-02-02-hydration-reminder-system-design.md` - Full design document
- `SmartWaterBottleCompanion/` - iOS app source
- `SmartWaterBottleCompanion.xcodeproj` - Xcode project

## Tech Stack

- **iOS/watchOS**: Swift, SwiftUI, CoreBluetooth, WatchConnectivity
- **ESP32** (later): Arduino, NimBLE-Arduino, TFT_eSPI, WiFiManager
