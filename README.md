# AirPressure iOS App

Minimal SwiftUI iPhone app for the `JingQiBMP` BLE pressure sensor.

## What it does

- Scans and connects to the Arduino peripheral named `JingQiBMP`
- Uses Nordic UART Service (NUS) to send `S`, `P`, and `C`
- Parses BLE payloads such as `B:99183,99184,99183,99185,99183|S:1`
- Shows live pressure, sensor state, and a rolling pressure chart

## Open in Xcode

Open:

- `/Users/linjingqi/Projects/Ear/Air_Pressure/AirPressure.xcodeproj`

## Before running on iPhone

1. Select your Apple Development Team in Signing & Capabilities.
2. If needed, change the bundle identifier from `com.linjingqi.AirPressure`.
3. Connect your iPhone and trust the Mac if Xcode asks.
4. Make sure Bluetooth is enabled on the phone.

## Important note about this Mac

The project file is valid and the Swift sources pass SDK type-checking, but command-line `xcodebuild` could not perform a full app build because the current Xcode installation is missing the required iOS platform component/runtime. In Xcode, you can fix that from:

- `Xcode > Settings > Components`

Then install the iOS platform/runtime Xcode asks for.
