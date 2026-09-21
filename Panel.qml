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
  readonly property string weatherJsonPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
  readonly property real panelWidth: Style.space(380)

  // Open-Meteo needs numeric coordinates. Prefer the widget's own location,
  // then the Omarchy weather.json default, then a hardcoded Pato Branco.
  property real resolvedLatitude: NaN
  property real resolvedLongitude: NaN

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string geocodeLanguage: String(Qt.locale().name || "en")

  property var forecast: null
  property int forecastRetries: 0

  property bool editingLocation: false
  property bool savingLocation: false
  property string persistedName: ""
  property bool locationReady: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // The bar chip and tooltip keep the shape the old wttr.in parser produced.
  readonly property var compact: {
    if (!forecast || !forecast.current) return null
    var c = forecast.current
    return {
      emoji: c.emoji || "",
      temp: c.temperature === null ? "" : c.temperature + "°",
      tempShort: c.temperature === null ? "" : String(c.temperature),
      condition: c.condition || "",
      humidity: c.humidity === null ? "" : c.humidity + "%",
      wind: c.wind === null ? "" : c.wind + " km/h",
      location: ""
    }
  }
  readonly property string displayLocation: locationName || (forecast && forecast.days && forecast.days.length ? forecast.days[0].label : "")
  readonly property string label: Model.barLabel(compact, !!(bar && bar.vertical))
  readonly property string tooltipText: Model.tooltip(compact, locationName)
  readonly property bool fetching: forecastProc.running || compactGeocodeProc.running || forecastRetryTimer.running
  readonly property string statusMessage: forecast ? "" : (fetching ? "Fetching Open-Meteo…" : "Couldn't reach Open-Meteo")

  onLocationQueryChanged: {
    forecastRetries = 0
    forecastProc.running = false
    forecast = null
    Qt.callLater(refresh)
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    if (!forecast) root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    if (!forecast) root.refresh()
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

  // Third-party plugins get the read-only PluginBarApi facade, so the state
  // flip goes through its method. Fall back to the property for first-party
  // hosts that expose a writable Bar.
  function setCenterHoverRevealSuppressed(value) {
    if (!root.bar) return
    if (typeof root.bar.setCenterHoverRevealSuppressed === "function") {
      root.bar.setCenterHoverRevealSuppressed(value)
      return
    }
    if ("centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    forecastRetries = 0
    startForecast()
  }

  function startForecast() {
    var lat = Model.parseCoordinate(root.locationLatitude)
    var lon = Model.parseCoordinate(root.locationLongitude)
    if (lat !== null && lon !== null) {
      fetchForecast(lat, lon)
      return
    }
    if (isFinite(root.resolvedLatitude) && isFinite(root.resolvedLongitude)) {
      fetchForecast(root.resolvedLatitude, root.resolvedLongitude)
      return
    }
    if (root.locationName) {
      startForecastGeocode(root.locationName)
      return
    }
    fetchForecast(-26.22861, -52.67056)
  }

  function fetchForecast(latitude, longitude) {
    var url = Model.forecastUrl(latitude, longitude)
    if (!url) return
    restartProc(forecastProc, Model.cappedCurl(url, 10, Model.MAX_FORECAST_BYTES))
  }

  function startForecastGeocode(name) {
    var url = Model.geocodeUrl(name, root.geocodeLanguage)
    if (!url) return
    compactGeocodeProc.command = Model.cappedCurl(url, 5, 16384)
    compactGeocodeProc.running = true
  }

  function loadDefaultLocation() {
    if (defaultLocationProc.running) return
    defaultLocationProc.running = true
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

  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
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
    loadDefaultLocation()
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
      forecast = null
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
    id: forecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!Model.withinByteCap(text, Model.MAX_FORECAST_BYTES)) {
          root.scheduleForecastRetry()
          return
        }
        var parsed = Model.parseForecast(text)
        if (!parsed) {
          root.scheduleForecastRetry()
          return
        }
        root.forecast = parsed
        root.forecastRetries = 0
        root.finishSavingLocation()
      }
    }
  }

  Process {
    id: compactGeocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var results = Model.parseGeocodingResults(text)
        if (!results.length) return
        root.resolvedLatitude = results[0].latitude
        root.resolvedLongitude = results[0].longitude
        root.fetchForecast(results[0].latitude, results[0].longitude)
      }
    }
  }

  Process {
    id: defaultLocationProc
    command: ["cat", root.weatherJsonPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var def = Model.parseWeatherJson(text)
        if (!def) return
        root.resolvedLatitude = def.latitude
        root.resolvedLongitude = def.longitude
        Qt.callLater(root.startForecast)
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
    id: forecastRetryTimer
    interval: 2500
    onTriggered: root.startForecast()
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
    contentWidth: panel.fittedContentWidth(root.panelWidth + panel.padding * 2)
    contentHeight: panel.fittedContentHeight(Math.max(Style.space(120), contentColumn.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: root.startEditingLocation()
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: popupScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(8)

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

          // Current conditions summary.
          Item {
            visible: !root.editingLocation && root.forecast !== null
            width: parent.width
            height: summaryColumn.implicitHeight

            Column {
              id: summaryColumn
              width: parent.width
              spacing: Style.space(2)

              Row {
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: root.forecast && root.forecast.current ? root.forecast.current.emoji : ""
                  font.pixelSize: Style.font.display
                  anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                  spacing: 0
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: root.forecast && root.forecast.current && root.forecast.current.temperature !== null
                      ? root.forecast.current.temperature + "°C" : "—"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.title
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.forecast && root.forecast.current ? root.forecast.current.condition : ""
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.7)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                text: {
                  if (!root.forecast || !root.forecast.current) return ""
                  var c = root.forecast.current
                  var bits = []
                  if (c.apparent !== null) bits.push("Feels " + c.apparent + "°")
                  if (c.humidity !== null) bits.push(c.humidity + "%")
                  if (c.wind !== null) bits.push(c.wind + " km/h")
                  return bits.join("   ·   ")
                }
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.7)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          ForecastChart {
            visible: !root.editingLocation && root.forecast !== null
            width: parent.width
            height: visible ? Style.space(164) : 0
            hours: root.forecast ? root.forecast.hours : []
            days: root.forecast ? root.forecast.days : []
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            visible: root.forecast === null && !root.editingLocation
            width: parent.width
            text: root.statusMessage
            textFormat: Text.PlainText
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }
        }
      }
    }
  }
}
