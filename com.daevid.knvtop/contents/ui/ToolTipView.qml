import QtQuick
import QtQuick.Layouts

// Hover tooltip. It paints its own dark card instead of drawing on Plasma's popup
// background, so the colors read the same on light and dark themes (the fixed grays
// used before were nearly invisible on a light theme).
Item {
    id: tip

    property var gpu: ({ util: null, mem_used: null, mem_total: null,
                          temp: null, power_w: null })
    property var sys: ({ ram_used: 0, ram_total: 0, cpu: null, load1: 0 })
    property var npu: null   // null on hosts without an NPU: no NPU row at all
    property var llama: []
    property var flm: []
    property var ollamaModels: []

    readonly property bool hasNpu: !!(npu && npu.present)
    readonly property bool npuReadable: hasNpu && !!npu.readable

    readonly property color textColor: "#e6e9ed"
    readonly property color dimColor: "#8d949c"
    readonly property color trackColor: "#272d34"

    function mb(v) {
        if (v === null || v === undefined) return "N/A";
        return (v / 1024).toFixed(1);
    }

    function gib(v) {
        if (v === null || v === undefined) return "N/A";
        return (v / 1073741824).toFixed(1);
    }

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    function clamp01(v) { return Math.max(0, Math.min(1, v || 0)); }

    implicitWidth: 300
    implicitHeight: card.implicitHeight

    // One metric: colored label, thin bar, value text (right aligned).
    component MetricRow: RowLayout {
        id: row
        property string label: ""
        property color accent: "#4d9fff"
        property real ratio: 0
        property string value: ""
        property string detail: ""

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: row.label
            color: row.accent
            font.bold: true
            font.pointSize: 8
            Layout.preferredWidth: 30
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: tip.trackColor
            Rectangle {
                width: Math.max(parent.height, parent.width * tip.clamp01(row.ratio))
                visible: row.ratio > 0
                height: parent.height
                radius: 3
                color: row.accent
            }
        }
        Text {
            text: row.value
            color: tip.textColor
            font.bold: true
            font.pointSize: 9
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 44
        }
        Text {
            text: row.detail
            color: tip.dimColor
            font.pointSize: 8
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 92
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: col.implicitHeight + 20
        color: "#14181d"
        radius: 8

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "knvtop"
                    color: tip.textColor
                    font.bold: true
                    font.pointSize: 10
                    Layout.fillWidth: true
                }
                Text {
                    visible: tip.llama.length > 0
                    text: tip.llama.length + " llama.cpp"
                    color: "#4d9fff"
                    font.pointSize: 8
                }
                Text {
                    visible: tip.flm.length > 0
                    text: tip.flm.length + " FastFlowLM"
                    color: "#ec60a0"
                    font.pointSize: 8
                }
            }

            MetricRow {
                label: "GPU"; accent: "#4d9fff"
                ratio: (tip.gpu.util || 0) / 100
                value: tip.fmt(tip.gpu.util, "%")
                detail: tip.gpu.clock_gfx ? tip.gpu.clock_gfx + " MHz" : ""
            }
            MetricRow {
                label: "GTT"; accent: "#e8c33a"
                ratio: (tip.gpu.mem_used !== null && tip.gpu.mem_total) ? tip.gpu.mem_used / tip.gpu.mem_total : 0
                value: (tip.gpu.mem_used !== null && tip.gpu.mem_total)
                       ? tip.fmt(tip.gpu.mem_used * 100 / tip.gpu.mem_total, "%") : "N/A"
                detail: tip.mb(tip.gpu.mem_used) + " / " + tip.mb(tip.gpu.mem_total) + " GiB"
            }
            MetricRow {
                label: "TMP"; accent: "#b07fe8"
                ratio: Math.min(1, (tip.gpu.temp || 0) / 100)
                value: tip.fmt(tip.gpu.temp, "°")
                detail: ""
            }
            MetricRow {
                label: "PWR"; accent: "#3ddc84"
                ratio: (tip.gpu.power_w || 0) / (tip.gpu.power_cap_w || 100)
                value: tip.fmt(tip.gpu.power_w, "W")
                detail: tip.gpu.power_cap_w ? "of " + tip.fmt(tip.gpu.power_cap_w, "W") : ""
            }
            MetricRow {
                label: "CPU"; accent: "#ff8c42"
                ratio: (tip.sys.cpu || 0) / 100
                value: tip.fmt(tip.sys.cpu, "%")
                detail: "load " + Number(tip.sys.load1 || 0).toFixed(2)
            }
            MetricRow {
                visible: tip.hasNpu
                label: "NPU"; accent: "#ec60a0"
                ratio: tip.npuReadable ? (tip.npu.util || 0) / 100 : 0
                value: tip.npuReadable ? tip.fmt(tip.npu.util, "%") : "N/A"
                detail: tip.npuReadable
                        ? (tip.npu.clock_mhz ? tip.npu.clock_mhz + " MHz" : "")
                        : ((tip.npu && tip.npu.reason) ? tip.npu.reason.split(":")[0] : "")
            }
            MetricRow {
                label: "RAM"; accent: "#89929c"
                ratio: tip.sys.ram_total ? tip.sys.ram_used / tip.sys.ram_total : 0
                value: tip.sys.ram_total ? tip.fmt(tip.sys.ram_used * 100 / tip.sys.ram_total, "%") : "N/A"
                detail: tip.gib(tip.sys.ram_used) + " / " + tip.gib(tip.sys.ram_total) + " GiB"
            }

            Text {
                text: "Click for details"
                color: tip.dimColor
                font.pointSize: 7
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 1
            }
        }
    }
}
