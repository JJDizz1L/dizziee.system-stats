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
    gpu: { enabled: false, showInBar: false, barDisplay: "usage", pollIntervalSec: 30 },
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

function barDisplayMode(config, id) {
  if (config && config[id] && config[id].barDisplay === "temp") return "temp"
  if (config && config[id] && config[id].barDisplay === "both") return "both"
  return "usage"
}

function formatPct(value) {
  return Math.round(value || 0) + "%"
}

function formatTemp(value) {
  return Math.round(value || 0) + "\u00B0C"
}

function formatBarText(config, statsData) {
  var parts = []
  if (compartmentBarEnabled(config, "cpu")) {
    var cpu = statsData ? statsData["cpu"] : null
    var cpuMode = barDisplayMode(config, "cpu")
    var cpuText = ""
    if (cpuMode === "temp") {
      cpuText = formatTemp(cpu ? cpu.temp : 0)
    } else if (cpuMode === "both") {
      cpuText = formatPct(cpu ? cpu.usagePct : 0) + " " + formatTemp(cpu ? cpu.temp : 0)
    } else {
      cpuText = formatPct(cpu ? cpu.usagePct : 0)
    }
    parts.push(glyphFor("cpu") + " " + cpuText)
  }
  if (compartmentBarEnabled(config, "gpu")) {
    var gpu = statsData ? statsData["gpu"] : null
    if (gpu && gpu.available !== false) {
      var gpuMode = barDisplayMode(config, "gpu")
      var gpuText = ""
      if (gpuMode === "temp") {
        gpuText = formatTemp(gpu.temp || 0)
      } else if (gpuMode === "both") {
        gpuText = formatPct(gpu.usagePct || 0) + " " + formatTemp(gpu.temp || 0)
      } else {
        gpuText = formatPct(gpu.usagePct || 0)
      }
      parts.push(glyphFor("gpu") + " " + gpuText)
    }
  }
  if (compartmentBarEnabled(config, "memory")) {
    var mem = statsData ? statsData["memory"] : null
    parts.push(glyphFor("memory") + " " + formatPct(mem ? mem.usagePct : 0))
  }
  if (compartmentBarEnabled(config, "storage")) {
    var stg = statsData ? statsData["storage"] : null
    var stgPct = (stg && stg.mounts && stg.mounts.length > 0 && stg.mounts[0]) ? stg.mounts[0].usagePct : 0
    parts.push(glyphFor("storage") + " " + formatPct(stgPct))
  }
  if (parts.length > 0) return parts.join("  ")
  return ""
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
    barDisplayMode: barDisplayMode,
    formatBarText: formatBarText
  }
}
