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
    }
}
