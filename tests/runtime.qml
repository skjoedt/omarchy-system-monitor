import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: root
  property int stage: 0
  property int ticks: 0

  Plugin.Metrics {
    id: metrics
    settings: ({ openRefreshSec: 1 })
  }

  function check(condition, message) {
    if (!condition) {
      console.error("FAIL: " + message)
      Qt.exit(1)
    }
    return condition
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (!root.check(++root.ticks < 240, "timed out at stage " + root.stage)) return
      switch (root.stage) {
      case 0:
        if (metrics.chipsetTempPath === "" || metrics.chipsetFanPath === "") return
        if (metrics.cpuTemperature !== 45 || metrics.gpuPercent !== 25 || metrics.gpuTemperature !== -1
            || metrics.gpuVramUsed !== 1024 || metrics.gpuVramTotal !== 2048) return
        if (!root.check(metrics.hasChipset && metrics.chipsetTemperature === -1 && metrics.chipsetFanRpm === -1,
                        "closed panel must not read chipset sensors")) return
        metrics.panelOpen = true
        root.stage++
        break
      case 1:
        if (metrics.gpuTemperature !== 33) return
        if (metrics.chipsetTemperature !== 42.5 || metrics.chipsetFanRpm !== 0) return
        metrics.settings = { openRefreshSec: 1, chipsetTemperatureSensor: "board:SMBUSMASTER 1", chipsetFanSensor: "board:fan6_input" }
        root.stage++
        break
      case 2:
        if (metrics.chipsetTemperature !== 58.25 || metrics.chipsetFanRpm !== 1200) return
        console.log("FIXTURE:malformed")
        root.stage++
        break
      case 3:
        if (metrics.chipsetTemperature !== -1 || metrics.chipsetFanRpm !== -1) return
        console.log("FIXTURE:restore")
        root.stage++
        break
      case 4:
        if (metrics.chipsetTemperature !== 58.25 || metrics.chipsetFanRpm !== 1200) return
        console.log("FIXTURE:remove")
        root.stage++
        break
      case 5:
        if (metrics.chipsetTemperature !== -1 || metrics.chipsetFanRpm !== -1) return
        if (!root.check(metrics.hasChipset, "failed reads must leave the row visible")) return
        console.log("FIXTURE:renumber")
        root.stage++
        break
      case 6:
        // The runner restores the inputs under another hwmon index. Rescan
        // explicitly, without relying on a plugin or shell restart.
        metrics.refresh()
        root.stage++
        break
      case 7:
        if (metrics.chipsetTempPath.indexOf("/hwmon42/") < 0 || metrics.chipsetTemperature !== 58.25 || metrics.chipsetFanRpm !== 1200) return
        metrics.panelOpen = false
        metrics.settings = { chipsetTemperatureSensor: "board:missing", chipsetFanSensor: "board:missing" }
        root.stage++
        break
      case 8:
        if (metrics.chipsetTempPath !== "" || metrics.chipsetFanPath !== "" || metrics.discoveryPending) return
        if (!root.check(metrics.hasChipset && metrics.chipsetTemperature === -1 && metrics.chipsetFanRpm === -1,
                        "invalid selectors must clear previous values without hiding the row")) return
        // Queue another selection while the first probe is running.
        metrics.settings = { chipsetTemperatureSensor: "board:temp1_input" }
        Qt.callLater(function() {
          metrics.settings = { chipsetTemperatureSensor: "board:SMBUSMASTER 1", chipsetFanSensor: "board:fan6_input" }
        })
        root.stage++
        break
      case 9:
        if (metrics.chipsetTempPath.indexOf("/temp7_input") < 0 || metrics.chipsetFanPath.indexOf("/fan6_input") < 0) return
        if (!root.check(metrics.chipsetTemperature === -1 && metrics.chipsetFanRpm === -1,
                        "selector changes must not read closed-panel sensors")) return
        metrics.panelOpen = true
        root.stage++
        break
      case 10:
        if (metrics.chipsetTemperature !== 58.25 || metrics.chipsetFanRpm !== 1200) return
        console.log("FIXTURE:empty")
        root.stage++
        break
      case 11:
        console.log("FIXTURE:nvidia-malformed")
        root.stage++
        break
      case 12:
        if (metrics.gpuTemperature !== -1) return
        console.log("FIXTURE:nvidia-restore")
        root.stage++
        break
      case 13:
        if (metrics.gpuTemperature !== 33) return
        metrics.settings = {}
        metrics.refresh()
        root.stage++
        break
      case 14:
        if (metrics.hasChipset) return
        if (!root.check(metrics.chipsetTemperature === -1 && metrics.chipsetFanRpm === -1,
                        "missing hardware must clear readings")) return
        if (!root.check(metrics.cpuTemperature === -1 && metrics.gpuPercent === -1 && metrics.gpuTemperature === 33
                        && metrics.gpuVramUsed === -1 && metrics.gpuVramTotal === -1 && metrics.gpuHistory.length === 0,
                        "rediscovery must also clear removed CPU/GPU readings")) return
        console.log("PASS: chipset runtime lifecycle")
        Qt.exit(0)
      }
    }
  }
}
