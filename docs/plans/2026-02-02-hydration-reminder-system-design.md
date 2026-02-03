# Hydration Reminder System Design

## Overview

A hydration reminder system for a child that monitors a WaterH Bluetooth water bottle and provides alerts. The system has two implementation paths:

1. **Chapter 1: iOS + watchOS App** - iPhone handles BLE polling, syncs state to Apple Watch. Faster iteration, validates BLE parsing, enables wearable alerts.

2. **Chapter 2: ESP32 Desk Display** - Standalone desk-mounted device with LCD. No phone dependency, always-visible display, physical alerts.

Both approaches can coexist - the ESP32 could receive state from the iPhone rather than connecting to the bottle directly.

## Goals

- Remind child to drink water based on daily goal spread across waking hours
- Detect drinks via water bottle BLE sensors
- Reset reminder timer when drink is detected
- Display progress with halo ring UI (inspired by bottle's LED)
- Notifications on iPhone and Apple Watch

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

### Parsing Example (Swift for iOS/watchOS)

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

1. **Single connection only** - The bottle supports one BLE connection at a time. If the WaterH app is connected, other devices cannot connect.

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

## Part 2: iOS + watchOS App (Chapter 1)

### Concept

An iOS app that polls the WaterH bottle via BLE and syncs hydration state to Apple Watch. Uses brief polling connections so the WaterH app can still be used.

### Key Design Decisions

- **Background polling** - App connects briefly to grab drink data, then disconnects. Coexists with WaterH app.
- **Goal-based reminders** - User sets daily goal (e.g., 8 glasses), app calculates intervals to spread drinks across waking hours.
- **Halo ring UI** - Inspired by bottle's rainbow LED. Ring fills with progress, pulses rainbow when it's time to drink.
- **Watch-first design** - UI designed to fit Apple Watch, then expanded for iPhone.
- **Fixed schedule** - User sets wake/sleep times in settings (e.g., 7am-9pm).
- **Adaptive polling** - More frequent polling when timer is running low.

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      iOS App                             │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ BLE Manager  │  │ Hydration    │  │ Notification │   │
│  │              │  │ Tracker      │  │ Manager      │   │
│  │ - Scan/connect│ │              │  │              │   │
│  │ - Poll bottle │→│ - Daily goal │→│ - Schedule   │   │
│  │ - Parse drinks│ │ - Timer calc │  │ - iPhone/Watch│  │
│  │ - Disconnect │  │ - History    │  │ - Halo state │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│                            ↓                             │
│                    ┌──────────────┐                      │
│                    │ WatchConnect │                      │
│                    │ - Sync state │                      │
│                    │ - Push updates│                     │
│                    └──────────────┘                      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    watchOS App                           │
├─────────────────────────────────────────────────────────┤
│  - Receives state from iPhone via WatchConnectivity     │
│  - Displays halo ring, progress, countdown              │
│  - Shows notifications with haptics                     │
│  - Complication for watch face                          │
└─────────────────────────────────────────────────────────┘
```

**Data flow:**
1. iPhone does all BLE work (Watch BLE in background is unreliable)
2. iPhone calculates timer state and syncs to Watch
3. Both devices can fire notifications, but iPhone is source of truth

### Adaptive Polling Schedule

| Timer State | Poll Interval |
|-------------|---------------|
| >10 min remaining | Every 10 minutes |
| 5-10 min remaining | Every 5 minutes |
| <5 min remaining | Every 2 minutes |
| Alert firing | Every 1 minute (to detect drink and stop alert) |

**Connection sequence (each poll):**
1. Scan for bottle (timeout 10s)
2. Connect
3. Write `01` to command characteristic
4. Read drink history from response
5. Disconnect immediately
6. Parse new drinks, update tracker

### iPhone UI

**Main Screen:**
```
┌─────────────────────────────┐
│  ╭─────────────────────╮    │
│  │                     │    │
│  │      ◐ 6/8         │    │  ← Large halo ring
│  │       💧            │    │     (fills as progress)
│  │                     │    │
│  ╰─────────────────────╯    │
│                             │
│        18:32                │  ← Countdown timer
│     until next drink        │
│                             │
├─────────────────────────────┤
│  Today                      │
│  ├ 3:42pm   120ml          │  ← Drink history
│  ├ 1:15pm    85ml          │
│  ├ 11:30am  200ml          │
│  └ 9:02am   150ml          │
│                             │
│            ⚙️               │  ← Settings
└─────────────────────────────┘
```

**Settings Screen:**
- Daily goal (glasses or ml)
- Wake time / Sleep time
- Notification sound on/off
- Bottle connection status

**Alert State:** Halo pulses rainbow, background shifts color, notification fires.

### Watch UI

**Main View:**
```
┌─────────────────────┐
│ ╭─────────────────╮ │
│ │                 │ │
│ │     6/8 💧      │ │  ← Glass count
│ │                 │ │
│ │     18:32       │ │  ← Countdown
│ │                 │ │
│ ╰─────────────────╯ │
│ ═══════════════╗    │  ← Halo ring (75%)
└─────────────────────┘
```

**Alert State:** Halo animates rainbow pulse, haptic tap pattern fires.

**Complication (circular):** Mini halo ring with count (e.g., "6/8") - glanceable from any watch face.

### Halo Ring Design

Inspired by the WaterH bottle's rainbow LED halo:
- Shows progress (fills up as you drink toward goal)
- Pulses/animates rainbow when it's time to drink
- Subtle color shifts based on status:
  - Blue/green = on track
  - Orange = timer running low
  - Rainbow pulse = time to drink!

---

## Part 3: ESP32 Desk Display (Chapter 2)

### Hardware

- **WaterH Bluetooth water bottle** - Existing device
- **ideaspark ESP32 + 1.9" LCD (170x320)** - Desk display unit, 16MB flash, CH340 USB
- **Passive buzzer** - Audio alerts (external, wired to GPIO + GND)
- **Temperature sensor (DHT22 or BME280)** - Adjust reminder frequency based on ambient temperature
- **PIR motion sensor** - Detect child stillness, encourage movement breaks
- **LDR (Light Dependent Resistor)** - Gesture input: cover device with hand to dismiss/snooze alerts

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

## Part 4: ESP32 Display UI/UX

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

## Part 5: ESP32 Alert System

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

## Part 6: Future Integration Options

### Option A: Apple Watch Direct to Bottle

```
┌─────────────────┐         BLE          ┌─────────────────┐
│  WaterH Bottle  │ ◀────────────────── │  Apple Watch    │
└─────────────────┘                      └─────────────────┘
```

**Feasibility:** Medium. watchOS BLE in background is unreliable. Not recommended.

### Option B: iPhone → Apple Watch (CURRENT APPROACH)

```
┌─────────────┐  BLE  ┌─────────────┐  WatchConnect  ┌─────────────┐
│   Bottle    │──────▶│   iPhone    │───────────────▶│ Apple Watch │
└─────────────┘       └─────────────┘                └─────────────┘
```

**Feasibility:** High. This is Chapter 1.

### Option C: ESP32 → iPhone → Apple Watch

```
┌─────────────┐  BLE  ┌─────────────┐  WiFi  ┌─────────────┐  Watch  ┌─────────────┐
│   Bottle    │──────▶│    ESP32    │───────▶│   iPhone    │────────▶│ Apple Watch │
└─────────────┘       └─────────────┘        └─────────────┘         └─────────────┘
```

**Feasibility:** High. ESP32 could push to iPhone app, which relays to Watch. ESP32 maintains always-on desk display.

### Option D: ESP32 as Display-Only (receives from iPhone)

```
┌─────────────┐  BLE  ┌─────────────┐  WiFi  ┌─────────────┐
│   Bottle    │──────▶│   iPhone    │───────▶│    ESP32    │
└─────────────┘       └─────────────┘        │ (display)   │
                             │               └─────────────┘
                             ▼
                      ┌─────────────┐
                      │ Apple Watch │
                      └─────────────┘
```

**Feasibility:** High. iPhone becomes the brain, ESP32 just displays. Avoids BLE connection conflicts entirely.

---

## Development Phases

### Phase 1: BLE Reverse Engineering ✓ COMPLETE
- [x] Enumerate all bottle services/characteristics with nRF Connect
- [x] Subscribe to all notify characteristics
- [x] Document protocol (characteristics, data formats, commands)
- [x] Decode drink event packet format
- [x] Verify decoded data against WaterH app (16ml reading confirmed)
- [ ] Document remaining unknown fields (flags/checksum bytes 9-13)

### Phase 2: iOS + watchOS App (Chapter 1) ← CURRENT
- [ ] Add watchOS target to Xcode project
- [ ] Implement BLE Manager (scan, connect, poll, disconnect)
- [ ] Implement Hydration Tracker (goal, timer calculation, history)
- [ ] Build iPhone UI (halo ring, countdown, history list, settings)
- [ ] Build Watch UI (halo ring, countdown, complication)
- [ ] Implement WatchConnectivity sync
- [ ] Add local notifications (iPhone + Watch)
- [ ] Test adaptive polling behavior

### Phase 3: Testing & Refinement
- [ ] Test with actual child user
- [ ] Tune reminder intervals
- [ ] Adjust UI for engagement
- [ ] Handle edge cases (bottle out of range, app backgrounded, etc.)

### Phase 4: ESP32 Desk Display (Chapter 2)
- [ ] Set up ESP32 development environment (Arduino + PlatformIO)
- [ ] Implement BLE connection to bottle (or receive from iPhone)
- [ ] Parse drink events from BLE notifications
- [ ] Implement timer engine with persistence
- [ ] Build LCD UI (countdown, progress, alerts)
- [ ] Add buzzer alert system
- [ ] Add WiFi setup portal (WiFiManager)
- [ ] Implement REST API for status

### Phase 5: Integration
- [ ] Connect ESP32 to iPhone app (push/pull state)
- [ ] Unified experience across all devices
- [ ] Handle failover gracefully

---

## Open Questions

1. ~~**Bottle BLE behavior:**~~ **ANSWERED** - Single connection only. Apps cannot connect simultaneously.

2. **Drink detection accuracy:** How does the bottle detect drinks? Tilt sensor? Flow sensor? Weight? (Works reliably in testing, exact mechanism unknown)

3. **Power considerations:** Does the ESP32 need a physical on/off switch, or is always-on acceptable?

4. **Alert preferences:** What times should alerts be suppressed? (School hours? Nighttime?) → User sets wake/sleep times in settings.

5. **Multi-child support:** Is this for one child, or should the system support multiple bottles/children?

6. **Bytes 9-13 meaning:** The `00 00 01 61 00` at the end of each drink record - what do these represent? Possibly: checksum, cumulative total, sensor flags?

7. **Year field:** No obvious year byte in the packet. How does the bottle handle year rollover? (Probably resets or inferred from sync)

---

## Success Criteria

### Chapter 1 Complete (iOS + watchOS)
- iPhone successfully polls water bottle via BLE
- Drink events are detected and logged
- Timer resets when drink is detected
- Halo ring shows progress toward daily goal
- Notifications fire on iPhone and Watch when timer expires
- Watch complication shows current progress
- System coexists with WaterH app (polling, not persistent connection)

### Chapter 2 Complete (ESP32 Desk Display)
- ESP32 displays hydration status on LCD
- Audible/visual alerts when timer expires
- Receives state from iPhone OR connects to bottle directly
- Device survives 7 days of continuous use

### Full System
- All devices show consistent state
- Reliable for 30 days of daily use
