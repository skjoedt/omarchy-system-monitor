#!/bin/bash

shopt -s nullglob

hwmon_root="${OMARCHY_SYSMON_HWMON_ROOT:-/sys/class/hwmon}"
[[ "$hwmon_root" == /* ]] || hwmon_root="$PWD/$hwmon_root"

for hwmon in "$hwmon_root"/hwmon*; do
  [[ -r "$hwmon/name" ]] || continue
  IFS= read -r name <"$hwmon/name"
  [[ "$name" == "coretemp" || "$name" == "k10temp" || "$name" == "zenpower" ]] || continue

  selected=""
  for label_file in "$hwmon"/temp*_label; do
    IFS= read -r label <"$label_file"
    if [[ "$label" == "Package id 0" || "$label" == "Tctl" ]]; then
      candidate="${label_file%_label}_input"
      [[ -r "$candidate" ]] && selected="$candidate"
      break
    fi
  done

  if [[ -z "$selected" ]]; then
    for candidate in "$hwmon"/temp*_input; do
      [[ -r "$candidate" ]] && selected="$candidate" && break
    done
  fi

  if [[ -n "$selected" ]]; then
    printf 'cpu_temp\t%s\n' "$selected"
    break
  fi
done

discover_chipset_sensor() {
  local kind="$1" selector="$2" chip="" sensor="" filename=false
  local hwmon name candidate input label normalized suffix automatic_pattern selected="" matches=0

  if [[ -n "$selector" ]]; then
    [[ "$selector" == *:* ]] || return 0
    chip="${selector%%:*}"
    sensor="${selector#*:}"
    [[ -n "$chip" && -n "$sensor" && "$sensor" != *:* ]] || return 0
    if [[ "$sensor" =~ ^(temp|fan)[0-9]+_input$ ]]; then
      [[ "$sensor" =~ ^${kind}[0-9]+_input$ ]] || return 0
      filename=true
    fi
  fi

  if [[ "$kind" == temp ]]; then suffix='temp(erature)?'; else suffix='fan'; fi
  automatic_pattern="^(chipset|pch|sb|south *bridge)( +($suffix))?$"
  for hwmon in "$hwmon_root"/hwmon*; do
    [[ -r "$hwmon/name" ]] || continue
    name=""
    IFS= read -r name <"$hwmon/name"
    [[ -z "$selector" || "$name" == "$chip" ]] || continue
    for candidate in "$hwmon"/"$kind"*_input; do
      input="${candidate##*/}"
      [[ "$input" =~ ^${kind}[0-9]+_input$ ]] || continue
      [[ -f "$candidate" && -r "$candidate" ]] || continue
      if [[ "$filename" == true ]]; then
        [[ "$input" == "$sensor" ]] || continue
      else
        [[ -r "${candidate%_input}_label" ]] || continue
        label=""
        IFS= read -r label <"${candidate%_input}_label"
        if [[ -n "$selector" ]]; then
          [[ "$label" == "$sensor" ]] || continue
        else
          normalized="${label,,}"
          normalized="${normalized//_/ }"
          # Only named chipset sensors, never board-specific channel guesses.
          [[ "$normalized" =~ $automatic_pattern ]] || continue
        fi
      fi
      selected="$candidate"
      matches=$((matches + 1))
    done
  done
  if (( matches == 1 )); then
    printf 'chipset_%s\t%s\n' "$kind" "$selected"
  fi
}

# Blank selectors use labels automatically; explicit chip:label/input never falls back.
discover_chipset_sensor temp "${1:-}"
discover_chipset_sensor fan "${2:-}"

for block_path in /sys/class/block/*; do
  device="${block_path##*/}"
  [[ -e "$block_path/partition" ]] && continue
  [[ -e "$block_path/device" ]] || continue
  case "$device" in
    loop*|ram*|zram*|fd*|sr*) continue ;;
  esac
  printf 'disk\t%s\n' "$device"
done

# GPU. Vendors expose different subsets, so each sensor is probed on its own
# rather than gated behind one capability:
#
#   amdgpu        gpu_busy_percent, hwmon temperature (temp1_input), mem_info_vram_*
#   i915          hwmon temperature only (temp1_input); no device-wide busy
#                 counter exists in sysfs, utilisation needs the PMU or
#                 per-client fdinfo
#   xe            hwmon temperature only, but as temp2_input: xe's hwmon ABI
#                 numbers package temp starting at 2, there is no temp1 (see
#                 Documentation/ABI/testing/sysfs-driver-intel-xe-hwmon)
#   nouveau       hwmon temperature only (temp1_input)
#   NVIDIA prop.  nothing readable via sysfs at all, not even temperature —
#                 every reading requires NVML (nvidia-smi), which means a
#                 helper process. Deliberately left unsupported rather than
#                 spawning one per sample.
#
# Cards are ranked so one publishing utilisation wins outright, then by video
# memory. That keeps the discrete adapter on hybrid systems without hardcoding
# device IDs, and still reports a temperature-only card when it is all there is.
# Overridable so the discovery logic can be exercised against fixture trees
# that stand in for hardware this machine does not have.
drm_root="${OMARCHY_SYSMON_DRM_ROOT:-/sys/class/drm}"

best_rank=-1
best_vram=-1
gpu_busy=""
gpu_temp=""
gpu_vram_used=""
gpu_vram_total=""

for card in "$drm_root"/card*; do
  name="${card##*/}"
  [[ "$name" =~ ^card[0-9]+$ ]] || continue
  device="$card/device"
  [[ -d "$device" ]] || continue

  busy=""
  [[ -r "$device/gpu_busy_percent" ]] && busy="$device/gpu_busy_percent"

  # temp1_input covers amdgpu, i915, and nouveau. xe has no temp1 at all —
  # its package sensor starts numbering at temp2 — so that is checked as a
  # fallback rather than a replacement.
  temp=""
  for hwmon in "$device"/hwmon/hwmon*; do
    if [[ -r "$hwmon/temp1_input" ]]; then
      temp="$hwmon/temp1_input"
    elif [[ -r "$hwmon/temp2_input" ]]; then
      temp="$hwmon/temp2_input"
    else
      continue
    fi
    break
  done

  # Nothing readable here — an NVIDIA card on the proprietary driver, or a
  # display-only device. Reporting it would mean a panel full of dashes.
  [[ -n "$busy" || -n "$temp" ]] || continue

  vram=0
  [[ -r "$device/mem_info_vram_total" ]] && IFS= read -r vram <"$device/mem_info_vram_total"
  [[ "$vram" =~ ^[0-9]+$ ]] || vram=0

  if [[ -n "$busy" ]]; then rank=2; else rank=1; fi
  if (( rank > best_rank )) || { (( rank == best_rank )) && (( vram > best_vram )); }; then
    best_rank=$rank
    best_vram=$vram
    gpu_busy="$busy"
    gpu_temp="$temp"
    gpu_vram_used=""
    gpu_vram_total=""
    [[ -r "$device/mem_info_vram_used" ]] && gpu_vram_used="$device/mem_info_vram_used"
    [[ -r "$device/mem_info_vram_total" ]] && gpu_vram_total="$device/mem_info_vram_total"
  fi
done

[[ -n "$gpu_busy" ]] && printf 'gpu_busy\t%s\n' "$gpu_busy"
[[ -n "$gpu_temp" ]] && printf 'gpu_temp\t%s\n' "$gpu_temp"
[[ -n "$gpu_vram_used" ]] && printf 'gpu_vram_used\t%s\n' "$gpu_vram_used"
[[ -n "$gpu_vram_total" ]] && printf 'gpu_vram_total\t%s\n' "$gpu_vram_total"
exit 0
