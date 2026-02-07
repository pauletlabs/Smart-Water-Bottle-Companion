# Smart Water Bottle Companion

A hydration reminder system for children that monitors a WaterH Bluetooth water bottle and provides timely drink reminders.

## Features

- **Live BLE Connection** - Connects to WaterH-Boost-24oz water bottle via Bluetooth
- **Automatic Drink Detection** - Parses drink events from bottle notifications in real-time
- **Halo Clock Display** - Visual ring showing drink history mapped to time of day
- **Smart Countdown Timer** - Counts down to next drink, capped at 45 minutes max
- **Auto-Reconnect** - Automatically reconnects when bottle disconnects
- **Demo Mode** - Built-in simulator for testing without the physical bottle

## Screenshots

*Coming soon*

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      iOS App                            │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ BLE Manager  │  │  Hydration   │  │    Halo      │  │
│  │              │──│   Tracker    │──│  Clock View  │  │
│  │ - Connect    │  │              │  │              │  │
│  │ - Subscribe  │  │ - Daily goal │  │ - Time ring  │  │
│  │ - Parse data │  │ - Timer calc │  │ - Drink marks│  │
│  │ - Reconnect  │  │ - History    │  │ - Countdown  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## BLE Protocol

The app communicates with the WaterH bottle using a reverse-engineered BLE protocol:

| Service UUID | Characteristic | Purpose |
|--------------|----------------|---------|
| `0000FFE0-...` | `0000FFE4-...` | Read/Notify - Response data |
| `0000FFE5-...` | `0000FFE9-...` | WriteNoResp - Commands |

### Drink Record Format (13 bytes)

```
1A 02 07 0E 2E 20 00 11 00 00 01 47 00
│  │  │  │  │  │  │  │
│  │  │  │  │  │  │  └── Amount: 17ml
│  │  │  │  │  │  └───── Separator
│  │  │  │  │  └──────── Second
│  │  │  │  └─────────── Minute
│  │  │  └────────────── Hour (24h)
│  │  └───────────────── Day
│  └──────────────────── Month
└─────────────────────── Record type (0x1A = drink)
```

## Implementation Chapters

### Chapter 1: iOS + watchOS App (Current)
iPhone handles BLE polling and syncs state to Apple Watch.

### Chapter 2: ESP32 Desk Display (Future)
Standalone desk device with LCD for always-visible hydration status.

## Getting Started

### Prerequisites
- Xcode 15+
- iOS 17+
- WaterH-Boost-24oz water bottle

### Installation
1. Clone this repository
2. Open `SmartWaterBottleCompanion.xcodeproj` in Xcode
3. Build and run on your iOS device

### Testing Without a Bottle
Use the simulator controls (ant icon menu) to:
- Add simulated drinks (200ml, 150ml)
- Trigger 10-second demo countdown
- Clear all drink history

## Project Status

See [GitHub Issues](../../issues) for current epics and tasks.

**Current Branch:** `feature/ios-app-core-implementation`

## Author

Charlie Normand

## License

*TBD*
