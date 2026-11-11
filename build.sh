#!/usr/bin/env bash
# Build DataDial and optionally run it in the Connect IQ simulator.
#
# Usage: ./build.sh [run] [device]
#   run     also launch the simulator and load the app
#   device  product id (default: fenix9pro51mm)
#
# Uses the Temurin JRE bundled with STM32CubeMX unless JAVA_HOME is set.
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${2:-fenix9pro51mm}"
SDK="$(cat "$APPDATA/Garmin/ConnectIQ/current-sdk.cfg" | tr -d '\r\n' | sed 's#\\#/#g')"
JAVA_BIN="${JAVA_HOME:-/c/Program Files/STMicroelectronics/STM32Cube/STM32CubeMX/jre}/bin"
export PATH="$JAVA_BIN:$PATH"

mkdir -p bin
java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true \
    -jar "$SDK/bin/monkeybrains.jar" \
    -o bin/DataDial.prg -f monkey.jungle -y ../developer_key \
    -d "$DEVICE" -w -l 2

if [[ "${1:-}" == "run" ]]; then
    if ! tasklist //FI "IMAGENAME eq simulator.exe" | grep -qi simulator.exe; then
        "$SDK/bin/simulator.exe" &
        sleep 5
    fi
    "$SDK/bin/monkeydo.bat" bin/DataDial.prg "$DEVICE"
fi
