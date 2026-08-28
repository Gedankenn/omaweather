function defaultLocation() {
  return ""
}

function encodeLocation(location) {
  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  if (!name) return ""
  return encodeURIComponent(name).replace(/%20/g, "+")
}

function compactUrl(location) {
  return "https://wttr.in/" + encodeLocation(location) + "?format=%c|%t|%C|%h|%w|%l&m"
}

function chartUrl(location) {
  return "https://v2.wttr.in/" + encodeLocation(location) + "?F&m"
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
  var parts = stripAnsi(raw).replace(/\r/g, "").split("|")
  if (parts.length < 2) return null

  var temp = trim(parts[1]).replace(/^\+/, "")
  if (!temp) return null

  return {
    emoji: trim(parts[0]),
    temp: temp,
    tempShort: temp.replace(/[CF]$/, ""),
    condition: trim(parts[2] || ""),
    humidity: trim(parts[3] || ""),
    wind: trim(parts[4] || ""),
    location: trim(parts[5] || "")
  }
}

function parseWeatherLine(chart) {
  var match = String(chart || "").match(/^Weather:\s*(.+)$/m)
  if (!match) return null

  var parts = match[1].split(",").map(trim)
  if (parts.length < 2) return null

  var head = parts[0]
  var emojiMatch = head.match(/^(\S+)\s+(.*)$/)
  var emoji = emojiMatch ? emojiMatch[1] : ""
  var condition = emojiMatch ? emojiMatch[2] : head
  var temp = (parts[1] || "").replace(/^\+/, "")
  if (!temp) return null

  return {
    emoji: emoji,
    temp: temp,
    tempShort: temp.replace(/[CF]$/, ""),
    condition: condition,
    humidity: parts[2] || "",
    wind: parts[3] || "",
    location: ""
  }
}

function cleanChart(raw) {
  var text = String(raw || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  text = text.replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "")
  text = text.replace(/\x1B[()]./g, "")
  text = text.replace(/\n(?:\x1B\[[0-9;]*m)*Follow [^\n]*/g, "")
  return text.replace(/[\t ]+$/gm, "").replace(/\s+$/g, "")
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
    footer: trim(lines.slice(lastBox + 1).join("\n"))
  }
}

function chartFrameLine(raw) {
  var lines = stripAnsi(typeof raw === "string" ? raw : (raw && raw.box) || "").split("\n")
  var i
  for (i = 0; i < lines.length; i++) {
    var first = lines[i].charAt(0)
    if (first === "┌" || first === "└") return lines[i]
  }
  var best = ""
  for (i = 0; i < lines.length; i++) {
    if (isBoxLine(lines[i]) && lines[i].length > best.length) best = lines[i]
  }
  return best
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
  var s = cleanChart(raw)
  var fallback = colorToHex(defaultColor)
  var state = { fg: null, bg: null, dim: false, bold: false }
  var out = []
  var run = ""

  function flush() {
    if (!run) return
    var fg = state.fg || fallback
    if (state.dim) fg = dimHex(fg)
    var open = '<font color="' + fg + '">'
    if (state.bold) open = "<b>" + open
    var close = state.bold ? "</font></b>" : "</font>"
    out.push(open + htmlEscape(run).replace(/ /g, "&nbsp;") + close)
    run = ""
  }

  var re = /\x1B(?:\[([0-9;]*)([A-Za-z])|\][^\x07]*(?:\x07|\x1B\\)|[()].|.)/g
  var last = 0
  var match
  while ((match = re.exec(s))) {
    var chunk = s.slice(last, match.index)
    if (chunk) {
      var lines = chunk.split("\n")
      for (var i = 0; i < lines.length; i++) {
        if (i) {
          flush()
          out.push("<br/>")
        }
        run += lines[i]
      }
    }
    last = re.lastIndex
    if (match[2] === "m") {
      flush()
      applySgr(String(match[1] || "").split(";"), state)
    }
  }
  var tail = s.slice(last)
  if (tail) {
    var tailLines = tail.split("\n")
    for (var j = 0; j < tailLines.length; j++) {
      if (j) {
        flush()
        out.push("<br/>")
      }
      run += tailLines[j]
    }
  }
  flush()
  return out.join("")
}

function barLabel(compact, vertical) {
  if (!compact) return "…"
  if (vertical) return compact.emoji || compact.tempShort || "…"
  if (compact.emoji && compact.tempShort) return compact.emoji + " " + compact.tempShort
  return compact.emoji || compact.tempShort || "…"
}

function tooltip(compact) {
  if (!compact) return "wttr.in"
  var bits = []
  if (compact.location) bits.push(compact.location)
  if (compact.condition) bits.push(compact.condition)
  if (compact.temp) bits.push(compact.temp)
  if (compact.humidity) bits.push(compact.humidity)
  if (compact.wind) bits.push(compact.wind)
  return bits.length ? bits.join(" · ") : "wttr.in"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultLocation: defaultLocation,
    encodeLocation: encodeLocation,
    compactUrl: compactUrl,
    chartUrl: chartUrl,
    stripAnsi: stripAnsi,
    parseCompact: parseCompact,
    parseWeatherLine: parseWeatherLine,
    cleanChart: cleanChart,
    splitChart: splitChart,
    chartFrameLine: chartFrameLine,
    colorToHex: colorToHex,
    ansiToHtml: ansiToHtml,
    barLabel: barLabel,
    tooltip: tooltip
  }
}
