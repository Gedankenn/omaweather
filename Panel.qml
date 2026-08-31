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

  readonly property string locationName: Model.clampLocation(String(setting("location", Model.defaultLocation())))
  readonly property var locationLatitude: setting("latitude", null)
  readonly property var locationLongitude: setting("longitude", null)
  readonly property string locationQuery: Model.locationQuery(locationName, locationLatitude, locationLongitude)
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)
  readonly property string compactFetchUrl: Model.compactUrl(locationQuery)
  readonly property string chartFetchUrl: Model.chartUrl(locationQuery)
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string geocodeLanguage: String(Qt.locale().name || "en")

  property var compact: null
  property string chart: ""
  property int compactRetries: 0
  property int chartRetries: 0

  property bool editingLocation: false
  property bool savingLocation: false
  property string persistedName: ""
  property bool locationReady: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  readonly property string displayLocation: locationName || (compact && compact.location ? compact.location : "")
  readonly property string label: Model.barLabel(compact, !!(bar && bar.vertical))
  readonly property string tooltipText: Model.tooltip(compact, locationName)
  readonly property var chartParts: Model.splitChart(chart)
  readonly property string chartBox: chartParts && chartParts.box ? chartParts.box : ""
  readonly property string chartFooter: chartParts && chartParts.footer ? Model.stripAnsi(chartParts.footer) : ""
  readonly property string chartHtml: chartBox ? Model.ansiToHtml(chartBox, contentForeground) : ""
  readonly property bool fetching: compactProc.running || chartProc.running || compactRetryTimer.running || chartRetryTimer.running
  readonly property string statusMessage: chart ? "" : (fetching ? "Fetching v2.wttr.in…" : "Couldn't reach wttr.in")
  // Qt reports StyledText width as pixelSize*cols (em square). JetBrains Mono
  // and other bar fonts paint at ~0.6em, which is the cell we actually see.
  readonly property real chartInnerWidth: Math.ceil(Model.chartColumns(chartBox) * Style.font.bodySmall * 0.6)

  onLocationQueryChanged: {
    compactRetries = 0
    chartRetries = 0
    compactProc.running = false
    chartProc.running = false
    compact = null
    chart = ""
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
    if (root.editingLocation) root.cancelEditingLocation()
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
    restartProc(compactProc, Model.cappedCurl(root.compactFetchUrl, 8, Model.MAX_COMPACT_BYTES))
  }

  function startChart() {
    restartProc(chartProc, Model.cappedCurl(root.chartFetchUrl, 20, Model.MAX_CHART_BYTES))
  }

  function restartProc(proc, command) {
    proc.command = command
    if (proc.running) {
      proc.running = false
      Qt.callLater(function() { proc.running = true })
      return
    }
    proc.running = true
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

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var current = settings || {}
    for (var existing in current) if (existing !== "id") entry[existing] = current[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistLocation(name, latitude, longitude) {
    persistedName = Model.clampLocation(name)
    persistSettings({
      location: persistedName,
      latitude: latitude,
      longitude: longitude
    })
  }

  // A CLI/settings-only change of the city name must drop leftover coordinates
  // from the last search pick, otherwise the old lat,lon would keep winning.
  onLocationNameChanged: {
    if (!locationReady) return
    if (locationName === persistedName) return
    persistedName = locationName
    var hasCoords = (locationLatitude !== null && locationLatitude !== undefined && locationLatitude !== "")
      || (locationLongitude !== null && locationLongitude !== undefined && locationLongitude !== "")
    if (hasCoords) persistSettings({ latitude: null, longitude: null })
  }

  Component.onCompleted: {
    persistedName = locationName
    locationReady = true
  }

  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.locationName
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    locationSuggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLocation() {
    var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    applyLocation(location)
  }

  function clearLocation() {
    applyLocation({ name: "", latitude: null, longitude: null })
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    applyLocation(suggestion)
  }

  function applyLocation(location) {
    var name = Model.clampLocation(location && location.name)
    var latitude = location ? location.latitude : null
    var longitude = location ? location.longitude : null
    var nextQuery = Model.locationQuery(name, latitude, longitude)
    savingLocation = true
    persistLocation(name, latitude, longitude)
    if (nextQuery === root.locationQuery) {
      chart = ""
      refresh()
    }
  }

  function finishSavingLocation() {
    if (savingLocation) cancelEditingLocation()
  }

  function requestGeocode() {
    var query = Model.clampLocation(locationField.text)
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    var url = Model.geocodeUrl(geocodeActiveQuery, root.geocodeLanguage)
    if (!url) return
    geocodeProc.command = Model.cappedCurl(url, 5, 16384)
    geocodeProc.running = true
  }

  Process {
    id: compactProc
    command: Model.cappedCurl(root.compactFetchUrl, 8, Model.MAX_COMPACT_BYTES)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!Model.withinByteCap(text, Model.MAX_COMPACT_BYTES)) {
          root.scheduleCompactRetry()
          return
        }
        var parsed = Model.parseCompact(text)
        if (!parsed) {
          root.scheduleCompactRetry()
          return
        }
        root.compact = parsed
        root.compactRetries = 0
        root.finishSavingLocation()
      }
    }
  }

  Process {
    id: chartProc
    command: Model.cappedCurl(root.chartFetchUrl, 20, Model.MAX_CHART_BYTES)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!Model.withinByteCap(text, Model.MAX_CHART_BYTES)) {
          root.scheduleChartRetry()
          return
        }
        var cleaned = Model.cleanChart(text)
        if (!Model.stripAnsi(cleaned)) {
          root.scheduleChartRetry()
          return
        }
        root.chart = cleaned
        root.chartRetries = 0
        if (!root.compact) {
          var fromChart = Model.parseWeatherLine(Model.stripAnsi(cleaned))
          if (fromChart) {
            root.compact = fromChart
            root.finishSavingLocation()
          }
        }
      }
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
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
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
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
    function edit(): void { root.openFromHotkey(); root.startEditingLocation() }
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
    contentWidth: panel.fittedContentWidth(Math.max(root.chartInnerWidth, Style.space(280)) + panel.padding * 2 + Style.space(4))
    contentHeight: panel.fittedContentHeight(Math.max(Style.space(80), chartColumn.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: root.startEditingLocation()
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
          width: Math.max(root.chartInnerWidth, parent.width)
          spacing: Style.space(6)

          Item {
            visible: !root.editingLocation
            width: parent.width
            height: locationRow.implicitHeight

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startEditingLocation()
            }

            Row {
              id: locationRow
              spacing: Style.space(6)
              width: parent.width

              Text {
                text: ""
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: root.displayLocation ? root.displayLocation.toUpperCase() : "AUTO"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
                elide: Text.ElideRight
                width: Math.max(0, parent.width - Style.space(24))
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          Row {
            visible: root.editingLocation
            spacing: Style.space(6)
            width: parent.width

            TextField {
              id: locationField
              width: Math.min(Style.space(220), parent.width - Style.space(28))
              enabled: !root.savingLocation
              placeholderText: "Search city"
              foreground: root.contentForeground
              font.family: root.contentFontFamily

              onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditingLocation()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  if (root.suggestionIndex > 0) root.suggestionIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitLocation()
                  event.accepted = true
                }
              }
            }

            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: Math.min(4, Style.cornerRadius)
              color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.savingLocation ? "󰦖" : "✕"
                font.family: root.contentFontFamily
                color: Qt.darker(root.contentForeground, 1.4)
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: root.savingLocation
                  from: 0; to: 360
                  duration: 800
                  loops: Animation.Infinite
                }
              }

              MouseArea {
                id: clearLocationArea
                anchors.fill: parent
                enabled: !root.savingLocation
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.clearLocation()
              }
            }
          }

          Column {
            visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
            width: parent.width
            spacing: 0

            Repeater {
              model: root.locationSuggestions

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: suggestionRow.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: index === root.suggestionIndex ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                Row {
                  id: suggestionRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: index === root.suggestionIndex ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    textFormat: Text.PlainText
                    visible: text !== ""
                    text: modelData.description
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: root.suggestionIndex = index
                  onClicked: root.pickSuggestion(modelData)
                }
              }
            }
          }

          Text {
            id: chartText
            width: parent.width
            text: root.chartHtml || root.statusMessage
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
