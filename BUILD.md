# vis0g3 — Build & Install Guide

Developer: @ZeOne  
Target: iPhone 8 · iOS 16.7.x · Dopamine rootless · A11

---

## Prerequisites

Install Theos on macOS or Linux (once):
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

Ensure you have:
- `ldid` in PATH (ships with Theos install)
- iOS 16 SDK (via Xcode or the SDK package Theos downloads)
- SSH access to the iPhone 8 (`THEOS_DEVICE_IP` / `THEOS_DEVICE_PORT`)

Put device details in `~/.config/theos/rc.mk` (NOT in the project Makefile):
```makefile
THEOS_DEVICE_IP   = 192.168.x.x
THEOS_DEVICE_PORT = 22
```

---

## Build

```bash
cd vis0g3

# Development build + install
make clean package THEOS_PACKAGE_SCHEME=rootless
make install THEOS_PACKAGE_SCHEME=rootless

# Or in one step
make do THEOS_PACKAGE_SCHEME=rootless
```

The SpringBoard process restarts automatically after install.

### Release build (for distribution)
```bash
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

Output `.deb` is in `packages/`.

---

## Verify package contents

```bash
dpkg-deb -c packages/com.zeone.vis0g3_1.0.0_iphoneos-arm64.deb
```

Expected rootless paths:
```
./var/jb/Library/MobileSubstrate/DynamicLibraries/vis0g3.dylib
./var/jb/Library/MobileSubstrate/DynamicLibraries/vis0g3.plist
./var/jb/Library/PreferenceBundles/vis0g3Prefs.bundle/
./var/jb/Library/PreferenceLoader/Preferences/vis0g3Prefs.plist
```

If you see `./Library/` at the root the rootless scheme was not applied — clean and rebuild.

---

## Manual install

```bash
scp packages/com.zeone.vis0g3_1.0.0_iphoneos-arm64.deb mobile@DEVICE_IP:/var/mobile/
ssh mobile@DEVICE_IP
sudo dpkg -i /var/mobile/com.zeone.vis0g3_1.0.0_iphoneos-arm64.deb
killall SpringBoard
```

---

## First-time setup on device

1. Open **Settings → vis0g3**.
2. Enable the master switch.
3. Tap **Manage Faces → Add Face…**.
4. Enter a name, tap **Continue**.
5. Follow the 5-step enrollment:
   - Look straight
   - Turn left
   - Turn right
   - Tilt up
   - Tilt down
6. Tap **Capture** for each step.
7. Lock the device and verify recognition.

---

## Lock Screen hook compatibility notes

`SBUIBiometricResource` and `SBLockScreenManager` private APIs are confirmed
present on iOS 16. If SpringBoard crashes on injection:

1. Read `/var/mobile/Library/Logs/CrashReporter/SpringBoard*.ips` on device.
2. Check that the crashing selector matches what's in `Hooks/LockScreen.xm`.
3. Use FLEX on device to browse live SpringBoard class hierarchy and find the
   actual selector name, then update the hook.

Safe mode (hold volume-down during SpringBoard restart) always restores normal
behavior.

---

## Recognition tuning

- If false rejections are frequent: lower the threshold slider in Settings (try 0.75–0.78).
- If false acceptances occur: raise the threshold (try 0.88–0.92) and enable liveness.
- Re-enroll with more varied lighting/angles for best results.
- Enroll in the lighting conditions you typically unlock in (dark room = enroll in dark room).

---

## Testing checklist

### Lock Screen
- [ ] Successful unlock — enrolled face
- [ ] Failed unlock — different face / covered face
- [ ] Liveness: each toggle independently
- [ ] Liveness: combined toggles
- [ ] Passcode fallback button
- [ ] Screen flash in dark environment
- [ ] Respring persistence (prefs survive)

### App authentication
- [ ] App with `evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics`
- [ ] Password AutoFill in Safari
- [ ] Free App Store download

### Liveness spoofing resistance
- [ ] Static photo in front of camera — should fail liveness
- [ ] Photo moved around — should fail yaw/pitch threshold checks

### Lifecycle
- [ ] Camera released on dismissal (no persistent camera indicator in status bar)
- [ ] Incoming call during auth — camera stops, auth cancels gracefully
- [ ] Respring — no leftover state
