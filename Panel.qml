import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "dizziee.system-stats"
  ipcTarget: "dizziee.system-stats"
  property var statsData: ({})
  property var compartmentsConfig: ({})
  property bool settingsMode: false
  property var draftCompartments: ({})
  property string settingsStatusText: ""
  property int dataVersion: 0
  property var prevCpuStats: null

  readonly property string barIcon: "󰵃"
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var compartmentIds: ["cpu", "gpu", "memory", "storage"]

  function refresh() {
    if (Model.compartmentEnabled(compartmentsConfig, "cpu") && !cpuProc.running) cpuProc.running = true
    if (Model.compartmentEnabled(compartmentsConfig, "gpu") && !gpuProc.running) gpuProc.running = true
    if (Model.compartmentEnabled(compartmentsConfig, "storage") && !storageProc.running) storageProc.running = true
  }

  function mergeCompartment(id, raw) {
    var parsed = Model.parseStats(raw)
    if (!parsed[id]) return
    var next = {}
    for (var k in root.statsData) next[k] = root.statsData[k]
    next[id] = parsed[id]
    if (root.statsData["memory"]) next["memory"] = root.statsData["memory"]
    if (root.statsData["cpu"] && root.statsData["cpu"].usagePct !== undefined && next["cpu"]) {
      next["cpu"].usagePct = root.statsData["cpu"].usagePct
    }
    root.statsData = next
    root.dataVersion++
  }

  function parseMemory() {
    var text = fileMeminfo.text()
    var total = Number(text.match(/MemTotal:\s*(\d+)/)?.[1] ?? 1)
    var available = Number(text.match(/MemAvailable:\s*(\d+)/)?.[1] ?? 0)
    var swapTotal = Number(text.match(/SwapTotal:\s*(\d+)/)?.[1] ?? 1)
    var swapFree = Number(text.match(/SwapFree:\s*(\d+)/)?.[1] ?? 0)
    var used = total - available
    var swapUsed = swapTotal - swapFree
    var next = {}
    for (var k in root.statsData) next[k] = root.statsData[k]
    next["memory"] = {
        usagePct: Math.round(used / total * 1000) / 10,
        usedGb: Math.round(used / 1000000 * 10) / 10,
        totalGb: Math.round(total / 1000000 * 10) / 10,
        swapUsedGb: Math.round(swapUsed / 1000000 * 10) / 10,
        swapTotalGb: Math.round(swapTotal / 1000000 * 10) / 10,
    }
    root.statsData = next
    root.dataVersion++
  }

  function parseCpu() {
    var text = fileStat.text()
    var match = text.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
    if (!match) return
    var stats = match.slice(1).map(Number)
    var total = stats.reduce(function(a, b) { return a + b })
    var idle = stats[3]
    if (prevCpuStats) {
      var totalDiff = total - prevCpuStats.total
      var idleDiff = idle - prevCpuStats.idle
      var usage = totalDiff > 0 ? Math.round(1000 * (1 - idleDiff / totalDiff)) / 10 : 0
      var cpu = root.statsData["cpu"]
      if (cpu) {
        var nextCpu = {}
        for (var ck in cpu) nextCpu[ck] = cpu[ck]
        nextCpu.usagePct = usage
        var next = {}
        for (var k in root.statsData) next[k] = root.statsData[k]
        next["cpu"] = nextCpu
        root.statsData = next
      }
    }
    prevCpuStats = { total: total, idle: idle }
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function loadCompartments() {
    var fromSettings = settings ? settings.compartments : null
    if (fromSettings && typeof fromSettings === "object") {
      var merged = {}
      var defaults = Model.defaultCompartments()
      for (var id in defaults) {
        merged[id] = fromSettings[id] || defaults[id]
      }
      compartmentsConfig = merged
    } else {
      compartmentsConfig = Model.defaultCompartments()
    }
  }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try { return JSON.parse(JSON.stringify(value)) }
    catch (e) { return fallback }
  }

  function normalizedSettings(source) {
    var next = cloneObject(source, {}) || {}
    var defaults = Model.defaultCompartments()
    if (typeof next.compartments !== "object") next.compartments = {}
    for (var id in defaults) {
      var c = next.compartments[id]
      if (typeof c !== "object") c = {}
      c.enabled = c.enabled === true
      c.pollIntervalSec = Math.max(5, Math.min(3600, Math.round(c.pollIntervalSec || 30)))
      next.compartments[id] = c
    }
    return next
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function openSettings() {
    draftCompartments = cloneObject(compartmentsConfig, {})
    settingsStatusText = ""
    settingsMode = true
    open()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function showMain() {
    settingsMode = false
    settingsStatusText = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function saveSettings() {
    var next = normalizedSettings({ compartments: draftCompartments })
    compartmentsConfig = next.compartments
    root.settings = { compartments: next.compartments }
    applyTimer()
    if (opened) startCompartmentTimers()
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, { compartments: next.compartments })
      settingsStatusText = "Saved to shell.json"
    } else {
      settingsStatusText = "Saved for this session"
    }
  }

  function draftEnabled(id) {
    return draftCompartments && draftCompartments[id] ? draftCompartments[id].enabled === true : false
  }

  function setDraftEnabled(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, pollIntervalSec: 30 }
    next[id].enabled = value === true
    draftCompartments = next
  }

  function draftInterval(id) {
    return draftCompartments && draftCompartments[id] ? (draftCompartments[id].pollIntervalSec || 30) : 30
  }

  function setDraftInterval(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, pollIntervalSec: 30 }
    next[id].pollIntervalSec = Math.max(5, Math.min(3600, Math.round(value)))
    draftCompartments = next
  }

  function applyTimer() {
    cpuTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "cpu", 30) * 1000)
    gpuTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "gpu", 30) * 1000)
    storageTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "storage", 30) * 1000)
  }

  function startCompartmentTimers() {
    cpuTimer.running = opened && Model.compartmentEnabled(compartmentsConfig, "cpu")
    gpuTimer.running = opened && Model.compartmentEnabled(compartmentsConfig, "gpu")
    storageTimer.running = opened && Model.compartmentEnabled(compartmentsConfig, "storage")
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) {
      openSettings()
      return
    }
    if (button === Qt.MiddleButton) {
      refresh()
      return
    }
    if (opened) close()
    else { open(); refresh() }
  }

  onOpenedChanged: {
    if (opened) {
      idleTimer.stop()
      startCompartmentTimers()
      refresh()
      loadCompartments()
    } else {
      settingsMode = false
      idleTimer.restart()
    }
  }

  Component.onCompleted: {
    loadCompartments()
    applyTimer()
  }

  visible: {
    for (var i = 0; i < compartmentIds.length; i++) {
      if (Model.compartmentEnabled(compartmentsConfig, compartmentIds[i])) return true
    }
    return false
  }
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  FileView {
    id: fileMeminfo
    path: "/proc/meminfo"
    onLoaded: root.parseMemory()
  }

  FileView {
    id: fileStat
    path: "/proc/stat"
    onLoaded: root.parseCpu()
  }

  Process {
    id: cpuProc
    command: ["python3", pathFromUrl(Qt.resolvedUrl("scripts/system_stats_scanner.py")), "--compartments", "cpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mergeCompartment("cpu", text)
    }
  }

  Process {
    id: gpuProc
    command: ["python3", pathFromUrl(Qt.resolvedUrl("scripts/system_stats_scanner.py")), "--compartments", "gpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mergeCompartment("gpu", text)
    }
  }

  Process {
    id: storageProc
    command: ["python3", pathFromUrl(Qt.resolvedUrl("scripts/system_stats_scanner.py")), "--compartments", "storage"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mergeCompartment("storage", text)
    }
  }

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  Timer {
    id: cpuTimer
    interval: 30000
    running: false
    repeat: true
    triggeredOnStart: false
    onTriggered: { if (!cpuProc.running) cpuProc.running = true }
  }

  Timer {
    id: gpuTimer
    interval: 30000
    running: false
    repeat: true
    triggeredOnStart: false
    onTriggered: { if (!gpuProc.running) gpuProc.running = true }
  }

  Timer {
    id: storageTimer
    interval: 30000
    running: false
    repeat: true
    triggeredOnStart: false
    onTriggered: { if (!storageProc.running) storageProc.running = true }
  }

  Timer {
    id: idleTimer
    interval: 35000
    running: false
    repeat: false
    onTriggered: {
      cpuTimer.running = false
      gpuTimer.running = false
      storageTimer.running = false
    }
  }

  Timer {
    id: memCpuTimer
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      fileMeminfo.reload()
      fileStat.reload()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    tooltipText: "System Stats"
    onPressed: function(b) { root.triggerPress(b) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: settingsMode && settingsContentLayout.editorActive
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
        if (t === "r" || t === "R") root.refresh()
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: root.settingsMode ? "System Stats Settings" : "System Stats"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
          }

          Button {
            visible: root.settingsMode
            text: "Stats"
            foreground: root.fg
            tooltipText: "Back to stats"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.showMain()
          }

          Button {
            visible: root.settingsMode
            text: "Save"
            foreground: root.fg
            tooltipText: "Save settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: true
            onClicked: root.saveSettings()
          }

          Button {
            visible: !root.settingsMode
            text: "Refresh"
            foreground: root.fg
            tooltipText: "Refresh stats"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.refresh()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.fg
        }

        // Main stats view
        BorderSurface {
          visible: root.dataVersion >= 0 && !root.settingsMode && root.statsData["cpu"] !== undefined && Model.compartmentEnabled(root.compartmentsConfig, "cpu")
          Layout.fillWidth: true
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
          borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
          radius: Style.cornerRadius
          id: cpuCard
          padding: 12
          implicitHeight: cpuBody.implicitHeight + cpuCard.contentTopInset + cpuCard.contentBottomInset

          ColumnLayout {
            id: cpuBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: cpuCard.contentTopInset
            anchors.rightMargin: cpuCard.contentRightInset
            anchors.bottomMargin: cpuCard.contentBottomInset
            anchors.leftMargin: cpuCard.contentLeftInset
            spacing: 8

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              Text {
                text: Model.glyphFor("cpu") + "  " + (root.statsData["cpu"].name || "CPU")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (root.statsData["cpu"].cores || "?") + "C/" + (root.statsData["cpu"].threads || "?") + "T"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(6)
              BarFill {
                fraction: (root.statsData["cpu"].usagePct || 0) / 100
                barColor: Model.usageColor(root.statsData["cpu"].usagePct || 0) || root.fg
              }
              Text {
                text: Math.round(root.statsData["cpu"].usagePct || 0) + "%"
                color: Model.usageColor(root.statsData["cpu"].usagePct || 0) || root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(12)
              Text {
                text: "󰔏  " + (root.statsData["cpu"].temp || 0) + "\u00B0C"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: "󰓅  " + (root.statsData["cpu"].freq || 0) + "GHz"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: (root.statsData["cpu"].governor || "") !== ""
                text: "\u2699  " + (root.statsData["cpu"].governor || "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: (root.statsData["cpu"].power || 0) > 0
                text: "  " + (root.statsData["cpu"].power || 0) + "W"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        BorderSurface {
          visible: root.dataVersion >= 0 && !root.settingsMode && root.statsData["gpu"] !== undefined && Model.compartmentEnabled(root.compartmentsConfig, "gpu") && root.statsData["gpu"].available === true
          Layout.fillWidth: true
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
          borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
          radius: Style.cornerRadius
          id: gpuCard
          padding: 12
          implicitHeight: gpuBody.implicitHeight + gpuCard.contentTopInset + gpuCard.contentBottomInset

          ColumnLayout {
            id: gpuBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: gpuCard.contentTopInset
            anchors.rightMargin: gpuCard.contentRightInset
            anchors.bottomMargin: gpuCard.contentBottomInset
            anchors.leftMargin: gpuCard.contentLeftInset
            spacing: 8

            Text {
              text: Model.glyphFor("gpu") + "  " + (root.statsData["gpu"].name || "GPU")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(6)
              BarFill {
                fraction: (root.statsData["gpu"].usagePct || 0) / 100
                barColor: Model.usageColor(root.statsData["gpu"].usagePct || 0) || root.fg
              }
              Text {
                text: Math.round(root.statsData["gpu"].usagePct || 0) + "%"
                color: Model.usageColor(root.statsData["gpu"].usagePct || 0) || root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(12)
              Text {
                text: "󰔏  " + (root.statsData["gpu"].temp || 0) + "\u00B0C"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: (root.statsData["gpu"].power || 0) > 0
                text: "  " + (root.statsData["gpu"].power || 0) + "W"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: "󰟽  VRAM " + (root.statsData["gpu"].vramUsedGb || 0) + "/" + (root.statsData["gpu"].vramTotalGb || 0) + "GB"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        BorderSurface {
          visible: root.dataVersion >= 0 && !root.settingsMode && root.statsData["memory"] !== undefined && Model.compartmentEnabled(root.compartmentsConfig, "memory")
          Layout.fillWidth: true
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
          borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
          radius: Style.cornerRadius
          id: memCard
          padding: 12
          implicitHeight: memBody.implicitHeight + memCard.contentTopInset + memCard.contentBottomInset

          ColumnLayout {
            id: memBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: memCard.contentTopInset
            anchors.rightMargin: memCard.contentRightInset
            anchors.bottomMargin: memCard.contentBottomInset
            anchors.leftMargin: memCard.contentLeftInset
            spacing: 8

            Text {
              text: Model.glyphFor("memory") + "  Memory"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(6)
              BarFill {
                fraction: (root.statsData["memory"].usagePct || 0) / 100
                barColor: Model.usageColor(root.statsData["memory"].usagePct || 0) || root.fg
              }
              Text {
                text: Math.round(root.statsData["memory"].usagePct || 0) + "%"
                color: Model.usageColor(root.statsData["memory"].usagePct || 0) || root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: Style.space(12)
              Text {
                text: Model.glyphFor("memory") + "  " + (root.statsData["memory"].usedGb || 0) + "/" + (root.statsData["memory"].totalGb || 0) + "GB"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: (root.statsData["memory"].swapTotalGb || 0) > 0
                text: "󰓡  Swap " + (root.statsData["memory"].swapUsedGb || 0) + "/" + (root.statsData["memory"].swapTotalGb || 0) + "GB"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        BorderSurface {
          visible: root.dataVersion >= 0 && !root.settingsMode && root.statsData["storage"] !== undefined && Model.compartmentEnabled(root.compartmentsConfig, "storage")
          Layout.fillWidth: true
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
          borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
          radius: Style.cornerRadius
          id: stgCard
          padding: 12
          implicitHeight: stgBody.implicitHeight + stgCard.contentTopInset + stgCard.contentBottomInset

          ColumnLayout {
            id: stgBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: stgCard.contentTopInset
            anchors.rightMargin: stgCard.contentRightInset
            anchors.bottomMargin: stgCard.contentBottomInset
            anchors.leftMargin: stgCard.contentLeftInset
            spacing: 8

            Text {
              text: Model.glyphFor("storage") + "  Storage"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: {
                var d = root.statsData["storage"]
                return d ? (d.mounts || []) : []
              }

              delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  Layout.leftMargin: 4
                  Layout.rightMargin: 4
                  spacing: Style.space(6)
                  BarFill {
                    fraction: (modelData.usagePct || 0) / 100
                    barColor: Model.usageColor(modelData.usagePct || 0) || root.fg
                  }
                  Text {
                    text: Math.round(modelData.usagePct || 0) + "%"
                    color: Model.usageColor(modelData.usagePct || 0) || root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  Layout.fillWidth: true
                  Layout.leftMargin: 4
                  Layout.rightMargin: 4
                  text: modelData.path + "  " + (modelData.usedGb || 0) + "/" + (modelData.totalGb || 0) + "GB"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // Settings view
        ColumnLayout {
          id: settingsContentLayout
          visible: root.settingsMode
          Layout.fillWidth: true
          spacing: Style.space(12)

          readonly property bool editorActive: {
            for (var i = 0; i < settingsContentLayout.children.length; i++) {
              var child = settingsContentLayout.children[i]
              if (child.editorActive === true) return true
            }
            return false
          }

          Repeater {
            model: root.compartmentIds

            delegate: SectionCard {
              required property var modelData
              property bool editorActive: intervalField.field.activeFocus
              Layout.fillWidth: true
              title: {
                var glyph = Model.glyphFor(modelData)
                var name = ""
                if (modelData === "cpu") name = "CPU"
                else if (modelData === "gpu") name = "GPU"
                else if (modelData === "memory") name = "Memory"
                else if (modelData === "storage") name = "Storage"
                return glyph + "  " + name
              }

              ColumnLayout {
                width: parent.width
                spacing: Style.space(8)

                Toggle {
                  Layout.fillWidth: true
                  label: "Enabled"
                  description: draftEnabled(modelData) ? "Active in the stats panel" : "Hidden from the stats panel"
                  checked: root.draftEnabled(modelData)
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftEnabled(modelData, !checked)
                }

                RowLayout {
                  visible: true
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    text: "Poll interval"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Item { Layout.fillWidth: true }

                  NumberField {
                    id: intervalField
                    property bool editorActive: field.activeFocus
                    value: Number(root.draftInterval(modelData))
                    from: 5
                    to: 3600
                    stepSize: 5
                    fieldWidth: 80
                    foreground: root.fg
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    onModified: function(value) { root.setDraftInterval(modelData, value) }
                  }

                  Text {
                    text: "sec"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
              }
            }
          }

          Text {
            visible: root.settingsStatusText !== ""
            Layout.fillWidth: true
            text: root.settingsStatusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            Layout.fillWidth: true
            text: "s saves \u00B7 esc closes"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    default property alias content: body.data

    Layout.fillWidth: true
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
    borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
    radius: Style.cornerRadius
    padding: 12
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.rightMargin: section.contentRightInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      spacing: 8

      Text {
        visible: section.title !== ""
        Layout.fillWidth: true
        text: section.title
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
  }

  component BarFill: Item {
    property real fraction: 0
    property string barColor: root.fg

    implicitHeight: Style.space(6)
    Layout.fillWidth: true

    Rectangle {
      id: barTrack
      anchors.fill: parent
      radius: 0
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
    }

    Rectangle {
      id: barFill
      anchors.left: barTrack.left
      anchors.verticalCenter: barTrack.verticalCenter
      height: barTrack.height
      radius: barTrack.radius
      color: barColor
      width: Math.max(barTrack.height, barTrack.width * Math.max(0, Math.min(1, fraction)))

      Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 220 } }
    }
  }
}
