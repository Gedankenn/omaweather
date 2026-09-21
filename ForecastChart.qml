import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var hours: []
  property var days: []
  property color foreground: "#ffffff"
  property string fontFamily: ""

  implicitWidth: Style.space(360)
  implicitHeight: Style.space(164)

  readonly property int hourCount: hours ? hours.length : 0
  readonly property real padX: Style.space(8)
  readonly property real dayLabelH: Style.space(18)
  readonly property real hourRowH: Style.space(13)
  readonly property real emojiRowH: Style.space(18)
  readonly property real sunRowH: Style.space(15)
  readonly property real plotTop: dayLabelH
  readonly property real plotBottom: Math.max(plotTop + Style.space(24), height - hourRowH - emojiRowH - sunRowH)
  readonly property real plotH: plotBottom - plotTop

  readonly property var tempRange: {
    var lo = Infinity
    var hi = -Infinity
    for (var i = 0; i < hourCount; i++) {
      var v = Number(hours[i].temp)
      if (!isFinite(v)) continue
      if (v < lo) lo = v
      if (v > hi) hi = v
    }
    if (!isFinite(lo) || !isFinite(hi)) return { lo: 0, hi: 1 }
    if (hi - lo < 2) hi = lo + 2
    return { lo: lo, hi: hi }
  }

  function plotWidth() {
    return Math.max(1, width - padX * 2)
  }

  function xForIndex(i) {
    if (hourCount <= 1) return padX
    return padX + (i / (hourCount - 1)) * plotWidth()
  }

  function yForTemp(t) {
    var pad = Style.space(7)
    var span = Math.max(1, tempRange.hi - tempRange.lo)
    var usable = Math.max(1, plotH - pad * 2)
    return plotBottom - pad - ((Number(t) - tempRange.lo) / span) * usable
  }

  function centerXForDay(d) {
    return xForIndex(Math.min(hourCount - 1, d * 24 + 12))
  }

  function rgbaString(color, alpha) {
    return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + "," + alpha + ")"
  }

  onHoursChanged: plot.requestPaint()
  onWidthChanged: plot.requestPaint()
  onHeightChanged: plot.requestPaint()
  onDaysChanged: plot.requestPaint()

  Canvas {
    id: plot
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      var w = root.width
      var h = root.height
      ctx.clearRect(0, 0, w, h)
      if (root.hourCount < 2 || root.plotH <= 0) return

      var base = root.plotBottom
      var top = root.plotTop
      var i

      // Horizontal guide lines.
      ctx.lineWidth = 1
      ctx.strokeStyle = root.rgbaString(root.foreground, 0.10)
      for (var g = 0; g <= 4; g++) {
        var gy = top + (root.plotH / 4) * g
        ctx.beginPath()
        ctx.moveTo(root.padX, gy)
        ctx.lineTo(w - root.padX, gy)
        ctx.stroke()
      }

      // Day dividers.
      ctx.strokeStyle = root.rgbaString(root.foreground, 0.22)
      var dayCount = root.days ? root.days.length : 0
      for (var d = 1; d < dayCount; d++) {
        var dx = root.xForIndex(d * 24)
        ctx.beginPath()
        ctx.moveTo(dx, top)
        ctx.lineTo(dx, base)
        ctx.stroke()
      }

      // Precipitation bars, rising from the baseline.
      var slot = root.plotWidth() / Math.max(1, root.hourCount)
      var barW = Math.max(1, Math.min(slot * 0.6, Style.space(6)))
      var maxBarH = root.plotH * 0.42
      ctx.fillStyle = root.rgbaString(root.foreground, 0.20)
      for (i = 0; i < root.hourCount; i++) {
        var p = Number(root.hours[i].precip) || 0
        if (p <= 0) continue
        var bh = (Math.min(100, p) / 100) * maxBarH
        ctx.fillRect(root.xForIndex(i) - barW / 2, base - bh, barW, bh)
      }

      // Temperature area, soft fill under the curve.
      var grad = ctx.createLinearGradient(0, top, 0, base)
      grad.addColorStop(0, root.rgbaString(root.foreground, 0.20))
      grad.addColorStop(1, root.rgbaString(root.foreground, 0.02))
      ctx.fillStyle = grad
      ctx.beginPath()
      ctx.moveTo(root.xForIndex(0), base)
      for (i = 0; i < root.hourCount; i++) {
        ctx.lineTo(root.xForIndex(i), root.yForTemp(root.hours[i].temp))
      }
      ctx.lineTo(root.xForIndex(root.hourCount - 1), base)
      ctx.closePath()
      ctx.fill()

      // Temperature curve, stroked in the temperature color per segment.
      ctx.lineWidth = 2.2
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      for (i = 0; i < root.hourCount - 1; i++) {
        var mid = (Number(root.hours[i].temp) + Number(root.hours[i + 1].temp)) / 2
        ctx.strokeStyle = Model.tempColor(mid)
        ctx.beginPath()
        ctx.moveTo(root.xForIndex(i), root.yForTemp(root.hours[i].temp))
        ctx.lineTo(root.xForIndex(i + 1), root.yForTemp(root.hours[i + 1].temp))
        ctx.stroke()
      }
    }
  }

  // Day labels plus each day's high/low, centered over the day.
  Repeater {
    model: root.days

    Column {
      required property var modelData
      required property int index

      readonly property real anchorX: root.centerXForDay(index)
      x: Math.max(0, Math.min(root.width - width, anchorX - width / 2))
      y: 0
      spacing: 0

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: modelData.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: (modelData.max === null ? "" : modelData.max + "°") + (modelData.min === null ? "" : " " + modelData.min + "°")
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall - 2
      }
    }
  }

  // Condition emoji per day.
  Repeater {
    model: root.days

    Text {
      required property var modelData
      required property int index

      textFormat: Text.PlainText
      text: modelData.emoji
      font.pixelSize: Style.font.body
      x: root.centerXForDay(index) - width / 2
      y: root.plotBottom + root.hourRowH + Style.space(2)
    }
  }

  // Hour ticks every six hours.
  Repeater {
    model: root.hours

    Text {
      required property var modelData
      required property int index

      visible: index % 6 === 0
      textFormat: Text.PlainText
      text: modelData.label
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall - 2
      x: root.xForIndex(index) - width / 2
      y: root.plotBottom + Style.space(1)
    }
  }

  Text {
    textFormat: Text.PlainText
    text: "☀ ↑ " + (root.days.length ? root.days[0].sunrise : "") + "    ↓ " + (root.days.length ? root.days[0].sunset : "")
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.plotBottom + root.hourRowH + root.emojiRowH
  }
}
