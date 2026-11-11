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
            "110",      // 4 floors
            "3500",     // 5 calories
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
}
