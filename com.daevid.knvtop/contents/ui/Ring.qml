import QtQuick

// Reusable progress ring gauge, drawn on Canvas. Extracted from the 5x
// duplicated GPU/MEM/TMP/PWR/CPU blocks that used to live inline in
// main.qml's fullRepresentation.
Item {
    id: ring

    property real ratio: 0          // 0..1, arc fill
    property color ringColor: "#4d9fff"
    property string valueText: "0%"
    property string label: ""
    property bool active: true
    property real trackWidth: 5

    opacity: active ? 1 : 0.3

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - 4
            var frac = Math.max(0, Math.min(1, ring.ratio))

            ctx.lineWidth = ring.trackWidth
            ctx.strokeStyle = "#3a3f45"
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()

            ctx.strokeStyle = ring.ringColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2)
            ctx.stroke()

            ctx.fillStyle = "#c8ccd2"; ctx.font = "bold 12px sans-serif"
            ctx.textAlign = "center"; ctx.textBaseline = "middle"
            ctx.fillText(ring.valueText, cx, cy - 3)

            ctx.font = "7px sans-serif"; ctx.fillStyle = "#8a9199"
            ctx.fillText(ring.label, cx, cy + 10)
        }
    }

    // Canvas.onPaint does not re-run just because a property it reads
    // changed — without these, the ring only ever painted once when the
    // popup opened and never updated while it stayed open.
    onRatioChanged: canvas.requestPaint()
    onValueTextChanged: canvas.requestPaint()
    onRingColorChanged: canvas.requestPaint()
    onLabelChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
