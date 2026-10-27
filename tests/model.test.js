// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("cleanDisplayText truncates and rejects non-strings", () => {
  assert.equal(Model.cleanDisplayText("  balanced  "), "balanced")
  assert.equal(Model.cleanDisplayText(""), "")
  assert.equal(Model.cleanDisplayText(null), "")
  assert.equal(Model.cleanDisplayText(123), "")
  assert.equal(Model.cleanDisplayText("x".repeat(200), 128).length, 128)
  assert.equal(Model.cleanDisplayText("x".repeat(200)).length, Model.MAX_TEXT_LEN)
})

test("markup-shaped hardware names survive as inert text", () => {
  const evil = '<img src="https://example.invalid/tracker">'
  const cleaned = Model.cleanDisplayText(evil, 128)
  assert.equal(cleaned, evil)
  // PlainText sinks render this literally; it must never be executed or stripped here.
  assert.match(cleaned, /<img/)
  const longEvil = ("<b>" + "x".repeat(200) + "</b>")
  assert.equal(Model.cleanDisplayText(longEvil, 128).length, 128)
})

test("cleanMounts caps count and truncates paths", () => {
  const mounts = Array.from({ length: 30 }, (_, i) => ({
    path: "/mnt/disk-" + i + "-" + "x".repeat(200),
    usagePct: 50,
    usedGb: 1,
    totalGb: 2
  }))
  const cleaned = Model.cleanMounts(mounts)
  assert.equal(cleaned.length, Model.MAX_MOUNTS)
  assert.ok(cleaned[0].path.length <= 128)
  assert.equal(cleaned[0].usagePct, 50)
})

test("cleanMounts drops non-objects and coerces numbers", () => {
  const cleaned = Model.cleanMounts([
    null,
    "string",
    { path: '<img src="x">', usagePct: "high", usedGb: null, totalGb: undefined }
  ])
  assert.equal(cleaned.length, 1)
  assert.equal(cleaned[0].path, '<img src="x">')
  assert.equal(cleaned[0].usagePct, 0)
})

test("glyphFor covers compartments", () => {
  assert.notEqual(Model.glyphFor("cpu"), "")
  assert.notEqual(Model.glyphFor("gpu"), "")
  assert.notEqual(Model.glyphFor("memory"), "")
  assert.notEqual(Model.glyphFor("storage"), "")
  assert.equal(Model.glyphFor("unknown"), "")
})
