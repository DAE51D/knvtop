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
    // Live per-process stats row, shown between the title and subtitle
    // when any of them is available (all null → row hidden). null renders
    // as N/A -- e.g. GPU%/VRAM read /proc/<pid>/fdinfo, which the kernel
    // restricts to same-uid-or-root, so a process owned by a different
    // user than this poller (a real, current case: llama.cpp running
    // under its own service account) always shows N/A for those two.
    property var gpuPct: null
    property var vramKb: null
    property var cpuPct: null
    property var hostMemKb: null

    function fmtPct(v) { return (v === null || v === undefined) ? "N/A" : v.toFixed(0) + "%" }
    function fmtMiB(kb) { return (kb === null || kb === undefined) ? "N/A" : (kb / 1024).toFixed(0) + " MiB" }
    // Raw argv (not the flattened cmdline string) so each flag can be
    // paired with its own value unambiguously -- a value containing spaces
    // (e.g. a JSON flag argument) is one argv element but can't be
    // re-split correctly out of a joined string. argv[0] (the binary path)
    // is skipped.
    property var argv: []

    // A token starting with "-" that isn't a bare negative number (e.g.
    // "-0.5") is a flag name; the next token is its value unless that next
    // token is itself a flag, in which case this one is a boolean switch.
    readonly property var flags: {
        var out = []
        for (var i = 1; i < argv.length; i++) {
            var tok = argv[i]
            if (!/^-(?!\d)/.test(tok)) continue
            var key = tok.replace(/^-+/, "")
            var value = ""
            if (i + 1 < argv.length && !/^-(?!\d)/.test(argv[i + 1])) {
                value = argv[i + 1]
                i++
            }
            out.push({ key: key, value: value })
        }
        out.sort(function(a, b) { return a.key.localeCompare(b.key) })
        return out
    }

    Layout.fillWidth: true
    color: "#1a1f25"
    radius: 3
    // ColumnLayout sizes children from Layout.preferredHeight/implicitHeight,
    // not a plain height: binding — a raw `height:` here never reaches the
    // outer layout, so a card with wrapped multi-line cmdline text just
    // overflows its own Rectangle and paints over whatever comes next.
    implicitHeight: col.implicitHeight + 16

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
            visible: card.gpuPct !== null || card.vramKb !== null
                  || card.cpuPct !== null || card.hostMemKb !== null
            text: "GPU (proc): " + card.fmtPct(card.gpuPct)
                + "   GPU MEM (proc): " + card.fmtMiB(card.vramKb)
                + "   CPU: " + card.fmtPct(card.cpuPct)
                + "   RSS: " + card.fmtMiB(card.hostMemKb)
            color: "#aeb4bb"
            font.pointSize: 8
            // NOT wrapped, deliberately: this line's numbers change every
            // poll tick, and a digit-count crossing a width threshold
            // (e.g. "9%" -> "10%") would make it intermittently wrap to
            // two lines and back, changing this card's height and hopping
            // the scroll position under the user every second. It always
            // comfortably fits the card width unwrapped; NoWrap trades an
            // impossible-in-practice overflow for a guaranteed-stable
            // height instead.
            wrapMode: Text.NoWrap
        }
        Text {
            Layout.fillWidth: true
            visible: card.subtitle.length > 0
            text: card.subtitle
            color: "#aeb4bb"
            font.pointSize: 8
            wrapMode: Text.Wrap
        }
        // CLI flags as a wrapping key/value table, sorted alphabetically --
        // only shown when argv was supplied (llama.cpp/vllm); falls back to
        // the raw cmdline text otherwise (e.g. the trivial "ollama serve").
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: card.argv.length > 0
            spacing: 5

            Repeater {
                model: card.flags
                delegate: Row {
                    spacing: 4
                    Text {
                        text: modelData.key + ":"
                        color: "#8a9199"
                        font.pointSize: 7
                        font.family: "monospace"
                    }
                    Text {
                        text: modelData.value.length > 0 ? modelData.value : "on"
                        color: "#c8ccd2"
                        font.pointSize: 7
                        font.family: "monospace"
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: card.cmdline.length > 0 && card.argv.length === 0
            text: card.cmdline
            color: "#6a7078"
            font.pointSize: 7
            font.family: "monospace"
            wrapMode: Text.Wrap
        }
    }
}
