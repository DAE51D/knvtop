import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.workspace.dbus as PlasmaDBus

KCM.SimpleKCM {
    id: page

    property alias cfg_showGpu: gpuBox.checked
    property alias cfg_showMem: memBox.checked
    property alias cfg_showTemp: tempBox.checked
    property alias cfg_showPower: powerBox.checked
    property alias cfg_showCpu: cpuBox.checked
    property alias cfg_llmOnly: llmOnlyBox.checked
    property string cfg_filterUser
    property string cfg_filterType

    // Populated from a live D-Bus query so the dropdown offers the users
    // actually seen right now (aistack/dae51d/root, ...), not a guess --
    // this is meant to be reusable on other people's machines with
    // whatever accounts THEY happen to run things under.
    property var knownUsers: []

    function refreshKnownUsers() {
        var msg = new PlasmaDBus.dbusMessage({
            service: "com.daevid.knvtop",
            path: "/com/daevid/knvtop",
            iface: "com.daevid.knvtop.Sample",
            member: "Get",
            arguments: []
        })
        PlasmaDBus.SessionBus.asyncCall(msg, function(reply) {
            if (reply.isError || !reply.values || reply.values.length === 0) return
            try {
                var s = JSON.parse(reply.values[0])
                var seen = {}
                var procs = s.gpu_procs || []
                for (var i = 0; i < procs.length; i++) {
                    if (procs[i].user) seen[procs[i].user] = true
                }
                var llm = s.llm || {}
                ["llama", "ollama", "vllm"].forEach(function(kind) {
                    (llm[kind] || []).forEach(function(e) {
                        if (e.user) seen[e.user] = true
                    })
                })
                page.knownUsers = Object.keys(seen).sort()
            } catch (e) {
                // leave knownUsers as-is on a malformed/partial reply
            }
        }, function() {})
    }

    Component.onCompleted: refreshKnownUsers()

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.CheckBox {
            id: gpuBox
            Kirigami.FormData.label: "Show by default:"
            text: "GPU utilization"
        }
        QQC2.CheckBox {
            id: memBox
            text: "GPU memory"
        }
        QQC2.CheckBox {
            id: tempBox
            text: "GPU temperature"
        }
        QQC2.CheckBox {
            id: powerBox
            text: "GPU power"
        }
        QQC2.CheckBox {
            id: cpuBox
            text: "CPU utilization"
        }

        Item {
            Kirigami.FormData.isSection: false
            implicitHeight: Kirigami.Units.smallSpacing
        }

        QQC2.CheckBox {
            id: llmOnlyBox
            Kirigami.FormData.label: "Process list:"
            text: "AI/LLM processes only"
        }

        // User/Type apply within whichever list is showing -- AI/LLM-only
        // or the full generic list -- not just the generic one, so they
        // stay enabled regardless of the checkbox above.
        QQC2.ComboBox {
            id: userBox
            Kirigami.FormData.label: "Filter by user:"
            // Editable so a user not currently running anything GPU-side
            // (and therefore not in knownUsers yet) can still be typed in
            // by hand.
            editable: true
            model: ["All Users"].concat(page.knownUsers)
            editText: page.cfg_filterUser
            onEditTextChanged: page.cfg_filterUser = editText
        }

        QQC2.ComboBox {
            id: typeBox
            Kirigami.FormData.label: "Filter by type:"
            textRole: "label"
            valueRole: "key"
            model: [
                { key: "both", label: "Both" },
                { key: "graphic", label: "Graphic" },
                { key: "compute", label: "Compute" }
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_filterType))
            onActivated: page.cfg_filterType = currentValue
        }
    }
}
