#!/usr/bin/env bash
# Exercises GPU and hwmon discovery against fixture sysfs trees.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/discover-sensors.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
export OMARCHY_SYSMON_HWMON_ROOT="$work/empty-hwmon"
export OMARCHY_SYSMON_DRM_ROOT="$work/empty-drm"

card() { # <tree> <card> [busy] [vram_total] [temp]
  local dir="$work/$1/$2/device"
  mkdir -p "$dir"
  [[ -n "${3:-}" ]] && printf '%s\n' "$3" >"$dir/gpu_busy_percent"
  if [[ -n "${4:-}" ]]; then
    printf '%s\n' "$4" >"$dir/mem_info_vram_total"
    printf '%s\n' "1000" >"$dir/mem_info_vram_used"
  fi
  if [[ -n "${5:-}" ]]; then
    mkdir -p "$dir/hwmon/hwmon0"
    printf '%s\n' "$5" >"$dir/hwmon/hwmon0/temp1_input"
  fi
  return 0
}

check() { # <name> <tree> <key> <expected-substring-or-EMPTY>
  local out actual
  out="$(OMARCHY_SYSMON_DRM_ROOT="$work/$2" bash "$script" | grep "^$3	" || true)"
  actual="${out#*	}"
  if [[ "$4" == "EMPTY" ]]; then
    if [[ -z "$actual" ]]; then echo "  ok   $1: $3 absent"; else
      echo "  FAIL $1: $3 expected absent, got '$actual'"; failures=$((failures+1)); fi
  elif [[ "$actual" == *"$4"* ]]; then
    echo "  ok   $1: $3 -> $actual"
  else
    echo "  FAIL $1: $3 expected '*$4*', got '$actual'"; failures=$((failures+1))
  fi
}

echo "AMD hybrid (discrete + integrated) - picks the card with more VRAM"
card amd card0 "100" "536870912"   "35000"
card amd card1 "6"   "17095983104" "28000"
check "amd" amd gpu_busy  "card1"
check "amd" amd gpu_temp  "card1"
check "amd" amd gpu_vram_total "card1"

echo "Intel Arc (no busy counter anywhere) - still reports temperature"
card intel card0 "" "" "40000"
card intel card1 "" "" "52000"
check "intel" intel gpu_busy EMPTY
check "intel" intel gpu_temp "card"
check "intel" intel gpu_vram_total EMPTY

echo "Intel xe (package temp is temp2_input, there is no temp1) - still found"
mkdir -p "$work/xe/card0/device/hwmon/hwmon0"
printf '48000\n' >"$work/xe/card0/device/hwmon/hwmon0/temp2_input"
check "xe" xe gpu_busy EMPTY
check "xe" xe gpu_temp "temp2_input"

echo "Card with both temp1 and temp2 - temp1 wins (amdgpu edge sensor over the rest)"
mkdir -p "$work/temp-precedence/card0/device/hwmon/hwmon0"
printf '30000\n' >"$work/temp-precedence/card0/device/hwmon/hwmon0/temp1_input"
printf '55000\n' >"$work/temp-precedence/card0/device/hwmon/hwmon0/temp2_input"
check "temp-precedence" temp-precedence gpu_temp "temp1_input"

echo "NVIDIA proprietary (nothing readable) - reports nothing at all"
card nvidia card0 "" "" ""
check "nvidia" nvidia gpu_busy EMPTY
check "nvidia" nvidia gpu_temp EMPTY

echo "nouveau alongside AMD - utilisation outranks a temperature-only card"
card mixed card0 ""    ""            "60000"
card mixed card1 "12"  "8589934592"  "45000"
check "mixed" mixed gpu_busy "card1"
check "mixed" mixed gpu_temp "card1"

echo "AMD with less VRAM than a temperature-only card - utilisation still wins"
card rank card0 ""   "34359738368" "60000"
card rank card1 "3"  "8589934592"  "45000"
check "rank" rank gpu_busy "card1"

hwmon() { # <tree> <hwmon-directory> <chip-name>
  mkdir -p "$work/$1/$2"
  printf '%s\n' "$3" >"$work/$1/$2/name"
}

sensor() { # <tree> <hwmon-directory> <tempN-or-fanN> <label-or-empty> [value]
  local base="$work/$1/$2/$3"
  printf '%s\n' "${5:-42000}" >"${base}_input"
  [[ -z "$4" ]] || printf '%s\n' "$4" >"${base}_label"
  return 0
}

check_hwmon() { # <name> <tree> <expected-temp-or-EMPTY> <expected-fan-or-EMPTY> [temp-selector] [fan-selector] [expected-cpu]
  local out key output_key path expected actual status
  out="$(OMARCHY_SYSMON_HWMON_ROOT="$work/$2" bash "$script" "${5:-}" "${6:-}")"
  status=$?
  if (( status != 0 )); then
    echo "  FAIL $1: discovery exited $status"
    failures=$((failures+1))
  fi
  for key in chipset_temp chipset_fan cpu_temp; do
    case "$key" in
      chipset_temp) expected="$3" ;;
      chipset_fan) expected="$4" ;;
      cpu_temp) expected="${7:-EMPTY}" ;;
    esac
    [[ "$expected" == EMPTY ]] && expected="" || expected="$work/$2/$expected"
    actual=""
    while IFS=$'\t' read -r output_key path; do
      [[ "$output_key" == "$key" ]] || continue
      # Preserve duplicate output so exact comparison rejects it.
      actual+="${actual:+$'\n'}$path"
    done <<<"$out"
    if [[ "$actual" == "$expected" ]]; then
      echo "  ok   $1: $key ${actual:-absent}"
    else
      echo "  FAIL $1: $key expected '$expected', got '$actual'"
      failures=$((failures+1))
    fi
  done
}

echo "Automatic chipset labels are case-insensitive, with space/underscore variants"
labels=(Chipset PCH SB Southbridge 'South Bridge' south_bridge 'cHiPsEt_TeMp' 'PCH Temperature' 'SB_TEMP' 'South_Bridge_Temperature')
fan_labels=(Chipset PCH SB Southbridge 'South Bridge' south_bridge 'cHiPsEt_FaN' 'PCH Fan' 'SB_FAN' 'South_Bridge_Fan')
for i in "${!labels[@]}"; do
  tree="labels-$i"
  hwmon "$tree" hwmon4 controller
  sensor "$tree" hwmon4 temp2 "${labels[$i]}"
  sensor "$tree" hwmon4 fan3 "${fan_labels[$i]}" 0
  check_hwmon "${labels[$i]} / ${fan_labels[$i]} (zero RPM)" "$tree" hwmon4/temp2_input hwmon4/fan3_input
done

echo "Temperature and fan discovery are independent, even across chips"
hwmon independent hwmon1 thermal
sensor independent hwmon1 temp7 PCH
check_hwmon "temperature only" independent hwmon1/temp7_input EMPTY
hwmon independent hwmon9 cooling
sensor independent hwmon9 fan2 'Chipset Fan' 900
check_hwmon "separate chips" independent hwmon1/temp7_input hwmon9/fan2_input
hwmon fan-only hwmon3 cooling
sensor fan-only hwmon3 fan1 SB 0
check_hwmon "fan only" fan-only EMPTY hwmon3/fan1_input

echo "Unlabeled, generic, wrong-type and non-allowlisted labels are not guessed"
hwmon rejected hwmon0 nct6798
labels=('' SYSTIN AUXTIN SMBUSMASTER temp1 fan6 'CPU PCH' 'PCH Core' 'Chipset Fan')
for i in "${!labels[@]}"; do sensor rejected hwmon0 "temp$((i+1))" "${labels[$i]}"; done
labels=('' SYSTIN AUXTIN SMBUSMASTER temp1 fan6 'CPU PCH' 'PCH Core' 'Chipset Temp')
for i in "${!labels[@]}"; do sensor rejected hwmon0 "fan$((i+1))" "${labels[$i]}"; done
sensor rejected hwmon0 tempX PCH
sensor rejected hwmon0 fanX PCH
check_hwmon "no guessed channels" rejected EMPTY EMPTY

echo "Ambiguity is rejected per sensor, within a chip and globally"
hwmon ambiguous hwmon0 controller
sensor ambiguous hwmon0 temp1 PCH
sensor ambiguous hwmon0 temp2 PCH
sensor ambiguous hwmon0 fan1 SB
check_hwmon "duplicate temperature labels" ambiguous EMPTY hwmon0/fan1_input
check_hwmon "explicit duplicate label" ambiguous EMPTY hwmon0/fan1_input controller:PCH
sensor ambiguous hwmon0 fan2 SB
check_hwmon "both ambiguous" ambiguous EMPTY EMPTY
check_hwmon "explicit duplicate fan label" ambiguous hwmon0/temp1_input EMPTY controller:temp1_input controller:SB
check_hwmon "filenames disambiguate channels" ambiguous hwmon0/temp2_input hwmon0/fan2_input controller:temp2_input controller:fan2_input

hwmon duplicates hwmon1 controller
hwmon duplicates hwmon8 controller
for chip in hwmon1 hwmon8; do
  sensor duplicates "$chip" temp1 PCH
  sensor duplicates "$chip" fan1 SB
done
check_hwmon "same-name chips automatic" duplicates EMPTY EMPTY
check_hwmon "same-name chips explicit labels" duplicates EMPTY EMPTY controller:PCH controller:SB
check_hwmon "same-name chips explicit filenames" duplicates EMPTY EMPTY controller:temp1_input controller:fan1_input
hwmon duplicates hwmon8 other-controller
check_hwmon "different-name chips still globally ambiguous" duplicates EMPTY EMPTY
check_hwmon "explicit chip names disambiguate" duplicates hwmon1/temp1_input hwmon8/fan1_input controller:PCH other-controller:SB

echo "Explicit label and filename overrides are exact, type-specific and never fall back"
hwmon overrides hwmon5 Board
sensor overrides hwmon5 temp1 PCH
sensor overrides hwmon5 fan1 SB
sensor overrides hwmon5 temp4 'Custom Temp'
sensor overrides hwmon5 fan4 'Custom Fan' 0
sensor overrides hwmon5 temp6 ''
sensor overrides hwmon5 fan6 '' 0
check_hwmon "custom labels" overrides hwmon5/temp4_input hwmon5/fan4_input 'Board:Custom Temp' 'Board:Custom Fan'
check_hwmon "unlabeled filename overrides" overrides hwmon5/temp6_input hwmon5/fan6_input Board:temp6_input Board:fan6_input
check_hwmon "invalid temp leaves fan automatic" overrides EMPTY hwmon5/fan1_input Board:missing
check_hwmon "invalid fan leaves temp automatic" overrides hwmon5/temp1_input EMPTY '' Board:missing
for selector in board:PCH Board:pch Board:SB Board:fan1_input Board:fan4_input Board:fan6_input Board:temp99_input Board:tempX_input Board:temp1_label Board:../temp1_input Board: '':PCH Board Board:PCH:extra '*:PCH' 'Board:*'; do
  check_hwmon "invalid temperature $selector" overrides EMPTY hwmon5/fan1_input "$selector"
done
for selector in board:SB Board:sb Board:PCH Board:temp1_input Board:temp4_input Board:temp6_input Board:fan99_input Board:fanX_input Board:fan1_label Board:../fan1_input Board: '':SB Board Board:SB:extra '*:SB' 'Board:*'; do
  check_hwmon "invalid fan $selector" overrides hwmon5/temp1_input EMPTY '' "$selector"
done
malicious='Board:$(touch "'"$work"'/selector-executed")'
check_hwmon "literal command substitution" overrides EMPTY EMPTY "$malicious" "$malicious"
malicious='Board:SB; touch "'"$work"'/selector-executed"'
check_hwmon "literal shell commands" overrides EMPTY EMPTY "$malicious" "$malicious"
malicious='Board:`touch "'"$work"'/selector-executed"`'
check_hwmon "literal backticks" overrides EMPTY EMPTY "$malicious" "$malicious"
if [[ -e "$work/selector-executed" ]]; then
  echo "  FAIL selector executed a command"
  failures=$((failures+1))
fi

echo "Missing or non-file inputs are ineligible, without making readable candidates ambiguous"
hwmon missing hwmon2 controller
printf 'PCH\n' >"$work/missing/hwmon2/temp1_label"
printf 'SB\n' >"$work/missing/hwmon2/fan1_label"
check_hwmon "labels without inputs" missing EMPTY EMPTY
check_hwmon "missing explicit labels" missing EMPTY EMPTY controller:PCH controller:SB
check_hwmon "missing explicit filenames" missing EMPTY EMPTY controller:temp1_input controller:fan1_input
mkdir "$work/missing/hwmon2/temp1_input" "$work/missing/hwmon2/fan1_input"
check_hwmon "directories are not inputs" missing EMPTY EMPTY controller:temp1_input controller:fan1_input
sensor missing hwmon2 temp2 PCH
sensor missing hwmon2 fan2 SB 0
check_hwmon "only readable files count" missing hwmon2/temp2_input hwmon2/fan2_input controller:PCH controller:SB

hwmon unreadable hwmon0 controller
sensor unreadable hwmon0 temp1 PCH
sensor unreadable hwmon0 fan1 SB 0
chmod 000 "$work/unreadable/hwmon0/temp1_input" "$work/unreadable/hwmon0/fan1_input"
if [[ ! -r "$work/unreadable/hwmon0/temp1_input" && ! -r "$work/unreadable/hwmon0/fan1_input" ]]; then
  check_hwmon "unreadable automatic inputs" unreadable EMPTY EMPTY
  check_hwmon "unreadable explicit inputs" unreadable EMPTY EMPTY controller:temp1_input controller:fan1_input
  sensor unreadable hwmon0 temp2 PCH
  sensor unreadable hwmon0 fan2 SB 0
  check_hwmon "unreadable inputs do not cause ambiguity" unreadable hwmon0/temp2_input hwmon0/fan2_input controller:PCH controller:SB
else
  echo "  SKIP unreadable inputs: current user can read mode-000 files"
fi

echo "CPU discovery uses the same fixture root; selectors survive hwmon renumbering"
hwmon renumber hwmon1 coretemp
sensor renumber hwmon1 temp1 'Core 0'
sensor renumber hwmon1 temp2 'Package id 0'
hwmon renumber hwmon3 controller
sensor renumber hwmon3 temp3 PCH
sensor renumber hwmon3 fan5 SB 0
check_hwmon "before renumbering" renumber hwmon3/temp3_input hwmon3/fan5_input controller:PCH controller:fan5_input hwmon1/temp2_input
mv "$work/renumber/hwmon3" "$work/renumber/hwmon42"
check_hwmon "after renumbering" renumber hwmon42/temp3_input hwmon42/fan5_input controller:PCH controller:fan5_input hwmon1/temp2_input
check_hwmon "automatic after renumbering" renumber hwmon42/temp3_input hwmon42/fan5_input '' '' hwmon1/temp2_input

echo
if (( failures == 0 )); then echo "all discovery fixtures passed"; else
  echo "$failures failing check(s)"; exit 1; fi
