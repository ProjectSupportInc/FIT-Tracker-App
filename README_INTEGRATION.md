# FitTracker integration

The workout path is now connected to the ESP32 firmware at
`/home/kavindu/fitness-tracker/fit-tracker`. The previous overlay instructions have
been replaced by the current [BLE workout setup guide](docs/BLE_WORKOUT_SETUP.md).

Normal launches use real BLE and locally persisted results. The ESP32 must be
flashed with the updated sensor runtime; the older BLE_TEST firmware generates
artificial counts despite sharing the same service UUID. Google authentication
and backend workout prescriptions remain demo/local features.

Read the setup guide for wiring, permissions, calibration, recovery, the firmware
file changes, and the distinction between automated checks and hardware validation.
