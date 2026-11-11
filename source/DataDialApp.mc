//! @file DataDialApp.mc
//! Application entry point for the DataDial watch face.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Watch face application. Creates the single DataDialView.
class DataDialApp extends Application.AppBase {

    //! Constructor.
    public function initialize() {
        AppBase.initialize();
    }

    //! Called when the app starts.
    //! @param state Startup arguments (unused)
    public function onStart(state as Dictionary?) as Void {
    }

    //! Called when the app stops.
    //! @param state Shutdown arguments (unused)
    public function onStop(state as Dictionary?) as Void {
    }

    //! Return the initial view of the watch face.
    //! @return Array holding the watch face view
    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new DataDialView()];
    }
}
