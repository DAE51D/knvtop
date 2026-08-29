import QtQuick
import QtQuick.Layouts

// Reusable card for one LLM process (llama.cpp / ollama / vllm entry).
// Extracted from 3x near-identical Rectangle+ColumnLayout blocks in
// main.qml's fullRepresentation.
Rectangle {
    id: card

    property string title
    property color titleColor: "#4d9fff"
    property string subtitle: ""
    property string cmdline: ""

    Layout.fillWidth: true
    color: "#1a1f25"
    radius: 3
    height: col.implicitHeight + 16

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 8
        spacing: 3

        Text {
            Layout.fillWidth: true
            text: card.title
            color: card.titleColor
            font.bold: true
            font.pointSize: 9
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: card.subtitle.length > 0
            text: card.subtitle
            color: "#aeb4bb"
            font.pointSize: 8
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: card.cmdline.length > 0
            text: card.cmdline
            color: "#6a7078"
            font.pointSize: 7
            font.family: "monospace"
            wrapMode: Text.Wrap
        }
    }
}
