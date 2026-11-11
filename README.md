# DataDial

Analog Connect IQ watch face for the Garmin fēnix 9 Pro 51mm (466×466 AMOLED).

![DataDial in the Connect IQ simulator](docs/screenshot.png)

- Hour and minute hands; a red seconds hand while the watch is awake (after a wrist raise).
- Eight fields around the dial, clockwise from 12: date, heart rate, battery, steps,
  floors, calories, elevation, temperature.
- Elevation and temperature follow the watch's unit settings.
- Burn-in-safe sleep mode: if always-on is enabled, only thin gray hands are drawn,
  shifted a few pixels each minute.

All geometry and text sizes are relative to the screen radius, so other round
displays only need to be added to `manifest.xml`.

## Layout

| File | Purpose |
|---|---|
| `manifest.xml` | App id, target products, `SensorHistory` permission |
| `source/DataDialApp.mc` | Application entry point |
| `source/DataDialView.mc` | Drawing: ticks, fields, hands, sleep mode |
| `source/Metrics.mc` | Reads and formats each data value (`--` when unavailable) |

## Build

Requires Connect IQ SDK 9.3.0 and the developer key at `../developer_key`.

```sh
./build.sh          # build bin/DataDial.prg
./build.sh run      # build, start the simulator, load the face
```

`build.sh` uses the Java runtime bundled with STM32CubeMX unless `JAVA_HOME` is set.

## Install on the watch

1. Build (above). The `.prg` is built for the watch, not only the simulator.
2. Connect the watch over USB. It shows up in File Explorer as a portable device.
3. Copy `bin/DataDial.prg` into `GARMIN\Apps` on the watch.
4. Unplug, then pick **DataDial** under Watch Face on the watch.

## Notes

- Temperature comes from the watch's own sensor, so it reads high while worn.
- Heart rate is the live reading when available, otherwise the latest history sample.
