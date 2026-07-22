#!/bin/zsh
set -euo pipefail
setopt null_glob

ROOT="/Users/kenshin/Desktop/BulletDodge"
PROJECT="$ROOT/BulletDodge/BulletDodge.xcodeproj"
DERIVED="$ROOT/BulletDodge/DerivedData"
BUNDLE_ID="com.kenshin.BulletDodge"
SIMULATOR_NAME="${1:-iPhone 17 Pro}"
OUTPUT_DIR="$ROOT/auto-wall-captures"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png "$OUTPUT_DIR"/auto-wall.log 2>/dev/null || true

DEVICE_ID="$(xcrun simctl list devices available | sed -n "s/.*$SIMULATOR_NAME (\\([^)]*\\)) (.*/\\1/p" | head -n 1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "Simulator not found: $SIMULATOR_NAME" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild \
  -project "$PROJECT" \
  -scheme BulletDodge \
  -sdk iphonesimulator \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -quiet build

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/BulletDodge.app"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
SIMCTL_CHILD_BULLETDODGE_AUTO_START=1 \
SIMCTL_CHILD_BULLETDODGE_AUTO_WALL_TEST=1 \
SIMCTL_CHILD_BULLETDODGE_AUTO_WALL_CAPTURE=1 \
SIMCTL_CHILD_BULLETDODGE_HIDE_HUD=1 \
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

sleep 30

DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
DOCS_DIR="$DATA_CONTAINER/Documents"
LOG_PATH="$DOCS_DIR/auto-wall.log"

CAPTURED=0
for _ in {1..80}; do
  if [[ -f "$LOG_PATH" ]]; then
    cp "$LOG_PATH" "$OUTPUT_DIR"/auto-wall.log
    while IFS= read -r line; do
      if [[ "$line" == CAPTURE\ saved=* ]]; then
        FILE_NAME="${line#CAPTURE saved=}"
        INDEX="${FILE_NAME%%_*}"
        if [[ "$INDEX" -gt "$CAPTURED" ]]; then
          xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/$FILE_NAME" >/dev/null
          CAPTURED="$INDEX"
        fi
      fi
    done < "$LOG_PATH"
  fi

  if [[ "$CAPTURED" -ge 9 ]]; then
    break
  fi
  sleep 0.5
done

if [[ -f "$LOG_PATH" ]]; then
  cp "$LOG_PATH" "$OUTPUT_DIR"/auto-wall.log
fi

echo "Saved captures to $OUTPUT_DIR"
