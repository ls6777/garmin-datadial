/**
 * @file PushSettings.java
 * Send a compiled app's settings file (bin/NAME-settings.json) to a running
 * Connect IQ simulator, so File > Edit Persistent Storage > Edit
 * Application.Properties data can show the app's settings.
 *
 * Uses the SDK's own transfer code. monkeydo's /a option can't be used for
 * this on Windows: it rebuilds the destination path with backslashes and the
 * simulator drops the file.
 *
 * Run as a single-file program with monkeybrains.jar on the class path:
 *   java -cp monkeybrains.jar PushSettings.java SHELL_EXE SETTINGS_JSON NAME
 */

import com.garmin.connectiq.common.communication.shell.ShellUtils;
import java.io.File;

/** Command-line entry point. */
public class PushSettings {
    /**
     * Push the settings file.
     * @param args shell.exe path, settings JSON path, and the file name to
     *             use in the simulator (PRG name in capitals + "-settings.json")
     * @throws Exception if the simulator can't be reached
     */
    public static void main(String[] args) throws Exception {
        File shell = new File(args[0]);
        int port = ShellUtils.findSimulatorPort(shell);
        ShellUtils.pushFile(new File(args[1]), "0:/GARMIN/Settings/" + args[2], shell, port);
    }
}
