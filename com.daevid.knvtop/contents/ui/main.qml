import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as PlasmaDBus

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    property var gpu: ({ util: null, mem_used: null, mem_total: null,
                          temp: null, power_w: null, power_cap_w: null })
    property var sys: ({ ram_used: 0, ram_total: 0, swap_used: 0, swap_total: 0,
                          load1: 0, load5: 0, load15: 0, cpu: null })
    property var llama: []
    property var ollama: []
    property var vllm: []
    property var ollamaModels: []

    readonly property int windowSize: 21
    property var histUtil: []
    property var histMem: []
    property var histTemp: []
    property var histPower: []
    property var histCpu: []

    property bool pollerAlive: false

    readonly property int tempMax: 100
    readonly property double tempFloor: 30

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    function mb(v) {
        if (v === null || v === undefined) return "N/A";
        return (v / 1073741824).toFixed(1) + " GiB";
    }

    function pctNorm(v, floor, max) {
        if (v === null || v === undefined) return 0;
        var p = (v - floor) * 100 / (max - floor);
        return Math.max(0, Math.min(100, p));
    }

    function latest(arr) {
        if (!arr || arr.length === 0) return 0;
        var v = arr[arr.length - 1];
        return v === null || v === undefined ? 0 : Number(v);
    }

    function histVal(metric, i) {
        var arr = metric === 0 ? histUtil : metric === 1 ? histMem
                : metric === 2 ? histTemp : metric === 3 ? histPower : histCpu;
        if (!arr || arr.length === 0) return null;
        var idx = arr.length - windowSize + i;
        if (idx < 0) return null;
        var v = arr[idx];
        if (v === null || v === undefined) return null;
        if (metric === 2) return pctNorm(v, tempFloor, tempMax);
        return v;
    }

    function pushSample(s) {
        if (s.gpu) gpu = s.gpu;
        if (s.sys) sys = s.sys;
        if (s.llm) {
            llama = s.llm.llama || [];
            ollama = s.llm.ollama || [];
            vllm = s.llm.vllm || [];
            ollamaModels = s.llm.ollama_models || [];
        }
        function push(arr, v) {
            arr.push(v === null || v === undefined ? null : Number(v));
            while (arr.length > windowSize) arr.shift();
        }
        push(histUtil, gpu.util);
        push(histMem, (gpu.mem_used !== null && gpu.mem_total)
                      ? gpu.mem_used * 100 / gpu.mem_total : null);
        push(histTemp, gpu.temp);
        push(histPower, (gpu.power_w !== null && gpu.power_cap_w)
                         ? Math.min(100, gpu.power_w * 100 / gpu.power_cap_w) : null);
        push(histCpu, sys.cpu);
    }

    function restartPoller() {
        pollerAlive = false;
        var msg = new PlasmaDBus.dbusMessage({
            service: "com.daevid.knvtop",
            path: "/com/daevid/knvtop",
            iface: "com.daevid.knvtop.Status",
            member: "Restart",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, () => {}, () => {});
    }

    function poll() {
        var msg = new PlasmaDBus.dbusMessage({
            service: "com.daevid.knvtop",
            path: "/com/daevid/knvtop",
            iface: "com.daevid.knvtop.Sample",
            member: "Get",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            try {
                if (!reply.isError && reply.values && reply.values.length > 0) {
                    var s = JSON.parse(reply.values[0]);
                    pushSample(s);
                    pollerAlive = true;
                }
            } catch (e) {
                pollerAlive = false;
            }
        }, () => {
            pollerAlive = false;
        });
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    // ---- compact: sparkline graph (thin bars, no Canvas/Shape) --------
    compactRepresentation: Item {
        id: compact
        Layout.fillWidth: inPanel
        Layout.fillHeight: inPanel
        Layout.minimumWidth: inPanel ? 160 : 280
        Layout.minimumHeight: inPanel ? 50 : 120
        Layout.preferredWidth: inPanel ? 220 : 360
        Layout.preferredHeight: inPanel ? 70 : 160
        width: inPanel ? 220 : 360
        height: inPanel ? 70 : 160

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "#101418"
            radius: 3

            // 5 horizontal strips, each a 21-bar sparkline
            Column {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 1

                Repeater {
                    model: 5
                    delegate: Item {
                        width: parent.width
                        height: parent.height / 5

                        // label on the left
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData === 0 ? "GPU"
                                 : modelData === 1 ? "MEM"
                                 : modelData === 2 ? "TMP"
                                 : modelData === 3 ? "PWR"
                                 : "CPU"
                            font.pointSize: 6
                            font.bold: true
                            color: modelData === 0 ? "#4d9fff"
                                 : modelData === 1 ? "#e8c33a"
                                 : modelData === 2 ? "#b07fe8"
                                 : modelData === 3 ? "#3ddc84"
                                 : "#ff8c42"
                            width: 22
                        }

                        // current value on the right
                        Label {
                            anchors.right: parent.right
                            anchors.rightMargin: 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData === 0 ? root.fmt(root.latest(root.histUtil), "%")
                                 : modelData === 1 ? root.fmt(root.latest(root.histMem), "%")
                                 : modelData === 2 ? root.fmt(root.latest(root.histTemp), "°C", 1)
                                 : modelData === 3 ? root.fmt(root.latest(root.histPower), "%")
                                 : root.fmt(root.latest(root.histCpu), "%", 1)
                            font.pointSize: 6
                            color: "#c8ccd2"
                            width: 30
                            horizontalAlignment: Text.AlignRight
                        }

                        // sparkline bars
                        Item {
                            id: barArea
                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 32

                            Repeater {
                                model: root.windowSize
                                delegate: Rectangle {
                                    width: Math.max(1, barArea.width / root.windowSize - 1)
                                    height: barArea.height * (root.histVal(modelData, index) !== null ? root.histVal(modelData, index) / 100 : 0)
                                    x: index * (barArea.width / root.windowSize)
                                    anchors.bottom: parent.bottom
                                    color: modelData === 0 ? "#4d9fff"
                                         : modelData === 1 ? "#e8c33a"
                                         : modelData === 2 ? "#b07fe8"
                                         : modelData === 3 ? "#3ddc84"
                                         : "#ff8c42"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- full representation: detail panel ---------------------------
    fullRepresentation: ScrollView {
        width: inPanel ? 420 : 480
        height: inPanel ? 320 : 420

        ColumnLayout {
            width: parent.width

            RowLayout {
                Layout.fillWidth: true
                Label { text: "knvtop"; font.bold: true; Layout.preferredWidth: 80 }
                Label {
                    text: "GPU " + fmt(gpu.util, "%") + "  "
                         + mb(gpu.mem_used) + "/" + mb(gpu.mem_total)
                         + "  " + fmt(gpu.temp, "°C", 1)
                         + "  " + fmt(gpu.power_w, " W", 1)
                         + (gpu.power_cap_w ? " / " + fmt(gpu.power_cap_w, " W") : "")
                         + "  CPU " + fmt(sys.cpu, "%", 1)
                    color: "#c8ccd2"
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: pollerAlive ? "● live" : "○ poller down"
                    color: pollerAlive ? "#3ddc84" : "#e85555"
                }
            }

            // history graph: 5 rows of horizontal bars
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: 5
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            text: modelData === 0 ? "GPU"
                                 : modelData === 1 ? "MEM"
                                 : modelData === 2 ? "TMP"
                                 : modelData === 3 ? "PWR"
                                 : "CPU"
                            font.pointSize: 8
                            color: "#8a9199"
                            Layout.preferredWidth: 30
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            Repeater {
                                model: root.windowSize
                                delegate: Rectangle {
                                    width: Math.max(1, parent.width / root.windowSize - 1)
                                    height: parent.height * (
                                        (modelData === 0 ? (root.histUtil.length > root.windowSize - 1 - index ? (root.histUtil[root.histUtil.length - 1 - (root.windowSize - 1 - index)] || 0) / 100 : 0)
                                         : modelData === 1 ? (root.histMem.length > root.windowSize - 1 - index ? (root.histMem[root.histMem.length - 1 - (root.windowSize - 1 - index)] || 0) / 100 : 0)
                                         : modelData === 2 ? (root.histTemp.length > root.windowSize - 1 - index ? root.pctNorm(root.histTemp[root.histTemp.length - 1 - (root.windowSize - 1 - index)], root.tempFloor, root.tempMax) / 100 : 0)
                                         : modelData === 3 ? (root.histPower.length > root.windowSize - 1 - index ? (root.histPower[root.histPower.length - 1 - (root.windowSize - 1 - index)] || 0) / 100 : 0)
                                         : (root.histCpu.length > root.windowSize - 1 - index ? (root.histCpu[root.histCpu.length - 1 - (root.windowSize - 1 - index)] || 0) / 100 : 0))
                                    )
                                    color: modelData === 0 ? "#4d9fff"
                                         : modelData === 1 ? "#e8c33a"
                                         : modelData === 2 ? "#b07fe8"
                                         : modelData === 3 ? "#3ddc84"
                                         : "#ff8c42"
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: root.llama
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "llama.cpp  pid " + modelData.pid
                             + (modelData.alias ? "  [" + modelData.alias + "]" : "")
                             + (modelData.port ? "  :port " + modelData.port : "")
                        color: "#4d9fff"; font.bold: true; font.pointSize: 9
                    }
                    Label {
                        text: "model: " + (modelData.model || "N/A")
                             + "\nngl: " + (modelData.ngl || "N/A")
                             + "   ctx: " + (modelData.ctx || "N/A")
                             + "   parallel: " + (modelData.parallel || "N/A")
                             + "\n" + modelData.cmdline
                        color: "#aeb4bb"; font.pointSize: 8; font.family: "monospace"
                    }
                }
            }

            Repeater {
                model: root.ollama
                delegate: Label {
                    Layout.fillWidth: true
                    text: "ollama  pid " + modelData.pid
                         + (modelData.subcmd ? "  " + modelData.subcmd : "")
                         + "   " + modelData.cmdline
                    color: "#e8c33a"; font.pointSize: 8; font.family: "monospace"
                }
            }

            Repeater {
                model: root.ollamaModels
                delegate: Label {
                    Layout.fillWidth: true
                    text: "  loaded: " + modelData.name
                         + "  " + (modelData.quantization || "")
                         + "  " + (modelData.parameter_size || "")
                         + "  vram " + (modelData.size_vram ? (modelData.size_vram / 1073741824).toFixed(1) + " GiB" : "N/A")
                    color: "#c8ccd2"; font.pointSize: 8
                }
            }

            Repeater {
                model: root.vllm
                delegate: Label {
                    Layout.fillWidth: true
                    text: "vllm  pid " + modelData.pid + "  " + modelData.cmdline
                    color: "#b07fe8"; font.pointSize: 8; font.family: "monospace"
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 4 }

            Label {
                text: "RAM " + root.mb(root.sys.ram_used) + " / " + root.mb(root.sys.ram_total)
                     + "   swap " + root.mb(root.sys.swap_used) + " / " + root.mb(root.sys.swap_total)
                     + "   load " + root.sys.load1.toFixed(2) + " " + root.sys.load5.toFixed(2) + " " + root.sys.load15.toFixed(2)
                color: "#8a9199"; font.pointSize: 9; Layout.fillWidth: true
            }
        }
    }

    toolTipMainText: "GPU " + fmt(gpu.util, "%") + "  "
        + fmt((gpu.mem_used !== null && gpu.mem_total) ? gpu.mem_used * 100 / gpu.mem_total : null, "%")
        + " mem  " + fmt(gpu.temp, "°C", 1) + "  " + fmt(gpu.power_w, "W", 1)
        + "  CPU " + fmt(sys.cpu, "%", 1)
    toolTipSubText: "RAM " + mb(sys.ram_used) + "/" + mb(sys.ram_total)
        + "  load " + sys.load1.toFixed(2)
        + (llama.length ? "  " + llama.length + " llama.cpp" : "")
        + (ollamaModels.length ? "  " + ollamaModels.length + " ollama model(s)" : "")

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Restart poller")
            icon.name: "view-refresh"
            onTriggered: root.restartPoller()
        }
    ]
}
