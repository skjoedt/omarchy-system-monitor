# Changelog

All notable changes to this project will be documented in this file.

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
- Document that NVIDIA's proprietary driver exposes no sysfs data whatsoever,
  not even temperature, and is unsupported by design rather than by omission

## 1.0.1 - 2026-08-20

- Render configuration-derived network interface names as plain text
- Escape interface-name markup before passing it to the shared bar tooltip

## 1.0.0 - 2026-08-20

Initial public release.

- Bar widget with adaptive CPU and memory display modes
- Expandable dashboard with sparklines, per-core load, network, disk, and capacity sections
- Automatic CPU temperature and disk device discovery
- Configurable refresh intervals and warning thresholds
