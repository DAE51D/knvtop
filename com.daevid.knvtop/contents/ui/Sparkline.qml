import QtQuick

Canvas {
    id: chart

    property var values: []
    property int revision: 0
    property real maximum: 100
    property color lineColor: "#4d9fff"
    property real lineWidth: 1.5
    property int capacity: 21
    // Time-based scrolling: when `times` (ms since epoch, one per value) is given,
    // each point sits at x = right edge - age * (plot width / windowSec), and a
    // timer keeps repainting so the line slides smoothly between 1 s samples
    // instead of jumping once per poll. Without `times` it falls back to evenly
    // spaced points.
    property var times: []
    property real windowSec: 20
    property bool mirrored: false
    property real cornerRadius: 0
    property real padTop: 4
    property real padBottom: 2
    property real padLeft: 2
    property real padRight: 2

    // `revision` is referenced so this re-evaluates when the arrays are mutated in place
    readonly property bool timed: revision >= 0 && !!times && !!values && times.length === values.length && times.length > 1

    // ~20 fps repaint while visible; costs little (small canvas) and is what makes
    // the scroll continuous.
    Timer {
        interval: 50
        repeat: true
        running: chart.timed && chart.visible
        onTriggered: chart.requestPaint()
    }

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
        var firstIndex = timed ? 0 : Math.max(0, values.length - span)
        var points = []
        var now = Date.now()

        for (var i = firstIndex; i < values.length; i++) {
            var v = values[i]
            if (v === null || v === undefined)
                continue
            var ratio = Math.max(0, Math.min(1, v / max))
            var x = timed
                ? padLeft + plotW - ((now - times[i]) / 1000 / windowSec) * plotW
                : padLeft + plotW - (values.length - 1 - i) * stepX
            var y = padTop + plotH - ratio * plotH
            points.push({ x: x, y: y })
        }

        if (timed && points.length > 0) {
            // Keep a single point beyond the left edge (the canvas clips it) so the
            // line's left end slides out instead of snapping, and hold the newest
            // value flat out to the right edge.
            var firstVisible = -1
            for (var k = 0; k < points.length; k++) {
                if (points[k].x >= 0) { firstVisible = k; break }
            }
            points.splice(0, firstVisible < 0 ? Math.max(0, points.length - 1)
                                              : Math.max(0, firstVisible - 1))
            var tail = points[points.length - 1]
            var edge = padLeft + plotW
            if (tail.x < edge)
                points.push({ x: edge, y: tail.y })
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
