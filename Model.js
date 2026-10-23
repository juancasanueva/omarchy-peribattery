.pragma library

// Pure helpers for the PeriBattery widget. Devices are plain objects:
// { kind: "keyboard" | "mouse", name, percent: 0..100 | null, approximate, state, path }
// where state is one of charging, discharging, full, not-charging, offline, unknown.
// The raw input comes from the kernel's hid-logitech-hidpp power supplies in
// /sys/class/power_supply/hidpp_battery_N.

var chargingGlyph = "󱐋"
var emptyGlyph = "󰍽"

var DEFAULT_MAX = 64
var NAME_MAX = 48
var SYSFS_VALUE_MAX = 128
var MAX_DEVICES = 16

var SYSFS_ROOT = "/sys/class/power_supply/"
var ATTRIBUTES = ["model_name", "serial_number", "status", "capacity", "capacity_level", "online"]

var STATE_LABELS = {
  charging: "Charging",
  discharging: "On battery",
  full: "Fully charged",
  "not-charging": "Not charging",
  offline: "Not connected",
  unknown: "Unknown"
}

var STATUS_STATES = {
  Charging: "charging",
  Full: "full",
  Discharging: "discharging",
  "Not charging": "not-charging"
}

// Coarse capacity_level values, mapped like the macOS app does.
var LEVEL_PERCENT = { Full: 95, High: 80, Normal: 60, Low: 20, Critical: 5 }

var KIND_ORDER = { keyboard: 0, mouse: 1 }

function own(table, key) {
  return typeof key === "string" && Object.prototype.hasOwnProperty.call(table, key)
}

// The kernel hid-logitech-hidpp driver names its power supplies hidpp_battery_N.
// Only such names may be joined onto the sysfs root.
function isBatteryEntry(name) {
  return typeof name === "string" && /^hidpp_battery_\d{1,3}$/.test(name)
}

function attributePath(entry, attribute) {
  if (!isBatteryEntry(entry) || ATTRIBUTES.indexOf(attribute) < 0) return ""
  return SYSFS_ROOT + entry + "/" + attribute
}

function parseSysfsValue(text) {
  if (text === undefined || text === null) return ""
  return String(text).slice(0, SYSFS_VALUE_MAX * 2).trim().slice(0, SYSFS_VALUE_MAX)
}

// sysfs exposes no device type and both devices advertise the same input
// capabilities, so keyboards are recognised by their model name.
function kindFromName(name) {
  if (typeof name !== "string") return "mouse"
  return /keyboard|\bkeys\b|\bcraft\b|mechanical|\bk\d{3}\b/i.test(name) ? "keyboard" : "mouse"
}

function levelPercent(level) {
  return own(LEVEL_PERCENT, level) ? LEVEL_PERCENT[level] : null
}

function stateFromStatus(status, online) {
  var state = own(STATUS_STATES, status) ? STATUS_STATES[status] : "unknown"
  if (online === "0" && state !== "charging" && state !== "full") return "offline"
  return state
}

function capacityPercent(capacity) {
  if (typeof capacity !== "string" || !/^\d{1,3}$/.test(capacity)) return null
  return Math.min(100, parseInt(capacity, 10))
}

function fromSysfs(record) {
  var r = record && typeof record === "object" ? record : {}
  var name = parseSysfsValue(r.name)
  var kind = kindFromName(name)
  var state = stateFromStatus(parseSysfsValue(r.status), parseSysfsValue(r.online))
  var percent = capacityPercent(parseSysfsValue(r.capacity))
  var approximate = false
  if (percent === null) {
    percent = levelPercent(parseSysfsValue(r.capacityLevel))
    approximate = percent !== null
  }
  if (state === "offline") {
    percent = null
    approximate = false
  }
  return {
    kind: kind,
    name: displayName(name, kind),
    percent: percent,
    approximate: approximate,
    state: state,
    path: isBatteryEntry(r.path) ? r.path : ""
  }
}

// A device charging over its cable appears twice: once behind the receiver
// (offline) and once on USB. Twins share a serial number; keep the live one.
function buildDevices(records) {
  if (!Array.isArray(records)) return []
  var out = []
  var bySerial = Object.create(null)
  for (var i = 0; i < records.length && out.length < MAX_DEVICES; i++) {
    var r = records[i]
    if (!r || !isBatteryEntry(r.path)) continue
    var device = fromSysfs(r)
    var serial = parseSysfsValue(r.serial)
    if (serial === "") {
      out.push(device)
    } else if (!(serial in bySerial)) {
      bySerial[serial] = out.length
      out.push(device)
    } else if (out[bySerial[serial]].state === "offline" && device.state !== "offline") {
      out[bySerial[serial]] = device
    }
  }
  return sortDevices(out)
}

// Device-supplied strings reach host sinks (tooltips) the plugin cannot pin to
// plain text, so markup characters and C0/C1/bidi controls are removed and the
// length is capped.
function plain(value, max) {
  if (value === undefined || value === null) return ""
  var limit = typeof max === "number" && max > 0 ? max : DEFAULT_MAX
  var text = String(value)
    .replace(/[<>&]/g, "")
    .replace(/[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]/g, "")
    .trim()
  if (text.length > limit) {
    text = text.slice(0, limit)
    var last = text.charCodeAt(text.length - 1)
    if (last >= 0xd800 && last <= 0xdbff) text = text.slice(0, -1)
  }
  return text
}

function kindLabel(kind) {
  return kind === "keyboard" ? "Keyboard" : "Mouse"
}

function displayName(model, kind) {
  var name = plain(model, 256).replace(/^Logitech(\s+|$)/i, "")
  name = plain(name, NAME_MAX)
  return name !== "" ? name : kindLabel(kind)
}

function sortDevices(devices) {
  if (!Array.isArray(devices)) return []
  return devices.slice().sort(function(a, b) {
    var ka = KIND_ORDER[a.kind] !== undefined ? KIND_ORDER[a.kind] : 2
    var kb = KIND_ORDER[b.kind] !== undefined ? KIND_ORDER[b.kind] : 2
    if (ka !== kb) return ka - kb
    return String(a.name).localeCompare(String(b.name))
  })
}

function glyph(kind) {
  return kind === "keyboard" ? "󰌌" : "󰍽"
}

function levelTier(percent) {
  if (typeof percent !== "number" || !isFinite(percent)) return "unknown"
  if (percent <= 10) return "critical"
  if (percent <= 20) return "low"
  return "ok"
}

// Charging wins over the level: a low or unknown level is not alarming while plugged in.
function colorTier(device) {
  if (!device) return "unknown"
  if (device.state === "charging") return "charging"
  return levelTier(device.percent)
}

// A device charging over its cable still talks through the receiver; the label names the power source.
function connectionLabel(state) {
  if (state === "charging") return "Charging via USB"
  if (state === "offline") return "Not connected to the receiver"
  return "Connected via receiver"
}

function stateLabel(state) {
  return own(STATE_LABELS, state) ? STATE_LABELS[state] : STATE_LABELS.unknown
}

function hasPercent(percent) {
  return typeof percent === "number" && isFinite(percent)
}

function percentText(percent, approximate) {
  if (!hasPercent(percent)) return "—"
  return (approximate === true ? "~" : "") + percent + "%"
}

// A charging device that reports no level shows only its bolt, not a dash.
function levelText(device) {
  if (!hasPercent(device.percent) && device.state === "charging") return ""
  return percentText(device.percent, device.approximate)
}

// Vertical bars stack the number under the glyph, without the % sign.
function shortLevelText(device) {
  return levelText(device).replace("%", "")
}

function barLabel(device, showPercentage) {
  var parts = [glyph(device.kind)]
  var level = showPercentage ? levelText(device) : ""
  if (level !== "") parts.push(level)
  if (device.state === "charging") parts.push(chargingGlyph)
  return parts.join(" ")
}

function tooltip(devices) {
  if (!Array.isArray(devices) || devices.length === 0) return "No Logitech devices"
  return devices.map(function(d) {
    var level = levelText(d)
    return plain(d.name, NAME_MAX) + (level !== "" ? " " + level : "") + " · " + stateLabel(d.state)
  }).join("\n")
}
