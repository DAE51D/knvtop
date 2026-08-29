import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

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
            editable: true
            model: ["All Users"]
            currentIndex: 0
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
