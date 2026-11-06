"""
Publish an incrementing number over BLE from a Linux laptop (BlueZ peripheral).

Setup (Debian/Ubuntu):
  sudo apt install bluez
  sudo systemctl enable --now bluetooth
  bluetoothctl power on
  pip install bless

Run:
  python3 counter_ble_linux.py        # try without sudo first
  sudo python3 counter_ble_linux.py   # if you get a D-Bus permission error

Read it from a phone with nRF Connect / LightBlue: scan for "PyCounter",
connect, open the service, enable notifications on the characteristic.
The value is a 4-byte little-endian unsigned integer.
"""
import asyncio
import logging

from bless import (
    BlessGATTCharacteristic,
    BlessServer,
    GATTAttributePermissions,
    GATTCharacteristicProperties,
)

logging.basicConfig(level=logging.INFO)

DEVICE_NAME = "FitnessTrackerBLE"
SERVICE_UUID = "A07498CA-AD5B-474E-940D-16F1FBE7E8CD"
CHAR_UUID = "51FF12BB-3ED8-46E5-B4F9-D64E2FEC021B"
INTERVAL_S = 1.0


def on_read(characteristic: BlessGATTCharacteristic, **kwargs) -> bytearray:
    # Called when a client does an explicit read.
    return characteristic.value


async def main():
    loop = asyncio.get_running_loop()
    server = BlessServer(name=DEVICE_NAME, loop=loop)
    server.read_request_func = on_read

    await server.add_new_service(SERVICE_UUID)
    await server.add_new_characteristic(
        SERVICE_UUID,
        CHAR_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
        bytearray(4),
        GATTAttributePermissions.readable,
    )

    await server.start()
    logging.info("Advertising as '%s'. Ctrl+C to stop.", DEVICE_NAME)

    counter = 0
    try:
        while True:
            counter += 1
            char = server.get_characteristic(CHAR_UUID)
            char.value = bytearray(counter.to_bytes(4, "little"))
            server.update_value(SERVICE_UUID, CHAR_UUID)  # notifies subscribers
            logging.info("Published %d", counter)
            await asyncio.sleep(INTERVAL_S)
    finally:
        await server.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
