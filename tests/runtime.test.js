const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawn } = require("node:child_process")

test("Quickshell chipset sampling, selector changes, failures and rediscovery", { timeout: 20000 }, async (t) => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "sysmon runtime-"))
  t.after(() => fs.rmSync(work, { recursive: true, force: true }))
  // Quickshell confines relative imports to its config directory. Keep the
  // real collector and its script together in an isolated test config.
  for (const file of ["Metrics.qml", "Metrics.js", "discover-sensors.sh"])
    fs.copyFileSync(path.join(__dirname, "..", file), path.join(work, file))
  fs.copyFileSync(path.join(__dirname, "runtime.qml"), path.join(work, "runtime.qml"))
  const hwmon = path.join(work, "hwmon")
  let chip = path.join(hwmon, "hwmon3")
  fs.mkdirSync(chip, { recursive: true })
  for (const [name, value] of Object.entries({
    name: "board", temp1_label: "Chipset", temp1_input: "42500",
    fan1_label: "SB Fan", fan1_input: "0",
    temp7_label: "SMBUSMASTER 1", temp7_input: "58250", fan6_input: "1200"
  })) fs.writeFileSync(path.join(chip, name), value + "\n")

  const cpu = path.join(hwmon, "hwmon0")
  fs.mkdirSync(cpu)
  fs.writeFileSync(path.join(cpu, "name"), "coretemp\n")
  fs.writeFileSync(path.join(cpu, "temp1_input"), "45000\n")
  const drm = path.join(work, "drm")
  const gpu = path.join(drm, "card0", "device")
  fs.mkdirSync(path.join(gpu, "hwmon", "hwmon0"), { recursive: true })
  for (const [file, value] of Object.entries({ gpu_busy_percent: "25", mem_info_vram_used: "1024", mem_info_vram_total: "2048", "hwmon/hwmon0/temp1_input": "48000" }))
    fs.writeFileSync(path.join(gpu, file), value + "\n")

  const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", OMARCHY_SYSMON_HWMON_ROOT: hwmon, OMARCHY_SYSMON_DRM_ROOT: drm }
  delete env.WAYLAND_DISPLAY
  const child = spawn("qs", ["-p", path.join(work, "runtime.qml"), "--no-color"], { env })
  t.after(() => child.kill())
  let output = ""
  const handled = new Set()
  const collect = (data) => {
    output += data
    for (const action of ["malformed", "restore", "remove", "renumber", "empty"]) {
      if (handled.has(action) || !output.includes("FIXTURE:" + action)) continue
      handled.add(action)
      if (action === "renumber") {
        const renamed = path.join(hwmon, "hwmon42")
        fs.renameSync(chip, renamed)
        chip = renamed
      }
      if (action === "empty") {
        fs.rmSync(hwmon, { recursive: true })
        fs.rmSync(drm, { recursive: true })
      }
      else for (const [file, value] of [["temp7_input", "58250"], ["fan6_input", "1200"]]) {
        const input = path.join(chip, file)
        if (action === "remove") fs.unlinkSync(input)
        else fs.writeFileSync(input, action === "malformed" ? "invalid\n" : value + "\n")
      }
    }
  }
  child.stdout.on("data", collect)
  child.stderr.on("data", collect)
  const code = await new Promise((resolve, reject) => {
    child.on("error", reject)
    child.on("close", resolve)
  })
  assert.equal(code, 0, output)
  assert.match(output, /PASS: chipset runtime lifecycle/)
  assert.doesNotMatch(output, /ReferenceError|TypeError|Binding loop|FAIL:/)
})
