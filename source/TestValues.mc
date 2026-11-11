//! @file TestValues.mc
//! Optional fixed stat values for checking the layout in the simulator.
//!
//! Two versions of the TestValues class exist. The normal build
//! (monkey.jungle) excludes the :testValues one, so no stat is overridden.
//! The test build (monkey.test.jungle, `./build.sh test`) excludes the
//! :realValues one, so the fixed values below replace the real readings.

import Toybox.Lang;

//! Normal build: nothing is overridden.
(:realValues)
class TestValues {

    //! Display text that replaces a stat's real value.
    //! @param slot Field slot (see the SLOT_ constants in DataDialView)
    //! @return Always null: use the real value
    public static function text(slot as Number) as String? {
        return null;
    }

    //! Battery level that replaces the real one.
    //! @return Always null: use the real level
    public static function batteryPercent() as Number? {
        return null;
    }

    //! Battery estimate text that replaces the real one.
    //! @return Always null: use the real estimate
    public static function batteryEstimate() as String? {
        return null;
    }

    //! Goal state that replaces the real one.
    //! @param slot Field slot
    //! @return Always null: use the real goal state
    public static function goalMet(slot as Number) as Boolean? {
        return null;
    }

    //! Goal progress that replaces the real one.
    //! @param slot Field slot
    //! @return Always null: use the real progress
    public static function progress(slot as Number) as Float? {
        return null;
    }
}

//! Test build: fixed values chosen to stress the layout.
(:testValues)
class TestValues {

    //! Display text that replaces a stat's real value.
    //! @param slot Field slot (see the SLOT_ constants in DataDialView)
    //! @return The fixed text, or null to keep the real value (the date)
    public static function text(slot as Number) as String? {
        var values = [
            null,       // 0 date: real
            "160",      // 1 heart rate
            "100%",     // 2 battery
            "25000",    // 3 steps
            "3500",     // 4 calories
            "110",      // 5 floors
            "13000ft",  // 6 elevation
            "110°"      // 7 temperature
        ] as Array<String?>;
        return values[slot];
    }

    //! Battery level that replaces the real one.
    //! @return The fixed level, 0..100
    public static function batteryPercent() as Number? {
        return 100;
    }

    //! Battery estimate text that replaces the real one.
    //! @return The fixed estimate
    public static function batteryEstimate() as String? {
        return "31d";
    }

    //! Goal state that replaces the real one: floors (slot 5) has met its
    //! goal, steps has not.
    //! @param slot Field slot
    //! @return Whether the goal counts as met
    public static function goalMet(slot as Number) as Boolean? {
        return slot == 5;
    }

    //! Goal progress that replaces the real one: steps (slot 3) part-way,
    //! floors at its goal.
    //! @param slot Field slot
    //! @return Progress, 0..1
    public static function progress(slot as Number) as Float? {
        return (slot == 3) ? 0.6 : 1.0;
    }
}
