import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: tip

    property var gpu: ({ util: null, mem_used: null, mem_total: null,
                          temp: null, power_w: null })
    property var sys: ({ ram_used: 0, ram_total: 0, cpu: null, load1: 0 })
    property var llama: []
    property var ollamaModels: []

    function mb(v) {
        if (v === null || v === undefined) return "N/A";
        return (v / 1073741824).toFixed(1) + " GiB";
    }

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6
        width: 280

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "knvtop"
                font.bold: true
                font.pointSize: 11
                Layout.fillWidth: true
            }
            Label {
                text: tip.llama.length ? tip.llama.length + " llama.cpp" : ""
                color: "#4d9fff"
                font.pointSize: 9
            }
        }

        // GPU row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: "GPU"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Label {
                text: tip.fmt(tip.gpu.util, "%")
                color: "#4d9fff"
                font.bold: true
                font.pointSize: 10
                Layout.preferredWidth: 36
            }
            Label {
                text: tip.gpu.temp !== null ? tip.fmt(tip.gpu.temp, "°C", 0) : ""
                color: "#6a7078"
                font.pointSize: 9
            }
            Item { Layout.fillWidth: true }
            Label {
                text: tip.gpu.mem_used !== null && tip.gpu.mem_total
                      ? tip.mb(tip.gpu.mem_used) + "/" + tip.mb(tip.gpu.mem_total)
                      : ""
                color: "#e8c33a"
                font.pointSize: 9
            }
        }

        // GPU bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * ((tip.gpu.util || 0) / 100)
                height: parent.height
                color: "#4d9fff"
                radius: 2
            }
        }

        // MEM bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * ((tip.gpu.mem_used !== null && tip.gpu.mem_total)
                                        ? tip.gpu.mem_used / tip.gpu.mem_total : 0)
                height: parent.height
                color: "#e8c33a"
                radius: 2
            }
        }

        // PWR row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: "PWR"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Label {
                text: tip.fmt(tip.gpu.power_w, "W", 1)
                color: "#3ddc84"
                font.bold: true
                font.pointSize: 10
            }
            Item { Layout.fillWidth: true }
            Label {
                text: tip.gpu.power_cap_w ? "/" + tip.fmt(tip.gpu.power_cap_w, "W") : ""
                color: "#6a7078"
                font.pointSize: 9
            }
        }

        // CPU row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: "CPU"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Label {
                text: tip.fmt(tip.sys.cpu, "%", 1)
                color: "#ff8c42"
                font.bold: true
                font.pointSize: 10
            }
            Item { Layout.fillWidth: true }
            Label {
                text: "load " + tip.sys.load1.toFixed(2)
                color: "#6a7078"
                font.pointSize: 9
            }
        }

        // CPU bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * ((tip.sys.cpu || 0) / 100)
                height: parent.height
                color: "#ff8c42"
                radius: 2
            }
        }

        // RAM row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: "RAM"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Label {
                text: tip.mb(tip.sys.ram_used) + "/" + tip.mb(tip.sys.ram_total)
                color: "#c8ccd2"
                font.pointSize: 9
            }
        }

        // RAM bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * ((tip.sys.ram_total ? tip.sys.ram_used / tip.sys.ram_total : 0))
                height: parent.height
                color: "#b07fe8"
                radius: 2
            }
        }

        // LLM summary
        Label {
            Layout.fillWidth: true
            visible: tip.llama.length > 0 || tip.ollamaModels.length > 0
            text: {
                var parts = [];
                if (tip.llama.length)
                    parts.push(tip.llama.length + " llama.cpp" +
                               (tip.llama[0].alias ? " [" + tip.llama[0].alias + "]" : ""));
                if (tip.ollamaModels.length)
                    parts.push(tip.ollamaModels.length + " ollama model(s)");
                return parts.join("  ");
            }
            color: "#6a7078"
            font.pointSize: 8
        }

        Label {
            text: "Click for details"
            color: "#4a4f55"
            font.pointSize: 8
            Layout.topMargin: 4
        }
    }
}
