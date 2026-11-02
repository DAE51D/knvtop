import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Two-click button for destructive actions: the first click arms it (shows
// armedText with a warning icon for 3s), the second click emits confirmed().
// One stray click on a card should never take down a running llama-server.
PlasmaComponents.ToolButton {
    id: btn

    property string idleIcon: "application-exit"
    property string armedText: "Confirm?"
    property string tip: ""
    property bool armed: false
    signal confirmed()

    icon.name: armed ? "dialog-warning" : idleIcon
    icon.width: 14
    icon.height: 14
    implicitHeight: 22
    implicitWidth: armed ? 90 : 22
    text: armed ? armedText : ""
    // Let Plasma/Kirigami supply a foreground color that adapts to the
    // current Plasma theme (light/day vs dark/night); a hard-coded color
    // would be unreadable in one of the modes.
    palette.buttonText: Kirigami.Theme.textColor

    onClicked: {
        if (armed) {
            armed = false
            confirmed()
        } else {
            armed = true
            disarmTimer.restart()
        }
    }

    Timer { id: disarmTimer; interval: 3000; onTriggered: btn.armed = false }
    PlasmaComponents.ToolTip { text: btn.tip }
}
