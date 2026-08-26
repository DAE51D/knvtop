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

    // ---- data state -------------------------------------------------
    property var gpu: ({ util: null, mem_used: null, mem_total: null,
                          temp: null, power_w: null, power_cap_w: null })
    property var sys: ({ ram_used: 0, ram_total: 0, swap_used: 0, swap_total: 0,
                          load1: 0, load5: 0, load15: 0, cpu: null })
    property var llama: []
    property var ollama: []
    property var vllm: []
    property var ollamaModels: []

    // 21-second ring buffer, one sample per second
    readonly property int windowSize: 21
    property var histUtil: []
    property var histMem: []
    property var histTemp: []
    property var histPower: []
    property var histCpu: []

    property bool pollerAlive: false

    // y-axis ranges
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
        if (compactGraph) compactGraph.requestPaint();
        if (bigGraph) bigGraph.requestPaint();
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

    // ---- data bridge: D-Bus polling ---------------------------------
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
                    var json = reply.values[0];
                    var s = JSON.parse(json);
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
        id: pollTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (compactGraph) compactGraph.requestPaint();
            if (bigGraph) bigGraph.requestPaint();
        }
    }

    // ---- graph drawing helpers ---------------------------------------
    function drawLines(ctx, w, h) {
        function px(i) { return 2 + (w - 4) * i / (windowSize - 1); }
        function py(v) { return h - 2 - (h - 4) * v / 100; }
        function line(data, color, yOf) {
            ctx.strokeStyle = color;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            var started = false;
            for (var i = 0; i < windowSize; i++) {
                var v = data[i];
                if (v === null || v === undefined) { started = false; continue; }
                var x = px(i);
                var y = py(yOf(v));
                if (!started) { ctx.moveTo(x, y); started = true; }
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
        // grid
        ctx.strokeStyle = "#2a2f35";
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (var g = 0; g <= 4; g++) {
            var y = py(g * 25);
            ctx.moveTo(2, y); ctx.lineTo(w - 2, y);
        }
        ctx.stroke();
        // axis labels
        ctx.fillStyle = "#8a9199";
        ctx.font = "9px sans-serif";
        ctx.textAlign = "left";
        for (var t = 0; t <= 100; t += 25) {
            ctx.fillText(String(t), 3, py(t) - 2);
        }
        // lines: util blue, mem yellow, temp purple, power green, cpu orange
        line(histUtil, "#4d9fff", function(v) { return v; });
        line(histMem,  "#e8c33a", function(v) { return v; });
        line(histTemp, "#b07fe8", function(v) { return (v - tempFloor) * 100 / (tempMax - tempFloor); });
        line(histPower, "#3ddc84", function(v) { return v; });
        line(histCpu,  "#ff8c42", function(v) { return v; });
    }

    // ---- compact representation: the graph ---------------------------
    compactRepresentation: Item {
        implicitWidth: inPanel ? 200 : 320
        implicitHeight: inPanel ? 80 : 180
        width: inPanel ? 200 : 320
        height: inPanel ? 80 : 180

        Canvas {
            id: compactGraph
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = "#101418";
                ctx.fillRect(0, 0, width, height);
                var ws = root.windowSize;
                var hu = root.histUtil;
                var hm = root.histMem;
                var ht = root.histTemp;
                var hp = root.histPower;
                var hc = root.histCpu;
                var tf = root.tempFloor;
                var tm = root.tempMax;
                function px(i) { return 2 + (width - 4) * i / (ws - 1); }
                function py(v) { return height - 2 - (height - 4) * v / 100; }
                // grid
                ctx.strokeStyle = "#2a2f35";
                ctx.lineWidth = 1;
                ctx.beginPath();
                for (var g = 0; g <= 4; g++) {
                    var gy = py(g * 25);
                    ctx.moveTo(2, gy); ctx.lineTo(width - 2, gy);
                }
                ctx.stroke();
                function draw(data, color, yOf) {
                    ctx.strokeStyle = color;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    var st = false;
                    for (var i = 0; i < ws; i++) {
                        var v = data[i];
                        if (v === null || v === undefined) { st = false; continue; }
                        var x = px(i);
                        var y = py(yOf(v));
                        if (!st) { ctx.moveTo(x, y); st = true; }
                        else ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }
                draw(hu, "#4d9fff", function(v) { return v; });
                draw(hm, "#e8c33a", function(v) { return v; });
                draw(ht, "#b07fe8", function(v) { return (v - tf) * 100 / (tm - tf); });
                draw(hp, "#3ddc84", function(v) { return v; });
                draw(hc, "#ff8c42", function(v) { return v; });
                // legend
                ctx.font = "9px sans-serif";
                ctx.textAlign = "left";
                var lx = 14, ly = 0;
                ctx.fillStyle = "#4d9fff"; ctx.fillText("GPU", lx, ly + 10);
                ctx.fillStyle = "#e8c33a"; ctx.fillText("MEM", lx + 25, ly + 10);
                ctx.fillStyle = "#b07fe8"; ctx.fillText("TMP", lx + 50, ly + 10);
                ctx.fillStyle = "#3ddc84"; ctx.fillText("PWR", lx + 75, ly + 10);
                ctx.fillStyle = "#ff8c42"; ctx.fillText("CPU", lx + 100, ly + 10);
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                color: "#101418"
                Canvas {
                    id: bigGraph
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = "#101418";
                        ctx.fillRect(0, 0, width, height);
                        drawLines(ctx, width, height);
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

    // ---- hover / tooltip ---------------------------------------------
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
