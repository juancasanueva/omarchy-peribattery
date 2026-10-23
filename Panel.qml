import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "juancasanueva.peribattery"
  ipcTarget: "juancasanueva.peribattery"

  readonly property bool showPercentage: setting("showPercentage", true) === true
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color urgentColor: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property color panelText: Commons.Color.popups.text

  // Logitech keyboards and mice as plain objects, read from the kernel's
  // hid-logitech-hidpp power supplies in /sys/class/power_supply. sysfs sends
  // no change notifications, so the list is refreshed every 30 s and whenever
  // the panel opens.
  property var devices: []
  readonly property bool hasDevices: devices.length > 0
  readonly property real openPanelIndicatorWidth: button.vertical ? 0 : barRow.implicitWidth

  // Publishes only once the folder scan and every reader have settled, so a
  // rescan never flashes an empty or half-read list.
  function rebuild() {
    if (entries.status !== FolderListModel.Ready || readers.count !== entries.count) return
    var records = []
    for (var i = 0; i < readers.count; i++) {
      var reader = readers.objectAt(i)
      if (!reader || !reader.ready) return
      records.push(reader.record)
    }
    root.devices = Model.buildDevices(records)
  }

  // Resetting the folder rescans the directory; the readers are recreated and
  // every attribute is read again.
  function refresh() {
    entries.folder = ""
    entries.folder = "file://" + Model.SYSFS_ROOT
  }

  onOpenedChanged: if (root.opened) root.refresh()

  FolderListModel {
    id: entries
    folder: "file://" + Model.SYSFS_ROOT
    nameFilters: ["hidpp_battery_*"]
    showDirs: true
    showFiles: true
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    onStatusChanged: settle.restart()
  }

  Instantiator {
    id: readers
    model: entries
    onObjectAdded: settle.restart()
    onObjectRemoved: settle.restart()

    delegate: QtObject {
      id: reader
      required property string fileName
      required property int index
      // The entry name is validated before it is joined onto the sysfs root.
      readonly property string entry: index < Model.MAX_DEVICES && Model.isBatteryEntry(fileName) ? fileName : ""
      readonly property bool ready: entry === "" || (modelName.settled && serialNumber.settled && status.settled && capacity.settled && capacityLevel.settled && online.settled)
      readonly property var record: ({
        path: entry,
        name: modelName.value,
        serial: serialNumber.value,
        status: status.value,
        capacity: capacity.value,
        capacityLevel: capacityLevel.value,
        online: online.value
      })
      onRecordChanged: settle.restart()
      onReadyChanged: settle.restart()

      property SysfsAttribute modelName: SysfsAttribute { path: Model.attributePath(reader.entry, "model_name") }
      property SysfsAttribute serialNumber: SysfsAttribute { path: Model.attributePath(reader.entry, "serial_number") }
      property SysfsAttribute status: SysfsAttribute { path: Model.attributePath(reader.entry, "status") }
      property SysfsAttribute capacity: SysfsAttribute { path: Model.attributePath(reader.entry, "capacity") }
      property SysfsAttribute capacityLevel: SysfsAttribute { path: Model.attributePath(reader.entry, "capacity_level") }
      property SysfsAttribute online: SysfsAttribute { path: Model.attributePath(reader.entry, "online") }
    }
  }

  // Read-only view of one kernel attribute. A missing file (the keyboard has
  // no capacity while charging over USB) settles as an empty value.
  component SysfsAttribute: FileView {
    property bool ok: false
    property bool settled: false
    readonly property string value: ok ? Model.parseSysfsValue(text()) : ""
    printErrors: false
    watchChanges: false
    onLoaded: { ok = true; settled = true }
    onLoadFailed: { ok = false; settled = true }
  }

  Timer {
    id: settle
    interval: 150
    onTriggered: root.rebuild()
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  function tierColor(device, fallback, chargingColor) {
    var tier = Model.colorTier(device)
    if (tier === "charging") return chargingColor
    if (tier === "critical" || tier === "low") return root.urgentColor
    if (tier === "unknown") return Commons.Color.muted
    return fallback
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : barRow.implicitWidth + Style.space(14)
    fixedHeight: vertical ? barColumn.implicitHeight + Style.space(12) : -1
    tooltipText: Model.tooltip(root.devices) + "\nLeft-click: details · Right-click: toggle percentage"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }

    // Horizontal bar: glyph + percentage per device, hairline between devices.
    Row {
      id: barRow
      visible: !button.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        visible: !root.hasDevices
        textFormat: Text.PlainText
        text: Model.emptyGlyph
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Repeater {
        model: root.devices

        Row {
          required property var modelData
          required property int index
          spacing: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            visible: index > 0
            width: 1
            height: Math.round(button.height * 0.45)
            color: Qt.alpha(root.barForeground, 0.35)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: Model.barLabel(modelData, root.showPercentage)
            color: root.tierColor(modelData, root.barForeground, root.barForeground)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    // Vertical bar: glyph stacked over the number per device.
    Column {
      id: barColumn
      visible: button.vertical
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        visible: !root.hasDevices
        textFormat: Text.PlainText
        text: Model.emptyGlyph
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Repeater {
        model: root.devices

        Column {
          required property var modelData
          required property int index
          spacing: Style.space(1)
          anchors.horizontalCenter: parent.horizontalCenter

          Rectangle {
            visible: index > 0
            width: Style.space(12)
            height: 1
            color: Qt.alpha(root.barForeground, 0.35)
            anchors.horizontalCenter: parent.horizontalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: Model.glyph(modelData.kind)
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.horizontalCenter: parent.horizontalCenter
          }

          Text {
            visible: root.showPercentage && text !== ""
            textFormat: Text.PlainText
            text: Model.shortLevelText(modelData)
            color: root.tierColor(modelData, root.barForeground, root.barForeground)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
          }

          Text {
            visible: modelData.state === "charging"
            textFormat: Text.PlainText
            text: Model.chargingGlyph
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          text: "PeriBattery"
          color: root.panelText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          visible: !root.hasDevices
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "No Logitech devices found. Turn on a keyboard or mouse paired to a Logitech receiver."
          color: Commons.Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.devices
          DeviceCard {
            required property var modelData
            width: column.width
            device: modelData
          }
        }

        Text {
          textFormat: Text.PlainText
          text: "Refreshes every 30 s and on open · Esc closes"
          color: Commons.Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component DeviceCard: Rectangle {
    id: card
    property var device: ({})
    readonly property color levelColor: root.tierColor(device, Commons.Color.accent, root.panelText)

    implicitHeight: cardContent.implicitHeight + Style.space(24)
    radius: Style.space(8)
    color: Qt.alpha(root.panelText, 0.05)
    border.width: 1
    border.color: Commons.Color.popups.border

    Column {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(cardGlyph.implicitHeight, cardLabels.implicitHeight, cardPercent.implicitHeight)

        Text {
          id: cardGlyph
          textFormat: Text.PlainText
          text: Model.glyph(card.device.kind)
          color: root.panelText
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: cardLabels
          anchors.left: cardGlyph.right
          anchors.leftMargin: Style.space(12)
          anchors.right: cardPercent.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: card.device.name
            elide: Text.ElideRight
            color: root.panelText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: (card.device.state === "charging" ? Model.chargingGlyph + " " : "") + Model.stateLabel(card.device.state)
            elide: Text.ElideRight
            color: card.device.state === "charging" ? root.panelText : Commons.Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: cardPercent
          textFormat: Text.PlainText
          text: Model.levelText(card.device)
          color: card.levelColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Item {
        width: parent.width
        implicitHeight: Style.space(6)

        Rectangle {
          id: gaugeTrack
          anchors.fill: parent
          radius: height / 2
          color: Qt.alpha(root.panelText, 0.12)
        }

        Rectangle {
          anchors.left: gaugeTrack.left
          anchors.verticalCenter: gaugeTrack.verticalCenter
          height: gaugeTrack.height
          radius: gaugeTrack.radius
          color: card.levelColor
          visible: card.device.percent !== null
          width: Math.max(gaugeTrack.height, gaugeTrack.width * (card.device.percent || 0) / 100)

          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: Model.connectionLabel(card.device.state)
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
