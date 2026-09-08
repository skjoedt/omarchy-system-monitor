# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Split the dashboard headline into CPU and MEMORY usage cards, followed by CPU,
  CHIPSET, and GPU temperature cards. Missing temperature readings remain
  unavailable; each bar runs from 30 C to its own configurable limit, warns 10
  C below it, and is urgent at or above it.
- Add separate CPU (95 C), chipset (95 C), and GPU (89 C) temperature limits,
  configurable from 60 C through 110 C.
- Show a compact CHIPSET FAN line only when a chipset sensor is discovered or
  configured. Chipset inputs are sampled only while the dashboard is open;
  conservative automatic labels or exact hwmon-name selectors avoid guessing
  motherboard channels, missing readings stay unavailable, and a stopped fan's
  0 RPM remains valid.
- Add a panel-open-only NVIDIA proprietary temperature fallback using a strict,
  single-value `nvidia-smi` query. It does not add NVIDIA GPU utilization or
  VRAM monitoring.
- Rescan sensors at initialization, on manual refresh, and when chipset selectors
  change, applying settings at runtime without persisting volatile hwmon numbers.
- Document chipset driver prerequisites, selector ambiguity, and board-specific
  input verification. Monitoring remains read-only with no fan control.
- Test chipset discovery parsing, strict hwmon and NVIDIA readings, selector
  defaults, and bounded temperature limits; run shell syntax checks and
  GPU/chipset discovery fixture tests in CI.

## 1.2.0 - 2026-08-31

- Add an `Icon` bar display mode: the plugin glyph alone, no live text, for
  bars that should stay quiet. It still tints at warning/critical pressure and
  keeps the tooltip and dashboard; right-click cycling includes it
- List every mounted local disk in the capacity section automatically, one row
  per physical device, alongside the existing root and swap meters. Pseudo and
  network filesystems (tmpfs, overlay, squashfs, NFS, and the like) are left
  out, and subvolumes or bind mounts on one device collapse to a single row.
  No configuration.
- Render auto-discovered mount labels as plain text, so a mount path can never
  be interpreted as rich text in the shared shell process

## 1.1.1 - 2026-08-26

- Fix GPU temperature discovery on the `xe` driver (Intel Arc, Meteor Lake,
  Lunar Lake and newer): its hwmon package sensor is `temp2_input`, not
  `temp1_input`, so those cards previously reported no temperature at all
- Document that NVIDIA's proprietary driver exposes no sysfs utilization or
  VRAM data; the later `nvidia-smi` temperature fallback supersedes the former
  unsupported-temperature behavior

## 1.0.1 - 2026-08-20

- Render configuration-derived network interface names as plain text
- Escape interface-name markup before passing it to the shared bar tooltip

## 1.0.0 - 2026-08-20

Initial public release.

- Bar widget with adaptive CPU and memory display modes
- Expandable dashboard with sparklines, per-core load, network, disk, and capacity sections
- Automatic CPU temperature and disk device discovery
- Configurable refresh intervals and warning thresholds
