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
    property int revision: 0

    property bool pollerAlive: false

    readonly property int tempMax: 100
    readonly property double tempFloor: 30

    // line visibility toggles
    property bool showGpu: true
    property bool showMem: true
    property bool showTemp: true
    property bool showPower: true
    property bool showCpu: true

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
        var pwrMax = gpu.power_cap_w || 100;
        push(histPower, (gpu.power_w !== null)
                         ? Math.min(100, gpu.power_w * 100 / pwrMax) : null);
        push(histCpu, sys.cpu);
        revision++;
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

    // ---- compact: overlaid graph + clickable legend -------------------
    compactRepresentation: Item {
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

            Item {
                id: graphArea
                anchors.fill: parent
                anchors.bottomMargin: 12

                Sparkline {
                    anchors.fill: parent
                    visible: root.showGpu
                    values: root.histUtil
                    revision: root.revision
                    maximum: 100
                    lineColor: "#4d9fff"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: root.showMem
                    values: root.histMem
                    revision: root.revision
                    maximum: 100
                    lineColor: "#e8c33a"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: root.showTemp
                    values: root.histTemp
                    revision: root.revision
                    maximum: root.tempMax
                    lineColor: "#b07fe8"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: root.showPower
                    values: root.histPower
                    revision: root.revision
                    maximum: 100
                    lineColor: "#3ddc84"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: root.showCpu
                    values: root.histCpu
                    revision: root.revision
                    maximum: 100
                    lineColor: "#ff8c42"
                    capacity: root.windowSize
                }
            }

            // clickable legend
            Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: 4
                spacing: 4

                Repeater {
                    model: [
                        { label: "GPU", color: "#4d9fff", prop: "showGpu" },
                        { label: "MEM", color: "#e8c33a", prop: "showMem" },
                        { label: "TMP", color: "#b07fe8", prop: "showTemp" },
                        { label: "PWR", color: "#3ddc84", prop: "showPower" },
                        { label: "CPU", color: "#ff8c42", prop: "showCpu" },
                    ]
                    delegate: Item {
                        width: 28
                        height: 10
                        Row {
                            anchors.fill: parent
                            spacing: 1
                            Rectangle {
                                width: 6; height: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.color
                                opacity: root[modelData.prop] ? 1 : 0.3
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pointSize: 6
                                color: root[modelData.prop] ? "#8a9199" : "#4a4f55"
                                opacity: root[modelData.prop] ? 1 : 0.4
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root[modelData.prop] = !root[modelData.prop]
                        }
                    }
                }
            }
        }
    }

    // ---- full representation: detail panel ---------------------------
    fullRepresentation: ScrollView {
        width: inPanel ? 480 : 560
        height: inPanel ? 400 : 500

        ColumnLayout {
            width: parent.width
            spacing: 8

            // header
            RowLayout {
                Layout.fillWidth: true
                Label { text: "knvtop"; font.bold: true; font.pointSize: 12 }
                Item { Layout.fillWidth: true }
                Label {
                    text: pollerAlive ? "● live" : "○ poller down"
                    color: pollerAlive ? "#3ddc84" : "#e85555"
                    font.pointSize: 9
                }
            }

            // ring gauges row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // CPU ring
                Item {
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 70
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2, cy = height / 2
                            var r = Math.min(cx, cy) - 4
                            var cpu = root.sys.cpu || 0
                            ctx.lineWidth = 5
                            ctx.strokeStyle = "#2a2f35"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.strokeStyle = "#ff8c42"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + (cpu / 100) * Math.PI * 2)
                            ctx.stroke()
                            ctx.fillStyle = "#c8ccd2"
                            ctx.font = "bold 14px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText(Math.round(cpu) + "%", cx, cy - 4)
                            ctx.font = "8px sans-serif"
                            ctx.fillStyle = "#8a9199"
                            ctx.fillText("CPU", cx, cy + 10)
                        }
                    }
                }

                // GPU ring
                Item {
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 70
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2, cy = height / 2
                            var r = Math.min(cx, cy) - 4
                            var util = root.gpu.util || 0
                            ctx.lineWidth = 5
                            ctx.strokeStyle = "#2a2f35"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.strokeStyle = "#4d9fff"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + (util / 100) * Math.PI * 2)
                            ctx.stroke()
                            ctx.fillStyle = "#c8ccd2"
                            ctx.font = "bold 14px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText(Math.round(util) + "%", cx, cy - 4)
                            ctx.font = "8px sans-serif"
                            ctx.fillStyle = "#8a9199"
                            ctx.fillText("GPU", cx, cy + 10)
                        }
                    }
                }

                // MEM ring
                Item {
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 70
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2, cy = height / 2
                            var r = Math.min(cx, cy) - 4
                            var memPct = (root.gpu.mem_used !== null && root.gpu.mem_total)
                                          ? root.gpu.mem_used * 100 / root.gpu.mem_total : 0
                            ctx.lineWidth = 5
                            ctx.strokeStyle = "#2a2f35"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.strokeStyle = "#e8c33a"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + (memPct / 100) * Math.PI * 2)
                            ctx.stroke()
                            ctx.fillStyle = "#c8ccd2"
                            ctx.font = "bold 14px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText(Math.round(memPct) + "%", cx, cy - 4)
                            ctx.font = "8px sans-serif"
                            ctx.fillStyle = "#8a9199"
                            ctx.fillText("MEM", cx, cy + 10)
                        }
                    }
                }

                // stats column
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "GPU " + (root.gpu.mem_used !== null && root.gpu.mem_total ? root.mb(root.gpu.mem_used) + "/" + root.mb(root.gpu.mem_total) : "N/A")
                             + "  " + root.fmt(root.gpu.temp, "°C", 1)
                             + "  " + root.fmt(root.gpu.power_w, "W", 1)
                        color: "#c8ccd2"; font.pointSize: 9
                    }
                    Label {
                        text: "sys RAM " + root.mb(root.sys.ram_used) + "/" + root.mb(root.sys.ram_total)
                             + "  load " + root.sys.load1.toFixed(2) + " " + root.sys.load5.toFixed(2) + " " + root.sys.load15.toFixed(2)
                        color: "#8a9199"; font.pointSize: 9
                    }
                }
            }

            // graph section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: "#101418"
                radius: 3
                Item {
                    anchors.fill: parent
                    anchors.margins: 2
                    Sparkline { anchors.fill: parent; visible: root.showGpu; values: root.histUtil; revision: root.revision; maximum: 100; lineColor: "#4d9fff"; capacity: root.windowSize }
                    Sparkline { anchors.fill: parent; visible: root.showMem; values: root.histMem; revision: root.revision; maximum: 100; lineColor: "#e8c33a"; capacity: root.windowSize }
                    Sparkline { anchors.fill: parent; visible: root.showTemp; values: root.histTemp; revision: root.revision; maximum: root.tempMax; lineColor: "#b07fe8"; capacity: root.windowSize }
                    Sparkline { anchors.fill: parent; visible: root.showPower; values: root.histPower; revision: root.revision; maximum: 100; lineColor: "#3ddc84"; capacity: root.windowSize }
                    Sparkline { anchors.fill: parent; visible: root.showCpu; values: root.histCpu; revision: root.revision; maximum: 100; lineColor: "#ff8c42"; capacity: root.windowSize }
                }
            }

            // llama.cpp section
            Repeater {
                model: root.llama
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: "#1a1f25"
                    radius: 3
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Label {
                            text: "llama.cpp  pid " + modelData.pid
                                 + (modelData.alias ? "  [" + modelData.alias + "]" : "")
                                 + (modelData.port ? "  :port " + modelData.port : "")
                                 + (modelData.model ? "  " + modelData.model.split("/").pop() : "")
                            color: "#4d9fff"; font.bold: true; font.pointSize: 9
                        }
                        Label {
                            text: "ngl: " + (modelData.ngl || "N/A")
                                 + "   ctx: " + (modelData.ctx || "N/A")
                                 + "   parallel: " + (modelData.parallel || "N/A")
                                 + "   rss: " + (modelData.rss_kb ? (modelData.rss_kb / 1048576).toFixed(1) + " GiB" : "N/A")
                                 + "   threads: " + (modelData.threads || "N/A")
                            color: "#aeb4bb"; font.pointSize: 8
                        }
                        Label {
                            text: modelData.cmdline
                            color: "#6a7078"; font.pointSize: 7; font.family: "monospace"
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ollama section
            Repeater {
                model: root.ollama
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#1a1f25"
                    radius: 3
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Label {
                            text: "ollama  pid " + modelData.pid
                                 + (modelData.subcmd ? "  " + modelData.subcmd : "")
                            color: "#e8c33a"; font.bold: true; font.pointSize: 9
                        }
                        Label {
                            text: modelData.cmdline
                            color: "#6a7078"; font.pointSize: 7; font.family: "monospace"
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ollama loaded models
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

            // vllm section
            Repeater {
                model: root.vllm
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#1a1f25"
                    radius: 3
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Label {
                            text: "vllm  pid " + modelData.pid
                            color: "#b07fe8"; font.bold: true; font.pointSize: 9
                        }
                        Label {
                            text: modelData.cmdline
                            color: "#6a7078"; font.pointSize: 7; font.family: "monospace"
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // ---- hover tooltip: bar-style values ------------------------------
    toolTipMainText: "GPU " + fmt(gpu.util, "%") + "  "
        + (gpu.mem_used !== null && gpu.mem_total ? mb(gpu.mem_used) + "/" + mb(gpu.mem_total) : "N/A")
        + "  " + fmt(gpu.temp, "°C", 1) + "  " + fmt(gpu.power_w, "W", 1)
        + "  CPU " + fmt(sys.cpu, "%", 1)
    toolTipSubText: "sys RAM " + mb(sys.ram_used) + "/" + mb(sys.ram_total)
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
