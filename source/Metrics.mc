//! @file Metrics.mc
//! Reads the activity and sensor values shown around the dial and formats
//! them as display strings. Every getter returns "--" when the value is not
//! available, so the view never has to deal with null.

import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Static accessors for the watch face data fields. Not instantiable.
class Metrics {

    //! Placeholder shown when a value is unavailable.
    public static const NO_VALUE = "--";

    //! Meters to feet.
    private static const FEET_PER_METER = 3.28084;

    //! Short weekday name for today, e.g. "TUE".
    //! @return Weekday string
    public static function weekday() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return (info.day_of_week as String).toUpper();
    }

    //! Day of month and short month name, e.g. "10 NOV".
    //! @return Date string
    public static function dayMonth() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return info.day.format("%d") + " " + (info.month as String).toUpper();
    }

    //! Current heart rate in bpm. Uses the live reading when there is one,
    //! otherwise the newest valid sample from the heart rate history.
    //! @return Heart rate string
    public static function heartRate() as String {
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null && activityInfo.currentHeartRate != null) {
            return (activityInfo.currentHeartRate as Number).format("%d");
        }

        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != null
                    && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return (sample.heartRate as Number).format("%d");
            }
        }
        return NO_VALUE;
    }

    //! Battery charge in whole percent.
    //! @return Battery percentage as a Number (0..100)
    public static function batteryPercent() as Number {
        return (System.getSystemStats().battery + 0.5).toNumber();
    }

    //! Steps taken today.
    //! @return Step count string
    public static function steps() as String {
        var info = ActivityMonitor.getInfo();
        return (info.steps != null) ? (info.steps as Number).format("%d") : NO_VALUE;
    }

    //! Floors climbed today.
    //! @return Floor count string
    public static function floors() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :floorsClimbed) && info.floorsClimbed != null) {
            return (info.floorsClimbed as Number).format("%d");
        }
        return NO_VALUE;
    }

    //! Calories burned today (active plus resting), in kcal.
    //! @return Calorie string
    public static function calories() as String {
        var info = ActivityMonitor.getInfo();
        return (info.calories != null) ? (info.calories as Number).format("%d") : NO_VALUE;
    }

    //! Current elevation in the user's units, with unit suffix, e.g. "1234m".
    //! Uses the barometric altimeter history, falling back to Activity.Info.
    //! @return Elevation string
    public static function elevation() as String {
        var meters = null;
        if ((Toybox has :SensorHistory) && (SensorHistory has :getElevationHistory)) {
            meters = newestSample(SensorHistory.getElevationHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            }));
        }
        if (meters == null) {
            var activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                meters = activityInfo.altitude;
            }
        }
        if (meters == null) {
            return NO_VALUE;
        }

        if (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE) {
            return (meters * FEET_PER_METER).format("%d") + "ft";
        }
        return meters.format("%d") + "m";
    }

    //! Sensor temperature in the user's units, e.g. "21°". This is the
    //! watch's own sensor, so it reads high while worn (body heat).
    //! @return Temperature string
    public static function temperature() as String {
        if (!((Toybox has :SensorHistory) && (SensorHistory has :getTemperatureHistory))) {
            return NO_VALUE;
        }
        var celsius = newestSample(SensorHistory.getTemperatureHistory({
            :period => 1,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        }));
        if (celsius == null) {
            return NO_VALUE;
        }

        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            return (celsius * 9.0 / 5.0 + 32.0).format("%d") + "°";
        }
        return celsius.format("%d") + "°";
    }

    //! Return the data value of the first sample of a sensor history iterator.
    //! @param iter Iterator from a SensorHistory getter, or null
    //! @return The sample value, or null if there is none
    private static function newestSample(iter as SensorHistory.SensorHistoryIterator?) as Numeric? {
        if (iter == null) {
            return null;
        }
        var sample = iter.next();
        return (sample != null) ? sample.data : null;
    }
}
