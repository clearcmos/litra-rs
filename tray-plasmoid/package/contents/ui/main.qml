import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property bool lightOn: false
    property int brightness: 50
    property int temperature: 4500
    property string statusText: i18n("Ready")
    property color statusColor: Kirigami.Theme.disabledTextColor

    readonly property url iconOn: Qt.resolvedUrl("../icons/lightbulb-on.svg")
    readonly property url iconOff: Qt.resolvedUrl("../icons/lightbulb-off.svg")

    Plasmoid.icon: lightOn ? iconOn : iconOff
    Plasmoid.title: i18n("Litra Glow Control")

    toolTipMainText: i18n("Litra Glow Control")
    toolTipSubText: lightOn
        ? i18n("Light is ON · %1%", brightness)
        : i18n("Light is OFF")

    preferredRepresentation: compactRepresentation

    Plasma5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []

        property var pendingApplyAfterOn: false

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"]
            const stderr = (data["stderr"] || "").trim()
            disconnectSource(sourceName)

            if (exitCode !== 0) {
                root.statusText = stderr.length
                    ? i18n("Error: %1", stderr)
                    : i18n("Command failed (exit %1)", exitCode)
                root.statusColor = Kirigami.Theme.negativeTextColor
            }
        }

        function run(cmd) {
            connectSource(cmd)
        }
    }

    function applyBrightness() {
        if (!lightOn) return
        shell.run("litra brightness --percentage " + brightness)
        statusText = i18n("Brightness: %1%", brightness)
        statusColor = Kirigami.Theme.positiveTextColor
    }

    function applyTemperature() {
        if (!lightOn) return
        shell.run("litra temperature --value " + temperature)
        statusText = i18n("Temperature: %1K", temperature)
        statusColor = Kirigami.Theme.positiveTextColor
    }

    function togglePower() {
        if (lightOn) {
            shell.run("litra off")
            lightOn = false
            statusText = i18n("Light is OFF")
            statusColor = Kirigami.Theme.disabledTextColor
        } else {
            shell.run("litra on")
            shell.run("litra brightness --percentage " + brightness)
            shell.run("litra temperature --value " + temperature)
            lightOn = true
            statusText = i18n("Light is ON")
            statusColor = Kirigami.Theme.positiveTextColor
        }
    }

    // Throttle slider updates to ~12 Hz so we don't flood the device with
    // shell-spawned `litra` calls, but still feel real-time.
    readonly property int sliderThrottleMs: 80
    property double brightnessLastSent: 0
    property double temperatureLastSent: 0

    Timer {
        id: brightnessTrailing
        interval: sliderThrottleMs
        onTriggered: root.applyBrightness()
    }
    Timer {
        id: temperatureTrailing
        interval: sliderThrottleMs
        onTriggered: root.applyTemperature()
    }

    function pumpBrightness() {
        const now = Date.now()
        if (now - brightnessLastSent >= sliderThrottleMs) {
            applyBrightness()
            brightnessLastSent = now
        }
        brightnessTrailing.restart()
    }

    function pumpTemperature() {
        const now = Date.now()
        if (now - temperatureLastSent >= sliderThrottleMs) {
            applyTemperature()
            temperatureLastSent = now
        }
        temperatureTrailing.restart()
    }

    compactRepresentation: MouseArea {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) {
                root.togglePower()
            } else {
                root.expanded = !root.expanded
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: root.lightOn ? root.iconOn : root.iconOff
            active: parent.containsMouse
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
            text: i18n("Litra Glow Control")
        }

        PlasmaComponents.Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5

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
                from: 1
                to: 100
                value: root.brightness
                stepSize: 1

                onMoved: {
                    root.brightness = Math.round(value)
                    root.pumpBrightness()
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
                id: tempSlider
                Layout.fillWidth: true
                from: 2700
                to: 6500
                value: root.temperature
                stepSize: 100

                onMoved: {
                    root.temperature = Math.round(value / 100) * 100
                    root.pumpTemperature()
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: i18n("Warm (2700K)")
                    color: "#FF9800"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Label {
                    text: i18n("Cool (6500K)")
                    color: "#2196F3"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        Item { Layout.fillHeight: true }

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
