//! @file DataDialView.mc
//! Analog watch face view: a dot dial, eight data fields in wedge-shaped
//! sections, skeleton hour/minute hands, and a seconds hand while the watch
//! is awake. All geometry is derived from the screen size so other round
//! displays work.
//!
//! Drawing is cached in two off-screen images: the parts that never change
//! are drawn once, and the stat values are redrawn only when one changes.
//! Each frame copies the cached image and draws the hands on top.

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
    private const COLOR_ACCENT = 0x2EA3F2;
    private const COLOR_CHARGING = 0x3DDC57;
    //! Dimmed colors used by the always-on sleep view.
    private const COLOR_SLEEP = 0x9A9A9A;
    private const COLOR_SLEEP_MINOR = 0x5A5A5A;

    //! Field slots, clockwise from 12 o'clock at 45-degree steps.
    private const SLOT_DATE = 0;
    private const SLOT_HEART = 1;
    private const SLOT_BATTERY = 2;
    private const SLOT_STEPS = 3;
    private const SLOT_FLOORS = 4;
    private const SLOT_CALORIES = 5;
    private const SLOT_ELEVATION = 6;
    private const SLOT_TEMPERATURE = 7;
    private const SLOT_COUNT = 8;

    //! Battery level (percent) below which the battery icon and value turn red.
    private const BATTERY_LOW = 20;

    //! How often the hands move: the minute hand every MINUTE_HAND_STEP
    //! seconds, the hour hand every HOUR_HAND_STEP minutes.
    private const MINUTE_HAND_STEP = 10;
    private const HOUR_HAND_STEP = 10;

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

    //! Icon per slot; null for slots drawn in code (date text, battery gauge).
    private var _icons as Array<BitmapResource?> = new Array<BitmapResource?>[8];
    private var _iconSize as Number = 0;

    //! Colors of the dial, hands and hub: full brightness while awake,
    //! dimmed in the always-on sleep view.
    private var _ink as Number = COLOR_WHITE;
    private var _inkMinor as Number = COLOR_MINUTE_DOT;

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
    }

    //! Compute layout and load fonts and icons.
    //! @param dc Device context
    public function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;
        _radius = (_cx < _cy) ? _cx : _cy;

        _labelFont = vectorFont(["BionicBold", "RobotoCondensedBold"], 0.12, Graphics.FONT_XTINY);
        _valueFont = vectorFont(["BionicBold", "RobotoCondensedBold"], 0.165, Graphics.FONT_TINY);

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

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (!_awake && _burnInProtection) {
            clearScreen(dc);
            drawLowPower(dc, clockTime);
            return;
        }

        refreshValues(clockTime);
        updateHands(clockTime);
        drawBackground(dc);
        drawHands(dc);

        if (_awake) {
            var secondAngle = clockTime.sec / 60.0 * Math.PI * 2;
            var tip = polar(secondAngle, _radius * 0.92);
            var tail = polar(secondAngle + Math.PI, _radius * 0.30);
            dc.setColor(COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
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
        }

        if (all || now - _slowTime >= SLOW_PERIOD) {
            _slowTime = now;
            setValue(SLOT_FLOORS, Metrics.floors());
            setValue(SLOT_CALORIES, Metrics.calories());
            setValue(SLOT_ELEVATION, Metrics.elevation());
            setValue(SLOT_TEMPERATURE, Metrics.temperature());
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
            return;
        }

        if (_dirtyAll || _dirtySlots != 0) {
            var compositeDc = composite.getDc();
            if (compositeDc has :setAntiAlias) {
                compositeDc.setAntiAlias(true);
            }
            if (_dirtyAll) {
                compositeDc.drawBitmap(0, 0, layer);
                drawFields(compositeDc, false);
                for (var i = 0; i < SLOT_COUNT; i++) {
                    _drawnWidth[i] = compositeDc.getTextWidthInPixels(_values[i], _valueFont);
                }
            } else {
                for (var i = 0; i < SLOT_COUNT; i++) {
                    if ((_dirtySlots & (1 << i)) != 0) {
                        redrawSlot(compositeDc, layer, i);
                    }
                }
            }
            _dirtyAll = false;
            _dirtySlots = 0;
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
        var outer = polar(angle, _radius * 0.68);
        var width = dc.getTextWidthInPixels(_values[slot], _valueFont);
        var clearWidth = ((width > _drawnWidth[slot]) ? width : _drawnWidth[slot]);
        var clearHeight = dc.getFontHeight(_valueFont);
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
        dc.clearClip();
    }


    //! Dial: a dot for every minute, larger at the hours and largest at the
    //! quarters.
    //! @param dc Device context
    private function drawDial(dc as Dc) as Void {
        for (var i = 0; i < 60; i++) {
            var p = polar(i / 60.0 * Math.PI * 2, _radius * 0.94);
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
        radialLine(dc, angle + Math.PI / SLOT_COUNT, 0.30, 0.86, 2, COLOR_ACCENT);
        var icon = _icons[slot];
        if (icon != null) {
            var inner = polar(angle, _radius * 0.38);
            dc.drawBitmap(inner[0] - _iconSize / 2, inner[1] - _iconSize / 2, icon);
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
                    low ? COLOR_RED : COLOR_ACCENT);
            if (_charging) {
                drawBolt(dc, inner[0], inner[1], _iconSize);
            }
        } else if (slot == SLOT_DATE) {
            // The weekday sits directly under the date instead of at the icon radius.
            var day = polar(angle, _radius * 0.525);
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(day[0], day[1], _labelFont, _weekday, center);
        }

        var outer = polar(angle, _radius * 0.68);
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

        dc.setColor(low ? COLOR_RED : COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(outer[0], valueY, _valueFont, _values[slot], center);
    }

    //! Distance from the battery cell's centerline to the center of each of
    //! its two lines (percentage above, estimate below).
    //! @return Offset in pixels
    private function batteryLineOffset() as Number {
        return (_radius * 0.115).toNumber();
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

    //! Draw the hour and minute hands at their current stepped angles.
    //! @param dc Device context
    private function drawHands(dc as Dc) as Void {
        drawHand(dc, _hourAngle, _radius * 0.52, 12, 0.24);
        drawHand(dc, _minuteAngle, _radius * 0.86, 10, 0.30);
    }

    //! Skeleton hand: a rounded hollow bar on a thin stem, so the fields
    //! show through the middle of the hand.
    //! @param dc Device context
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param length Distance from center to tip
    //! @param width Bar width in pixels
    //! @param start Radius fraction where the bar begins
    private function drawHand(dc as Dc, angle as Float, length as Float, width as Number,
            start as Float) as Void {
        var inner = _radius * start;
        var a = polar(angle, inner);
        var b = polar(angle, length - width / 2);

        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(_cx, _cy, a[0], a[1]);
        roundLine(dc, a, b, width + 4, COLOR_BG);
        roundLine(dc, a, b, width, _ink);
        roundLine(dc, polar(angle, inner + width * 0.6), polar(angle, length - width * 1.4), width - 5, COLOR_BG);
    }

    //! Draw the open center hub.
    //! @param dc Device context
    private function drawCap(dc as Dc) as Void {
        var r = (_radius * 0.028).toNumber();
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r + 2);
        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r);
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r / 3);
    }

    //! Burn-in-safe sleep face (only used if always-on is enabled on AMOLED):
    //! the dot dial and the hollow hour and minute hands, dimmed, with no
    //! stats and no seconds hand. Everything is shifted each minute, by more
    //! than the size of a dot over the cycle, so no pixel stays lit in place.
    //! @param dc Device context
    //! @param clockTime Current clock time
    private function drawLowPower(dc as Dc, clockTime as System.ClockTime) as Void {
        var shiftX = (clockTime.min % 5) * 4 - 8;
        var shiftY = ((clockTime.min / 5) % 5) * 4 - 8;

        _cx += shiftX;
        _cy += shiftY;
        _ink = COLOR_SLEEP;
        _inkMinor = COLOR_SLEEP_MINOR;

        updateHands(clockTime);
        drawDial(dc);
        drawHands(dc);
        drawCap(dc);

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

    //! Draw a thick line with round ends.
    //! @param dc Device context
    //! @param a Start point
    //! @param b End point
    //! @param width Line width
    //! @param color Line color
    private function roundLine(dc as Dc, a as [Number, Number], b as [Number, Number],
            width as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        dc.drawLine(a[0], a[1], b[0], b[1]);
        dc.setPenWidth(1);
        dc.fillCircle(a[0], a[1], width / 2);
        dc.fillCircle(b[0], b[1], width / 2);
    }
}
