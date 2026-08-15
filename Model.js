function parseStats(raw) {
  try {
    return JSON.parse(String(raw || "{}"))
  } catch (e) {
    return {}
  }
}

function compartmentEnabled(config, id) {
  return !!(config && config[id] && config[id].enabled === true)
}

function compartmentBarEnabled(config, id) {
  return !!(config && config[id] && config[id].enabled !== false && config[id].showInBar === true)
}

function compartmentInterval(config, id, fallback) {
  if (config && config[id] && typeof config[id].pollIntervalSec === "number")
    return Math.max(5, config[id].pollIntervalSec)
  return fallback
}

function defaultCompartments() {
  return {
    cpu: { enabled: true, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 },
    gpu: { enabled: true, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 },
    memory: { enabled: true, showInBar: false, pollIntervalSec: 30 },
    storage: { enabled: true, showInBar: false, pollIntervalSec: 30 }
  }
}

function glyphFor(id) {
  if (id === "cpu") return "󰍛"
  if (id === "gpu") return "󰟽"
  if (id === "memory") return "󰾆"
  if (id === "storage") return "󰋊"
  return ""
}

function usageColor(pct) {
  if (pct >= 75) return "#ef4444"
  if (pct >= 50) return "#eab308"
  return ""
}

function formatBarText(config, statsData) {
  if (!config) return "󰵃"
  var parts = []
  if (compartmentBarEnabled(config, "cpu")) {
    var cpu = statsData ? statsData["cpu"] : null
    var cpuMode = (config.cpu && config.cpu.barDisplay) ? config.cpu.barDisplay : "usage"
    var cpuPct = (cpu && typeof cpu.usagePct === "number") ? Math.round(cpu.usagePct) : 0
    var cpuTemp = (cpu && typeof cpu.temp === "number") ? Math.round(cpu.temp) : 0
    var cpuText = ""
    if (cpuMode === "temp") {
      cpuText = cpuTemp + "°C"
    } else if (cpuMode === "both") {
      cpuText = cpuPct + "% " + cpuTemp + "°C"
    } else {
      cpuText = cpuPct + "%"
    }
    parts.push(glyphFor("cpu") + " " + cpuText)
  }
  if (compartmentBarEnabled(config, "gpu")) {
    var gpu = statsData ? statsData["gpu"] : null
    if (gpu && gpu.available !== false) {
      var gpuMode = (config.gpu && config.gpu.barDisplay) ? config.gpu.barDisplay : "usage"
      var gpuPct = (typeof gpu.usagePct === "number") ? Math.round(gpu.usagePct) : 0
      var gpuTemp = (typeof gpu.temp === "number") ? Math.round(gpu.temp) : 0
      var gpuText = ""
      if (gpuMode === "temp") {
        gpuText = gpuTemp + "°C"
      } else if (gpuMode === "both") {
        gpuText = gpuPct + "% " + gpuTemp + "°C"
      } else {
        gpuText = gpuPct + "%"
      }
      parts.push(glyphFor("gpu") + " " + gpuText)
    }
  }
  if (compartmentBarEnabled(config, "memory")) {
    var mem = statsData ? statsData["memory"] : null
    var memPct = (mem && typeof mem.usagePct === "number") ? Math.round(mem.usagePct) : 0
    parts.push(glyphFor("memory") + " " + memPct + "%")
  }
  if (compartmentBarEnabled(config, "storage")) {
    var stg = statsData ? statsData["storage"] : null
    var stgPct = (stg && stg.mounts && stg.mounts.length > 0 && typeof stg.mounts[0].usagePct === "number")
      ? Math.round(stg.mounts[0].usagePct)
      : 0
    parts.push(glyphFor("storage") + " " + stgPct + "%")
  }
  if (parts.length > 0) {
    return parts.join("  ")
  }
  return "󰵃"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStats: parseStats,
    compartmentEnabled: compartmentEnabled,
    compartmentBarEnabled: compartmentBarEnabled,
    compartmentInterval: compartmentInterval,
    defaultCompartments: defaultCompartments,
    glyphFor: glyphFor,
    usageColor: usageColor,
    formatBarText: formatBarText
  }
}
