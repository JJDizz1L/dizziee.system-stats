import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
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
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var compartmentIds: ["cpu", "gpu", "memory", "storage"]

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function compartmentName(id) {
    if (id === "cpu") return strings.t("stats.cpu")
    if (id === "gpu") return strings.t("stats.gpu")
    if (id === "memory") return strings.t("stats.memory")
    if (id === "storage") return strings.t("stats.storage")
    return String(id || "")
  }

  function fmtInt(value) {
    return Commons.I18n.formatNumber(Math.round(value || 0))
  }

  readonly property bool hasBarWidgets: {
    for (var i = 0; i < compartmentIds.length; i++) {
      if (Model.compartmentBarEnabled(compartmentsConfig, compartmentIds[i])) return true
    }
    return false
  }

  readonly property string computedBarText: {
    if (hasBarWidgets) {
      var text = Model.formatBarText(compartmentsConfig, statsData)
      return text !== "" ? text : barIcon
    }
    return barIcon
  }

  function refresh() {
    if (Model.compartmentEnabled(compartmentsConfig, "cpu") && !cpuProc.running) cpuProc.running = true
    if (Model.compartmentEnabled(compartmentsConfig, "gpu") && !gpuProc.running) gpuProc.running = true
    if (Model.compartmentEnabled(compartmentsConfig, "storage") && !storageProc.running) storageProc.running = true
    fileMeminfo.reload()
    fileStat.reload()
  }

  function mergeCompartment(id, raw) {
    var parsed = Model.parseStats(raw)
    if (!parsed[id]) return
    var next = {}
    for (var k in root.statsData) next[k] = root.statsData[k]
    var incoming = parsed[id]
    if (id === "storage" && incoming && typeof incoming === "object") {
      incoming = { mounts: Model.cleanMounts(incoming.mounts) }
    }
    if ((id === "cpu" || id === "gpu") && incoming && typeof incoming === "object" && typeof incoming.name === "string") {
      var bounded = {}
      for (var ck in incoming) bounded[ck] = incoming[ck]
      bounded.name = Model.cleanDisplayText(incoming.name, 128)
      if (typeof incoming.governor === "string") bounded.governor = Model.cleanDisplayText(incoming.governor, 64)
      incoming = bounded
    }
    next[id] = incoming
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
        var cur = fromSettings[id] || {}
        merged[id] = {
          enabled: cur.enabled !== undefined ? cur.enabled === true : defaults[id].enabled,
          showInBar: cur.showInBar !== undefined ? cur.showInBar === true : defaults[id].showInBar,
          barDisplay: (cur.barDisplay === "temp" || cur.barDisplay === "both" || cur.barDisplay === "usage")
            ? cur.barDisplay
            : (defaults[id].barDisplay || "usage"),
          pollIntervalSec: typeof cur.pollIntervalSec === "number" ? cur.pollIntervalSec : defaults[id].pollIntervalSec
        }
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
      c.showInBar = c.showInBar === true
      if (defaults[id].barDisplay !== undefined) {
        c.barDisplay = (c.barDisplay === "temp" || c.barDisplay === "both" || c.barDisplay === "usage")
          ? c.barDisplay
          : "usage"
      }
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
    startCompartmentTimers()
    if (hasBarWidgets) refresh()
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, { compartments: next.compartments })
      settingsStatusText = strings.t("stats.savedToShell")
    } else {
      settingsStatusText = strings.t("stats.savedForSession")
    }
  }

  function draftEnabled(id) {
    return draftCompartments && draftCompartments[id] ? draftCompartments[id].enabled === true : false
  }

  function setDraftEnabled(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 }
    next[id].enabled = value === true
    draftCompartments = next
  }

  function draftBarEnabled(id) {
    return draftCompartments && draftCompartments[id] ? draftCompartments[id].showInBar === true : false
  }

  function setDraftBarEnabled(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 }
    next[id].showInBar = value === true
    if (value === true && !next[id].enabled) {
      next[id].enabled = true
    }
    draftCompartments = next
  }

  function draftBarDisplay(id) {
    return draftCompartments && draftCompartments[id] && draftCompartments[id].barDisplay
      ? draftCompartments[id].barDisplay
      : "usage"
  }

  function setDraftBarDisplay(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, showInBar: true, barDisplay: "usage", pollIntervalSec: 30 }
    next[id].barDisplay = (value === "temp" || value === "both" || value === "usage") ? value : "usage"
    draftCompartments = next
  }

  function draftInterval(id) {
    return draftCompartments && draftCompartments[id] ? (draftCompartments[id].pollIntervalSec || 30) : 30
  }

  function setDraftInterval(id, value) {
    var next = cloneObject(draftCompartments, {})
    if (!next[id]) next[id] = { enabled: false, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 }
    next[id].pollIntervalSec = Math.max(5, Math.min(3600, Math.round(value)))
    draftCompartments = next
  }

  function applyTimer() {
    cpuTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "cpu", 30) * 1000)
    gpuTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "gpu", 30) * 1000)
    storageTimer.interval = Math.max(5000, Model.compartmentInterval(compartmentsConfig, "storage", 30) * 1000)
  }

  function startCompartmentTimers() {
    cpuTimer.running = (opened || Model.compartmentBarEnabled(compartmentsConfig, "cpu")) && Model.compartmentEnabled(compartmentsConfig, "cpu")
    gpuTimer.running = (opened || Model.compartmentBarEnabled(compartmentsConfig, "gpu")) && Model.compartmentEnabled(compartmentsConfig, "gpu")
    storageTimer.running = (opened || Model.compartmentBarEnabled(compartmentsConfig, "storage")) && Model.compartmentEnabled(compartmentsConfig, "storage")
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
      prevCpuStats = null
      fileMeminfo.reload()
      fileStat.reload()
    } else {
      settingsMode = false
      if (!hasBarWidgets) idleTimer.restart()
    }
  }

  Component.onCompleted: {
    loadCompartments()
    applyTimer()
    startCompartmentTimers()
    if (hasBarWidgets) refresh()
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
      if (!Model.compartmentBarEnabled(compartmentsConfig, "cpu")) cpuTimer.running = false
      if (!Model.compartmentBarEnabled(compartmentsConfig, "gpu")) gpuTimer.running = false
      if (!Model.compartmentBarEnabled(compartmentsConfig, "storage")) storageTimer.running = false
    }
  }

  Timer {
    id: memCpuTimer
    interval: 3000
    running: (root.opened || (root.hasBarWidgets && (Model.compartmentBarEnabled(root.compartmentsConfig, "cpu")
      || Model.compartmentBarEnabled(root.compartmentsConfig, "memory"))))
      && (Model.compartmentEnabled(root.compartmentsConfig, "memory") || Model.compartmentEnabled(root.compartmentsConfig, "cpu"))
    repeat: true
    onTriggered: {
      fileMeminfo.reload()
      fileStat.reload()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.computedBarText
    fixedWidth: root.hasBarWidgets ? -1 : (root.bar && root.bar.vertical ? -1 : Style.space(27))
    fixedHeight: root.hasBarWidgets ? -1 : (root.bar && root.bar.vertical ? Style.space(26) : -1)
    tooltipText: strings.t("stats.title")
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
            textFormat: Text.PlainText
            text: root.settingsMode ? strings.t("stats.settingsTitle") : strings.t("stats.title")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
          }

          Button {
            visible: root.settingsMode
            text: strings.t("stats.stats")
            foreground: root.fg
            tooltipText: strings.t("stats.backToStats")
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.showMain()
          }

          Button {
            visible: root.settingsMode
            text: strings.t("stats.save")
            foreground: root.fg
            tooltipText: strings.t("stats.saveSettings")
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: true
            onClicked: root.saveSettings()
          }

          Button {
            visible: !root.settingsMode
            text: strings.t("stats.refresh")
            foreground: root.fg
            tooltipText: strings.t("stats.refreshStats")
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
                  textFormat: Text.PlainText
                text: Model.glyphFor("cpu") + "  " + Model.cleanDisplayText(root.statsData["cpu"].name || compartmentName("cpu"), 128)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                  textFormat: Text.PlainText
                text: (root.statsData["cpu"].cores ? fmtInt(root.statsData["cpu"].cores) : "?") + "C/" + (root.statsData["cpu"].threads ? fmtInt(root.statsData["cpu"].threads) : "?") + "T"
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
                  textFormat: Text.PlainText
                text: fmtInt(root.statsData["cpu"].usagePct) + "%"
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
                  textFormat: Text.PlainText
                text: "󰔏  " + fmtInt(root.statsData["cpu"].temp) + "\u00B0C"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                text: "󰓅  " + Commons.I18n.formatNumber(root.statsData["cpu"].freq || 0, 2) + "GHz"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                visible: (root.statsData["cpu"].governor || "") !== ""
                text: "\u2699  " + Model.cleanDisplayText(root.statsData["cpu"].governor || "", 64)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                visible: (root.statsData["cpu"].power || 0) > 0
                text: "  " + Commons.I18n.formatNumber(root.statsData["cpu"].power || 0, 1) + "W"
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
                textFormat: Text.PlainText
              text: Model.glyphFor("gpu") + "  " + Model.cleanDisplayText(root.statsData["gpu"].name || compartmentName("gpu"), 128)
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
                  textFormat: Text.PlainText
                text: fmtInt(root.statsData["gpu"].usagePct) + "%"
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
                  textFormat: Text.PlainText
                text: "󰔏  " + fmtInt(root.statsData["gpu"].temp) + "\u00B0C"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                visible: (root.statsData["gpu"].power || 0) > 0
                text: "  " + Commons.I18n.formatNumber(root.statsData["gpu"].power || 0, 1) + "W"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                text: "󰟽  " + strings.t("stats.vram") + " " + Commons.I18n.formatNumber(root.statsData["gpu"].vramUsedGb || 0, 1) + "/" + Commons.I18n.formatNumber(root.statsData["gpu"].vramTotalGb || 0, 1) + "GB"
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
                textFormat: Text.PlainText
              text: Model.glyphFor("memory") + "  " + compartmentName("memory")
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
                  textFormat: Text.PlainText
                text: fmtInt(root.statsData["memory"].usagePct) + "%"
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
                  textFormat: Text.PlainText
                text: Model.glyphFor("memory") + "  " + Commons.I18n.formatNumber(root.statsData["memory"].usedGb || 0, 1) + "/" + Commons.I18n.formatNumber(root.statsData["memory"].totalGb || 0, 1) + "GB"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                  textFormat: Text.PlainText
                visible: (root.statsData["memory"].swapTotalGb || 0) > 0
                text: "󰓡  " + strings.t("stats.swap") + " " + Commons.I18n.formatNumber(root.statsData["memory"].swapUsedGb || 0, 1) + "/" + Commons.I18n.formatNumber(root.statsData["memory"].swapTotalGb || 0, 1) + "GB"
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
                textFormat: Text.PlainText
              text: Model.glyphFor("storage") + "  " + compartmentName("storage")
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
                      textFormat: Text.PlainText
                    text: fmtInt(modelData.usagePct) + "%"
                    color: Model.usageColor(modelData.usagePct || 0) || root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                    textFormat: Text.PlainText
                  Layout.fillWidth: true
                  Layout.leftMargin: 4
                  Layout.rightMargin: 4
                  text: Model.cleanDisplayText(modelData.path || "", 128) + "  " + Commons.I18n.formatNumber(modelData.usedGb || 0, 1) + "/" + Commons.I18n.formatNumber(modelData.totalGb || 0, 1) + "GB"
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
                return glyph + "  " + compartmentName(modelData)
              }

              ColumnLayout {
                width: parent.width
                spacing: Style.space(8)

                Toggle {
                  Layout.fillWidth: true
                  label: strings.t("stats.enabled")
                  description: draftEnabled(modelData) ? strings.t("stats.activeInPanel") : strings.t("stats.hiddenFromPanel")
                  checked: root.draftEnabled(modelData)
                  foreground: root.fg
                  accent: Commons.Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftEnabled(modelData, !checked)
                }

                Toggle {
                  Layout.fillWidth: true
                  label: strings.t("stats.showInBar")
                  description: draftBarEnabled(modelData) ? strings.t("stats.showInBarActive") : strings.t("stats.hiddenFromBar")
                  checked: root.draftBarEnabled(modelData)
                  foreground: root.fg
                  accent: Commons.Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setDraftBarEnabled(modelData, !checked)
                }

                RowLayout {
                  visible: (modelData === "cpu" || modelData === "gpu") && root.draftBarEnabled(modelData)
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                      textFormat: Text.PlainText
                    text: strings.t("stats.barDisplay")
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Item { Layout.fillWidth: true }

                  ButtonGroup {
                    options: [
                      { value: "usage", label: strings.t("stats.usage") },
                      { value: "temp", label: strings.t("stats.temp") },
                      { value: "both", label: strings.t("stats.both") }
                    ]
                    value: root.draftBarDisplay(modelData)
                    foreground: root.fg
                    accent: Commons.Color.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onChanged: function(val) { root.setDraftBarDisplay(modelData, val) }
                  }
                }

                RowLayout {
                  visible: true
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                      textFormat: Text.PlainText
                    text: strings.t("stats.pollInterval")
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
                    accent: Commons.Color.accent
                    fontFamily: root.fontFamily
                    onModified: function(value) { root.setDraftInterval(modelData, value) }
                  }

                  Text {
                      textFormat: Text.PlainText
                    text: strings.t("stats.sec")
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
              textFormat: Text.PlainText
            visible: root.settingsStatusText !== ""
            Layout.fillWidth: true
            text: root.settingsStatusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
              textFormat: Text.PlainText
            Layout.fillWidth: true
            text: strings.t("stats.keysHint")
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
          textFormat: Text.PlainText
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
