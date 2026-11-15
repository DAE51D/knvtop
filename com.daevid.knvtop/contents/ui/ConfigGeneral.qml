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
    property alias cfg_showNpu: npuBox.checked
    property alias cfg_llmOnly: llmOnlyBox.checked
    property string cfg_filterUser
    property alias cfg_filterGraphic: graphicBox.checked
    property alias cfg_filterCompute: computeBox.checked
    property alias cfg_filterNpu: npuTypeBox.checked

    // Populated from a live D-Bus query so the dropdown offers the users
    // actually seen right now (desktop user, service account, root, etc.),
    // not a machine-specific guess. This stays reusable across installations
    // with whatever account layout they happen to use.
    property var knownUsers: []
    // True only when the service reports an NPU; the NPU checkbox and the NPU type
    // filter are hidden otherwise, so machines without one see no NPU options.
    property bool hasNpu: false

    function refreshKnownUsers() {
        var msg = new PlasmaDBus.dbusMessage({
            service: "com.daevid.nvstats",
            path: "/com/daevid/nvstats",
            iface: "com.daevid.nvstats.Sample",
            member: "Get",
            arguments: []
        })
        PlasmaDBus.SessionBus.asyncCall(msg, function(reply) {
            if (reply.isError || !reply.values || reply.values.length === 0) return
            try {
                var s = JSON.parse(reply.values[0])
                page.hasNpu = !!(s.npu && s.npu.present)
                var seen = {}
                var procs = s.gpu_procs || []
                for (var i = 0; i < procs.length; i++) {
                    if (procs[i].user) seen[procs[i].user] = true
                }
                var llm = s.llm || {}
                ["llama", "ollama", "vllm", "sglang", "tgi", "flm"].forEach(function(kind) {
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
        QQC2.CheckBox {
            id: npuBox
            visible: page.hasNpu
            text: "NPU utilization"
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

        // A process is listed if it matches any checked type (all checked = no filter).
        QQC2.CheckBox {
            id: graphicBox
            Kirigami.FormData.label: "Filter by type:"
            text: "Graphic"
        }
        QQC2.CheckBox {
            id: computeBox
            text: "Compute"
        }
        QQC2.CheckBox {
            id: npuTypeBox
            visible: page.hasNpu
            text: "NPU"
        }
    }
}
