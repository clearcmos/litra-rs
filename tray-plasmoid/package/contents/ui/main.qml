// Binds outer ids (root) inside compactRepresentation and fullRepresentation,
// which Plasma instantiates as separate Components.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "../code/litra.mjs" as Litra

PlasmoidItem {
    id: root

    // Device state. Every property here is a cache of what the hardware last
    // reported through `litra devices --json`; none of it is authoritative on
    // its own. An earlier version tracked only its own guess, so anything that
    // changed the light out of band (a shell, a keybinding, the MCP server,
    // the button on the light itself) left the tray icon lit over a dark room
    // forever. Read the device, never trust the last thing we asked for.
    property bool deviceProbed: false
    property bool devicePresent: false
    property bool lightOn: false
    property int brightness: 100
    property int temperature: 4500
    property int minTemperature: 2700
    property int maxTemperature: 6500
    property string deviceName: ""
    property string errorText: ""

    readonly property bool controlsEnabled: deviceProbed && devicePresent

    readonly property string statusText: {
        if (errorText.length > 0) {
            return errorText;
        }
        if (!deviceProbed) {
            return i18n("Checking device...");
        }
        if (!devicePresent) {
            return i18n("No Litra device found");
        }
        return lightOn ? i18n("On - %1% - %2K", brightness, temperature) : i18n("Off");
    }

    readonly property color statusColor: {
        if (errorText.length > 0) {
            return Kirigami.Theme.negativeTextColor;
        }
        if (!devicePresent) {
            return Kirigami.Theme.neutralTextColor;
        }
        return lightOn ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor;
    }

    readonly property url iconOn: Qt.resolvedUrl("../icons/lightbulb-on.svg")
    readonly property url iconOff: Qt.resolvedUrl("../icons/lightbulb-off.svg")

    Plasmoid.icon: lightOn ? iconOn : iconOff
    Plasmoid.title: i18n("Litra Glow Control")

    toolTipMainText: deviceName.length > 0 ? deviceName : i18n("Litra Glow Control")
    toolTipSubText: {
        if (!deviceProbed) {
            return i18n("Checking device...");
        }
        if (!devicePresent) {
            return i18n("No device connected");
        }
        return lightOn ? i18n("Light is ON - %1%", brightness) : i18n("Light is OFF");
    }

    preferredRepresentation: compactRepresentation

    // A poll issued just before a command lands would report the pre-command
    // state and undo the user's own click. Ignore polled values for a short
    // settle window after we drive the device ourselves. Held per field, so an
    // out-of-band power change still lands while a slider is being dragged.
    readonly property int settleMs: 900
    property double powerHeldUntil: 0
    property double brightnessHeldUntil: 0
    property double temperatureHeldUntil: 0

    // The sliders live in fullRepresentation, which Plasma destroys when the
    // popup closes, so "is the user dragging" has to be held out here where
    // the poll handler can always read it.
    property bool brightnessDragging: false
    property bool temperatureDragging: false

    // A panel widget has no business making network calls, and the CLI's daily
    // update check would otherwise fire from inside plasmashell.
    readonly property string statusCommand: "LITRA_DISABLE_UPDATE_CHECK=1 litra devices --json"

    Plasma5Support.DataSource {
        id: statusSource

        engine: "executable"
        connectedSources: []

        property bool inFlight: false
        property double startedAt: 0

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            inFlight = false;
            root.applyDeviceRead(data["exit code"], data["stdout"] || "", (data["stderr"] || "").trim());
        }

        function poll() {
            // Self-healing guard: one read at a time, but a source that never
            // came back must not wedge polling for the life of the session.
            const now = Date.now();
            if (inFlight && now - startedAt < 10000) {
                return;
            }
            inFlight = true;
            startedAt = now;
            connectSource(root.statusCommand);
        }
    }

    Plasma5Support.DataSource {
        id: shell

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            const exitCode = data["exit code"];
            if (exitCode !== 0) {
                root.reportCommandFailure(exitCode, (data["stderr"] || "").trim());
            }
            // Re-read immediately so the widget settles on what the hardware
            // actually did rather than on what we asked it to do.
            statusSource.poll();
        }

        function run(command) {
            connectSource(command);
        }
    }

    // Poll cadence. The collapsed case is the common one and has to stay cheap;
    // one `litra devices --json` costs roughly 25 ms of CPU, so 5 s in the
    // panel is negligible and still corrects a stale icon quickly. triggeredOnStart
    // gives the first read at load, which is what makes the widget correct after
    // a plasmashell restart instead of defaulting to off.
    Timer {
        id: statusPoll

        interval: root.expanded ? 1500 : 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: statusSource.poll()
    }

    onExpandedChanged: {
        if (expanded) {
            statusSource.poll();
        } else {
            brightnessDragging = false;
            temperatureDragging = false;
        }
    }

    function reportCommandFailure(exitCode, stderr) {
        // Cleared by the next successful read, so a transient failure does not
        // stick around once the device is answering again.
        root.errorText = stderr.length > 0 ? i18n("litra: %1", stderr) : i18n("litra exited with %1", exitCode);
    }

    function applyDeviceRead(exitCode, stdout, stderr) {
        root.deviceProbed = true;

        if (exitCode !== 0) {
            root.devicePresent = false;
            root.reportCommandFailure(exitCode, stderr);
            return;
        }

        const state = Litra.deviceStateFromJson(stdout);
        if (!state.ok) {
            root.devicePresent = false;
            root.errorText = state.error === Litra.ERROR_BAD_JSON ? i18n("Could not read the litra device list") : i18n("Unexpected output from litra");
            return;
        }

        root.errorText = "";
        root.devicePresent = state.present;
        if (!state.present) {
            root.deviceName = "";
            return;
        }

        root.deviceName = state.name;
        root.minTemperature = state.minTemperature;
        root.maxTemperature = state.maxTemperature;

        const now = Date.now();
        if (now >= root.powerHeldUntil) {
            root.lightOn = state.on;
        }
        if (now >= root.brightnessHeldUntil && !root.brightnessDragging) {
            root.brightness = state.brightnessPercent;
        }
        if (now >= root.temperatureHeldUntil && !root.temperatureDragging) {
            root.temperature = state.temperature;
        }
    }

    function applyBrightness() {
        if (!root.controlsEnabled) {
            return;
        }
        // The device stores brightness while it is off and stays off, so the
        // slider is live either way; gating it on lightOn made the control
        // look broken and then snap back on the next read.
        root.brightnessHeldUntil = Date.now() + root.settleMs;
        shell.run("litra brightness --percentage " + root.brightness);
    }

    function applyTemperature() {
        if (!root.controlsEnabled) {
            return;
        }
        root.temperatureHeldUntil = Date.now() + root.settleMs;
        shell.run("litra temperature --value " + root.temperature);
    }

    function togglePower() {
        if (!root.controlsEnabled) {
            return;
        }

        const turningOn = !root.lightOn;
        root.powerHeldUntil = Date.now() + root.settleMs;

        if (turningOn) {
            // One chained command rather than three sources: the executable
            // engine runs separate sources concurrently, and three `litra`
            // processes racing for the same HID handle is how a toggle ends up
            // half applied.
            shell.run("litra on && litra brightness --percentage " + root.brightness + " && litra temperature --value " + root.temperature);
        } else {
            shell.run("litra off");
        }

        // Optimistic, so the click feels instant. The read that follows the
        // command, and every poll after it, is what makes it true.
        root.lightOn = turningOn;
    }

    // Throttle slider updates to ~12 Hz so we don't flood the device with
    // shell-spawned `litra` calls, but still feel real-time.
    readonly property int sliderThrottleMs: 80
    property double brightnessLastSent: 0
    property double temperatureLastSent: 0

    Timer {
        id: brightnessTrailing

        interval: root.sliderThrottleMs
        onTriggered: root.applyBrightness()
    }

    Timer {
        id: temperatureTrailing

        interval: root.sliderThrottleMs
        onTriggered: root.applyTemperature()
    }

    function pumpBrightness() {
        const now = Date.now();
        if (now - root.brightnessLastSent >= root.sliderThrottleMs) {
            root.applyBrightness();
            root.brightnessLastSent = now;
        }
        brightnessTrailing.restart();
    }

    function pumpTemperature() {
        const now = Date.now();
        if (now - root.temperatureLastSent >= root.sliderThrottleMs) {
            root.applyTemperature();
            root.temperatureLastSent = now;
        }
        temperatureTrailing.restart();
    }

    compactRepresentation: MouseArea {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) {
                root.togglePower();
            } else {
                root.expanded = !root.expanded;
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: root.lightOn ? root.iconOn : root.iconOff
            active: parent.containsMouse
            // Nothing has been read yet, or there is no light to talk to.
            opacity: root.controlsEnabled ? 1.0 : 0.6
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14

        spacing: Kirigami.Units.largeSpacing

        PlasmaExtras.Heading {
            Layout.alignment: Qt.AlignHCenter
            level: 2
            text: root.deviceName.length > 0 ? root.deviceName : i18n("Litra Glow Control")
        }

        PlasmaComponents.Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5

            enabled: root.controlsEnabled
            text: root.lightOn ? i18n("Turn Off") : i18n("Turn On")
            icon.name: root.lightOn ? "system-shutdown" : "media-playback-start"

            onClicked: root.togglePower()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("Brightness: %1%", root.brightness)
                font.bold: true
            }

            QQC2.Slider {
                id: brightnessSlider

                Layout.fillWidth: true
                enabled: root.controlsEnabled
                from: 1
                to: 100
                value: root.brightness
                stepSize: 1

                onPressedChanged: root.brightnessDragging = pressed
                onMoved: {
                    root.brightness = Math.round(value);
                    root.pumpBrightness();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("Temperature: %1K", root.temperature)
                font.bold: true
            }

            QQC2.Slider {
                id: temperatureSlider

                Layout.fillWidth: true
                enabled: root.controlsEnabled
                from: root.minTemperature
                to: root.maxTemperature
                value: root.temperature
                stepSize: 100

                onPressedChanged: root.temperatureDragging = pressed
                onMoved: {
                    root.temperature = Math.round(value / 100) * 100;
                    root.pumpTemperature();
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: i18n("Warm (%1K)", root.minTemperature)
                    color: "#FF9800"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: i18n("Cool (%1K)", root.maxTemperature)
                    color: "#2196F3"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.statusText
            color: root.statusColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
        }
    }
}
