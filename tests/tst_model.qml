import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "PeriBatteryModel"

  function device(kind, name, percent, state, approximate) {
    return { kind: kind, name: name, percent: percent, approximate: approximate === true, state: state || "discharging", path: "hidpp_battery_0" }
  }

  function test_plain_strips_markup_and_controls() {
    compare(Model.plain("<img src=\"leak.png\">MX & Keys", 64), "img src=\"leak.png\"MX  Keys")
    compare(Model.plain("A\u0000B\u001fC\u007fD\u0085E", 64), "ABCDE")
    compare(Model.plain("\u202eevil\u2066x\u200fy\u2028z", 64), "evilxyz")
    compare(Model.plain("  padded  ", 64), "padded")
  }

  function test_plain_caps_length_and_handles_non_strings() {
    compare(Model.plain("abcdefghij", 4), "abcd")
    compare(Model.plain(undefined, 10), "")
    compare(Model.plain(null, 10), "")
    compare(Model.plain(42, 10), "42")
    compare(Model.plain("x".repeat(500)).length, 64)
  }

  function test_displayName_strips_vendor_prefix_and_sanitizes() {
    compare(Model.displayName("Logitech MX Keys"), "MX Keys")
    compare(Model.displayName("Logitech PRO X 2 SE"), "PRO X 2 SE")
    compare(Model.displayName("G502 <b>"), "G502 b")
    compare(Model.displayName("", "mouse"), "Mouse")
    compare(Model.displayName("Logitech ", "keyboard"), "Keyboard")
    compare(Model.displayName("Logitech " + "z".repeat(100)).length, 48)
  }

  function test_sortDevices_keyboard_first_then_mouse_then_name() {
    var sorted = Model.sortDevices([
      device("mouse", "PRO X", 93),
      device("keyboard", "MX Keys", 100),
      device("mouse", "Anywhere", 50)
    ])
    compare(sorted.length, 3)
    compare(sorted[0].name, "MX Keys")
    compare(sorted[1].name, "Anywhere")
    compare(sorted[2].name, "PRO X")
  }

  function test_sortDevices_does_not_mutate_and_tolerates_bad_input() {
    var input = [device("mouse", "B", 1), device("keyboard", "A", 2)]
    Model.sortDevices(input)
    compare(input[0].name, "B")
    compare(Model.sortDevices(null).length, 0)
    compare(Model.sortDevices(undefined).length, 0)
  }

  function test_glyph_per_kind() {
    compare(Model.glyph("keyboard"), "󰌌")
    compare(Model.glyph("mouse"), "󰍽")
    compare(Model.glyph("other"), "󰍽")
    compare(Model.chargingGlyph, "󱐋")
  }

  function test_colorTier_charging_overrides_level() {
    compare(Model.colorTier({ state: "charging", percent: null }), "charging")
    compare(Model.colorTier({ state: "charging", percent: 5 }), "charging")
    compare(Model.colorTier({ state: "discharging", percent: 5 }), "critical")
    compare(Model.colorTier({ state: "discharging", percent: 93 }), "ok")
    compare(Model.colorTier({ state: "offline", percent: null }), "unknown")
    compare(Model.colorTier(null), "unknown")
  }

  function test_connectionLabel_by_state() {
    compare(Model.connectionLabel("charging"), "Charging via USB")
    compare(Model.connectionLabel("offline"), "Not connected to the receiver")
    compare(Model.connectionLabel("discharging"), "Connected via receiver")
    compare(Model.connectionLabel("full"), "Connected via receiver")
    compare(Model.connectionLabel(undefined), "Connected via receiver")
  }

  function test_levelTier_thresholds() {
    compare(Model.levelTier(5), "critical")
    compare(Model.levelTier(10), "critical")
    compare(Model.levelTier(11), "low")
    compare(Model.levelTier(20), "low")
    compare(Model.levelTier(21), "ok")
    compare(Model.levelTier(100), "ok")
    compare(Model.levelTier(null), "unknown")
    compare(Model.levelTier(undefined), "unknown")
  }

  function test_stateLabel_maps_known_states() {
    compare(Model.stateLabel("charging"), "Charging")
    compare(Model.stateLabel("discharging"), "On battery")
    compare(Model.stateLabel("full"), "Fully charged")
    compare(Model.stateLabel("not-charging"), "Not charging")
    compare(Model.stateLabel("offline"), "Not connected")
    compare(Model.stateLabel("unknown"), "Unknown")
    compare(Model.stateLabel("garbage"), "Unknown")
    compare(Model.stateLabel("__proto__"), "Unknown")
  }

  function test_barLabel_shows_glyph_percent_and_charging_bolt() {
    compare(Model.barLabel(device("keyboard", "MX Keys", 100, "full"), true), "󰌌 100%")
    compare(Model.barLabel(device("mouse", "PRO", 93), true), "󰍽 93%")
    compare(Model.barLabel(device("mouse", "PRO", 40, "charging"), true), "󰍽 40% 󱐋")
  }

  function test_barLabel_hides_percent_when_disabled_or_unknown() {
    compare(Model.barLabel(device("mouse", "PRO", 93), false), "󰍽")
    compare(Model.barLabel(device("mouse", "PRO", 40, "charging"), false), "󰍽 󱐋")
    compare(Model.barLabel(device("keyboard", "MX", null), true), "󰌌 —")
  }

  function test_barLabel_charging_without_level_shows_only_glyph_and_bolt() {
    compare(Model.barLabel(device("keyboard", "MX", null, "charging"), true), "󰌌 󱐋")
  }

  function test_barLabel_marks_approximate_levels() {
    compare(Model.barLabel(device("keyboard", "MX", 95, "full", true), true), "󰌌 ~95%")
  }

  function test_percentText() {
    compare(Model.percentText(93), "93%")
    compare(Model.percentText(95, true), "~95%")
    compare(Model.percentText(null), "—")
    compare(Model.percentText(null, true), "—")
  }

  function test_levelText_is_empty_for_charging_device_without_level() {
    compare(Model.levelText(device("keyboard", "MX", null, "charging")), "")
    compare(Model.levelText(device("keyboard", "MX", null, "offline")), "—")
    compare(Model.levelText(device("mouse", "PRO", 93)), "93%")
    compare(Model.levelText(device("keyboard", "MX", 60, "discharging", true)), "~60%")
  }

  function test_shortLevelText_for_vertical_bar() {
    compare(Model.shortLevelText(device("mouse", "PRO", 93)), "93")
    compare(Model.shortLevelText(device("keyboard", "MX", 60, "discharging", true)), "~60")
    compare(Model.shortLevelText(device("keyboard", "MX", null, "charging")), "")
    compare(Model.shortLevelText(device("keyboard", "MX", null, "offline")), "—")
  }

  function test_tooltip_lists_devices_safely() {
    var text = Model.tooltip([
      device("keyboard", "MX <Keys>", 95, "full", true),
      device("mouse", "PRO", 93),
      device("keyboard", "Craft", null, "charging")
    ])
    compare(text, "MX Keys ~95% · Fully charged\nPRO 93% · On battery\nCraft · Charging")
    compare(Model.tooltip([]), "No Logitech devices")
  }

  // --- sysfs ---------------------------------------------------------------

  function test_isBatteryEntry_accepts_only_hidpp_battery_names() {
    verify(Model.isBatteryEntry("hidpp_battery_0"))
    verify(Model.isBatteryEntry("hidpp_battery_123"))
    verify(!Model.isBatteryEntry("hidpp_battery_1234"))
    verify(!Model.isBatteryEntry("hidpp_battery_"))
    verify(!Model.isBatteryEntry("hidpp_battery_1/../BAT0"))
    verify(!Model.isBatteryEntry("hidpp_battery_1\n"))
    verify(!Model.isBatteryEntry("xhidpp_battery_1"))
    verify(!Model.isBatteryEntry("BAT0"))
    verify(!Model.isBatteryEntry(""))
    verify(!Model.isBatteryEntry(null))
    verify(!Model.isBatteryEntry(undefined))
    verify(!Model.isBatteryEntry(7))
  }

  function test_attributePath_builds_fixed_paths_only() {
    compare(Model.attributePath("hidpp_battery_1", "status"), "/sys/class/power_supply/hidpp_battery_1/status")
    compare(Model.attributePath("hidpp_battery_0", "capacity_level"), "/sys/class/power_supply/hidpp_battery_0/capacity_level")
    compare(Model.attributePath("hidpp_battery_0", "model_name"), "/sys/class/power_supply/hidpp_battery_0/model_name")
    compare(Model.attributePath("hidpp_battery_0", "online"), "/sys/class/power_supply/hidpp_battery_0/online")
    compare(Model.attributePath("hidpp_battery_0", "capacity"), "/sys/class/power_supply/hidpp_battery_0/capacity")
    compare(Model.attributePath("hidpp_battery_0", "uevent"), "")
    compare(Model.attributePath("hidpp_battery_0", "../../../etc/passwd"), "")
    compare(Model.attributePath("../hidpp_battery_0", "status"), "")
    compare(Model.attributePath(undefined, "status"), "")
  }

  function test_parseSysfsValue_trims_and_caps() {
    compare(Model.parseSysfsValue("Charging\n"), "Charging")
    compare(Model.parseSysfsValue("  93 \n"), "93")
    compare(Model.parseSysfsValue(""), "")
    compare(Model.parseSysfsValue(null), "")
    compare(Model.parseSysfsValue(undefined), "")
    compare(Model.parseSysfsValue("x".repeat(500)).length, 128)
  }

  function test_kindFromName_classifies_keyboards_by_name() {
    compare(Model.kindFromName("MX Keys Wireless Keyboard"), "keyboard")
    compare(Model.kindFromName("MX Keys Mini"), "keyboard")
    compare(Model.kindFromName("Craft Advanced Keyboard"), "keyboard")
    compare(Model.kindFromName("MX Mechanical"), "keyboard")
    compare(Model.kindFromName("K850"), "keyboard")
    compare(Model.kindFromName("Wireless Keyboard K270"), "keyboard")
    compare(Model.kindFromName("POP KEYS"), "keyboard")
  }

  function test_kindFromName_defaults_to_mouse() {
    compare(Model.kindFromName("PRO X SUPERLIGHT 2 SE"), "mouse")
    compare(Model.kindFromName("MX Master 3S"), "mouse")
    compare(Model.kindFromName("G502 X PLUS"), "mouse")
    compare(Model.kindFromName("Keystone Mouse"), "mouse")
    compare(Model.kindFromName("K1234 Mouse"), "mouse")
    compare(Model.kindFromName(""), "mouse")
    compare(Model.kindFromName(undefined), "mouse")
  }

  function test_levelPercent_maps_coarse_levels() {
    compare(Model.levelPercent("Full"), 95)
    compare(Model.levelPercent("High"), 80)
    compare(Model.levelPercent("Normal"), 60)
    compare(Model.levelPercent("Low"), 20)
    compare(Model.levelPercent("Critical"), 5)
    compare(Model.levelPercent("Unknown"), null)
    compare(Model.levelPercent(""), null)
    compare(Model.levelPercent("constructor"), null)
    compare(Model.levelPercent(undefined), null)
  }

  function test_stateFromStatus_maps_kernel_status() {
    compare(Model.stateFromStatus("Charging", "1"), "charging")
    compare(Model.stateFromStatus("Full", "1"), "full")
    compare(Model.stateFromStatus("Discharging", "1"), "discharging")
    compare(Model.stateFromStatus("Not charging", "1"), "not-charging")
    compare(Model.stateFromStatus("Unknown", "1"), "unknown")
    compare(Model.stateFromStatus("", ""), "unknown")
    compare(Model.stateFromStatus("weird", "1"), "unknown")
  }

  function test_stateFromStatus_offline_unless_charging_or_full() {
    compare(Model.stateFromStatus("Charging", "0"), "charging")
    compare(Model.stateFromStatus("Full", "0"), "full")
    compare(Model.stateFromStatus("Discharging", "0"), "offline")
    compare(Model.stateFromStatus("Unknown", "0"), "offline")
    compare(Model.stateFromStatus("Not charging", "0"), "offline")
  }

  function test_fromSysfs_mouse_with_exact_capacity() {
    var d = Model.fromSysfs({ name: "PRO X SUPERLIGHT 2 SE", status: "Discharging", capacity: "93", capacityLevel: "", online: "1", path: "hidpp_battery_0" })
    compare(d.kind, "mouse")
    compare(d.name, "PRO X SUPERLIGHT 2 SE")
    compare(d.percent, 93)
    compare(d.approximate, false)
    compare(d.state, "discharging")
    compare(d.path, "hidpp_battery_0")
  }

  function test_fromSysfs_keyboard_charging_without_level() {
    var d = Model.fromSysfs({ name: "MX Keys Wireless Keyboard", status: "Charging", capacity: "", capacityLevel: "Unknown", online: "0", path: "hidpp_battery_1" })
    compare(d.kind, "keyboard")
    compare(d.name, "MX Keys Wireless Keyboard")
    compare(d.percent, null)
    compare(d.approximate, false)
    compare(d.state, "charging")
  }

  function test_fromSysfs_uses_coarse_level_as_approximate() {
    var d = Model.fromSysfs({ name: "MX Keys", status: "Discharging", capacity: "", capacityLevel: "Full", online: "1", path: "hidpp_battery_1" })
    compare(d.percent, 95)
    compare(d.approximate, true)
  }

  function test_fromSysfs_capacity_is_strict_and_clamped() {
    function pct(c) { return Model.fromSysfs({ name: "M", status: "Discharging", capacity: c, capacityLevel: "", online: "1" }).percent }
    compare(pct("0"), 0)
    compare(pct("100"), 100)
    compare(pct("250"), 100)
    compare(pct("-5"), null)
    compare(pct("9.5"), null)
    compare(pct("12abc"), null)
    compare(pct("1234"), null)
    compare(pct(""), null)
    compare(pct(undefined), null)
  }

  function test_fromSysfs_offline_has_no_percent() {
    var d = Model.fromSysfs({ name: "PRO", status: "Discharging", capacity: "40", capacityLevel: "", online: "0" })
    compare(d.state, "offline")
    compare(d.percent, null)
    compare(d.approximate, false)
  }

  function test_fromSysfs_sanitizes_name_and_tolerates_bad_input() {
    var d = Model.fromSysfs({ name: "Logitech <b>K" + "z".repeat(100), status: "Full", online: "1" })
    verify(d.name.indexOf("<") < 0)
    verify(d.name.length <= 48)
    compare(Model.fromSysfs(null).name, "Mouse")
    compare(Model.fromSysfs(undefined).state, "unknown")
  }

  function test_attributePath_allows_serial_number() {
    compare(Model.attributePath("hidpp_battery_3", "serial_number"), "/sys/class/power_supply/hidpp_battery_3/serial_number")
  }

  function test_buildDevices_merges_receiver_and_cable_twins_by_serial() {
    var records = [
      { name: "PRO X SUPERLIGHT 2 SE", serial: "dc-35-d8-6a", status: "Unknown", capacity: "93", online: "0", path: "hidpp_battery_0" },
      { name: "MX Keys Wireless Keyboard", serial: "5f-94-d9-9c", status: "Discharging", capacityLevel: "Full", online: "1", path: "hidpp_battery_1" },
      { name: "PRO X SUPERLIGHT 2 SE", serial: "dc-35-d8-6a", status: "Charging", capacity: "93", online: "1", path: "hidpp_battery_3" }
    ]
    var out = Model.buildDevices(records)
    compare(out.length, 2)
    compare(out[1].kind, "mouse")
    compare(out[1].state, "charging")
    compare(out[1].percent, 93)
    compare(out[1].path, "hidpp_battery_3")
  }

  function test_buildDevices_prefers_online_twin_regardless_of_order() {
    var records = [
      { name: "PRO X", serial: "aa-bb", status: "Charging", capacity: "50", online: "1", path: "hidpp_battery_3" },
      { name: "PRO X", serial: "aa-bb", status: "Unknown", capacity: "50", online: "0", path: "hidpp_battery_0" }
    ]
    var out = Model.buildDevices(records)
    compare(out.length, 1)
    compare(out[0].path, "hidpp_battery_3")
  }

  function test_buildDevices_does_not_merge_without_serial() {
    var records = [
      { name: "PRO X", status: "Discharging", capacity: "50", online: "1", path: "hidpp_battery_0" },
      { name: "PRO X", status: "Discharging", capacity: "40", online: "1", path: "hidpp_battery_1" }
    ]
    compare(Model.buildDevices(records).length, 2)
  }

  function test_buildDevices_filters_sorts_and_caps() {
    var records = [
      { name: "PRO X", status: "Discharging", capacity: "93", online: "1", path: "hidpp_battery_0" },
      { name: "MX Keys Wireless Keyboard", status: "Charging", capacityLevel: "Unknown", online: "0", path: "hidpp_battery_1" },
      { name: "Evil", status: "Full", online: "1", path: "../BAT0" },
      null
    ]
    var out = Model.buildDevices(records)
    compare(out.length, 2)
    compare(out[0].kind, "keyboard")
    compare(out[1].percent, 93)
    var many = []
    for (var i = 0; i < 40; i++) many.push({ name: "M" + i, status: "Full", online: "1", path: "hidpp_battery_" + i })
    compare(Model.buildDevices(many).length, Model.MAX_DEVICES)
    compare(Model.buildDevices(null).length, 0)
  }
}
