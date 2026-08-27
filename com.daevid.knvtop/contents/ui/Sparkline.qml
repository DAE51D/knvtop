import QtQuick

Canvas {
    id: chart

    property var values: []
    property int revision: 0
    property real maximum: 100
    property color lineColor: "#4d9fff"
    property real lineWidth: 1.5
    property int capacity: 21
    property bool mirrored: false
    property real cornerRadius: 0
    property real padTop: 4
    property real padBottom: 2
    property real padLeft: 2
    property real padRight: 2

    onRevisionChanged: requestPaint()
    onMaximumChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (width <= 0 || height <= 0)
            return

        if (cornerRadius > 0) {
            ctx.beginPath()
            ctx.roundedRect(0, 0, width, height, cornerRadius, cornerRadius)
            ctx.clip()
        }

        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.05)
        ctx.fillRect(0, 0, width, height)

        if (!values || values.length < 2)
            return

        var span = Math.max(2, capacity)
        var max = Math.max(maximum, 0.0001)
        var plotW = width - padLeft - padRight
        var plotH = height - padTop - padBottom
        var stepX = plotW / (span - 1)
        var firstIndex = Math.max(0, values.length - span)
        var points = []

        for (var i = firstIndex; i < values.length; i++) {
            var v = values[i]
            if (v === null || v === undefined)
                continue
            var ratio = Math.max(0, Math.min(1, v / max))
            var x = padLeft + plotW - (values.length - 1 - i) * stepX
            var y = padTop + plotH - ratio * plotH
            points.push({ x: x, y: y })
        }

        if (points.length < 2)
            return

        var gradient = ctx.createLinearGradient(0, padTop, 0, padTop + plotH)
        gradient.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.34))
        gradient.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.02))

        ctx.beginPath()
        ctx.moveTo(points[0].x, padTop + plotH)
        for (var p = 0; p < points.length; p++)
            ctx.lineTo(points[p].x, points[p].y)
        ctx.lineTo(points[points.length - 1].x, padTop + plotH)
        ctx.closePath()
        ctx.fillStyle = gradient
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(points[0].x, points[0].y)
        for (var q = 1; q < points.length; q++)
            ctx.lineTo(points[q].x, points[q].y)
        ctx.strokeStyle = lineColor
        ctx.lineWidth = lineWidth
        ctx.lineJoin = "round"
        ctx.stroke()
    }
}
