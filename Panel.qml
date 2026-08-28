import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.gedankenn.omaweather"
  ipcTarget: "io.github.gedankenn.omaweather"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string location: {
    var value = String(setting("location", Model.defaultLocation()))
    return Model.clampLocation(value)
  }
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)
  readonly property string compactFetchUrl: Model.compactUrl(location)
  readonly property string chartFetchUrl: Model.chartUrl(location)
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property var compact: null
  property string chart: ""
  property int compactRetries: 0
  property int chartRetries: 0

  readonly property string label: Model.barLabel(compact, !!(bar && bar.vertical))
  readonly property string tooltipText: Model.tooltip(compact)
  readonly property var chartParts: Model.splitChart(chart)
  readonly property string chartBox: chartParts && chartParts.box ? chartParts.box : ""
  readonly property string chartFooter: chartParts && chartParts.footer ? Model.stripAnsi(chartParts.footer) : ""
  readonly property string chartHtml: chartBox ? Model.ansiToHtml(chartBox, contentForeground) : ""
  readonly property string statusMessage: compact || chart ? "" : "Fetching v2.wttr.in…"
  // Qt reports StyledText width as pixelSize*cols (em square). JetBrains Mono
  // and other bar fonts paint at ~0.6em, which is the cell we actually see.
  readonly property real chartInnerWidth: Math.ceil(Model.chartColumns(chartBox) * Style.font.bodySmall * 0.6)

  onLocationChanged: {
    compactRetries = 0
    chartRetries = 0
    compactProc.running = false
    chartProc.running = false
    Qt.callLater(refresh)
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    if (!chart) root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    if (!chart) root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    compactRetries = 0
    chartRetries = 0
    startCompact()
    startChart()
  }

  function startCompact() {
    if (!compactProc.running) compactProc.running = true
  }

  function startChart() {
    if (!chartProc.running) chartProc.running = true
  }

  function scheduleCompactRetry() {
    if (compactRetries >= 3) return
    compactRetries++
    compactRetryTimer.restart()
  }

  function scheduleChartRetry() {
    if (chartRetries >= 3) return
    chartRetries++
    chartRetryTimer.restart()
  }

  Process {
    id: compactProc
    command: Model.cappedCurl(root.compactFetchUrl, 8, Model.MAX_COMPACT_BYTES)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!Model.withinByteCap(text, Model.MAX_COMPACT_BYTES)) return
        var parsed = Model.parseCompact(text)
        if (!parsed) {
          root.scheduleCompactRetry()
          return
        }
        root.compact = parsed
        root.compactRetries = 0
      }
    }
  }

  Process {
    id: chartProc
    command: Model.cappedCurl(root.chartFetchUrl, 20, Model.MAX_CHART_BYTES)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!Model.withinByteCap(text, Model.MAX_CHART_BYTES)) return
        var cleaned = Model.cleanChart(text)
        if (!Model.stripAnsi(cleaned)) {
          root.scheduleChartRetry()
          return
        }
        root.chart = cleaned
        root.chartRetries = 0
        if (!root.compact) {
          var fromChart = Model.parseWeatherLine(Model.stripAnsi(cleaned))
          if (fromChart) root.compact = fromChart
        }
      }
    }
  }

  Timer {
    id: compactRetryTimer
    interval: 2500
    onTriggered: root.startCompact()
  }

  Timer {
    id: chartRetryTimer
    interval: 2500
    onTriggered: root.startChart()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    padding: Style.spacing.md
    contentWidth: panel.fittedContentWidth(root.chartInnerWidth + panel.padding * 2 + Style.space(4))
    contentHeight: panel.fittedContentHeight(Math.max(Style.space(80), chartColumn.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: chartScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: chartColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: chartColumn
          width: root.chartInnerWidth
          spacing: Style.space(6)

          Text {
            id: chartText
            width: parent.width
            text: root.chartHtml || root.statusMessage || "Couldn't reach wttr.in"
            textFormat: root.chartHtml ? Text.StyledText : Text.PlainText
            color: root.chartHtml ? root.contentForeground : Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.kerning: false
            wrapMode: Text.NoWrap
            clip: true
            renderType: Text.QtRendering
            lineHeight: 1.02
            lineHeightMode: Text.ProportionalHeight
            font.italic: !root.chart
          }

          Text {
            visible: root.chartFooter !== ""
            width: parent.width
            text: root.chartFooter
            textFormat: Text.PlainText
            color: Qt.darker(root.contentForeground, 1.15)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
