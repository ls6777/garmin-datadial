//! @file DataDialView.mc
//! Analog watch face view: a dot dial, eight data fields in wedge-shaped
//! sections, skeleton hour/minute hands, and a seconds hand while the watch
//! is awake. All geometry is derived from the screen size so other round
//! displays work.
//!
//! Drawing is cached in two off-screen images: the parts that never change
//! are drawn once, and the stat values are redrawn only when one changes.
//! Each frame copies the cached image and draws the hands on top.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! The DataDial watch face.
class DataDialView extends WatchUi.WatchFace {

    // Colors.
    private const COLOR_BG = Graphics.COLOR_BLACK;
    private const COLOR_WHITE = 0xFFFFFF;
    private const COLOR_RED = 0xFF3B30;
    private const COLOR_MINUTE_DOT = 0xB0B0B0;
    //! Defaults for the user color settings (see resources/settings).
    private const DEFAULT_ACCENT = 0x2EA3F2;
    private const DEFAULT_HEART = 0xFF5A5A;
    private const COLOR_CHARGING = 0x3DDC57;
    //! Value colour once a stat's daily goal is met.
    private const COLOR_GOAL = 0x3DDC57;
    //! Temperature value and symbol colour when it is cold.
    private const COLOR_COLD = 0x4FC3F7;
    //! Below this temperature (40 °F, in Celsius) the cold styling shows.
    private const COLD_BELOW_C = 4.44;
    //! Above this temperature (90 °F, in Celsius) the hot styling shows.
    private const HOT_ABOVE_C = 32.22;
    //! Temperature states.
    private const TEMP_NORMAL = 0;
    private const TEMP_COLD = 1;
    private const TEMP_HOT = 2;
    //! Unfilled part of a goal gauge.
    private const COLOR_GAUGE_TRACK = 0x333333;

    //! Goal gauges: radius as a fraction of the screen radius, pen width,
    //! and the gap in degrees left at each end of a cell.
    private const GAUGE_RADIUS = 0.855;
    private const GAUGE_PEN = 6;
    private const GAUGE_MARGIN = 5;
    //! Gauge fill colours, and the progress (percent of goal) at which the
    //! fill turns yellow and then green.
    private const GAUGE_RED = 0xFF3B30;
    private const GAUGE_YELLOW = 0xFFD60A;
    private const GAUGE_YELLOW_FROM = 30;
    private const GAUGE_GREEN_FROM = 90;
    //! How far the steps value is moved left, as a fraction of the screen
    //! radius, to leave room for its gauge.
    private const STEPS_VALUE_SHIFT = 0.045;
    //! Dimmed colors used by the always-on sleep view.
    //! Chrome hands: flat colors for the lit and shaded sides, used if
    //! the chrome textures can't be built (see buildChrome).
    private const COLOR_CHROME_LIGHT = 0xE9ECF0;
    private const COLOR_CHROME_DARK = 0x8C939B;
    //! Plain silver for the hub and the thin stems: too small for the
    //! texture to show, and much quicker to fill.
    private const COLOR_STEEL = 0xD4D8DD;
    //! Chrome texture: tile size in pixels, the brightness of the shaded
    //! side, and the reflection pattern as brightness levels (0-255) at
    //! positions along it (0-1).
    private const CHROME_SIZE = 128;
    private const CHROME_SHADE = 0.84;
    private const CHROME_STOPS = [0.0, 0.15, 0.32, 0.42, 0.52, 0.70, 0.85, 1.0] as Array<Float>;
    private const CHROME_LEVELS = [255, 240, 214, 196, 220, 252, 232, 255] as Array<Number>;
    //! Digital time: font size and the vertical offsets from the center of
    //! the time and of the seconds below it, as fractions of the radius.
    //! In digital mode the divider lines start further out
    //! (DIGITAL_LINE_START) to make room.
    private const TIME_SIZE = 0.32;
    private const TIME_Y = -0.05;
    private const SECONDS_Y = 0.18;
    private const SECONDS_SIZE = 0.19;
    private const DIGITAL_LINE_START = 0.40;
    private const COLOR_SLEEP = 0x9A9A9A;
    private const COLOR_SLEEP_MINOR = 0x5A5A5A;

    //! Field slots, clockwise from 12 o'clock at 45-degree steps.
    private const SLOT_DATE = 0;
    private const SLOT_HEART = 1;
    private const SLOT_BATTERY = 2;
    private const SLOT_STEPS = 3;
    private const SLOT_CALORIES = 4;
    private const SLOT_FLOORS = 5;
    private const SLOT_ELEVATION = 6;
    private const SLOT_TEMPERATURE = 7;
    private const SLOT_COUNT = 8;

    //! Battery level (percent) below which the battery icon and value turn red.
    private const BATTERY_LOW = 20;

    //! How often the hands move: the minute hand every MINUTE_HAND_STEP
    //! seconds, the hour hand every HOUR_HAND_STEP minutes.
    private const MINUTE_HAND_STEP = 10;
    private const HOUR_HAND_STEP = 10;

    //! Cosines and sines of 0, 22.5, 45, 67.5 and 90 degrees: the points
    //! of each quarter circle in the rounded ends of the hand outlines.
    private const ARC_COS = [1.0, 0.9239, 0.7071, 0.3827, 0.0] as Array<Float>;
    private const ARC_SIN = [0.0, 0.3827, 0.7071, 0.9239, 1.0] as Array<Float>;

    //! Seconds between re-reads while awake. Everything is also re-read on
    //! every wake-up. Heart rate is read every update, battery once a
    //! minute, and the date when the day changes.
    private const STEPS_PERIOD = 3;
    private const SLOW_PERIOD = 10;

    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _radius as Number = 0;
    private var _labelFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var _valueFont as Graphics.FontType = Graphics.FONT_TINY;

    //! Value text size per slot, as a fraction of the screen radius. Short
    //! stats get larger text to fill their cells; long ones (steps,
    //! elevation, the two-line battery cell) keep the base size.
    private const VALUE_SIZES = [
        0.165, // date
        0.25,  // heart rate
        0.165, // battery (percentage and estimate)
        0.165, // steps
        0.21,  // calories
        0.25,  // floors
        0.165, // elevation
        0.25   // temperature
    ] as Array<Float>;
    //! Value font per slot, built from VALUE_SIZES.
    private var _slotFonts as Array<Graphics.FontType> = new Array<Graphics.FontType>[8];

    //! Icon per slot; null for slots drawn in code (date text, battery gauge).
    private var _icons as Array<BitmapResource?> = new Array<BitmapResource?>[8];
    private var _iconSize as Number = 0;

    //! Colors of the dial, hands and hub: full brightness while awake,
    //! dimmed in the always-on sleep view.
    private var _ink as Number = COLOR_WHITE;
    private var _inkMinor as Number = COLOR_MINUTE_DOT;

    //! User color settings: divider lines, stat icons and battery outline,
    //! and the heart rate icon.
    //! Clock style setting: true for the digital time in the middle
    //! instead of the hands.
    private var _digital as Boolean = false;
    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _secondsFont as Graphics.FontType = Graphics.FONT_TINY;
    //! Digital time: the text, the minute it shows (hour * 60 + minute), and
    //! whether the composite image needs it redrawn.
    private var _timeText as String = "";
    private var _timeMinute as Number = -1;
    private var _timeDirty as Boolean = false;
    //! Width of the time as drawn in the composite, so it can be erased.
    private var _timeWidth as Number = 0;
    private var _accentColor as Number = DEFAULT_ACCENT;
    private var _heartColor as Number = DEFAULT_HEART;

    private var _awake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    //! Display text per slot.
    private var _values as Array<String> = new Array<String>[8];
    private var _weekday as String = "";
    private var _batteryPercent as Number = 0;
    //! The watch's battery estimate ("12d" or "9h"), or "" if unavailable,
    //! shown under the battery percentage in the same font, and its width as
    //! currently drawn in the stats image.
    private var _batteryEstimate as String = "";
    private var _estimateWidth as Number = 0;
    private var _charging as Boolean = false;
    //! Bit per slot whose daily goal has been met (steps and floors).
    private var _goalsMet as Number = 0;
    //! TEMP_COLD below COLD_BELOW_C, TEMP_HOT above HOT_ABOVE_C, otherwise
    //! TEMP_NORMAL.
    private var _tempState as Number = TEMP_NORMAL;
    //! Goal progress per slot in whole percent, or -1 for no gauge.
    private var _progress as Array<Number> = [-1, -1, -1, -1, -1, -1, -1, -1] as Array<Number>;

    //! Set on wake-up so the next update re-reads every value.
    private var _refreshAll as Boolean = true;
    //! Times (epoch seconds) of the last steps read and the last read of the
    //! slow group (floors, calories, elevation, temperature).
    private var _stepsTime as Number = 0;
    private var _slowTime as Number = 0;
    //! Minute the battery was last read in.
    private var _batteryMinute as Number = -1;
    //! Start of the day (epoch seconds) the date field was last read for.
    private var _lastDay as Number = -1;
    //! Hour seen on the previous update, to notice midnight passing.
    private var _lastHour as Number = 0;
    //! True when the whole stats image must be redrawn.
    private var _dirtyAll as Boolean = true;
    //! Bit per slot whose value changed since the stats image was drawn.
    private var _dirtySlots as Number = 0;
    //! Hour and minute hand angles (radians, clockwise from 12 o'clock) as
    //! currently shown, and the step they were computed for.
    private var _hourAngle as Float = 0.0;
    private var _minuteAngle as Float = 0.0;
    private var _handStep as Number = -1;
    //! Cached hand outline polygons, and the hand step and center they
    //! were built for (see drawHands).
    private var _handShapes as Array<Array<Array<Point2D> > >?;
    private var _shapeStep as Number = -1;
    private var _shapeCx as Number = 0;
    private var _shapeCy as Number = 0;
    //! Chrome textures for the hands [lit side, shaded side], built on
    //! first use (see buildChrome).
    private var _chrome as Array<BitmapTexture>?;
    private var _chromeTried as Boolean = false;
    //! Width in pixels of each value as currently drawn in the stats image,
    //! so the old text can be erased when a value changes.
    private var _drawnWidth as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;

    //! Off-screen image of the parts that never change (dots, divider lines,
    //! icons). Drawn once.
    private var _staticLayer as Graphics.BufferedBitmapReference?;
    //! Off-screen image of the static layer plus the stat values. Updated
    //! only when a displayed value changes; copied to the screen every frame.
    private var _composite as Graphics.BufferedBitmapReference?;

    //! Constructor.
    public function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnInProtection = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        for (var i = 0; i < SLOT_COUNT; i++) {
            _values[i] = Metrics.NO_VALUE;
        }
        loadSettings();
    }

    //! Read the user settings and redraw the cached images with them.
    //! Called at startup and when the settings change on the phone.
    public function loadSettings() as Void {
        _accentColor = numberSetting("AccentColor", DEFAULT_ACCENT);
        _heartColor = numberSetting("HeartColor", DEFAULT_HEART);
        _digital = (numberSetting("ClockStyle", 0) == 1);
        _staticLayer = null;
        _dirtyAll = true;
    }

    //! Read a number setting (a color or a list choice).
    //! @param key Property id
    //! @param fallback Color to use if the property is missing or invalid
    //! @return Color as 0xRRGGBB
    private function numberSetting(key as String, fallback as Number) as Number {
        var value = Properties.getValue(key);
        return (value instanceof Number) ? value : fallback;
    }

    //! Compute layout and load fonts and icons.
    //! @param dc Device context
    public function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;
        _radius = (_cx < _cy) ? _cx : _cy;

        _labelFont = vectorFont(["BionicBold", "RobotoCondensedBold"], 0.12, Graphics.FONT_XTINY);
        _valueFont = vectorFont(["BionicBold", "RobotoCondensedBold"], 0.165, Graphics.FONT_TINY);
        _timeFont = vectorFont(["BionicBold", "RobotoCondensedBold"], TIME_SIZE, Graphics.FONT_NUMBER_MEDIUM);
        _secondsFont = vectorFont(["BionicBold", "RobotoCondensedBold"], SECONDS_SIZE, Graphics.FONT_TINY);
        for (var i = 0; i < SLOT_COUNT; i++) {
            _slotFonts[i] = (VALUE_SIZES[i] == 0.165) ? _valueFont
                    : vectorFont(["BionicBold", "RobotoCondensedBold"], VALUE_SIZES[i], Graphics.FONT_SMALL);
        }

        _icons[SLOT_HEART] = loadIcon($.Rez.Drawables.HeartIcon);
        _icons[SLOT_STEPS] = loadIcon($.Rez.Drawables.StepsIcon);
        _icons[SLOT_FLOORS] = loadIcon($.Rez.Drawables.FloorsIcon);
        _icons[SLOT_CALORIES] = loadIcon($.Rez.Drawables.CaloriesIcon);
        _icons[SLOT_ELEVATION] = loadIcon($.Rez.Drawables.ElevationIcon);
        _icons[SLOT_TEMPERATURE] = loadIcon($.Rez.Drawables.TemperatureIcon);
        _iconSize = (_icons[SLOT_HEART] as BitmapResource).getHeight();
    }

    //! Draw the whole face.
    //! @param dc Device context
    public function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var fixedTime = TestValues.clockTime();
        if (fixedTime != null) {
            clockTime.hour = fixedTime[0];
            clockTime.min = fixedTime[1];
            clockTime.sec = fixedTime[2];
        }

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (!_awake && _burnInProtection) {
            clearScreen(dc);
            drawLowPower(dc, clockTime);
            return;
        }

        refreshValues(clockTime);
        if (_digital) {
            // The time is part of the cached composite image; the seconds
            // change every frame, so they are drawn on top while awake.
            updateTime(clockTime);
            drawBackground(dc);
            if (_awake) {
                dc.setColor(COLOR_MINUTE_DOT, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, _cy + (_radius * SECONDS_Y).toNumber(), _secondsFont, clockTime.sec.format("%02d"),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            return;
        }
        updateHands(clockTime);
        drawBackground(dc);
        drawHands(dc);

        if (_awake) {
            var secondAngle = clockTime.sec / 60.0 * Math.PI * 2;
            var tip = polar(secondAngle, _radius * 0.92);
            var tail = polar(secondAngle + Math.PI, _radius * 0.30);
            dc.setPenWidth(2);
            dc.setColor(COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(tail[0], tail[1], tip[0], tip[1]);
            dc.setPenWidth(1);
        }
        drawCap(dc);
    }

    //! The watch woke up (wrist raise): show the seconds hand and re-read
    //! every value.
    public function onExitSleep() as Void {
        _awake = true;
        _refreshAll = true;
        WatchUi.requestUpdate();
    }

    //! The watch went to sleep: hide the seconds hand.
    public function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------- data

    //! Re-read the data fields on their schedules:
    //! - heart rate: every update (once a second while awake)
    //! - steps: every wake-up, then every STEPS_PERIOD seconds
    //! - floors, calories, elevation, temperature: every wake-up, then every
    //!   SLOW_PERIOD seconds
    //! - battery and its days-remaining estimate: once a minute, or every
    //!   update while charging
    //! - date: on wake-up and when midnight passes; redrawn only if the day
    //!   changed
    //! While asleep the face is updated at most once a minute, and each of
    //! those updates re-reads everything.
    //! @param clockTime Current clock time
    private function refreshValues(clockTime as System.ClockTime) as Void {
        var now = Time.now().value();
        var all = _refreshAll || !_awake;
        _refreshAll = false;

        var hr = Metrics.heartRateValue();
        setValue(SLOT_HEART, (hr != null) ? hr.format("%d") : Metrics.NO_VALUE);

        // Charging state is checked every update so the bolt appears at once.
        var charging = Metrics.charging();
        if (charging != _charging) {
            _charging = charging;
            _batteryMinute = -1;
            _dirtySlots |= (1 << SLOT_BATTERY);
        }

        if (all || now - _stepsTime >= STEPS_PERIOD) {
            _stepsTime = now;
            setValue(SLOT_STEPS, Metrics.steps());
            setGoal(SLOT_STEPS, Metrics.stepGoalMet());
            setProgress(SLOT_STEPS, Metrics.stepProgress());
        }

        if (all || now - _slowTime >= SLOW_PERIOD) {
            _slowTime = now;
            setValue(SLOT_FLOORS, Metrics.floors());
            setGoal(SLOT_FLOORS, Metrics.floorsGoalMet());
            setProgress(SLOT_FLOORS, Metrics.floorsProgress());
            setValue(SLOT_CALORIES, Metrics.calories());
            setValue(SLOT_ELEVATION, Metrics.elevation());
            setValue(SLOT_TEMPERATURE, Metrics.temperature());
            var celsius = Metrics.temperatureCelsius();
            var state = TEMP_NORMAL;
            if (celsius != null && celsius < COLD_BELOW_C) {
                state = TEMP_COLD;
            } else if (celsius != null && celsius > HOT_ABOVE_C) {
                state = TEMP_HOT;
            }
            var fixedState = TestValues.temperatureState();
            if (fixedState != null) {
                state = fixedState;
            }
            if (state != _tempState) {
                _tempState = state;
                _dirtySlots |= (1 << SLOT_TEMPERATURE);
            }
        }

        if (_charging || clockTime.min != _batteryMinute) {
            _batteryMinute = clockTime.min;
            var fixedPercent = TestValues.batteryPercent();
            _batteryPercent = (fixedPercent != null) ? fixedPercent : Metrics.batteryPercent();
            setValue(SLOT_BATTERY, _batteryPercent.format("%d") + "%");

            var fixedEstimate = TestValues.batteryEstimate();
            var estimate = (fixedEstimate != null) ? fixedEstimate : Metrics.batteryEstimate();
            if (estimate == null) {
                estimate = "";
            }
            if (!estimate.equals(_batteryEstimate)) {
                _batteryEstimate = estimate;
                _dirtySlots |= (1 << SLOT_BATTERY);
            }
        }

        // The day changes only at midnight: look at the date on wake-up (the
        // watch may have slept through midnight) and when the hour wraps to 0.
        var midnight = clockTime.hour < _lastHour;
        _lastHour = clockTime.hour;
        if (all || midnight) {
            var day = Time.today().value();
            if (day != _lastDay) {
                _lastDay = day;
                _weekday = Metrics.weekday();
                setValue(SLOT_DATE, Metrics.dayMonth());
                _dirtyAll = true;
            }
        }
    }

    //! Store whether a stat's daily goal is met, noting whether it changed.
    //! @param slot Field slot
    //! @param met Whether the goal is met
    private function setGoal(slot as Number, met as Boolean) as Void {
        var fixed = TestValues.goalMet(slot);
        if (fixed != null) {
            met = fixed;
        }
        var bit = 1 << slot;
        if (met != ((_goalsMet & bit) != 0)) {
            _goalsMet = met ? (_goalsMet | bit) : (_goalsMet & ~bit);
            _dirtySlots |= bit;
        }
    }

    //! Store a stat's goal progress, noting whether it changed by at least
    //! one percent.
    //! @param slot Field slot
    //! @param progress 0.0..1.0, or negative for no goal
    private function setProgress(slot as Number, progress as Float) as Void {
        var fixed = TestValues.progress(slot);
        if (fixed != null) {
            progress = fixed;
        }
        var percent = (progress < 0.0) ? -1 : (progress * 100).toNumber();
        if (percent != _progress[slot]) {
            _progress[slot] = percent;
            _dirtySlots |= (1 << slot);
        }
    }

    //! Store a field's display text, noting whether it changed. In the test
    //! build the text is replaced by a fixed value (see TestValues.mc).
    //! @param slot Field slot
    //! @param text New display text
    private function setValue(slot as Number, text as String) as Void {
        var fixed = TestValues.text(slot);
        if (fixed != null) {
            text = fixed;
        }
        if (!_values[slot].equals(text)) {
            _values[slot] = text;
            _dirtySlots |= (1 << slot);
        }
    }

    // ------------------------------------------------------ dial and stats

    //! Paint the dial and stats from cached images.
    //! The static layer (dots, divider lines, icons) is drawn once. The
    //! composite (static layer plus stat values) is copied to the screen
    //! every frame; when a value changes only that value's area is redrawn.
    //! If an image cannot be allocated, the missing part is drawn directly.
    //! @param dc Device context
    private function drawBackground(dc as Dc) as Void {
        var layer = (_staticLayer != null) ? _staticLayer.get() as BufferedBitmap? : null;
        if (layer == null) {
            _staticLayer = createLayer(dc);
            layer = (_staticLayer != null) ? _staticLayer.get() as BufferedBitmap? : null;
            if (layer != null) {
                var layerDc = layer.getDc();
                clearScreen(layerDc);
                drawDial(layerDc);
                drawFields(layerDc, true);
            }
            _dirtyAll = true;
        }
        if (layer == null) {
            clearScreen(dc);
            drawDial(dc);
            drawFields(dc, true);
            drawFields(dc, false);
            if (_digital) {
                drawTime(dc);
            }
            return;
        }

        var composite = (_composite != null) ? _composite.get() as BufferedBitmap? : null;
        if (composite == null) {
            _composite = createLayer(dc);
            composite = (_composite != null) ? _composite.get() as BufferedBitmap? : null;
            _dirtyAll = true;
        }
        if (composite == null) {
            dc.drawBitmap(0, 0, layer);
            drawFields(dc, false);
            if (_digital) {
                drawTime(dc);
            }
            return;
        }

        if (_dirtyAll || _dirtySlots != 0 || _timeDirty) {
            var compositeDc = composite.getDc();
            if (compositeDc has :setAntiAlias) {
                compositeDc.setAntiAlias(true);
            }
            if (_dirtyAll) {
                compositeDc.drawBitmap(0, 0, layer);
                drawFields(compositeDc, false);
                for (var i = 0; i < SLOT_COUNT; i++) {
                    _drawnWidth[i] = compositeDc.getTextWidthInPixels(_values[i], valueFont(i));
                }
                if (_digital) {
                    _timeWidth = drawTime(compositeDc);
                }
            } else {
                for (var i = 0; i < SLOT_COUNT; i++) {
                    if ((_dirtySlots & (1 << i)) != 0) {
                        redrawSlot(compositeDc, layer, i);
                    }
                }
                if (_timeDirty && _digital) {
                    redrawTime(compositeDc, layer);
                }
            }
            _dirtyAll = false;
            _dirtySlots = 0;
            _timeDirty = false;
        }

        // The composite covers the whole screen, so copy it without blending.
        if (dc has :setBlendMode) {
            dc.setBlendMode(Graphics.BLEND_MODE_NO_BLEND);
            dc.drawBitmap(0, 0, composite);
            dc.setBlendMode(Graphics.BLEND_MODE_DEFAULT);
        } else {
            dc.drawBitmap(0, 0, composite);
        }
    }

    //! Redraw one stat in the composite: restore the static layer under the
    //! value text (and under the battery gauge for the battery slot), then
    //! draw the stat's live parts again. Clipping limits the work to those
    //! small areas.
    //! @param dc Device context of the composite image
    //! @param layer The static layer
    //! @param slot Field slot to redraw
    private function redrawSlot(dc as Dc, layer as BufferedBitmap, slot as Number) as Void {
        var angle = slot / SLOT_COUNT.toFloat() * Math.PI * 2;
        var outer = valuePosition(slot);
        var font = valueFont(slot);
        var width = dc.getTextWidthInPixels(_values[slot], font);
        var clearWidth = ((width > _drawnWidth[slot]) ? width : _drawnWidth[slot]);
        var clearHeight = dc.getFontHeight(font);
        _drawnWidth[slot] = width;

        if (slot == SLOT_BATTERY) {
            // The percentage and estimate are stacked; clear both lines.
            var estimateWidth = dc.getTextWidthInPixels(_batteryEstimate, _valueFont);
            var widest = (estimateWidth > _estimateWidth) ? estimateWidth : _estimateWidth;
            clearWidth = (widest > clearWidth) ? widest : clearWidth;
            clearHeight += 2 * batteryLineOffset();
            _estimateWidth = estimateWidth;
        }
        clearWidth += 8;
        clearHeight += 6;

        dc.setClip(outer[0] - clearWidth / 2, outer[1] - clearHeight / 2, clearWidth, clearHeight);
        dc.drawBitmap(0, 0, layer);
        drawFieldLive(dc, slot);

        if (slot == SLOT_BATTERY) {
            // The gauge and charging bolt change with the value.
            var inner = polar(angle, _radius * 0.38);
            var half = (_iconSize * 0.6).toNumber() + 3;
            dc.setClip(inner[0] - half, inner[1] - half, 2 * half, 2 * half);
            dc.drawBitmap(0, 0, layer);
            drawFieldLive(dc, slot);
        }
        if (slot == SLOT_TEMPERATURE) {
            var flake = tempSymbolPosition();
            var half = tempSymbolRadius() + 4;
            dc.setClip(flake[0] - half, flake[1] - half, 2 * half, 2 * half);
            dc.drawBitmap(0, 0, layer);
            drawFieldLive(dc, slot);
        }
        if (_progress[slot] >= 0) {
            var box = gaugeBounds(slot);
            dc.setClip(box[0], box[1], box[2] - box[0], box[3] - box[1]);
            dc.drawBitmap(0, 0, layer);
            // The box can reach into the value text, so redraw all of the
            // stat's live parts, not just the gauge.
            drawFieldLive(dc, slot);
        }
        dc.clearClip();
    }


    //! Dial: a dot for every minute, larger at the hours and largest at the
    //! quarters.
    //! @param dc Device context
    private function drawDial(dc as Dc) as Void {
        for (var i = 0; i < 60; i++) {
            // Centered so the largest dots end 2 px inside the display edge.
            var p = polar(i / 60.0 * Math.PI * 2, (_radius - 7).toFloat());
            var size = (i % 15 == 0) ? 5 : ((i % 5 == 0) ? 4 : 2);
            dc.setColor((i % 5 == 0) ? _ink : _inkMinor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(p[0], p[1], size);
        }
    }

    //! Stat fields: the dial is split into eight sections by thin radial
    //! lines. Each section has a bold value toward the outside and a symbol
    //! toward the center.
    //! @param dc Device context
    //! @param fixed true to draw the parts that never change (divider lines
    //!        and icons); false to draw the live parts (values, weekday,
    //!        battery gauge)
    private function drawFields(dc as Dc, fixed as Boolean) as Void {
        for (var i = 0; i < SLOT_COUNT; i++) {
            if (fixed) {
                drawFieldFixed(dc, i);
            } else {
                drawFieldLive(dc, i);
            }
        }
    }

    //! Draw the parts of one field that never change: its divider line and
    //! bitmap icon.
    //! @param dc Device context
    //! @param slot Field slot
    private function drawFieldFixed(dc as Dc, slot as Number) as Void {
        var angle = slot / SLOT_COUNT.toFloat() * Math.PI * 2;
        radialLine(dc, angle + Math.PI / SLOT_COUNT, _digital ? DIGITAL_LINE_START : 0.30, 0.86, 2, _accentColor);
        var icon = _icons[slot];
        if (icon != null) {
            // The icons are white masks, tinted to the user's color.
            var inner = polar(angle, _radius * 0.38);
            var x = inner[0] - _iconSize / 2;
            var y = inner[1] - _iconSize / 2;
            if (dc has :drawBitmap2) {
                dc.drawBitmap2(x, y, icon, {
                    :tintColor => (slot == SLOT_HEART) ? _heartColor : _accentColor
                });
            } else {
                dc.drawBitmap(x, y, icon);
            }
        }
    }

    //! Draw the live parts of one field: its value, plus the battery gauge
    //! or the weekday for those slots.
    //! @param dc Device context
    //! @param slot Field slot
    private function drawFieldLive(dc as Dc, slot as Number) as Void {
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var angle = slot / SLOT_COUNT.toFloat() * Math.PI * 2;
        var low = false;

        if (slot == SLOT_BATTERY) {
            var inner = polar(angle, _radius * 0.38);
            low = _batteryPercent < BATTERY_LOW;
            drawBattery(dc, inner[0], inner[1] - _iconSize / 2, _iconSize, _batteryPercent,
                    low ? COLOR_RED : _accentColor);
            if (_charging) {
                drawBolt(dc, inner[0], inner[1], _iconSize);
            }
        } else if (slot == SLOT_DATE) {
            // The weekday sits directly under the date instead of at the icon radius.
            var day = polar(angle, _radius * 0.525);
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(day[0], day[1], _labelFont, _weekday, center);
        }

        drawGauge(dc, slot);
        if (slot == SLOT_TEMPERATURE && _tempState != TEMP_NORMAL) {
            var symbol = tempSymbolPosition();
            if (_tempState == TEMP_COLD) {
                drawSnowflake(dc, symbol[0], symbol[1]);
            } else {
                drawHeat(dc, symbol[0], symbol[1]);
            }
        }

        var outer = valuePosition(slot);
        var valueY = outer[1];

        if (slot == SLOT_BATTERY && _batteryEstimate.length() > 0) {
            // Percentage and estimate, same size, centered as a pair on the
            // cell's horizontal centerline.
            // The font's vertical centering sits glyphs about 1 px high,
            // so both lines move down 1 px to balance them on the centerline.
            var offset = batteryLineOffset();
            valueY += 1 - offset;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(outer[0], outer[1] + 1 + offset, _valueFont, _batteryEstimate, center);
        }

        var color = low ? COLOR_RED : (((_goalsMet & (1 << slot)) != 0) ? COLOR_GOAL : COLOR_WHITE);
        if (slot == SLOT_TEMPERATURE && _tempState == TEMP_COLD) {
            color = COLOR_COLD;
        } else if (slot == SLOT_TEMPERATURE && _tempState == TEMP_HOT) {
            color = COLOR_RED;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(outer[0], valueY, valueFont(slot), _values[slot], center);
    }

    //! Center of a stat's value text: on the cell's center line at 0.68 of
    //! the radius, with the steps value moved left to clear its gauge.
    //! @param slot Field slot
    //! @return [x, y]
    private function valuePosition(slot as Number) as [Number, Number] {
        var p = polar(slot / SLOT_COUNT.toFloat() * Math.PI * 2, _radius * 0.68);
        if (slot == SLOT_STEPS) {
            p[0] -= (_radius * STEPS_VALUE_SHIFT).toNumber();
        }
        return p;
    }

    //! Font for a stat's value (see VALUE_SIZES).
    //! @param slot Field slot
    //! @return The font
    private function valueFont(slot as Number) as Graphics.FontType {
        return _slotFonts[slot];
    }

    //! Distance from the battery cell's centerline to the center of each of
    //! its two lines (percentage above, estimate below).
    //! @return Offset in pixels
    private function batteryLineOffset() as Number {
        return (_radius * 0.115).toNumber();
    }


    //! Angles of a slot's goal gauge, in degrees counter-clockwise from
    //! 3 o'clock (as drawArc expects). The gauge spans the cell, less
    //! GAUGE_MARGIN at each end, and fills clockwise from its start.
    //! @param slot Field slot
    //! @return [start, end] angles
    private function gaugeAngles(slot as Number) as [Number, Number] {
        var center = 90 - slot * 45;
        var half = 180 / SLOT_COUNT - GAUGE_MARGIN;
        return [center + half, center - half];
    }

    //! Draw a slot's goal gauge: a dim track along the outer edge of the
    //! cell, filled from its lower end upward. The whole fill takes one
    //! colour from how far along it is: red below GAUGE_YELLOW_FROM percent of
    //! the goal, yellow below GAUGE_GREEN_FROM, green from there and once the
    //! goal is met. Draws nothing for a slot without a goal.
    //! @param dc Device context
    //! @param slot Field slot
    private function drawGauge(dc as Dc, slot as Number) as Void {
        var percent = _progress[slot];
        if (percent < 0) {
            return;
        }
        var ends = gaugeAngles(slot);
        // Start at the lower end: the one with the smaller sine (further down
        // the screen), and run toward the other end.
        var start = ends[0];
        var finish = ends[1];
        if (Math.sin(Math.toRadians(finish)) < Math.sin(Math.toRadians(start))) {
            start = ends[1];
            finish = ends[0];
        }
        var direction = (finish > start) ? Graphics.ARC_COUNTER_CLOCKWISE : Graphics.ARC_CLOCKWISE;
        var radius = _radius * GAUGE_RADIUS;
        var met = (_goalsMet & (1 << slot)) != 0;
        var progress = met ? 1.0 : percent / 100.0;

        dc.setPenWidth(GAUGE_PEN);
        if (progress < 1.0) {
            dc.setColor(COLOR_GAUGE_TRACK, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(_cx, _cy, radius, direction, start, finish);
        }
        if (progress > 0.01) {
            var color = (met || percent >= GAUGE_GREEN_FROM) ? COLOR_GOAL
                    : ((percent >= GAUGE_YELLOW_FROM) ? GAUGE_YELLOW : GAUGE_RED);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(_cx, _cy, radius, direction, start, start + (finish - start) * progress);
        }
        dc.setPenWidth(1);
    }

    //! Radius of the temperature symbol (snowflake or heat waves).
    //! @return Radius in pixels
    private function tempSymbolRadius() as Number {
        return (_radius * 0.05).toNumber();
    }

    //! Center of the temperature symbol: just above the temperature value.
    //! @return [x, y]
    private function tempSymbolPosition() as [Number, Number] {
        var value = valuePosition(SLOT_TEMPERATURE);
        var halfHeight = (Graphics.getFontHeight(valueFont(SLOT_TEMPERATURE)) * 0.36).toNumber();
        return [value[0], value[1] - halfHeight - tempSymbolRadius() - 4];
    }

    //! Draw a snowflake: six arms, each with a small V near its tip.
    //! @param dc Device context
    //! @param x Center x
    //! @param y Center y
    private function drawSnowflake(dc as Dc, x as Number, y as Number) as Void {
        var r = tempSymbolRadius();
        var branch = r * 0.4;
        dc.setColor(COLOR_COLD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var k = 0; k < 6; k++) {
            var a = k * Math.PI / 3;
            var sin = Math.sin(a);
            var cos = Math.cos(a);
            dc.drawLine(x, y, x + r * sin, y - r * cos);
            // V on the arm, 60% of the way out.
            var bx = x + r * 0.6 * sin;
            var by = y - r * 0.6 * cos;
            for (var side = -1; side <= 1; side += 2) {
                var b = a + side * Math.PI / 4;
                dc.drawLine(bx, by, bx + branch * Math.sin(b), by - branch * Math.cos(b));
            }
        }
        dc.setPenWidth(1);
    }

    //! Draw rising heat waves: three wavy vertical lines, in red.
    //! @param dc Device context
    //! @param x Center x
    //! @param y Center y
    private function drawHeat(dc as Dc, x as Number, y as Number) as Void {
        var r = tempSymbolRadius();
        var amplitude = r * 0.18;
        var steps = 12;
        dc.setColor(COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var w = -1; w <= 1; w++) {
            var x0 = x + w * r * 0.6;
            // One and a half waves from bottom to top; the middle line is
            // taller, like rising heat.
            var top = y - r * ((w == 0) ? 1.0 : 0.8);
            var bottom = y + r * ((w == 0) ? 1.0 : 0.8);
            var prevX = x0;
            var prevY = bottom;
            for (var k = 1; k <= steps; k++) {
                var t = k / steps.toFloat();
                var px = x0 + amplitude * Math.sin(t * 3 * Math.PI);
                var py = bottom + (top - bottom) * t;
                dc.drawLine(prevX, prevY, px, py);
                prevX = px;
                prevY = py;
            }
        }
        dc.setPenWidth(1);
    }

    //! Screen-aligned box around a slot's goal gauge, for partial redraws.
    //! @param slot Field slot
    //! @return [left, top, right, bottom]
    private function gaugeBounds(slot as Number) as [Number, Number, Number, Number] {
        var ends = gaugeAngles(slot);
        var inner = _radius * GAUGE_RADIUS - GAUGE_PEN;
        var outer = _radius * GAUGE_RADIUS + GAUGE_PEN;
        var box = [9999, 9999, -9999, -9999];
        // Sample every 5 degrees, always including both exact ends.
        for (var degrees = ends[1]; degrees < ends[0] + 5; degrees += 5) {
            if (degrees > ends[0]) {
                degrees = ends[0];
            }
            // Convert to this file's convention: radians clockwise from 12.
            var angle = Math.toRadians(90 - degrees).toFloat();
            var points = [polar(angle, inner), polar(angle, outer)];
            for (var k = 0; k < 2; k++) {
                var p = points[k];
                box[0] = (p[0] < box[0]) ? p[0] : box[0];
                box[1] = (p[1] < box[1]) ? p[1] : box[1];
                box[2] = (p[0] > box[2]) ? p[0] : box[2];
                box[3] = (p[1] > box[3]) ? p[1] : box[3];
            }
        }
        return [box[0] - 2, box[1] - 2, box[2] + 3, box[3] + 3];
    }

    //! Draw a horizontal battery gauge filled to the charge level.
    //! @param dc Device context
    //! @param cx Horizontal center of the icon
    //! @param top Top of the icon box
    //! @param size Icon box size (square), matching the bitmap icons
    //! @param percent Charge level, 0..100
    //! @param color Outline and fill color
    private function drawBattery(dc as Dc, cx as Number, top as Number, size as Number,
            percent as Number, color as Number) as Void {
        var pen = (size / 14 > 2) ? size / 14 : 2;
        var bodyW = (size * 0.80).toNumber();
        var bodyH = (size * 0.48).toNumber();
        var tipW = (size * 0.08).toNumber();
        var x = cx - (bodyW + tipW) / 2;
        var y = top + (size - bodyH) / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawRoundedRectangle(x, y, bodyW, bodyH, pen * 2);
        dc.setPenWidth(1);
        dc.fillRectangle(x + bodyW, y + bodyH / 3, tipW, bodyH / 3);

        var inset = pen + 2;
        var fillW = ((bodyW - 2 * inset) * percent) / 100;
        if (fillW > 0) {
            dc.fillRectangle(x + inset, y + inset, fillW, bodyH - 2 * inset);
        }
    }

    //! Draw a lightning bolt (the charging symbol) centered on a point.
    //! It is green with a dark outline so it reads over the battery gauge.
    //! @param dc Device context
    //! @param cx Horizontal center
    //! @param cy Vertical center
    //! @param size Icon box size; the bolt is slightly shorter than this
    private function drawBolt(dc as Dc, cx as Number, cy as Number, size as Number) as Void {
        // Bolt outline in units of its height, centered on the origin.
        var shape = [
            [0.16, -0.50], [-0.30, 0.08], [-0.03, 0.08],
            [-0.16, 0.50], [0.30, -0.08], [0.03, -0.08]
        ];
        var scales = [size * 1.15, size * 0.85];
        for (var pass = 0; pass < scales.size(); pass++) {
            var points = new Array<[Numeric, Numeric]>[shape.size()];
            for (var i = 0; i < shape.size(); i++) {
                points[i] = [cx + shape[i][0] * scales[pass], cy + shape[i][1] * scales[pass]];
            }
            dc.setColor((pass == 0) ? COLOR_BG : COLOR_CHARGING, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(points);
        }
    }

    // ---------------------------------------------------------- digital time

    //! Update the digital time text when the minute changes. Follows the
    //! watch's 12/24-hour setting; 12-hour time has no leading zero.
    //! @param clockTime Current clock time
    private function updateTime(clockTime as System.ClockTime) as Void {
        var minute = clockTime.hour * 60 + clockTime.min;
        if (minute == _timeMinute) {
            return;
        }
        _timeMinute = minute;
        var hour = clockTime.hour;
        var text;
        if (System.getDeviceSettings().is24Hour) {
            text = hour.format("%02d") + ":" + clockTime.min.format("%02d");
        } else {
            hour = hour % 12;
            text = ((hour == 0) ? 12 : hour).toString() + ":" + clockTime.min.format("%02d");
        }
        if (!text.equals(_timeText)) {
            _timeText = text;
            _timeDirty = true;
        }
    }

    //! Draw the digital time in the middle of the dial, a little above
    //! center to leave room for the seconds.
    //! @param dc Device context
    //! @return Width of the text in pixels
    private function drawTime(dc as Dc) as Number {
        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + (_radius * TIME_Y).toNumber(), _timeFont, _timeText,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        return dc.getTextWidthInPixels(_timeText, _timeFont);
    }

    //! Redraw the time in the composite: restore the static layer under the
    //! old and new text, then draw the new time. Nothing else is drawn in
    //! the middle of the dial.
    //! @param dc Device context of the composite image
    //! @param layer The static layer
    private function redrawTime(dc as Dc, layer as BufferedBitmap) as Void {
        var width = dc.getTextWidthInPixels(_timeText, _timeFont);
        var clearWidth = ((width > _timeWidth) ? width : _timeWidth) + 8;
        var clearHeight = dc.getFontHeight(_timeFont) + 4;
        var y = _cy + (_radius * TIME_Y).toNumber();
        dc.setClip(_cx - clearWidth / 2, y - clearHeight / 2, clearWidth, clearHeight);
        dc.drawBitmap(0, 0, layer);
        _timeWidth = drawTime(dc);
        dc.clearClip();
    }

    // --------------------------------------------------------------- hands

    //! Move the hour and minute hands in steps: the minute hand every
    //! MINUTE_HAND_STEP seconds and the hour hand every HOUR_HAND_STEP
    //! minutes. The hands are drawn straight to the screen each frame:
    //! profiling showed that drawing them into the cached image costs more
    //! than it saves.
    //! @param clockTime Current clock time
    private function updateHands(clockTime as System.ClockTime) as Void {
        var seconds = clockTime.sec - clockTime.sec % MINUTE_HAND_STEP;
        var step = (clockTime.hour * 60 + clockTime.min) * 60 + seconds;
        if (step == _handStep) {
            return;
        }
        _handStep = step;

        var hourMinutes = clockTime.min - clockTime.min % HOUR_HAND_STEP;
        _hourAngle = ((clockTime.hour % 12) * 60 + hourMinutes) / 720.0 * Math.PI * 2;
        _minuteAngle = (clockTime.min + seconds / 60.0) / 60.0 * Math.PI * 2;
    }

    //! Rebuild the hand outline shapes if a hand moved or the center
    //! shifted (always-on burn-in shift).
    private function updateHandShapes() as Void {
        if (_handShapes != null && _shapeStep == _handStep && _shapeCx == _cx && _shapeCy == _cy) {
            return;
        }
        _handShapes = [
            handShapes(_hourAngle, _radius * 0.52, 13, 0.24),
            handShapes(_minuteAngle, _radius * 0.86, 11, 0.30)
        ] as Array<Array<Array<Point2D> > >;
        _shapeStep = _handStep;
        _shapeCx = _cx;
        _shapeCy = _cy;
    }

    //! Draw the hour and minute hands at their current stepped angles.
    //! While awake they are bright steel (see buildChrome); in always-on
    //! mode they are flat and dim.
    //! @param dc Device context
    private function drawHands(dc as Dc) as Void {
        updateHandShapes();
        drawHand(dc, 0);
        drawHand(dc, 1);
    }

    //! Draw one hand: a thin stem from the center, then the hollow frame
    //! with a 1 px dark edge, bright on the side facing the light (upper
    //! left) and darker on the other, like a polished bevel.
    //! @param dc Device context
    //! @param index 0 for the hour hand, 1 for the minute hand
    private function drawHand(dc as Dc, index as Number) as Void {
        var chrome = (_ink == COLOR_WHITE);
        if (chrome && !_chromeTried && (dc has :setFill)) {
            buildChrome();
        }
        var angle = (index == 0) ? _hourAngle : _minuteAngle;
        var a = polar(angle, _radius * ((index == 0) ? 0.24 : 0.30));
        var hand = (_handShapes as Array<Array<Array<Point2D> > >)[index];
        var litFirst = (-Math.cos(angle) - Math.sin(angle)) > 0;

        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(_cx, _cy, a[0], a[1]);
        dc.fillPolygon(hand[0]);
        dc.fillPolygon(hand[1]);
        dc.setPenWidth(2);
        dc.setColor(chrome ? COLOR_STEEL : _ink, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx, _cy, a[0], a[1]);
        setChrome(dc, chrome, litFirst);
        dc.fillPolygon(hand[2]);
        setChrome(dc, chrome, !litFirst);
        dc.fillPolygon(hand[3]);
        dc.setPenWidth(1);
    }

    //! Set the fill and pen for one side of a hand.
    //! @param dc Device context
    //! @param chrome true for chrome, false for the flat always-on color
    //! @param lit true for the side facing the light
    private function setChrome(dc as Dc, chrome as Boolean, lit as Boolean) as Void {
        if (!chrome) {
            dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
            return;
        }
        var textures = _chrome;
        if (textures != null) {
            var texture = textures[lit ? 0 : 1];
            dc.setFill(texture);
            dc.setStroke(texture);
            return;
        }
        dc.setColor(lit ? COLOR_CHROME_LIGHT : COLOR_CHROME_DARK, Graphics.COLOR_TRANSPARENT);
    }

    //! Build the chrome textures for the hands: small images of soft
    //! diagonal bands of light and dark, like the reflections on polished
    //! metal. The texture is fixed to the screen, so the reflections slide
    //! along a hand as it turns. One image is for the side of a hand facing
    //! the light, a darker one for the other side. Built once; if images are
    //! not available the hands use two flat grays instead.
    private function buildChrome() as Void {
        _chromeTried = true;
        if (!(Graphics has :createBufferedBitmap) || !(Graphics has :BitmapTexture)) {
            return;
        }
        try {
            var textures = [] as Array<BitmapTexture>;
            var size = CHROME_SIZE;
            for (var side = 0; side < 2; side++) {
                var bitmap = Graphics.createBufferedBitmap({ :width => size, :height => size }).get() as BufferedBitmap;
                var bdc = bitmap.getDc();
                bdc.setPenWidth(1);
                // Each diagonal x + y = k gets one shade, repeating every
                // CHROME_SIZE pixels so the image tiles without seams.
                for (var k = 0; k < 2 * size - 1; k++) {
                    bdc.setColor(chromeColor((k % size) / size.toFloat(), (side == 0) ? 1.0 : CHROME_SHADE),
                            Graphics.COLOR_TRANSPARENT);
                    var x0 = (k < size) ? 0 : k - size + 1;
                    var x1 = (k < size) ? k : size - 1;
                    bdc.drawLine(x0, k - x0, x1, k - x1);
                    bdc.drawPoint(x1, k - x1);
                }
                textures.add(new Graphics.BitmapTexture({ :bitmap => bitmap }));
            }
            _chrome = textures;
        } catch (e) {
            _chrome = null;
        }
    }

    //! Shade of the chrome reflection pattern.
    //! @param t Position in the pattern, 0 to 1
    //! @param scale Brightness factor (1 for the lit side)
    //! @return Color (a cool, slightly blue gray)
    private function chromeColor(t as Float, scale as Float) as Number {
        var level = (CHROME_LEVELS[0] as Number).toFloat();
        for (var i = 1; i < CHROME_STOPS.size(); i++) {
            var stop = CHROME_STOPS[i] as Float;
            if (t <= stop) {
                var prev = CHROME_STOPS[i - 1] as Float;
                var f = (t - prev) / (stop - prev);
                f = f * f * (3 - 2 * f);
                var low = (CHROME_LEVELS[i - 1] as Number).toFloat();
                level = low + ((CHROME_LEVELS[i] as Number) - low) * f;
                break;
            }
        }
        level = level * scale;
        var r = (level * 0.95).toNumber();
        var g = (level * 0.975).toNumber();
        var b = level.toNumber();
        return (r << 16) | (g << 8) | b;
    }

    //! Outline shapes of a skeleton hand: a rounded bar on a thin stem
    //! with an open middle, so the fields show through the hand. The frame
    //! and its 1 px dark edge (inside and out) are stadium-shaped rings,
    //! split along the hand's axis into two simple polygons for fillPolygon.
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param length Distance from center to tip
    //! @param width Bar width in pixels
    //! @param start Radius fraction where the bar begins
    //! @return [edge side 1, edge side 2, frame side 1, frame side 2]
    private function handShapes(angle as Float, length as Float, width as Number,
            start as Float) as Array<Array<Point2D> > {
        var from = _radius * start;
        var to = length - width / 2.0;
        var half = width / 2.0;
        var holeHalf = (width - 6) / 2.0;
        var holeFrom = from + width * 0.6;
        var holeTo = length - width * 1.4;
        return [
            ringHalf(angle, from, to, half + 1, holeFrom + 1, holeTo - 1, holeHalf - 1, 1),
            ringHalf(angle, from, to, half + 1, holeFrom + 1, holeTo - 1, holeHalf - 1, -1),
            ringHalf(angle, from, to, half, holeFrom, holeTo, holeHalf, 1),
            ringHalf(angle, from, to, half, holeFrom, holeTo, holeHalf, -1)
        ] as Array<Array<Point2D> >;
    }

    //! One side of a ring between two stadiums (rounded bars) that lie
    //! along the same radial axis.
    //! @param angle Axis angle in radians, clockwise from 12 o'clock
    //! @param from Outer stadium: distance of its back cap center
    //! @param to Outer stadium: distance of its tip cap center
    //! @param half Outer stadium: half width
    //! @param holeFrom Inner stadium: distance of its back cap center
    //! @param holeTo Inner stadium: distance of its tip cap center
    //! @param holeHalf Inner stadium: half width
    //! @param side 1 for the clockwise side, -1 for the other
    //! @return Polygon points (at most 4 * ARC_POINTS)
    private function ringHalf(angle as Float, from as Float, to as Float, half as Float,
            holeFrom as Float, holeTo as Float, holeHalf as Float, side as Number) as Array<Point2D> {
        var sinA = Math.sin(angle).toFloat();
        var cosA = Math.cos(angle).toFloat();
        var n = ARC_COS.size();
        var points = new Array<Point2D>[4 * n];
        for (var k = 0; k < n; k++) {
            var c = ARC_COS[k] as Float;
            var s = (ARC_SIN[k] as Float) * side;
            // Outer tip cap, from the axis to the side, then the outer back
            // cap from the side to the axis. The hole runs the other way.
            points[k] = ringPoint(sinA, cosA, to + half * c, half * s);
            points[2 * n - 1 - k] = ringPoint(sinA, cosA, from - half * c, half * s);
            points[2 * n + k] = ringPoint(sinA, cosA, holeFrom - holeHalf * c, holeHalf * s);
            points[4 * n - 1 - k] = ringPoint(sinA, cosA, holeTo + holeHalf * c, holeHalf * s);
        }
        return points;
    }

    //! Screen point at a distance along a radial axis plus an offset
    //! across it.
    //! @param sinA Sine of the axis angle
    //! @param cosA Cosine of the axis angle
    //! @param along Distance from the center along the axis
    //! @param across Offset across the axis (positive is clockwise)
    //! @return Screen point
    private function ringPoint(sinA as Float, cosA as Float, along as Float, across as Float) as Point2D {
        return [_cx + along * sinA + across * cosA, _cy - along * cosA + across * sinA] as Point2D;
    }

    //! Draw the open center hub.
    //! @param dc Device context
    private function drawCap(dc as Dc) as Void {
        var r = (_radius * 0.028).toNumber();
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r + 1);
        dc.setColor((_ink == COLOR_WHITE) ? COLOR_STEEL : _ink, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r);
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r / 3);
    }

    //! Burn-in-safe sleep face (only used if always-on is enabled on AMOLED):
    //! the dot dial and the hour and minute hands (or the digital time),
    //! dimmed, with no stats and no seconds hand. Following Garmin's always-on guidance
    //! (move static elements up to four pixels every minute), everything is
    //! shifted by up to 2 px, cycling through nine positions, one per minute.
    //! @param dc Device context
    //! @param clockTime Current clock time
    private function drawLowPower(dc as Dc, clockTime as System.ClockTime) as Void {
        var shiftX = (clockTime.min % 3 - 1) * 2;
        var shiftY = ((clockTime.min / 3) % 3 - 1) * 2;

        _cx += shiftX;
        _cy += shiftY;
        _ink = COLOR_SLEEP;
        _inkMinor = COLOR_SLEEP_MINOR;

        drawDial(dc);
        if (_digital) {
            updateTime(clockTime);
            drawTime(dc);
        } else {
            updateHands(clockTime);
            drawHands(dc);
            drawCap(dc);
        }

        _cx -= shiftX;
        _cy -= shiftY;
        _ink = COLOR_WHITE;
        _inkMinor = COLOR_MINUTE_DOT;
    }

    // ------------------------------------------------------------- helpers

    //! Allocate a full-screen off-screen image.
    //! @param dc Device context (for the screen size)
    //! @return The image reference, or null if unsupported or out of memory
    private function createLayer(dc as Dc) as Graphics.BufferedBitmapReference? {
        if (!(Graphics has :createBufferedBitmap)) {
            return null;
        }
        try {
            return Graphics.createBufferedBitmap({ :width => dc.getWidth(), :height => dc.getHeight() });
        } catch (e) {
            return null;
        }
    }

    //! Fill a drawing surface with the background color.
    //! @param dc Device context
    private function clearScreen(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();
    }

    //! Load a scalable system font, falling back to a built-in font.
    //! @param faces Font face names in order of preference
    //! @param size Font size as a fraction of the screen radius
    //! @param fallback Font used when vector fonts are unavailable
    //! @return The font
    private function vectorFont(faces as Array<String>, size as Float,
            fallback as Graphics.FontType) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            var font = Graphics.getVectorFont({ :face => faces, :size => (_radius * size).toNumber() });
            if (font != null) {
                return font;
            }
        }
        return fallback;
    }

    //! Load a bitmap resource.
    //! @param id Resource id
    //! @return The bitmap
    private function loadIcon(id as ResourceId) as BitmapResource {
        return WatchUi.loadResource(id) as BitmapResource;
    }

    //! Screen point at an angle and distance from the center.
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param distance Distance from the center in pixels
    //! @return [x, y]
    private function polar(angle as Float, distance as Float) as [Number, Number] {
        return [
            (_cx + distance * Math.sin(angle) + 0.5).toNumber(),
            (_cy - distance * Math.cos(angle) + 0.5).toNumber()
        ];
    }

    //! Draw a radial line between two radius fractions.
    //! @param dc Device context
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param from Inner end as a fraction of the screen radius
    //! @param to Outer end as a fraction of the screen radius
    //! @param pen Line width
    //! @param color Line color
    private function radialLine(dc as Dc, angle as Float, from as Float, to as Float,
            pen as Number, color as Number) as Void {
        var a = polar(angle, _radius * from);
        var b = polar(angle, _radius * to);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawLine(a[0], a[1], b[0], b[1]);
        dc.setPenWidth(1);
    }
}
