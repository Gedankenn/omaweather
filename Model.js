var MAX_COMPACT_BYTES = 2048
var MAX_CHART_BYTES = 65536
var MAX_LABEL_CHARS = 32
var MAX_TOOLTIP_CHARS = 240
var MAX_FOOTER_CHARS = 1500
var MAX_FIELD_EMOJI = 16
var MAX_FIELD_TEMP = 12
var MAX_FIELD_CONDITION = 96
var MAX_FIELD_HUMIDITY = 12
var MAX_FIELD_WIND = 24
var MAX_FIELD_LOCATION = 80
var MAX_LOCATION_CHARS = 128
var MAX_CHART_COLS = 80
var MAX_CHART_LINES = 48
var MAX_CHART_SPANS = 2048

function defaultLocation() {
  return ""
}

function clampLocation(location) {
  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  if (name.length > MAX_LOCATION_CHARS) name = name.slice(0, MAX_LOCATION_CHARS)
  return name
}

function encodeLocation(location) {
  var name = clampLocation(location)
  if (!name) return ""
  return encodeURIComponent(name).replace(/%20/g, "+")
}

function compactUrl(location) {
  return "https://wttr.in/" + encodeLocation(location) + "?format=%c|%t|%C|%h|%w|%l&m"
}

function chartUrl(location) {
  return "https://v2.wttr.in/" + encodeLocation(location) + "?F&m"
}

// Producer cap: curl aborts oversized Content-Length, head -c stops the pipe
// even when the length is unknown. URL/timeout/limit are positional so they
// are not interpolated into the script text.
function cappedCurl(url, timeoutSec, maxBytes) {
  return [
    "sh", "-c",
    "curl -fsS --max-time \"$2\" --max-filesize \"$3\" -o - -- \"$1\" | head -c \"$3\"",
    "omaweather-fetch",
    String(url || ""),
    String(timeoutSec),
    String(maxBytes)
  ]
}

function asPlainUi(value, maxLen) {
  var s = stripAnsi(String(value || ""))
  s = s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
  s = s.replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
  s = s.replace(/[<>&]/g, "")
  s = s.replace(/[ \t]+/g, " ")
  s = trim(s)
  var cap = parseInt(maxLen, 10)
  if (!isFinite(cap) || cap <= 0) cap = 80
  if (s.length > cap) s = s.slice(0, cap)
  return s
}

function asPlainMultiline(value, maxLen) {
  var s = stripAnsi(String(value || ""))
  s = s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
  s = s.replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
  s = s.replace(/[<>&]/g, "")
  var cap = parseInt(maxLen, 10)
  if (!isFinite(cap) || cap <= 0) cap = MAX_FOOTER_CHARS
  if (s.length > cap) s = s.slice(0, cap)
  return s
}

function withinByteCap(raw, maxBytes) {
  var s = String(raw || "")
  return s.length > 0 && s.length < maxBytes
}

function stripAnsi(text) {
  return String(text || "")
    .replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, "")
    .replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "")
    .replace(/\x1B[()]./g, "")
}

function trim(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "")
}

function parseCompact(raw) {
  if (!withinByteCap(raw, MAX_COMPACT_BYTES)) return null
  var parts = stripAnsi(raw).replace(/\r/g, "").split("|")
  if (parts.length < 2) return null

  var temp = asPlainUi(trim(parts[1]).replace(/^\+/, ""), MAX_FIELD_TEMP)
  if (!temp) return null

  return {
    emoji: asPlainUi(parts[0], MAX_FIELD_EMOJI),
    temp: temp,
    tempShort: asPlainUi(temp.replace(/[CF]$/, ""), MAX_FIELD_TEMP),
    condition: asPlainUi(parts[2] || "", MAX_FIELD_CONDITION),
    humidity: asPlainUi(parts[3] || "", MAX_FIELD_HUMIDITY),
    wind: asPlainUi(parts[4] || "", MAX_FIELD_WIND),
    location: asPlainUi(parts[5] || "", MAX_FIELD_LOCATION)
  }
}

function parseWeatherLine(chart) {
  if (!withinByteCap(chart, MAX_CHART_BYTES)) return null
  var match = String(chart || "").match(/^Weather:\s*(.+)$/m)
  if (!match) return null

  var parts = match[1].split(",").map(trim)
  if (parts.length < 2) return null

  var head = asPlainUi(parts[0], MAX_FIELD_EMOJI + MAX_FIELD_CONDITION + 1)
  var emojiMatch = head.match(/^(\S+)\s+(.*)$/)
  var emoji = emojiMatch ? emojiMatch[1] : ""
  var condition = emojiMatch ? emojiMatch[2] : head
  var temp = asPlainUi((parts[1] || "").replace(/^\+/, ""), MAX_FIELD_TEMP)
  if (!temp) return null

  return {
    emoji: asPlainUi(emoji, MAX_FIELD_EMOJI),
    temp: temp,
    tempShort: asPlainUi(temp.replace(/[CF]$/, ""), MAX_FIELD_TEMP),
    condition: asPlainUi(condition, MAX_FIELD_CONDITION),
    humidity: asPlainUi(parts[2] || "", MAX_FIELD_HUMIDITY),
    wind: asPlainUi(parts[3] || "", MAX_FIELD_WIND),
    location: ""
  }
}

function cleanChart(raw) {
  var text = String(raw || "")
  if (text.length >= MAX_CHART_BYTES) return ""
  text = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  text = text.replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "")
  text = text.replace(/\x1B[()]./g, "")
  text = text.replace(/\n(?:\x1B\[[0-9;]*m)*Follow [^\n]*/g, "")
  text = text.replace(/[\t ]+$/gm, "").replace(/\s+$/g, "")
  if (text.length >= MAX_CHART_BYTES) return ""
  return text
}

function isBoxLine(line) {
  var s = stripAnsi(line)
  var i = 0
  while (i < s.length && (s.charAt(i) === " " || s.charAt(i) === "\t")) i++
  if (i >= s.length) return false
  var code = s.charCodeAt(i)
  return code >= 0x2500 && code <= 0x257F
}

function splitChart(raw) {
  var cleaned = cleanChart(raw)
  if (!cleaned) return { box: "", footer: "" }
  var lines = cleaned.split("\n")
  var lastBox = -1
  for (var i = 0; i < lines.length; i++) {
    if (isBoxLine(lines[i])) lastBox = i
  }
  if (lastBox < 0) return { box: cleaned, footer: "" }
  return {
    box: lines.slice(0, lastBox + 1).join("\n"),
    footer: asPlainMultiline(trim(lines.slice(lastBox + 1).join("\n")), MAX_FOOTER_CHARS)
  }
}

function chartFrameLine(raw) {
  var lines = stripAnsi(typeof raw === "string" ? raw : (raw && raw.box) || "").split("\n")
  var i
  for (i = 0; i < lines.length; i++) {
    var code = lines[i].charCodeAt(0)
    if (code === 0x250C || code === 0x2514) return lines[i]
  }
  return ""
}

function visualWidth(text) {
  var s = String(text || "")
  var width = 0
  for (var i = 0; i < s.length; i++) {
    var code = s.charCodeAt(i)
    if (code >= 0xD800 && code <= 0xDBFF) {
      width += 2
      i++
      continue
    }
    if (code >= 0xFE00 && code <= 0xFE0F) continue
    if (code === 0x200D) continue
    if ((code >= 0x2600 && code <= 0x27BF) || (code >= 0x2B00 && code <= 0x2BFF)) {
      width += 2
      continue
    }
    width += 1
  }
  return width
}

function chartColumns(boxRaw) {
  var frame = chartFrameLine(boxRaw)
  var cols = visualWidth(frame)
  if (!(cols > 0)) cols = 74
  if (cols > MAX_CHART_COLS) cols = MAX_CHART_COLS
  return cols
}

function widthRuler(columns) {
  var n = Math.max(1, parseInt(columns, 10) || 74)
  if (n > MAX_CHART_COLS) n = MAX_CHART_COLS
  var s = ""
  for (var i = 0; i < n; i++) s += "0"
  return s
}

function pad2(n) {
  var v = Math.max(0, Math.min(255, Math.round(Number(n) || 0)))
  return ("0" + v.toString(16)).slice(-2)
}

function rgbHex(r, g, b) {
  return "#" + pad2(r) + pad2(g) + pad2(b)
}

function colorToHex(c) {
  if (!c) return "#ffffff"
  if (typeof c === "string") {
    var s = c.replace(/^\s+|\s+$/g, "")
    if (s.charAt(0) === "#" && s.length >= 7) return s.slice(0, 7).toLowerCase()
    return "#ffffff"
  }
  return rgbHex(c.r * 255, c.g * 255, c.b * 255)
}

function ansi256ToHex(n) {
  n = parseInt(n, 10)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 16) {
    var basic = [
      "#000000", "#800000", "#008000", "#808000",
      "#000080", "#800080", "#008080", "#c0c0c0",
      "#808080", "#ff0000", "#00ff00", "#ffff00",
      "#0000ff", "#ff00ff", "#00ffff", "#ffffff"
    ]
    return basic[n]
  }
  if (n >= 232) {
    var gray = 8 + (n - 232) * 10
    return rgbHex(gray, gray, gray)
  }
  n -= 16
  var levels = [0, 95, 135, 175, 215, 255]
  return rgbHex(levels[Math.floor(n / 36)], levels[Math.floor((n % 36) / 6)], levels[n % 6])
}

function dimHex(hex) {
  var s = String(hex || "#ffffff")
  if (s.charAt(0) !== "#" || s.length < 7) return "#999999"
  return rgbHex(
    parseInt(s.slice(1, 3), 16) * 0.6,
    parseInt(s.slice(3, 5), 16) * 0.6,
    parseInt(s.slice(5, 7), 16) * 0.6
  )
}

function htmlEscape(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

function applySgr(params, state) {
  if (!params || !params.length) params = ["0"]
  for (var i = 0; i < params.length; i++) {
    var n = parseInt(params[i], 10)
    if (!isFinite(n) || params[i] === "") n = 0
    if (n === 0) {
      state.fg = null
      state.bg = null
      state.dim = false
      state.bold = false
    } else if (n === 1) {
      state.bold = true
    } else if (n === 2) {
      state.dim = true
    } else if (n === 22) {
      state.dim = false
      state.bold = false
    } else if (n === 39) {
      state.fg = null
    } else if (n === 49) {
      state.bg = null
    } else if (n >= 30 && n <= 37) {
      state.fg = ansi256ToHex(n - 30)
    } else if (n >= 90 && n <= 97) {
      state.fg = ansi256ToHex(n - 90 + 8)
    } else if (n >= 40 && n <= 47) {
      state.bg = ansi256ToHex(n - 40)
    } else if (n >= 100 && n <= 107) {
      state.bg = ansi256ToHex(n - 100 + 8)
    } else if (n === 38 || n === 48) {
      var isFg = n === 38
      var mode = parseInt(params[++i], 10)
      if (mode === 5) {
        var hex = ansi256ToHex(params[++i])
        if (isFg) state.fg = hex
        else state.bg = hex
      } else if (mode === 2) {
        var hexRgb = rgbHex(params[++i], params[++i], params[++i])
        if (isFg) state.fg = hexRgb
        else state.bg = hexRgb
      }
    }
  }
}

function ansiToHtml(raw, defaultColor) {
  if (String(raw || "").length >= MAX_CHART_BYTES) return ""
  var s = cleanChart(raw)
  if (!s) return ""
  var fallback = colorToHex(defaultColor)
  var state = { fg: null, bg: null, dim: false, bold: false }
  var out = []
  var run = ""
  var lineCount = 1
  var colCount = 0
  var spanCount = 0
  var stopped = false

  function flush() {
    if (!run) return
    if (spanCount >= MAX_CHART_SPANS) {
      run = ""
      stopped = true
      return
    }
    var fg = state.fg || fallback
    if (state.dim) fg = dimHex(fg)
    var open = '<font color="' + fg + '">'
    if (state.bold) open = "<b>" + open
    var close = state.bold ? "</font></b>" : "</font>"
    out.push(open + htmlEscape(run).replace(/ /g, "&nbsp;") + close)
    run = ""
    spanCount++
  }

  function appendLine(text) {
    if (stopped) return
    var piece = String(text || "")
    var room = MAX_CHART_COLS - colCount
    if (room <= 0) return
    if (piece.length > room) piece = piece.slice(0, room)
    run += piece
    colCount += piece.length
  }

  function newline() {
    if (stopped) return
    if (lineCount >= MAX_CHART_LINES) {
      flush()
      stopped = true
      return
    }
    flush()
    out.push("<br/>")
    lineCount++
    colCount = 0
  }

  var re = /\x1B(?:\[([0-9;]*)([A-Za-z])|\][^\x07]*(?:\x07|\x1B\\)|[()].|.)/g
  var last = 0
  var match
  while (!stopped && (match = re.exec(s))) {
    var chunk = s.slice(last, match.index)
    if (chunk) {
      var lines = chunk.split("\n")
      for (var i = 0; i < lines.length; i++) {
        if (i) newline()
        appendLine(lines[i])
        if (stopped) break
      }
    }
    last = re.lastIndex
    if (!stopped && match[2] === "m") {
      flush()
      applySgr(String(match[1] || "").split(";"), state)
    }
  }
  if (!stopped) {
    var tail = s.slice(last)
    if (tail) {
      var tailLines = tail.split("\n")
      for (var j = 0; j < tailLines.length; j++) {
        if (j) newline()
        appendLine(tailLines[j])
        if (stopped) break
      }
    }
  }
  flush()
  var html = out.join("")
  if (html.length > MAX_CHART_BYTES * 4) return ""
  return html
}

function barLabel(compact, vertical) {
  if (!compact) return "…"
  var label = ""
  if (vertical) label = compact.emoji || compact.tempShort || "…"
  else if (compact.emoji && compact.tempShort) label = compact.emoji + " " + compact.tempShort
  else label = compact.emoji || compact.tempShort || "…"
  label = asPlainUi(label, MAX_LABEL_CHARS)
  return label || "…"
}

function tooltip(compact) {
  if (!compact) return "Omaweather"
  var bits = []
  if (compact.location) bits.push(compact.location)
  if (compact.condition) bits.push(compact.condition)
  if (compact.temp) bits.push(compact.temp)
  if (compact.humidity) bits.push(compact.humidity)
  if (compact.wind) bits.push(compact.wind)
  var text = asPlainUi(bits.length ? bits.join(" · ") : "Omaweather", MAX_TOOLTIP_CHARS)
  return text || "Omaweather"
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_COMPACT_BYTES: MAX_COMPACT_BYTES,
    MAX_CHART_BYTES: MAX_CHART_BYTES,
    defaultLocation: defaultLocation,
    clampLocation: clampLocation,
    encodeLocation: encodeLocation,
    compactUrl: compactUrl,
    chartUrl: chartUrl,
    cappedCurl: cappedCurl,
    asPlainUi: asPlainUi,
    asPlainMultiline: asPlainMultiline,
    withinByteCap: withinByteCap,
    stripAnsi: stripAnsi,
    parseCompact: parseCompact,
    parseWeatherLine: parseWeatherLine,
    cleanChart: cleanChart,
    splitChart: splitChart,
    chartFrameLine: chartFrameLine,
    chartColumns: chartColumns,
    widthRuler: widthRuler,
    colorToHex: colorToHex,
    ansiToHtml: ansiToHtml,
    barLabel: barLabel,
    tooltip: tooltip
  }
}
