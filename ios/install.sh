#!/bin/sh
# Build iOSAIBoard and put it on the iPhone plugged into this Mac.
#   sh ~/iOSAIBoard/install.sh
cd "$(dirname "$0")" || exit 1
LOG="$PWD/install.log"
: > "$LOG"

echo "1/4 Preparing the project..."
if ! xcodegen >>"$LOG" 2>&1; then
  echo "STOPPED: could not prepare the project. Paste this to Claude:"; tail -15 "$LOG"; exit 1
fi

echo "2/4 Looking for your iPhone..."
xcrun devicectl list devices --json-output /tmp/iosaiboard-devices.json >>"$LOG" 2>&1
UDID=$(python3 - <<'PY'
import json
try:
    devices = json.load(open("/tmp/iosaiboard-devices.json"))["result"]["devices"]
except Exception:
    devices = []
phones = [d for d in devices if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
# Prefer a phone that is connected right now.
phones.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if phones:
    print(phones[0]["hardwareProperties"].get("udid", ""))
PY
)
if [ -z "$UDID" ]; then
  echo "STOPPED: this Mac does not see an iPhone."
  echo "Plug the phone in with a cable, unlock it, tap Trust if it asks, then run this again."
  echo "Here is what the Mac sees. Paste it to Claude if it still fails:"
  xcrun devicectl list devices 2>&1 | tail -8
  exit 1
fi
echo "    Found it."

echo "3/4 Building the app (a few minutes the first time)..."
if ! xcodebuild -project iOSAIBoard.xcodeproj -scheme iOSAIBoard -configuration Debug \
     -destination "id=$UDID" -derivedDataPath build \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration build >>"$LOG" 2>&1; then
  echo "STOPPED: the build failed. Paste everything below to Claude:"
  grep -E "error:|error :|No profiles|requires a development team|Signing|provisioning" "$LOG" | sort -u | head -30
  echo "--- last lines ---"; tail -12 "$LOG"
  exit 1
fi

echo "4/4 Installing on the phone (keep it unlocked)..."
if ! xcrun devicectl device install app --device "$UDID" build/Build/Products/Debug-iphoneos/iOSAIBoard.app >>"$LOG" 2>&1; then
  echo "STOPPED: could not install. Paste this to Claude:"; tail -15 "$LOG"; exit 1
fi
xcrun devicectl device process launch --device "$UDID" com.kmages.iosaiboard >>"$LOG" 2>&1

echo
echo "DONE. iOSAIBoard is on your iPhone."
echo "Next, on the phone: Settings > General > Keyboard > Keyboards > Add New Keyboard > iOSAIBoard,"
echo "then tap iOSAIBoard in that list and turn on Allow Full Access."
