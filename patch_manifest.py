#!/usr/bin/env python3
"""Adds the Bluetooth permissions to android/app/src/main/AndroidManifest.xml.
Run from inside the Flutter project folder:  python3 patch_manifest.py
Safe to run twice."""
import pathlib
import sys

path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if not path.exists():
    sys.exit("Run this inside your Flutter project (android/ folder not found).")

text = path.read_text()
if "BLUETOOTH_SCAN" in text:
    print("Permissions already present - nothing to do.")
    sys.exit(0)

block = """    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />

"""
idx = text.index("<application")
# insert at the start of the line that holds <application
line_start = text.rfind("\n", 0, idx) + 1
path.write_text(text[:line_start] + block + text[line_start:])
print("Done: Bluetooth permissions added.")
