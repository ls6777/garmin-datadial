//! @file DataDialView.mc
//! Analog watch face view: minute/hour ticks, eight data fields in a ring,
//! hour/minute hands, and a seconds hand while the watch is awake.
//! All geometry is derived from the screen size so other round displays work.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! The DataDial watch face.
class DataDialView extends WatchUi.WatchFace {

    // Colors.
    private const COLOR_BG = Graphics.COLOR_BLACK;
    private const COLOR_HAND = 0xFFFFFF;
    private const COLOR_SECOND = 0xFF3B30;
    private const COLOR_TICK_HOUR = 0xFFFFFF;
    private const COLOR_TICK_MIN = 0x606060;
    private const COLOR_VALUE = 0xFFFFFF;
    private const COLOR_LOW_POWER = 0x808080;

    private const COLOR_WEEKDAY = 0xC0C0C0;
    private const COLOR_BATTERY = 0x5AD25A;

    //! Field slots, clockwise from 12 o'clock at 45-degree steps.
    private const SLOT_DATE = 0;
    private const SLOT_BATTERY = 2;
    private const SLOT_COUNT = 8;

    //! Battery level (percent) below which the battery icon turns red.
    private const BATTERY_LOW = 20;

    //! Icon per slot; null for slots drawn in code (date text, battery gauge).
    private var _icons as Array<BitmapResource?> = new Array<BitmapResource?>[8];
    private var _iconSize as Number = 0;

    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _radius as Number = 0;
    private var _fieldRadius as Float = 0.0;
    private var _labelFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var _valueFont as Graphics.FontType = Graphics.FONT_TINY;

    private var _awake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    //! Cached field values, refreshed once a minute (heart rate every update).
    private var _values as Array<String> = new Array<String>[8];
    private var _batteryPercent as Number = 0;
    private var _lastDataMinute as Number = -1;

    //! Constructor.
    public function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnInProtection = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        for (var i = 0; i < _values.size(); i++) {
            _values[i] = Metrics.NO_VALUE;
        }
    }

    //! Compute layout from the screen size.
    //! @param dc Device context
    public function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;
        _radius = (_cx < _cy) ? _cx : _cy;
        _fieldRadius = _radius * 0.62;

        _icons[1] = WatchUi.loadResource($.Rez.Drawables.HeartIcon) as BitmapResource;
        _icons[3] = WatchUi.loadResource($.Rez.Drawables.StepsIcon) as BitmapResource;
        _icons[4] = WatchUi.loadResource($.Rez.Drawables.FloorsIcon) as BitmapResource;
        _icons[5] = WatchUi.loadResource($.Rez.Drawables.CaloriesIcon) as BitmapResource;
        _icons[6] = WatchUi.loadResource($.Rez.Drawables.ElevationIcon) as BitmapResource;
        _icons[7] = WatchUi.loadResource($.Rez.Drawables.TemperatureIcon) as BitmapResource;
        _iconSize = (_icons[1] as BitmapResource).getHeight();

        // Scale text with the screen; the built-in fonts are too large to fit
        // eight fields on high-resolution displays.
        if (Graphics has :getVectorFont) {
            var label = Graphics.getVectorFont({
                :face => ["RobotoCondensedBold", "RobotoMedium", "RobotoRegular"],
                :size => (_radius * 0.10).toNumber()
            });
            var value = Graphics.getVectorFont({
                :face => ["RobotoCondensedRegular", "RobotoRegular"],
                :size => (_radius * 0.17).toNumber()
            });
            if (label != null && value != null) {
                _labelFont = label;
                _valueFont = value;
            }
        }
    }

    //! Draw the whole face.
    //! @param dc Device context
    public function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (!_awake && _burnInProtection) {
            drawLowPower(dc, clockTime);
            return;
        }

        refreshValues(clockTime);
        drawTicks(dc);
        drawFields(dc);

        var hourAngle = ((clockTime.hour % 12) * 60 + clockTime.min) / 720.0 * Math.PI * 2;
        var minuteAngle = (clockTime.min + clockTime.sec / 60.0) / 60.0 * Math.PI * 2;

        drawHand(dc, hourAngle, _radius * 0.50, _radius * 0.10, _radius * 0.065, COLOR_HAND);
        drawHand(dc, minuteAngle, _radius * 0.82, _radius * 0.10, _radius * 0.045, COLOR_HAND);

        if (_awake) {
            var secondAngle = clockTime.sec / 60.0 * Math.PI * 2;
            drawSecondHand(dc, secondAngle);
        } else {
            drawCap(dc, COLOR_HAND);
        }
    }

    //! The watch woke up (wrist raise): show the seconds hand.
    public function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    //! The watch went to sleep: hide the seconds hand.
    public function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    //! Re-read the data fields. Heart rate is read every update; everything
    //! else once per minute to keep the 1 Hz awake updates cheap.
    //! @param clockTime Current clock time
    private function refreshValues(clockTime as System.ClockTime) as Void {
        _values[1] = Metrics.heartRate();
        if (clockTime.min == _lastDataMinute) {
            return;
        }
        _lastDataMinute = clockTime.min;

        _values[0] = Metrics.dayMonth();
        _batteryPercent = Metrics.batteryPercent();
        _values[2] = _batteryPercent.format("%d") + "%";
        _values[3] = Metrics.steps();
        _values[4] = Metrics.floors();
        _values[5] = Metrics.calories();
        _values[6] = Metrics.elevation();
        _values[7] = Metrics.temperature();
    }

    //! Draw 60 minute ticks with longer, thicker hour ticks.
    //! @param dc Device context
    private function drawTicks(dc as Dc) as Void {
        var outer = _radius - 2;
        for (var i = 0; i < 60; i++) {
            var angle = i / 60.0 * Math.PI * 2;
            var sin = Math.sin(angle);
            var cos = Math.cos(angle);
            var isHour = (i % 5 == 0);
            var inner = isHour ? _radius * 0.89 : _radius * 0.95;

            dc.setColor(isHour ? COLOR_TICK_HOUR : COLOR_TICK_MIN, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(isHour ? ((i % 15 == 0) ? 7 : 4) : 2);
            dc.drawLine(_cx + inner * sin, _cy - inner * cos, _cx + outer * sin, _cy - outer * cos);
        }
        dc.setPenWidth(1);
    }

    //! Draw the eight fields at 45-degree steps, starting with the date at 12.
    //! Each field is a symbol (or the weekday, for the date) above a white value.
    //! @param dc Device context
    private function drawFields(dc as Dc) as Void {
        var valueHeight = dc.getFontHeight(_valueFont);
        var gap = _iconSize / 8;
        var blockHeight = _iconSize + gap + valueHeight;

        for (var i = 0; i < SLOT_COUNT; i++) {
            var angle = i / SLOT_COUNT.toFloat() * Math.PI * 2;
            var x = (_cx + _fieldRadius * Math.sin(angle)).toNumber();
            var y = (_cy - _fieldRadius * Math.cos(angle)).toNumber();
            var top = y - blockHeight / 2;

            var icon = _icons[i];
            if (icon != null) {
                dc.drawBitmap(x - icon.getWidth() / 2, top, icon);
            } else if (i == SLOT_BATTERY) {
                var color = (_batteryPercent < BATTERY_LOW) ? COLOR_SECOND : COLOR_BATTERY;
                drawBattery(dc, x, top, _iconSize, _batteryPercent, color);
            } else if (i == SLOT_DATE) {
                // Bottom-align the weekday with the icon row of the other fields.
                var labelHeight = dc.getFontHeight(_labelFont);
                dc.setColor(COLOR_WEEKDAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, top + _iconSize - labelHeight, _labelFont, Metrics.weekday(),
                        Graphics.TEXT_JUSTIFY_CENTER);
            }

            dc.setColor(COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, top + _iconSize + gap, _valueFont, _values[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
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

    //! Draw a tapered hand with a dark outline so it stays readable over text.
    //! @param dc Device context
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param length Distance from center to tip
    //! @param tail Length of the tail behind the center
    //! @param width Width of the hand at its base
    //! @param color Fill color
    private function drawHand(dc as Dc, angle as Float, length as Float, tail as Float,
            width as Float, color as Number) as Void {
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(handPolygon(angle, length + 3, tail + 3, width + 6));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(handPolygon(angle, length, tail, width));
    }

    //! Draw the thin seconds hand and the center cap on top of it.
    //! @param dc Device context
    //! @param angle Angle in radians, clockwise from 12 o'clock
    private function drawSecondHand(dc as Dc, angle as Float) as Void {
        var sin = Math.sin(angle);
        var cos = Math.cos(angle);
        var tip = _radius * 0.90;
        var tail = _radius * 0.18;

        dc.setColor(COLOR_SECOND, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(_cx - tail * sin, _cy + tail * cos, _cx + tip * sin, _cy - tip * cos);
        dc.setPenWidth(1);
        drawCap(dc, COLOR_SECOND);
    }

    //! Draw the center cap.
    //! @param dc Device context
    //! @param color Cap color
    private function drawCap(dc as Dc, color as Number) as Void {
        var r = (_radius * 0.035).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r);
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, r / 3);
    }

    //! Burn-in-safe sleep face (only used if always-on is enabled on AMOLED):
    //! thin gray hands only, no fills, shifted a few pixels each minute so no
    //! pixel stays lit in the same place.
    //! @param dc Device context
    //! @param clockTime Current clock time
    private function drawLowPower(dc as Dc, clockTime as System.ClockTime) as Void {
        var shiftX = (clockTime.min % 5) * 2 - 4;
        var shiftY = ((clockTime.min / 5) % 5) * 2 - 4;
        var cx = _cx + shiftX;
        var cy = _cy + shiftY;

        var hourAngle = ((clockTime.hour % 12) * 60 + clockTime.min) / 720.0 * Math.PI * 2;
        var minuteAngle = clockTime.min / 60.0 * Math.PI * 2;
        var hourLen = _radius * 0.50;
        var minuteLen = _radius * 0.80;

        dc.setColor(COLOR_LOW_POWER, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy, cx + hourLen * Math.sin(hourAngle), cy - hourLen * Math.cos(hourAngle));
        dc.drawLine(cx, cy, cx + minuteLen * Math.sin(minuteAngle), cy - minuteLen * Math.cos(minuteAngle));
        dc.setPenWidth(1);
    }

    //! Build a tapered, pointed hand polygon rotated around the screen center.
    //! @param angle Angle in radians, clockwise from 12 o'clock
    //! @param length Distance from center to tip
    //! @param tail Length of the tail behind the center
    //! @param width Width at the base
    //! @return Polygon points in screen coordinates
    private function handPolygon(angle as Float, length as Float, tail as Float,
            width as Float) as Array<[Numeric, Numeric]> {
        var half = width / 2;
        var shoulder = width * 0.30;
        // Hand pointing up (12 o'clock); +y is toward 6 o'clock.
        var shape = [
            [-half, tail],
            [-shoulder, -length + width],
            [0, -length],
            [shoulder, -length + width],
            [half, tail]
        ];
        var sin = Math.sin(angle);
        var cos = Math.cos(angle);
        var points = new Array<[Numeric, Numeric]>[shape.size()];
        for (var i = 0; i < shape.size(); i++) {
            var px = shape[i][0];
            var py = shape[i][1];
            points[i] = [_cx + px * cos - py * sin, _cy + px * sin + py * cos];
        }
        return points;
    }
}
