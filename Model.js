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

function compartmentInterval(config, id, fallback) {
  if (config && config[id] && typeof config[id].pollIntervalSec === "number")
    return Math.max(5, config[id].pollIntervalSec)
  return fallback
}

function defaultCompartments() {
  return {
    cpu: { enabled: true, pollIntervalSec: 30 },
    gpu: { enabled: false, pollIntervalSec: 30 },
    memory: { enabled: true, pollIntervalSec: 30 },
    storage: { enabled: true, pollIntervalSec: 30 }
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

if (typeof module !== "undefined") {
  module.exports = {
    parseStats: parseStats,
    compartmentEnabled: compartmentEnabled,
    compartmentInterval: compartmentInterval,
    defaultCompartments: defaultCompartments,
    glyphFor: glyphFor,
    usageColor: usageColor
  }
}
