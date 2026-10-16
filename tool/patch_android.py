"""Дописывает в сгенерированный Android-проект разрешения Bluetooth и название приложения."""
import pathlib
import re

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text(encoding="utf-8")

perms = [
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.WAKE_LOCK" />',
    '<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />',
]

if "BLUETOOTH_SCAN" not in text:
    if 'xmlns:tools=' not in text:
        text = text.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
    m = re.search(r"<manifest[^>]*>", text)
    insert = "\n    " + "\n    ".join(perms) + "\n"
    text = text[: m.end()] + insert + text[m.end():]

text = re.sub(r'android:label="[^"]*"', 'android:label="M365 Dashboard"', text, count=1)
manifest.write_text(text, encoding="utf-8")
print("AndroidManifest patched")
