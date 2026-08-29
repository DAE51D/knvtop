import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
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
    property var gpuProcs: []

    function matchesFilters(entry) {
        var user = Plasmoid.configuration.filterUser
        if (user && user !== "All Users" && entry.user !== user) return false
        var type = Plasmoid.configuration.filterType
        if ((type === "graphic" || type === "compute")
                && (!entry.type || entry.type.indexOf(type) === -1)) return false
        return true
    }

    // ONE process list, not two separate views: every GPU-touching process
    // (gpuProcs) merged by pid with the recognized-by-name LLM entries
    // (llama/ollama/vllm), which may not even show up in gpuProcs at all
    // (e.g. a pure HTTP router in front of the real GPU workers has no
    // open DRM fd of its own). "AI/LLM processes only" narrows this one
    // list down to entries with a recognized kind; it does not switch to
    // a different, disjoint list.
    readonly property var unifiedProcs: {
        var byPid = {}
        for (var i = 0; i < root.gpuProcs.length; i++) {
            var g = root.gpuProcs[i]
            byPid[g.pid] = Object.assign({ kind: null }, g)
        }
        function layer(list, kind) {
            for (var j = 0; j < list.length; j++) {
                var e = list[j]
                byPid[e.pid] = Object.assign({}, byPid[e.pid] || {}, e, { kind: kind })
            }
        }
        layer(root.llama.filter(function(l) { return l.model }), "llama")
        layer(root.ollama, "ollama")
        layer(root.vllm.filter(function(v) { return v.model }), "vllm")
        var out = []
        for (var pid in byPid) out.push(byPid[pid])
        return out
    }

    readonly property var visibleProcs: {
        var list = root.unifiedProcs
        if (Plasmoid.configuration.llmOnly)
            list = list.filter(function(p) { return p.kind !== null })
        list = list.filter(root.matchesFilters)
        // Stable order is what keeps cards from shuffling under a scroll:
        // this list is rebuilt from scratch every poll tick (a fresh
        // /proc scan, JS object key order isn't a reliable proxy for
        // "same as last tick"), so without an explicit sort the Repeater
        // sees a different-looking array each second even when the same
        // processes are still running.
        list.sort(function(a, b) { return a.pid - b.pid })
        return list
    }

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

    // Muted secondary text: theme-aware (unlike the compact widget/graph/
    // cards, which sit on their own fixed dark Rectangle and use fixed
    // colors on purpose) since the ring row and stats row sit directly on
    // Plasma's own popup background, which follows the system color scheme.
    readonly property color mutedTextColor: Qt.rgba(
        Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
        Kirigami.Theme.textColor.b, 0.65)

    // line visibility toggles — persisted via config/main.xml (Plasmoid.configuration)
    // so a toggle sticks across sessions, not just plain local properties

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
        gpuProcs = s.gpu_procs || [];
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
                    visible: Plasmoid.configuration.showGpu
                    values: root.histUtil
                    revision: root.revision
                    maximum: 100
                    lineColor: "#4d9fff"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: Plasmoid.configuration.showMem
                    values: root.histMem
                    revision: root.revision
                    maximum: 100
                    lineColor: "#e8c33a"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: Plasmoid.configuration.showTemp
                    values: root.histTemp
                    revision: root.revision
                    maximum: root.tempMax
                    lineColor: "#b07fe8"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: Plasmoid.configuration.showPower
                    values: root.histPower
                    revision: root.revision
                    maximum: 100
                    lineColor: "#3ddc84"
                    capacity: root.windowSize
                }
                Sparkline {
                    anchors.fill: parent
                    visible: Plasmoid.configuration.showCpu
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
                                opacity: Plasmoid.configuration[modelData.prop] ? 1 : 0.3
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pointSize: 7.5
                                color: Plasmoid.configuration[modelData.prop] ? "#8a9199" : "#4a4f55"
                                opacity: Plasmoid.configuration[modelData.prop] ? 1 : 0.4
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Plasmoid.configuration[modelData.prop] = !Plasmoid.configuration[modelData.prop]
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
        Layout.minimumWidth: inPanel ? 360 : 400
        Layout.preferredWidth: inPanel ? 430 : 490
        Layout.minimumHeight: 320
        Layout.preferredHeight: inPanel ? 440 : 540

        ScrollView {
            id: scrollView
            anchors.fill: parent
            // No explicit background here on purpose: the ring row and
            // stats row are meant to sit on Plasma's own popup background,
            // which follows the system light/dark color scheme (the graph
            // and cards below have their own fixed dark Rectangle, by
            // design, like nvtop's terminal panels). Ring.qml's text and
            // the stats Row's text use PlasmaCore.Theme colors so they stay
            // legible against either.
            // ColumnLayout { width: parent.width } inside a ScrollView is a
            // classic trap: "parent" here is the ScrollView's internal
            // Flickable, whose own width can settle smaller than the
            // ScrollView's actual width depending on how contentWidth gets
            // established, leaving content narrower than the popup with a
            // permanent gap on the right. ScrollView.availableWidth is
            // derived directly from the control's own (non-circular) width
            // and is the documented way to size content to fill it exactly.
            contentWidth: availableWidth

            ColumnLayout {
                width: scrollView.availableWidth
                spacing: 8

                // title top-left; configure + pin top-right (pin rightmost),
                // same button pattern as e.g. org.kde.desktopcontainment's
                // FolderViewLayer.qml
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "knvtop"
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: 10
                    }

                    Item { Layout.fillWidth: true }

                    PlasmaComponents.ToolButton {
                        icon.name: "configure"
                        onClicked: Plasmoid.internalAction("configure").trigger()
                        PlasmaComponents.ToolTip { text: "Configure…" }
                    }
                    PlasmaComponents.ToolButton {
                        checkable: true
                        icon.name: "window-pin"
                        onCheckedChanged: root.hideOnWindowDeactivate = !checked
                        PlasmaComponents.ToolTip { text: "Keep open" }
                    }
                }

                // 5 ring gauges in widget order: GPU MEM TMP PWR CPU (click to toggle line).
                // Not Layout.fillWidth: the row is only as wide as its 5 fixed-size
                // rings need — Qt.AlignHCenter centers that within the popup instead
                // of leaving it left-anchored with dead space to the right.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
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
                                active: Plasmoid.configuration[modelData.key]
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Plasmoid.configuration[modelData.key] = !Plasmoid.configuration[modelData.key]
                            }
                        }
                    }
                }

                // stats chips, centered like the ring row above. Row, not
                // Flow: Flow needs a width to decide when to wrap, and
                // without one explicitly set (same trap as the ScrollView
                // width issue above) it wrapped unpredictably even though
                // these 3 short chips comfortably fit on one line. Row's
                // implicitWidth is just the sum of its children, so it
                // doesn't have that problem.
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    spacing: 12

                    // Bold only the number that actually changes tick to
                    // tick (used/load); the total (78.0 GiB, 92.0 GiB) is
                    // fixed for this machine and stays normal weight so the
                    // live value is what pops out.
                    Text {
                        textFormat: Text.StyledText
                        text: "MEM " + (root.gpu.mem_used !== null && root.gpu.mem_total
                              ? "<b>" + (root.gpu.mem_used / 1024).toFixed(1) + "</b> GiB/"
                                + (root.gpu.mem_total / 1024).toFixed(1) + " GiB"
                              : "N/A")
                        color: root.mutedTextColor; font.pointSize: 8
                    }
                    Text {
                        textFormat: Text.StyledText
                        text: "sys <b>" + (root.sys.ram_used / 1073741824).toFixed(1) + "</b> GiB/"
                            + (root.sys.ram_total / 1073741824).toFixed(1) + " GiB"
                        color: root.mutedTextColor; font.pointSize: 8
                    }
                    Text {
                        textFormat: Text.StyledText
                        text: "load <b>" + root.sys.load1.toFixed(2) + "</b>"
                        color: root.mutedTextColor; font.pointSize: 8
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
                        Sparkline { anchors.fill: parent; visible: Plasmoid.configuration.showGpu; values: root.histUtil; revision: root.revision; maximum: 100; lineColor: "#4d9fff"; capacity: root.windowSize }
                        Sparkline { anchors.fill: parent; visible: Plasmoid.configuration.showMem; values: root.histMem; revision: root.revision; maximum: 100; lineColor: "#e8c33a"; capacity: root.windowSize }
                        Sparkline { anchors.fill: parent; visible: Plasmoid.configuration.showTemp; values: root.histTemp; revision: root.revision; maximum: root.tempMax; lineColor: "#b07fe8"; capacity: root.windowSize }
                        Sparkline { anchors.fill: parent; visible: Plasmoid.configuration.showPower; values: root.histPower; revision: root.revision; maximum: 100; lineColor: "#3ddc84"; capacity: root.windowSize }
                        Sparkline { anchors.fill: parent; visible: Plasmoid.configuration.showCpu; values: root.histCpu; revision: root.revision; maximum: 100; lineColor: "#ff8c42"; capacity: root.windowSize }
                    }
                }

                // One process list. "AI/LLM processes only" narrows it to
                // entries with a recognized kind (see root.visibleProcs);
                // it doesn't switch to a separate, disjoint view -- with it
                // off you get everything, LLM entries included.
                Repeater {
                    model: root.visibleProcs
                    delegate: LlmCard {
                        titleColor: modelData.kind === "llama" ? "#4d9fff"
                                  : modelData.kind === "ollama" ? "#e8c33a"
                                  : modelData.kind === "vllm" ? "#b07fe8"
                                  : Kirigami.Theme.positiveTextColor
                        // pid/port/model filename are already in the gray
                        // cmdline/flags text below for llama/vllm, so
                        // they're dropped from the bold title there; pid
                        // moves into the subtitle instead, de-emphasized
                        title: modelData.kind === "llama"
                                   ? "llama.cpp" + (modelData.alias ? "  [" + modelData.alias + "]" : "")
                             : modelData.kind === "ollama"
                                   ? "ollama" + (modelData.subcmd ? "  " + modelData.subcmd : "")
                             : modelData.kind === "vllm"
                                   ? "vllm" + (modelData.model ? "  [" + modelData.model + "]" : "")
                             : modelData.name
                        gpuPct: modelData.gpu_pct
                        vramKb: modelData.vram_kb
                        cpuPct: modelData.cpu_pct
                        hostMemKb: modelData.rss_kb
                        subtitle: modelData.kind === "llama"
                                      ? "ngl: " + (modelData.ngl || "N/A")
                                        + "   ctx: " + (modelData.ctx || "N/A")
                                        + "   parallel: " + (modelData.parallel || "N/A")
                                        + "   threads: " + (modelData.threads || "N/A")
                                        + "   pid: " + modelData.pid
                                  : modelData.kind === "ollama" || modelData.kind === "vllm"
                                      ? "pid: " + modelData.pid
                                  : "user: " + modelData.user
                                    + "   type: " + (modelData.type && modelData.type.length ? modelData.type.join("+") : "N/A")
                                    + "   pid: " + modelData.pid
                        cmdline: modelData.kind === "ollama" ? modelData.cmdline : ""
                        argv: modelData.argv || []
                    }
                }

                // ollama — one card per loaded model, same treatment as
                // llama.cpp/vllm (ollama doesn't expose CLI flags per model,
                // so the subtitle carries the equivalent info instead).
                // Not a "process" (no PID), so it sits outside unifiedProcs
                // and isn't affected by the checkbox or User/Type filters
                // -- always shown alongside whichever process view is up.
                Repeater {
                    model: root.ollamaModels
                    delegate: LlmCard {
                        titleColor: "#e8c33a"
                        title: "ollama  [" + modelData.name + "]"
                        subtitle: "params: " + (modelData.parameter_size || "N/A")
                             + "   quant: " + (modelData.quantization || "N/A")
                             + "   vram: " + (modelData.size_vram ? (modelData.size_vram / 1073741824).toFixed(1) + " GiB" : "N/A")
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
