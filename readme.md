This simplified manifest gives you a fresh start. It follows the "Functional Separation" model: the Backend is the brain, the Student app is the scanner (Joiner), and the Teacher app is the remote control (Host).

1. Backend: The Lean API (Node.js + Supabase)
Goal: Remove all experimental scripts and local DB bloat. Focus on REST and Realtime.

attendance-backend/
├── src/
│   ├── controllers/      # Logic for sessions and attendance
│   │   ├── attendance.controller.js
│   │   ├── session.controller.js
│   │   └── rssi.controller.js
│   ├── routes/           # Clean API endpoints
│   ├── services/         # The "Secret Sauce" math
│   │   ├── correlation.service.js
│   │   └── anomaly.service.js
│   ├── utils/            # Shared utilities
│   │   ├── supabase.js   # Single source for DB connection
│   │   └── security.js   # HMAC and Device signature logic
│   └── server.js         # Express setup
├── supabase/
│   └── migrations/       # One clean schema file
├── .env                  # Environment variables (No hardcoded demo modes)
└── package.json


This simplified manifest gives you a fresh start. It follows the "Functional Separation" model: the Backend is the brain, the Student app is the scanner (Joiner), and the Teacher app is the remote control (Host).

1. Backend: The Lean API (Node.js + Supabase)
Goal: Remove all experimental scripts and local DB bloat. Focus on REST and Realtime.

Plaintext
attendance-backend/
├── src/
│   ├── controllers/      # Logic for sessions and attendance
│   │   ├── attendance.controller.js
│   │   ├── session.controller.js
│   │   └── rssi.controller.js
│   ├── routes/           # Clean API endpoints
│   ├── services/         # The "Secret Sauce" math
│   │   ├── correlation.service.js
│   │   └── anomaly.service.js
│   ├── utils/            # Shared utilities
│   │   ├── supabase.js   # Single source for DB connection
│   │   └── security.js   # HMAC and Device signature logic
│   └── server.js         # Express setup
├── supabase/
│   └── migrations/       # One clean schema file
├── .env                  # Environment variables (No hardcoded demo modes)
└── package.json

2. Student App: The "Joiner" (Flutter)
Goal: Complete rewrite. Move from "Feature-Deep" folders to "Functional-Flat" folders.

attendance_app/
├── lib/
│   ├── core/             # API constants, Theme, Helpers
│   ├── services/         # Functional logic
│   │   ├── beacon_service.dart     # Only handles scanning
│   │   ├── attendance_service.dart # Check-in & RSSI streaming
│   │   └── biometric_service.dart  # Final fingerprint lock
│   ├── providers/        # State management (Keep to 2-3 max)
│   │   ├── attendance_provider.dart
│   │   └── auth_provider.dart
│   ├── models/           # Simplified JSON serializable classes
│   ├── ui/
│   │   ├── screens/      # Login, Home (Scan), History
│   │   └── widgets/      # Reusable UI (StatusCard, Timer)
│   └── main.dart
└── pubspec.yaml


3. Teacher App: The "Host" (New Flutter App)
Goal: A dedicated tool for teachers to activate classrooms and monitor joins.


attendance_host_app/
├── lib/
│   ├── services/
│   │   ├── session_service.dart    # Starts/Ends sessions
│   │   └── esp32_control.dart      # Local BLE command to activate ESP32
│   ├── providers/
│   │   └── host_state_provider.dart # Tracks active session & student count
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── session_activator.dart # Selection of Class/Room
│   │   │   └── live_monitor.dart     # Realtime list of students
│   │   └── widgets/
│   └── main.dart
└── pubspec.yaml


esp32
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEBeacon.h>

#define IBEACON_UUID "1a7f44b2-e25c-44a8-a634-3d0b98065d21" 
#define IBEACON_MAJOR 1
#define IBEACON_MINOR 101

BLEAdvertising *pAdvertising;

void setup() {
  Serial.begin(115200);
  Serial.println("Starting BLE Beacon...");

  BLEDevice::init("ESP32_Beacon");

  pAdvertising = BLEDevice::getAdvertising();

  BLEBeacon beacon;
  beacon.setManufacturerId(0x4C00); // Apple
  beacon.setProximityUUID(BLEUUID(IBEACON_UUID));
  beacon.setMajor(IBEACON_MAJOR);
  beacon.setMinor(IBEACON_MINOR);
  beacon.setSignalPower(0xc5);

  BLEAdvertisementData advertisementData;
  advertisementData.setFlags(0x06);
  advertisementData.setManufacturerData(beacon.getData());

  pAdvertising->setAdvertisementData(advertisementData);
  pAdvertising->setScanResponse(false);
  pAdvertising->setAdvertisementType(ADV_TYPE_NONCONN_IND);

  pAdvertising->start();
  Serial.println("Beacon broadcasting.");
}

void loop() {
  delay(2000);
}