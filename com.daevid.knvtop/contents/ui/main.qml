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
        return (v / 1024).toFixed(1) + " GiB";
    }

    function bytes(v) {
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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.expanded = !root.expanded
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
                                font.pointSize: 7.5
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
    // Plasma sizes the popup dialog from Layout.preferred/minimumWidth/Height
    // hints on this root item, not from a raw width/height assignment — an
    // Item wrapper carrying those hints (matching corestrip's FullView.qml)
    // is what keeps the dialog from ending up wider than the ScrollView
    // actually filling it.
    fullRepresentation: Item {
        Layout.minimumWidth: inPanel ? 400 : 460
        Layout.preferredWidth: inPanel ? 560 : 640
        Layout.minimumHeight: 320
        Layout.preferredHeight: inPanel ? 440 : 540

        ScrollView {
            anchors.fill: parent

            ColumnLayout {
                width: parent.width
                spacing: 8

                // 5 ring gauges in widget order: GPU MEM TMP PWR CPU (click to toggle line)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 8

                    Repeater {
                        model: [
                            { key: "showGpu", label: "GPU", color: "#4d9fff",
                              ratio: (root.gpu.util || 0) / 100,
                              text: root.fmt(root.gpu.util, "%") },
                            { key: "showMem", label: "MEM", color: "#e8c33a",
                              ratio: (root.gpu.mem_used !== null && root.gpu.mem_total)
                                     ? Math.min(1, root.gpu.mem_used / root.gpu.mem_total) : 0,
                              text: (root.gpu.mem_used !== null && root.gpu.mem_total)
                                    ? root.fmt(root.gpu.mem_used * 100 / root.gpu.mem_total, "%") : "N/A" },
                            { key: "showTemp", label: "TMP", color: "#b07fe8",
                              ratio: Math.min(1, (root.gpu.temp || 0) / root.tempMax),
                              text: root.fmt(root.gpu.temp, "°") },
                            { key: "showPower", label: "PWR", color: "#3ddc84",
                              ratio: Math.min(1, (root.gpu.power_w || 0) / (root.gpu.power_cap_w || 100)),
                              text: root.fmt(root.gpu.power_w, "W") },
                            { key: "showCpu", label: "CPU", color: "#ff8c42",
                              ratio: (root.sys.cpu || 0) / 100,
                              text: root.fmt(root.sys.cpu, "%") },
                        ]
                        delegate: Item {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 64
                            Ring {
                                anchors.fill: parent
                                ratio: modelData.ratio
                                ringColor: modelData.color
                                valueText: modelData.text
                                label: modelData.label
                                active: root[modelData.key]
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root[modelData.key] = !root[modelData.key]
                            }
                        }
                    }
                }

                // stats chips — wraps per-chip instead of mid-word, and never
                // visually crowds the ring row above it
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 12

                    Text {
                        text: "MEM " + (root.gpu.mem_used !== null && root.gpu.mem_total
                              ? root.mb(root.gpu.mem_used) + "/" + root.mb(root.gpu.mem_total) : "N/A")
                        color: "#8a9199"; font.pointSize: 8
                    }
                    Text {
                        text: "TMP " + root.fmt(root.gpu.temp, "°C", 1)
                        color: "#8a9199"; font.pointSize: 8
                    }
                    Text {
                        text: "PWR " + root.fmt(root.gpu.power_w, "W", 1)
                        color: "#8a9199"; font.pointSize: 8
                    }
                    Text {
                        text: "sys " + root.bytes(root.sys.ram_used) + "/" + root.bytes(root.sys.ram_total)
                        color: "#8a9199"; font.pointSize: 8
                    }
                    Text {
                        text: "load " + root.sys.load1.toFixed(2)
                        color: "#8a9199"; font.pointSize: 8
                    }
                }

                // graph section
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
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

                // llama.cpp — only show instances with a model loaded
                Repeater {
                    model: root.llama.filter(function(l) { return l.model !== null && l.model !== undefined && l.model !== "" })
                    delegate: LlmCard {
                        titleColor: "#4d9fff"
                        title: "llama.cpp  pid " + modelData.pid
                             + (modelData.alias ? "  [" + modelData.alias + "]" : "")
                             + (modelData.port ? "  :port " + modelData.port : "")
                             + (modelData.model ? "  " + modelData.model.split("/").pop() : "")
                        subtitle: "ngl: " + (modelData.ngl || "N/A")
                             + "   ctx: " + (modelData.ctx || "N/A")
                             + "   parallel: " + (modelData.parallel || "N/A")
                             + "   rss: " + (modelData.rss_kb ? (modelData.rss_kb / 1048576).toFixed(1) + " GiB" : "N/A")
                             + "   threads: " + (modelData.threads || "N/A")
                        cmdline: modelData.cmdline
                    }
                }

                // ollama — only show if there are loaded models
                Repeater {
                    model: root.ollamaModels.length > 0 ? root.ollama : []
                    delegate: LlmCard {
                        titleColor: "#e8c33a"
                        title: "ollama  pid " + modelData.pid
                             + (modelData.subcmd ? "  " + modelData.subcmd : "")
                        cmdline: modelData.cmdline
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

                // vllm — only show instances with a model
                Repeater {
                    model: root.vllm.filter(function(v) { return v.model !== null && v.model !== undefined && v.model !== "" })
                    delegate: LlmCard {
                        titleColor: "#b07fe8"
                        title: "vllm  pid " + modelData.pid
                             + (modelData.model ? "  " + modelData.model : "")
                        cmdline: modelData.cmdline
                    }
                }
            }
        }
    }

    // ---- hover tooltip: custom QML view --------------------------------
    toolTipItem: ToolTipView {
        gpu: root.gpu
        sys: root.sys
        llama: root.llama
        ollamaModels: root.ollamaModels
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Restart poller")
            icon.name: "view-refresh"
            onTriggered: root.restartPoller()
        }
    ]
}
