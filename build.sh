#!/usr/bin/env bash
# Build DataDial and optionally run it in the Connect IQ simulator.
#
# Usage: ./build.sh [run|test|export] [device]
#   run     also launch the simulator and load the app
#   test    like run, but with fixed stat values for layout checks
#           (monkey.test.jungle, source/TestValues.mc); never copy that
#           build to the watch
#   export  build the store package bin/DataDial.iq for every product in
#           manifest.xml (release build, no test values)
#   device  product id (default: fenix9pro51mm)
#
# Uses the Temurin JRE bundled with STM32CubeMX unless JAVA_HOME is set.
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${2:-fenix9pro51mm}"
JUNGLE=monkey.jungle
OUT=bin/DataDial.prg
if [[ "${1:-}" == "test" ]]; then
    JUNGLE=monkey.test.jungle
    OUT=bin/DataDial-test.prg
fi
SDK="$(cat "$APPDATA/Garmin/ConnectIQ/current-sdk.cfg" | tr -d '\r\n' | sed 's#\\#/#g')"
JAVA_BIN="${JAVA_HOME:-/c/Program Files/STMicroelectronics/STM32Cube/STM32CubeMX/jre}/bin"
export PATH="$JAVA_BIN:$PATH"

mkdir -p bin

if [[ "${1:-}" == "export" ]]; then
    java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true         -jar "$SDK/bin/monkeybrains.jar"         -e -r -o bin/DataDial.iq -f monkey.jungle -y ../developer_key -w -l 2
    exit 0
fi

java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true \
    -jar "$SDK/bin/monkeybrains.jar" \
    -o "$OUT" -f "$JUNGLE" -y ../developer_key \
    -d "$DEVICE" -w -l 2

if [[ "${1:-}" == "run" || "${1:-}" == "test" ]]; then
    if ! tasklist //FI "IMAGENAME eq simulator.exe" | grep -qi simulator.exe; then
        "$SDK/bin/simulator.exe" &
        sleep 5
    fi
    "$SDK/bin/monkeydo.bat" "$OUT" "$DEVICE"
fi
