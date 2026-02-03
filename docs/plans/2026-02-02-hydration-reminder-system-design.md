# Hydration Reminder System Design

## Overview

A hydration reminder system for a child that monitors a WaterH Bluetooth water bottle and provides alerts via a desk-mounted ESP32 device with LCD display. Version 2 adds Apple Watch support.

## Goals

- Remind child to drink water at regular intervals
- Detect when child drinks (via water bottle sensors)
- Reset reminder timer when drink is detected
- Display progress and encouragement on desk device
- No phone dependency for core functionality

## Hardware

### Version 1 (MVP)
- **WaterH Bluetooth water bottle** - Existing device
- **ideaspark ESP32 + 1.9" LCD (170x320)** - Desk display unit, 16MB flash, CH340 USB
- **Passive buzzer** - Audio alerts (external, wired to GPIO + GND)
- **Temperature sensor (DHT22 or BME280)** - Adjust reminder frequency based on ambient temperature
- **PIR motion sensor** - Detect child stillness, encourage movement breaks
- **LDR (Light Dependent Resistor)** - Gesture input: cover device with hand to dismiss/snooze alerts

### Version 2
- All of the above, plus:
- **Apple Watch** - Wearable alerts when away from desk
- **Mi Band 6** (alternative) - Cheaper wearable option with Gadgetbridge support

---

## Part 1: BLE Protocol (Reverse Engineered)

### Protocol Status: DECODED ✓

The WaterH bottle protocol has been successfully reverse-engineered using nRF Connect on iOS.

### BLE Characteristics

The bottle exposes custom 128-bit UUIDs (no standard advertised services):

| Characteristic | Properties | Purpose |
|----------------|------------|---------|
| #1 | Write Without Response | Command channel - send requests |
| #2 | Read, Write Without Response | Response channel - read data |
| #3 (SMP) | Notify | Status/keepalive (pulses every 5 seconds) |

### Commands

| Command | Bytes | Description |
|---------|-------|-------------|
| Request drink history | `01` | Write to characteristic #1, triggers drink data response |

**Note:** Writing `01`, `0100`, or `FF` to characteristic #2 causes disconnection - avoid.

### Message Types

Messages are identified by a 2-byte ASCII header:

| Header | ASCII | Purpose |
|--------|-------|---------|
| `50 54` | "PT" | **Drink data packet** - contains drink event records |
| `52 54` | "RT" | Real-time status |
| `52 50` | "RP" | Response/acknowledgment |

### Drink Event Packet Format

**Full packet structure:**

```
┌────────┬────────┬──────────┬─────────────────────────────┐
│ Header │ Length │ Metadata │ Drink Records (repeated)    │
│ 2 bytes│ 2 bytes│ 2 bytes  │ 13 bytes each               │
└────────┴────────┴──────────┴─────────────────────────────┘
```

**Example packet:**
```
50 54 00 0F 0E 06 | 1A 02 02 16 15 0F 00 10 00 00 01 61 00
─────────────────   ─────────────────────────────────────
     Header              Drink Record (13 bytes)
```

### Drink Record Format (13 bytes)

| Byte | Offset | Field | Format | Example | Decoded |
|------|--------|-------|--------|---------|---------|
| 1 | 0x00 | Record Type | uint8 | `1A` | 26 = Drink event |
| 2 | 0x01 | Month | uint8 | `02` | February |
| 3 | 0x02 | Day | uint8 | `02` | 2nd |
| 4 | 0x03 | Hour | uint8 (24h) | `16` | 22 (10 PM) |
| 5 | 0x04 | Minute | uint8 | `15` | 21 |
| 6 | 0x05 | Second | uint8 | `0F` | 15 |
| 7 | 0x06 | Separator | uint8 | `00` | - |
| 8 | 0x07 | **Amount (ml)** | uint8 | `10` | **16 ml** |
| 9-13 | 0x08-0x0C | Flags/Checksum | bytes | `00 00 01 61 00` | TBD |

### Parsing Example (C/Arduino)

```cpp
struct DrinkEvent {
  uint8_t recordType;  // Should be 0x1A for drink
  uint8_t month;
  uint8_t day;
  uint8_t hour;
  uint8_t minute;
  uint8_t second;
  uint8_t separator;
  uint8_t amountMl;
  uint8_t flags[5];
};

DrinkEvent parseDrinkRecord(uint8_t* data) {
  DrinkEvent event;
  event.recordType = data[0];
  event.month = data[1];
  event.day = data[2];
  event.hour = data[3];
  event.minute = data[4];
  event.second = data[5];
  event.separator = data[6];
  event.amountMl = data[7];
  memcpy(event.flags, &data[8], 5);
  return event;
}

bool isDrinkEvent(DrinkEvent* event) {
  return event->recordType == 0x1A;
}
```

### Parsing Example (Swift for Apple Watch)

```swift
struct DrinkEvent {
    let recordType: UInt8
    let month: UInt8
    let day: UInt8
    let hour: UInt8
    let minute: UInt8
    let second: UInt8
    let amountMl: UInt8

    init?(data: Data) {
        guard data.count >= 13, data[0] == 0x1A else { return nil }
        recordType = data[0]
        month = data[1]
        day = data[2]
        hour = data[3]
        minute = data[4]
        second = data[5]
        // data[6] is separator
        amountMl = data[7]
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

### Connection Notes

1. **Single connection only** - The bottle supports one BLE connection at a time. If the WaterH app is connected, ESP32 cannot connect.

2. **Advertising interval** - The bottle advertises infrequently to save battery. May take several seconds to appear in scans.

3. **Wake on interaction** - Shaking the bottle or removing/replacing the lid helps it appear faster in scans.

4. **Connection sequence:**
   1. Scan for device (custom UUID, no advertised name)
   2. Connect
   3. Discover services and characteristics
   4. Write `01` to command characteristic
   5. Read drink history from response characteristic
   6. Subscribe to SMP notify for keepalive (optional)

### Raw Data Samples

**Sample 1: Multiple drink records**
```
5054 00D4 6906 1A02 0215 1627 002D 0000 0161 001A 0202 1518 0800 2B00 0001 6100...
```
Decoded: Multiple drinks on Feb 2nd with amounts 45ml, 43ml, etc.

**Sample 2: Single drink record (verified)**
```
5054 000F 0E06 1A02 0216 150F 0010 0000 0161 00
```
Decoded: Feb 2nd, 22:21:15, **16ml** ✓ (verified against WaterH app)

---

## Part 2: ESP32 Firmware Architecture

### Platform

- **Framework:** Arduino or ESP-IDF (Arduino recommended for faster development)
- **Libraries:**
  - `NimBLE-Arduino` - Lightweight BLE stack
  - `TFT_eSPI` or `LovyanGFX` - Display driver
  - `WiFiManager` - Easy WiFi setup
  - `ArduinoJson` - Data serialization

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ESP32 Firmware                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ BLE Manager │    │ Timer Engine│    │ Display Mgr │     │
│  │             │    │             │    │             │     │
│  │ - Connect   │───▶│ - Countdown │───▶│ - Render UI │     │
│  │ - Subscribe │    │ - Reset     │    │ - Animations│     │
│  │ - Parse data│    │ - Alert     │    │ - Progress  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                  │                  │             │
│         │                  ▼                  │             │
│         │          ┌─────────────┐            │             │
│         │          │ Alert System│            │             │
│         │          │             │            │             │
│         │          │ - Buzzer    │            │             │
│         │          │ - LED flash │            │             │
│         │          └─────────────┘            │             │
│         │                                     │             │
│         ▼                                     ▼             │
│  ┌─────────────────────────────────────────────────┐       │
│  │              WiFi API Server                     │       │
│  │                                                  │       │
│  │  GET /status - Current state (for Apple Watch)  │       │
│  │  GET /history - Drink events                    │       │
│  │  POST /ack - Acknowledge reminder               │       │
│  └─────────────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Core Components

#### 1. BLE Manager
```
Responsibilities:
- Scan for and connect to water bottle
- Handle reconnection if connection drops
- Subscribe to notification characteristics
- Parse incoming data into drink events
- Maintain connection state

States:
- SCANNING
- CONNECTING
- CONNECTED
- DISCONNECTED (retry with backoff)
```

#### 2. Timer Engine
```
Responsibilities:
- Track time since last drink
- Configurable reminder interval (default: 30 mins)
- Trigger alert when timer expires
- Reset timer when drink detected
- Persist state across reboots (NVS storage)

Events:
- DRINK_DETECTED → Reset timer
- TIMER_EXPIRED → Trigger alert
- USER_ACK → Snooze for 5 minutes
```

#### 3. Display Manager
```
Responsibilities:
- Render current state to LCD
- Show countdown timer (big numbers)
- Show hydration progress (glasses/day)
- Play animations for encouragement
- Flash screen during alerts
```

#### 4. Alert System
```
Responsibilities:
- Buzzer patterns (gentle → urgent escalation)
- LED flashing (if available)
- Screen flash/animation
- Dismissable via button or drink detection
```

#### 5. WiFi API Server
```
Responsibilities:
- Serve REST API for external clients (Apple Watch)
- Provide current status, history, control
- mDNS for easy discovery (hydrate.local)
```

### Configuration (stored in NVS)

```cpp
struct Config {
  uint16_t reminderIntervalMins = 30;
  uint8_t dailyGoalGlasses = 8;
  bool soundEnabled = true;
  uint8_t volume = 50;
  char bottleMacAddress[18];
  char wifiSSID[32];
  char wifiPassword[64];
};
```

---

## Part 3: Display UI/UX

### Design Principles

- **Kid-friendly:** Bright colors, fun animations, encouraging messages
- **Glanceable:** Status visible from across room
- **Non-distracting:** Subtle when not alerting

### Screen States

#### 1. Normal State (Counting Down)
```
┌─────────────────────┐
│   Stay Hydrated!    │
│                     │
│      23:45          │  ← Big countdown timer
│   minutes left      │
│                     │
│  [████████░░] 6/8   │  ← Progress bar (glasses today)
│                     │
│   💧 Great job!     │  ← Encouraging message
└─────────────────────┘
```

#### 2. Alert State (Time to Drink!)
```
┌─────────────────────┐
│   ⚠️ DRINK TIME! ⚠️  │  ← Flashing
│                     │
│      💧💧💧          │  ← Animated water drops
│                     │
│   Grab your bottle! │
│                     │
│  [Press to snooze]  │
└─────────────────────┘
```
- Screen flashes blue/white
- Buzzer sounds pattern
- Escalates if ignored

#### 3. Celebration State (Just Drank!)
```
┌─────────────────────┐
│                     │
│      ⭐ YAY! ⭐      │
│                     │
│   You drank water!  │
│                     │
│  [████████░░] 7/8   │  ← Updated progress
│                     │
│   Keep it up!       │
└─────────────────────┘
```
- Happy animation
- Progress bar updates
- Returns to normal after 5 seconds

#### 4. Disconnected State
```
┌─────────────────────┐
│                     │
│   🔍 Looking for    │
│      bottle...      │
│                     │
│   Make sure it's    │
│      nearby         │
│                     │
└─────────────────────┘
```

#### 5. Setup Mode (First boot / button hold)
```
┌─────────────────────┐
│   Setup Mode        │
│                     │
│ Connect to WiFi:    │
│ "HydrateSetup"      │
│                     │
│ Then visit:         │
│ 192.168.4.1         │
└─────────────────────┘
```

### Animations

- **Water filling:** Progress bar fills like water
- **Droplet bounce:** Water drops bounce on celebrations
- **Gentle pulse:** Screen subtly pulses during countdown
- **Urgent shake:** Screen shakes during escalated alerts

---

## Part 4: Alert System

### Alert Escalation Sequence

| Time | Visual | Audio | Duration | Description |
|------|--------|-------|----------|-------------|
| 0:00 | Blue flash | 2 short beeps | 1 sec | Gentle reminder |
| 0:30 | Faster flash | 3 beeps | 2 sec | First escalation |
| 1:00 | Screen shake | Continuous beeping | **10 sec max** | Urgent |
| 2:00 | Full brightness | Loud pattern | **15 sec max** | Maximum urgency |
| 5:00 | Return to normal | Silence | - | Auto-snooze |

**Important:** Audio alerts are time-limited to avoid being annoying. Continuous beeping stops after 10 seconds, loud pattern stops after 15 seconds. Visual alerts continue.

### Snooze Behavior

- **LDR gesture (cover with hand):** Snooze 5 minutes
- **Drink detected:** Full reset to configured interval
- **Auto-snooze:** After 5 minutes of ignored alerts

### Temperature-Based Interval Adjustment

| Temperature | Reminder Interval |
|-------------|-------------------|
| < 20°C | 45 minutes (cool, less sweating) |
| 20-25°C | 30 minutes (default) |
| 25-30°C | 20 minutes (warm) |
| > 30°C | 15 minutes (hot, needs more water) |

### Movement Reminder (PIR Sensor)

If PIR detects no movement for 30 minutes:
- Display: "Time to stretch!"
- Audio: Single gentle tone
- Does not override hydration alerts (lower priority)

### Sound Patterns (Buzzer)

```cpp
// Gentle reminder (2 rising tones)
tone(BUZZER_PIN, 1000, 100);
delay(150);
tone(BUZZER_PIN, 1200, 100);

// Urgent alert (max 10 seconds)
unsigned long start = millis();
while (millis() - start < 10000) {  // 10 sec limit
  tone(BUZZER_PIN, 1500, 200);
  delay(100);
  if (alertDismissed()) break;
}
noTone(BUZZER_PIN);

// Loud pattern (max 15 seconds)
start = millis();
while (millis() - start < 15000) {  // 15 sec limit
  tone(BUZZER_PIN, 2000, 100);
  delay(50);
  tone(BUZZER_PIN, 1500, 100);
  delay(50);
  if (alertDismissed()) break;
}
noTone(BUZZER_PIN);

// Celebration - simple triad arpeggio
tone(BUZZER_PIN, 523, 100);  // C5
delay(100);
tone(BUZZER_PIN, 659, 100);  // E5
delay(100);
tone(BUZZER_PIN, 784, 150);  // G5
```

### LDR Gesture Detection

```cpp
#define LDR_PIN A0
#define COVER_THRESHOLD 100  // Adjust based on ambient light

bool isDeviceCovered() {
  int lightLevel = analogRead(LDR_PIN);
  return lightLevel < COVER_THRESHOLD;
}

// In alert loop:
if (isDeviceCovered()) {
  snoozeAlert(5 * 60 * 1000);  // 5 minute snooze
}
```

---

## Part 5: Version 2 - Apple Watch Integration

### Option Analysis

#### Option A: Apple Watch Direct to Bottle (Preferred if possible)

```
┌─────────────────┐         BLE          ┌─────────────────┐
│  WaterH Bottle  │ ◀────────────────── │  Apple Watch    │
└─────────────────┘                      └─────────────────┘
```

**Pros:**
- Simplest architecture
- No ESP32 needed for Watch users
- Works anywhere (not just at desk)

**Cons:**
- watchOS BLE has limitations (background time, connection limits)
- May not work if iPhone WaterH app is also connected (BLE single connection issue)
- Need to reverse-engineer protocol again in Swift

**Feasibility:** Medium. Worth attempting. watchOS 9+ improved background BLE.

#### Option B: ESP32 → WiFi → iPhone → Apple Watch

```
┌─────────────┐  BLE  ┌─────────────┐  WiFi  ┌─────────────┐  Watch  ┌─────────────┐
│   Bottle    │──────▶│    ESP32    │───────▶│   iPhone    │────────▶│ Apple Watch │
└─────────────┘       └─────────────┘        └─────────────┘         └─────────────┘
```

**Pros:**
- ESP32 does the hard BLE work
- iPhone app relays status to Watch via WatchConnectivity
- Most reliable for Watch updates

**Cons:**
- Requires iPhone in the loop
- More components, more failure points

**Feasibility:** High. Well-documented approach.

#### Option C: ESP32 → Web Service → Apple Watch

```
┌─────────────┐  BLE  ┌─────────────┐  WiFi  ┌─────────────┐  HTTPS  ┌─────────────┐
│   Bottle    │──────▶│    ESP32    │───────▶│ Web Server  │◀────────│ Apple Watch │
└─────────────┘       └─────────────┘        │ (Cloud/Local)│        └─────────────┘
                                             └─────────────┘
```

**Pros:**
- Watch can work independently of iPhone (cellular Watch)
- Could add web dashboard, multiple users

**Cons:**
- Requires running a server (or cloud service)
- Latency for alerts
- Internet dependency

**Feasibility:** High, but overkill for single-user home use.

#### Option D: ESP32 → Local WiFi → Apple Watch (Direct)

```
┌─────────────┐  BLE  ┌─────────────┐  WiFi  ┌─────────────┐
│   Bottle    │──────▶│    ESP32    │◀──────▶│ Apple Watch │
└─────────────┘       └─────────────┘        └─────────────┘
```

**Pros:**
- No iPhone needed
- No cloud needed
- Low latency

**Cons:**
- Apple Watch WiFi is limited (needs known network)
- Watch apps can't easily poll HTTP in background
- Complications can refresh but infrequently

**Feasibility:** Low. watchOS restricts background networking.

### Recommended Approach for V2

**Try Option A first** (Watch direct to bottle), with **Option B as fallback**.

#### Implementation Plan:

**Step 1: Test watchOS BLE capability**
- Build minimal watchOS app that scans for bottle
- Verify it can connect and receive notifications
- Test background behavior (does it maintain connection?)

**Step 2a: If Watch BLE works well**
- Port ESP32 BLE parsing logic to Swift
- Build standalone Watch app
- ESP32 becomes optional "desk display" accessory

**Step 2b: If Watch BLE is unreliable**
- Implement Option B
- ESP32 remains the brain
- iPhone app bridges to Watch via WatchConnectivity
- Watch app shows complications + alerts

### Apple Watch App Architecture (Option A or B)

#### Watch App Components

```
┌─────────────────────────────────────────────────────────────┐
│                   watchOS App                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ BLE Manager │    │ Timer Engine│    │Complication │     │
│  │ (Option A)  │    │             │    │   Provider  │     │
│  │             │───▶│ - Countdown │───▶│             │     │
│  │ OR          │    │ - Alerts    │    │ - Progress  │     │
│  │             │    │             │    │ - Timer     │     │
│  │ WatchConnect│    │             │    │             │     │
│  │ (Option B)  │    │             │    │             │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                            │                                │
│                            ▼                                │
│                     ┌─────────────┐                        │
│                     │ Haptic/Sound│                        │
│                     │   Alerts    │                        │
│                     └─────────────┘                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Watch UI Screens

**Main Screen:**
```
┌─────────────────┐
│    23:45        │  ← Countdown
│   until drink   │
│                 │
│  [██████░░] 6/8 │  ← Progress
│                 │
│ [Drink Now btn] │  ← Manual log
└─────────────────┘
```

**Complication (Circular):**
```
    ┌───┐
   ╱  6  ╲    ← Glasses today
  │  /8   │   ← Goal
   ╲ 💧 ╱    ← Water icon
    └───┘
```

**Alert Notification:**
```
┌─────────────────┐
│ 💧 Time to      │
│    Drink!       │
│                 │
│ [Snooze] [Done] │
└─────────────────┘
```
- Haptic tap pattern
- Optional sound

---

## Development Phases

### Phase 1: BLE Reverse Engineering ✓ COMPLETE
- [x] Enumerate all bottle services/characteristics with nRF Connect
- [x] Subscribe to all notify characteristics
- [x] Document protocol (characteristics, data formats, commands)
- [x] Decode drink event packet format
- [x] Verify decoded data against WaterH app (16ml reading confirmed)
- [ ] Document remaining unknown fields (flags/checksum bytes 9-13)

### Phase 2: ESP32 MVP (2-3 weeks development)
- [ ] Set up ESP32 development environment (Arduino + PlatformIO)
- [ ] Implement BLE connection to bottle
- [ ] Parse drink events from BLE notifications
- [ ] Implement timer engine with persistence
- [ ] Build LCD UI (countdown, progress, alerts)
- [ ] Add buzzer alert system
- [ ] Add WiFi setup portal (WiFiManager)
- [ ] Implement REST API for status

### Phase 3: Testing & Refinement
- [ ] Test with actual child user
- [ ] Tune alert escalation timing
- [ ] Adjust UI for readability/engagement
- [ ] Handle edge cases (bottle out of range, power loss, etc.)

### Phase 4: Apple Watch App (Option A attempt)
- [ ] Create watchOS app project
- [ ] Test BLE connection to bottle from Watch
- [ ] Evaluate background reliability
- [ ] If successful: port BLE parsing, build Watch UI
- [ ] If unsuccessful: proceed to Phase 5

### Phase 5: Apple Watch via iPhone Bridge (Option B fallback)
- [ ] Create iOS companion app
- [ ] Implement WatchConnectivity bridge
- [ ] ESP32 pushes events to iPhone via REST/WebSocket
- [ ] iPhone relays to Watch
- [ ] Build Watch complications and alerts

---

## Open Questions

1. ~~**Bottle BLE behavior:**~~ **ANSWERED** - Single connection only. ESP32 and WaterH app cannot connect simultaneously.

2. **Drink detection accuracy:** How does the bottle detect drinks? Tilt sensor? Flow sensor? Weight? (Works reliably in testing, exact mechanism unknown)

3. **Power considerations:** Does the ESP32 need a physical on/off switch, or is always-on acceptable?

4. **Alert preferences:** What times should alerts be suppressed? (School hours? Nighttime?)

5. **Multi-child support:** Is this for one child, or should the system support multiple bottles/children?

6. **Bytes 9-13 meaning:** The `00 00 01 61 00` at the end of each drink record - what do these represent? Possibly: checksum, cumulative total, sensor flags?

7. **Year field:** No obvious year byte in the packet. How does the bottle handle year rollover? (Probably resets or inferred from sync)

---

## Success Criteria

### MVP (Phase 2 complete)
- ESP32 successfully connects to water bottle
- Drink events are detected and logged
- Timer resets when drink is detected
- Visual countdown displays on LCD
- Audible alert sounds when timer expires
- Device survives 7 days of continuous use

### Full System (Phase 4 or 5 complete)
- All MVP criteria, plus:
- Apple Watch shows hydration status
- Watch alerts when timer expires
- Watch complications show progress
- System works reliably for 30 days
