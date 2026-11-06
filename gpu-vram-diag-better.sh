#!/usr/bin/env bash
# NVIDIA Quadro M6000 24GB (Maxwell GM200, sm_52) VRAM, compute and thermal stress diagnostics.
# Target: Ubuntu 24.04 with the NVIDIA driver already installed.
#
# Tools used (built locally, nothing is installed system-wide except build dependencies):
#   cuda_memtest  https://github.com/ComputationalRadiationPhysics/cuda_memtest
#                 VRAM pattern tests 0-8, test 9 (bit fade), test 10 (memory stress)
#   gpu-burn      https://github.com/wilicc/gpu-burn
#                 matrix-multiply load with result verification (compute + VRAM + power + heat)
set -Eeuo pipefail
umask 077

# ----------------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------------
GPU=0
MODE=standard
DURATION_S=""
NO_INSTALL=0
NO_INHIBIT=0
BIT_FADE_OVERRIDE=""
SKIP_LIST=""
TEMP_LIMIT=""
BURN_MEM_PCT=90
OUTPUT_BASE="${HOME}/gpu-vram-logs"
CACHE_DIR="${HOME}/.cache/gpu-vram-diag"
MEMTEST_URL="https://github.com/ComputationalRadiationPhysics/cuda_memtest.git"
BURN_URL="https://github.com/wilicc/gpu-burn.git"
MEMTEST_SRC="${CACHE_DIR}/cuda_memtest"
MEMTEST_BUILD="${MEMTEST_SRC}/build-sm52"
BURN_SRC="${CACHE_DIR}/gpu-burn"
BURN_STUB="${CACHE_DIR}/libcuda-stub"

# Tunables (environment overrides exist mainly for testing the script itself).
SAMPLE_INTERVAL="${GPU_DIAG_SAMPLE_INTERVAL:-2}"   # seconds between telemetry samples
HEARTBEAT_S="${GPU_DIAG_HEARTBEAT:-300}"            # console status line interval
XID_POLL="${GPU_DIAG_XID_POLL:-10}"                 # kernel log poll interval
MIN_SLICE="${GPU_DIAG_MIN_SLICE:-120}"              # minimum time slice per pattern test
MIN_PHASE="${GPU_DIAG_MIN_PHASE:-60}"               # phases with a smaller budget are skipped
BURN_MARGIN="${GPU_DIAG_BURN_MARGIN:-30}"           # gpu-burn startup/teardown allowance
STRESS_ITER=500                                     # iterations per cuda_memtest test 10 pass
KERNEL_RE='NVRM: Xid|has fallen off the bus'
MEMTEST_ERR_RE='ERROR:|[1-9][0-9]* errors found|memory corruption|illegal memory access|unspecified launch failure|Segmentation fault'

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------
MON_PID=""
KEEP_PID=""
PARENT_PID=$$
PERSIST_CHANGED=0
SUDO=()
SUDO_N=()
RUN_DIR=""
RUN_LOG=""
ARCHIVE=""
START_LOCAL=""
START_EPOCH=0
ABORT_FILE=""
CHILD_FILE=""
FATAL_MSG=""
INTERRUPTED=0
NVCC=""
CUDA_ROOT=""
BIN=""
BURN_OK=0
BIT_FADE=0
KERNEL_BASE=0
FIELD_CSV=""
THROTTLE_FIELD=""
LAUNCHED_PID=""
LAST_RC=0
EV_STATE=""
EV_NOTE=""
MT_STATE=""
declare -a FAILURES=()
declare -a WARNINGS=()
declare -a TEL_FIELDS=()
declare -A TEL_IDX=()
declare -A PRES=([patterns]="NOT RUN" [burn]="NOT RUN" [stress]="NOT RUN" [combined]="NOT RUN" [bitfade]="NOT RUN")
declare -A PNOTE=()
declare -A TS=()
ECC_FIELDS=(ecc.mode.current ecc.errors.corrected.volatile.total ecc.errors.uncorrected.volatile.total
  ecc.errors.corrected.aggregate.total ecc.errors.uncorrected.aggregate.total
  retired_pages.single_bit_ecc.count retired_pages.double_bit.count retired_pages.pending)

usage() {
  cat <<'EOF'
Usage: bash gpu-vram-diag.sh [options]

Time budget (test time only; build and report steps are extra):
  (default)        2 hours
  --quick          20 minutes
  --extended       6 hours
  --burn-in        12 hours, plus the 3 hour bit-fade test
  --duration T     Custom budget, e.g. 90m, 2h, 1h30m, 7200s (bare number = minutes)

Phases, run in this order, sharing the budget by weight:
  patterns  35%  cuda_memtest tests 0-8, one test at a time, round robin
  burn      25%  gpu-burn: FP32 matrix multiply with verification, ~90% of VRAM
  stress    25%  cuda_memtest test 10: sustained read/write/verify of all VRAM
  combined  15%  gpu-burn (35% of VRAM) and cuda_memtest stress (the rest) at the same time

Options:
  --skip LIST      Comma separated phases to skip (patterns,burn,stress,combined)
  --bit-fade       Also run test 9 (two 90 minute retention waits, about 3 hours extra)
  --no-bit-fade    Skip bit-fade even with --burn-in
  --temp-limit C   Abort if the GPU stays at or above C degrees (default: min(90, slowdown temp - 2))
  --burn-mem PCT   Percent of free VRAM gpu-burn uses in the burn phase (default 90)
  --gpu N          GPU index (default 0)
  --no-install     Do not install Ubuntu build dependencies or the CUDA toolkit
  --no-inhibit     Do not block sleep/idle with systemd-inhibit
  --out DIR        Base directory for logs (default ~/gpu-vram-logs)
  -h, --help       Show this help

Safety mechanisms: temperature abort, GPU responsiveness check, kernel Xid / fallen-off-bus
abort, throttle and PCIe link logging, ECC and retired-page before/after comparison.
Run on a GPU that is not driving a desktop if possible, with good airflow, inside tmux or screen.
Exit code: 0 pass (with or without warnings), 1 failure, 3 inconclusive, 130/143 interrupted.
EOF
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
info() {
  local m
  m="$(printf '[%s] %s' "$(date '+%F %T')" "$*")"
  printf '%s\n' "$m"
  if [[ -n "$RUN_LOG" ]]; then printf '%s\n' "$m" >> "$RUN_LOG"; fi
}
warn() {
  local m
  m="$(printf '[%s] [WARN] %s' "$(date '+%F %T')" "$*")"
  printf '%s\n' "$m" >&2
  if [[ -n "$RUN_LOG" ]]; then printf '%s\n' "$m" >> "$RUN_LOG"; fi
}
fatal() { FATAL_MSG="$*"; warn "$*"; exit 1; }
add_failure() { FAILURES+=("$*"); warn "FAILURE FINDING: $*"; }
add_warning() { WARNINGS+=("$*"); warn "WARNING FINDING: $*"; }

fmt_dur() {
  local s="$1"
  printf '%dh%02dm%02ds' $(( s / 3600 )) $(( (s % 3600) / 60 )) $(( s % 60 ))
}

parse_duration() {
  local s="$1"
  [[ -n "$s" ]] || return 1
  if [[ "$s" =~ ^[0-9]+$ ]]; then echo $(( 10#$s * 60 )); return 0; fi
  if [[ "$s" =~ ^(([0-9]+)h)?(([0-9]+)m)?(([0-9]+)s)?$ ]]; then
    echo $(( 10#${BASH_REMATCH[2]:-0} * 3600 + 10#${BASH_REMATCH[4]:-0} * 60 + 10#${BASH_REMATCH[6]:-0} ))
    return 0
  fi
  return 1
}

smi_value() {
  # smi_value FIELD -> prints the first line of the query result, or nothing if unsupported
  local v
  if v="$(timeout 10 nvidia-smi -i "$GPU" --query-gpu="$1" --format=csv,noheader,nounits 2>/dev/null)"; then
    printf '%s' "$v" | head -1 | tr -d '\r'
  fi
}

snapshot() {
  local stage="$1"
  timeout 60 nvidia-smi -q -i "$GPU" > "$RUN_DIR/nvidia-smi-${stage}.txt" 2>&1 || true
  timeout 60 nvidia-smi -q -i "$GPU" -d ECC,PAGE_RETIREMENT,PERFORMANCE,TEMPERATURE,POWER,CLOCK \
    > "$RUN_DIR/nvidia-smi-detail-${stage}.txt" 2>&1 || true
  timeout 60 nvidia-smi -L > "$RUN_DIR/gpu-list-${stage}.txt" 2>&1 || true
  if command -v lspci >/dev/null 2>&1; then
    timeout 60 "${SUDO[@]}" lspci -vv -d 10de: > "$RUN_DIR/pci-detail-${stage}.txt" 2>&1 || true
  fi
}

# Keeps the sudo timestamp fresh so background kernel-log checks (sudo -n) keep working for hours.
start_sudo_keepalive() {
  if (( ${#SUDO_N[@]} == 0 )); then return 0; fi
  (
    set +e
    local slp=""
    trap 'if [[ -n "$slp" ]]; then kill "$slp" 2>/dev/null; fi; exit 0' TERM
    while kill -0 "$PARENT_PID" 2>/dev/null; do
      "${SUDO_N[@]}" -v > /dev/null 2>&1
      sleep 50 &
      slp=$!
      wait "$slp"
    done
  ) &
  KEEP_PID=$!
}

ecc_snapshot() {
  local f v
  : > "$1"
  for f in "${ECC_FIELDS[@]}"; do
    v="$(smi_value "$f")"
    printf '%s=%s\n' "$f" "${v:-unavailable}" >> "$1"
  done
}

ecc_compare() {
  declare -A B=() A=()
  local k v f b a
  [[ -f "$RUN_DIR/ecc-before.txt" && -f "$RUN_DIR/ecc-after.txt" ]] || return 0
  while IFS='=' read -r k v; do B["$k"]="$v"; done < "$RUN_DIR/ecc-before.txt"
  while IFS='=' read -r k v; do A["$k"]="$v"; done < "$RUN_DIR/ecc-after.txt"
  ECC_MODE="${A[ecc.mode.current]:-unknown}"
  for f in "${ECC_FIELDS[@]:1}"; do
    b="${B[$f]:-}"; a="${A[$f]:-}"
    if [[ "$f" == retired_pages.pending ]]; then
      if [[ "${a,,}" == yes && "${b,,}" != yes ]]; then
        add_failure "GPU now reports a pending page retirement (retired_pages.pending)"
      fi
      continue
    fi
    if [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] && (( a > b )); then
      case "$f" in
        *uncorrected*|retired_pages.double_bit.count)
          add_failure "$f rose from $b to $a during the run" ;;
        *)
          add_warning "$f rose from $b to $a during the run" ;;
      esac
    fi
    if [[ "$f" == *aggregate* || "$f" == retired_pages.* ]] && [[ "$b" =~ ^[0-9]+$ ]] && (( b > 0 )); then
      add_warning "GPU already had $f=$b recorded before this run"
    fi
  done
}

count_kernel_events() {
  local out
  if out="$(timeout 20 "${SUDO_N[@]}" journalctl -k -b --no-pager 2>/dev/null)"; then
    :
  else
    out="$(timeout 20 "${SUDO_N[@]}" dmesg 2>/dev/null || true)"
  fi
  printf '%s\n' "$out" | grep -Eci "$1" || true
}

# ----------------------------------------------------------------------------
# Child process handling. Every test process is started through "timeout" in its own
# process group, so signalling the timeout process stops the whole tree (gpu-burn forks).
# ----------------------------------------------------------------------------
launch() {
  # launch LOGFILE TIMEOUT_SECONDS CMD...   (sets LAUNCHED_PID)
  local log="$1" secs="$2"
  shift 2
  timeout --signal=TERM --kill-after=45 "$secs" "$@" > "$log" 2>&1 &
  LAUNCHED_PID=$!
  printf '%s\n' "$LAUNCHED_PID" >> "$CHILD_FILE"
}

forget_children() { : > "$CHILD_FILE"; }

kill_children() {
  local p
  [[ -n "$CHILD_FILE" && -f "$CHILD_FILE" ]] || return 0
  while read -r p; do
    if [[ -n "$p" ]]; then kill -TERM "$p" 2>/dev/null || true; fi
  done < "$CHILD_FILE"
  return 0
}

wait_for() {
  # wait_for PID -> LAST_RC
  LAST_RC=0
  wait "$1" || LAST_RC=$?
}

burn_launch() {
  # burn_launch LOGFILE TIMEOUT RUN_SECONDS MEM_PERCENT
  # gpu-burn matches options by substring ("-d", "-l", "-h" anywhere in an argument), so it must be
  # started from its own directory with only plain arguments and no paths.
  launch "$1" "$2" bash -c 'cd "$1" && shift && exec ./gpu_burn "$@"' _ "$BURN_SRC" \
    -m "${4}%" -i "$GPU" "$3"
}

# ----------------------------------------------------------------------------
# Result evaluation
# ----------------------------------------------------------------------------
eval_stress() {
  # eval_stress LOG RC -> EV_STATE EV_NOTE
  local log="$1" rc="$2" passes mb
  EV_STATE=PASS
  EV_NOTE=""
  passes="$(grep -c 'Test10 finished' "$log" 2>/dev/null || true)"
  passes="${passes:-0}"
  mb="$(sed -n 's/.*Allocated \([0-9]*\) MB.*/\1/p' "$log" 2>/dev/null | head -1 || true)"
  if [[ -e "$ABORT_FILE" ]]; then
    EV_STATE=ABORTED; EV_NOTE="stopped by watchdog"
  elif grep -Eq "$MEMTEST_ERR_RE" "$log" 2>/dev/null; then
    EV_STATE=FAIL; EV_NOTE="cuda_memtest reported errors (exit code $rc)"
  elif [[ "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ]]; then
    EV_STATE=FAIL; EV_NOTE="cuda_memtest exited with code $rc"
  elif (( passes < 1 )); then
    EV_STATE=PARTIAL; EV_NOTE="no complete stress pass finished inside the time budget"
  else
    EV_NOTE="$passes complete pass(es) of ${STRESS_ITER} iterations over ${mb:-?} MB, no mismatches"
  fi
}

eval_burn() {
  # eval_burn LOG RC -> EV_STATE EV_NOTE
  local log="$1" rc="$2" clean="$RUN_DIR/.burn-clean.txt" range
  EV_STATE=PASS
  EV_NOTE=""
  tr '\r' '\n' < "$log" > "$clean" 2>/dev/null || true
  range="$(grep -o '([0-9]* Gflop/s)' "$clean" 2>/dev/null | tr -dc '0-9\n' \
    | awk 'NF && $1 > 0 { if (min == "" || $1 < min) min = $1; if ($1 > max) max = $1 } END { if (max > 0) printf "%d-%d Gflop/s", min, max }' || true)"
  if [[ -e "$ABORT_FILE" ]]; then
    EV_STATE=ABORTED; EV_NOTE="stopped by watchdog"
  elif grep -Eq 'FAULTY|DIED|\(WARNING!\)' "$clean" 2>/dev/null; then
    EV_STATE=FAIL; EV_NOTE="gpu-burn found result mismatches or a worker died (exit code $rc)"
  elif [[ "$rc" != 0 && "$rc" != 124 && "$rc" != 137 ]]; then
    EV_STATE=FAIL; EV_NOTE="gpu-burn exited with code $rc (see log)"
  elif grep -Eq 'GPU [0-9]+: OK' "$clean" 2>/dev/null; then
    EV_NOTE="all results verified OK${range:+, throughput $range}"
  else
    EV_STATE=PARTIAL; EV_NOTE="gpu-burn did not print a final verdict"
  fi
}

worst_state() {
  # worst_state A B -> prints the worse of two phase states
  local s order="FAIL ABORTED PARTIAL PASS"
  for s in $order; do
    if [[ "$1" == "$s" || "$2" == "$s" ]]; then printf '%s' "$s"; return 0; fi
  done
  printf '%s' "$1"
}

# ----------------------------------------------------------------------------
# Watchdog and telemetry: one sample every SAMPLE_INTERVAL seconds
# ----------------------------------------------------------------------------
getv() {
  GV=""
  local i="${TEL_IDX[$1]:-}"
  if [[ -n "$i" ]]; then GV="${V[$i]:-}"; fi
  return 0
}

wd_abort() {
  local kind="$1" reason="$2"
  if [[ ! -e "$ABORT_FILE" ]]; then
    printf '%s|%s\n' "$kind" "$reason" > "$ABORT_FILE"
    warn "WATCHDOG ABORT ($kind): $reason"
    kill_children
  fi
}

watchdog_loop() {
  set +e
  trap 'exit 0' TERM INT
  local bad_temp=0 fails=0 last_hb=0 last_x=0 now row hw swcap temp reasons cur r phase
  local -a V=()
  while :; do
    now="$(date +%s)"
    row=""
    if row="$(timeout 10 nvidia-smi -i "$GPU" --query-gpu="$FIELD_CSV" --format=csv,noheader,nounits 2>>"$RUN_DIR/telemetry-errors.log")" && [[ -n "$row" ]]; then
      fails=0
      row="${row//$'\r'/}"
      row="${row//, /,}"
      IFS=',' read -r -a V <<< "$row"
      hw=0; swcap=0
      if [[ -n "$THROTTLE_FIELD" ]]; then
        getv "$THROTTLE_FIELD"; reasons="$GV"
        if [[ "$reasons" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
          r=$(( reasons ))
          if (( r & 0xE8 )); then hw=1; fi      # HW slowdown, SW thermal, HW thermal, HW power brake
          if (( r & 0x04 )); then swcap=1; fi   # SW power cap
        fi
      fi
      printf '%s,%s,%s,%s,%s\n' "$now" "$(date '+%F %T')" "$row" "$hw" "$swcap" >> "$RUN_DIR/telemetry.csv"

      getv temperature.gpu; temp="$GV"
      if [[ "$temp" =~ ^[0-9]+$ ]] && (( temp >= TEMP_LIMIT )); then
        bad_temp=$(( bad_temp + 1 ))
        if (( bad_temp >= 3 )); then
          wd_abort THERMAL "GPU temperature ${temp}C stayed at or above the ${TEMP_LIMIT}C limit for 3 samples"
        fi
      else
        bad_temp=0
      fi

      if (( now - last_hb >= HEARTBEAT_S )); then
        last_hb=$now
        phase="$(cat "$RUN_DIR/.phase" 2>/dev/null)"
        getv power.draw; local pw="$GV"
        getv utilization.gpu; local ut="$GV"
        getv memory.used; local mu="$GV"
        getv clocks.sm; local sm="$GV"
        printf '[%s] [%s] GPU %s: %sC, %sW, util %s%%, VRAM %s MiB, SM %s MHz, throttle %s\n' \
          "$(date '+%F %T')" "${phase:-idle}" "$GPU" "$temp" "$pw" "$ut" "$mu" "$sm" "${reasons:-n/a}"
      fi
    else
      fails=$(( fails + 1 ))
      if (( fails >= 3 )); then
        wd_abort HW "GPU stopped answering nvidia-smi 3 times in a row (it may have fallen off the bus)"
      fi
    fi

    if (( now - last_x >= XID_POLL )); then
      last_x=$now
      cur="$(count_kernel_events "$KERNEL_RE")"
      if [[ "$cur" =~ ^[0-9]+$ ]] && (( cur > KERNEL_BASE )); then
        wd_abort HW "$(( cur - KERNEL_BASE )) new NVIDIA Xid or fallen-off-bus kernel message(s); see kernel-since-test.log"
      fi
    fi

    if ! kill -0 "$PARENT_PID" 2>/dev/null; then exit 0; fi
    sleep "$SAMPLE_INTERVAL"
  done
}

start_watchdog() {
  watchdog_loop &
  MON_PID=$!
}

ensure_watchdog() {
  if [[ -n "$MON_PID" ]] && ! kill -0 "$MON_PID" 2>/dev/null; then
    warn "Watchdog process died unexpectedly; restarting it"
    start_watchdog
  fi
}

stop_watchdog() {
  if [[ -n "$MON_PID" ]]; then
    kill "$MON_PID" 2>/dev/null || true
    wait "$MON_PID" 2>/dev/null || true
    MON_PID=""
  fi
}

probe_telemetry_fields() {
  local f
  local -a want=(temperature.gpu power.draw power.limit utilization.gpu utilization.memory memory.used
    clocks.sm clocks.max.sm clocks.mem fan.speed
    pcie.link.gen.current pcie.link.gen.max pcie.link.width.current pcie.link.width.max)
  TEL_FIELDS=()
  for f in "${want[@]}"; do
    if timeout 10 nvidia-smi -i "$GPU" --query-gpu="$f" --format=csv,noheader >/dev/null 2>&1; then
      TEL_FIELDS+=("$f")
    fi
  done
  THROTTLE_FIELD=""
  for f in clocks_event_reasons.active clocks_throttle_reasons.active; do
    if timeout 10 nvidia-smi -i "$GPU" --query-gpu="$f" --format=csv,noheader >/dev/null 2>&1; then
      THROTTLE_FIELD="$f"
      TEL_FIELDS+=("$f")
      break
    fi
  done
  local i
  TEL_IDX=()
  for i in "${!TEL_FIELDS[@]}"; do TEL_IDX["${TEL_FIELDS[$i]}"]="$i"; done
  [[ -n "${TEL_IDX[temperature.gpu]:-}" ]] || fatal "Cannot read GPU temperature through nvidia-smi; refusing to run without thermal monitoring."
  FIELD_CSV="$(IFS=,; printf '%s' "${TEL_FIELDS[*]}")"
  printf 'epoch,time,%s,hw_throttle,sw_power_cap\n' "$FIELD_CSV" > "$RUN_DIR/telemetry.csv"
}

telemetry_stats() {
  [[ -s "$RUN_DIR/telemetry.csv" ]] || return 0
  awk -F, '
    function isnum(x) { return (x ~ /^-?[0-9]+(\.[0-9]+)?$/) }
    function g(n) { return (n in c) ? $(c[n]) : "" }
    NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
    {
      rows++
      if (rows == 1) first = $1
      last = $1
      t = g("temperature.gpu"); u = g("utilization.gpu"); p = g("power.draw"); s = g("clocks.sm")
      m = g("memory.used"); ms = g("clocks.max.sm")
      if (isnum(t)) { if (!tseen) { tstart = t; tseen = 1 } if (t + 0 > tmax) tmax = t + 0 }
      if (isnum(p) && p + 0 > pmax) pmax = p + 0
      if (isnum(m) && m + 0 > mmax) mmax = m + 0
      if (isnum(ms) && ms + 0 > smaxclk) smaxclk = ms + 0
      if (isnum(s) && s + 0 > smaxseen) smaxseen = s + 0
      if (g("hw_throttle") == "1") hw++
      if (g("sw_power_cap") == "1") swc++
      if (isnum(u) && u + 0 >= 80) {
        load++
        if (isnum(p)) { psum += p; pn++ }
        if (isnum(s)) { ssum += s; sn++; if (smin == "" || s + 0 < smin) smin = s + 0 }
        gg = g("pcie.link.gen.current"); ww = g("pcie.link.width.current")
        if (isnum(gg) && (gmin == "" || gg + 0 < gmin)) gmin = gg + 0
        if (isnum(ww) && (wmin == "" || ww + 0 < wmin)) wmin = ww + 0
      }
      gm = g("pcie.link.gen.max"); wm = g("pcie.link.width.max")
      if (isnum(gm)) gmax = gm + 0
      if (isnum(wm)) wmax = wm + 0
    }
    END {
      printf "samples=%d\n", rows
      printf "span_s=%d\n", last - first
      printf "temp_start=%s\n", (tseen ? tstart : "")
      printf "temp_max=%s\n", (tmax == "" ? "" : tmax)
      printf "power_max=%s\n", (pmax == "" ? "" : pmax)
      printf "power_avg_load=%s\n", (pn > 0 ? sprintf("%.1f", psum / pn) : "")
      printf "load_samples=%d\n", load
      printf "sm_clock_min_load=%s\n", smin
      printf "sm_clock_avg_load=%s\n", (sn > 0 ? sprintf("%d", ssum / sn) : "")
      printf "sm_clock_max=%s\n", (smaxclk != "" ? smaxclk : smaxseen)
      printf "hw_throttle_samples=%d\n", hw
      printf "sw_power_cap_samples=%d\n", swc
      printf "pcie_gen_min_load=%s\n", gmin
      printf "pcie_gen_max=%s\n", gmax
      printf "pcie_width_min_load=%s\n", wmin
      printf "pcie_width_max=%s\n", wmax
      printf "vram_used_max=%s\n", mmax
    }' "$RUN_DIR/telemetry.csv" > "$RUN_DIR/telemetry-summary.txt" 2>/dev/null || true
  local k v
  TS=()
  while IFS='=' read -r k v; do TS["$k"]="$v"; done < "$RUN_DIR/telemetry-summary.txt"
}

telemetry_findings() {
  local n="${TS[samples]:-0}" hw="${TS[hw_throttle_samples]:-0}" tmax="${TS[temp_max]:-}"
  local smin="${TS[sm_clock_min_load]:-}" smax="${TS[sm_clock_max]:-}"
  local gmin="${TS[pcie_gen_min_load]:-}" gmax="${TS[pcie_gen_max]:-}"
  local wmin="${TS[pcie_width_min_load]:-}" wmax="${TS[pcie_width_max]:-}"
  if (( n == 0 )); then return 0; fi
  if [[ "$hw" =~ ^[0-9]+$ ]] && (( hw > 0 )); then
    add_warning "GPU reported hardware or thermal slowdown in $hw of $n samples (check cooling and power delivery)"
  fi
  if [[ "$tmax" =~ ^[0-9]+$ && "$TEMP_LIMIT" =~ ^[0-9]+$ ]] && (( tmax >= TEMP_LIMIT - 3 )); then
    add_warning "Peak GPU temperature ${tmax}C is within 3C of the ${TEMP_LIMIT}C abort limit"
  fi
  if [[ "$smin" =~ ^[0-9]+$ && "$smax" =~ ^[0-9]+$ ]] && (( smax > 0 && smin * 100 < smax * 70 )); then
    add_warning "SM clock fell to ${smin} MHz under load (max ${smax} MHz); the card was throttling"
  fi
  if [[ "$wmin" =~ ^[0-9]+$ && "$wmax" =~ ^[0-9]+$ ]] && (( wmin < wmax )); then
    add_warning "PCIe link width dropped to x${wmin} under load (max x${wmax}); reseat the card or check the slot"
  fi
  if [[ "$gmin" =~ ^[0-9]+$ && "$gmax" =~ ^[0-9]+$ ]] && (( gmin < gmax )); then
    add_warning "PCIe link generation dropped to Gen${gmin} under load (max Gen${gmax})"
  fi
}

# ----------------------------------------------------------------------------
# Verdict, report, cleanup
# ----------------------------------------------------------------------------
compute_verdict() {
  local p done_count=0 abort_kind=""
  VERDICT="PASSED"
  if (( ${#WARNINGS[@]} > 0 )); then VERDICT="PASSED WITH WARNINGS"; fi
  for p in patterns burn stress combined bitfade; do
    if [[ "${PRES[$p]}" == PASS || "${PRES[$p]}" == PARTIAL ]]; then done_count=$(( done_count + 1 )); fi
  done
  if [[ -e "$ABORT_FILE" ]]; then abort_kind="$(cut -d'|' -f1 "$ABORT_FILE")"; fi
  if (( done_count == 0 )) || [[ -n "$abort_kind" ]] || [[ -n "$FATAL_MSG" ]] || (( INTERRUPTED )); then
    VERDICT="INCONCLUSIVE (tests did not finish)"
  fi
  for p in patterns burn stress combined bitfade; do
    if [[ "${PRES[$p]}" == FAIL ]]; then VERDICT="FAILED"; fi
  done
  if [[ "$abort_kind" == HW ]]; then
    FAILURES+=("Watchdog stopped the run: $(cut -d'|' -f2- "$ABORT_FILE")")
  fi
  if (( ${#FAILURES[@]} > 0 )); then VERDICT="FAILED"; fi
}

write_summary() {
  local p k now_epoch
  now_epoch="$(date +%s)"
  {
    printf 'GPU VRAM / compute diagnostic report\n'
    printf 'Started : %s\nFinished: %s (elapsed %s)\n' "$START_LOCAL" "$(date '+%F %T')" "$(fmt_dur $(( now_epoch - START_EPOCH )))"
    printf 'GPU     : index %s, %s, driver %s\n' "$GPU" "$(cat "$RUN_DIR/gpu-model.txt" 2>/dev/null)" "$(smi_value driver_version)"
    printf 'Mode    : %s, test budget %s, bit-fade %s\n' "$MODE" "$(fmt_dur "$DURATION_S")" "$( (( BIT_FADE )) && echo on || echo off )"
    printf 'ECC mode: %s (when ECC is off, only the software tests can catch single-bit errors)\n' "${ECC_MODE:-unknown}"
    printf '\nPhase results:\n'
    for p in patterns burn stress combined bitfade; do
      printf '  %-9s %-8s %s\n' "$p" "${PRES[$p]}" "${PNOTE[$p]:-}"
    done
    if [[ -s "$RUN_DIR/pattern-times.csv" ]]; then
      printf '\nPattern test timings (seconds, last completed run of each test):\n  '
      awk -F, 'NR > 1 && $4 == "completed" { d[$2] = $3 } END { for (i = 0; i <= 8; i++) printf "test%d=%s ", i, ((i in d) ? d[i] : "-"); printf "\n" }' \
        "$RUN_DIR/pattern-times.csv"
    fi
    printf '\nTelemetry (%s samples):\n' "${TS[samples]:-0}"
    printf '  temperature : start %sC, max %sC (abort limit %sC)\n' "${TS[temp_start]:-?}" "${TS[temp_max]:-?}" "${TEMP_LIMIT:-?}"
    printf '  power       : max %s W, average under load %s W\n' "${TS[power_max]:-?}" "${TS[power_avg_load]:-?}"
    printf '  SM clock    : min under load %s MHz, average %s MHz, max %s MHz\n' "${TS[sm_clock_min_load]:-?}" "${TS[sm_clock_avg_load]:-?}" "${TS[sm_clock_max]:-?}"
    printf '  throttling  : %s hardware/thermal samples, %s software power cap samples\n' "${TS[hw_throttle_samples]:-?}" "${TS[sw_power_cap_samples]:-?}"
    printf '  PCIe link   : min under load Gen%s x%s (max Gen%s x%s)\n' "${TS[pcie_gen_min_load]:-?}" "${TS[pcie_width_min_load]:-?}" "${TS[pcie_gen_max]:-?}" "${TS[pcie_width_max]:-?}"
    printf '  VRAM used   : peak %s MiB\n' "${TS[vram_used_max]:-?}"
    printf '\nKernel log: %s Xid/fallen-off-bus line(s) and %s PCIe AER line(s) during the run\n' "${XID_DURING:-0}" "${AER_DURING:-0}"
    if (( ${#FAILURES[@]} > 0 )); then
      printf '\nFailure findings:\n'
      for k in "${FAILURES[@]}"; do printf '  - %s\n' "$k"; done
    fi
    if (( ${#WARNINGS[@]} > 0 )); then
      printf '\nWarnings:\n'
      for k in "${WARNINGS[@]}"; do printf '  - %s\n' "$k"; done
    fi
    if [[ -n "$FATAL_MSG" ]]; then printf '\nScript stopped early: %s\n' "$FATAL_MSG"; fi
    if (( INTERRUPTED )); then printf '\nThe run was interrupted by the user.\n'; fi
    if [[ -e "$ABORT_FILE" ]]; then printf '\nWatchdog abort: %s\n' "$(tr '|' ' ' < "$ABORT_FILE")"; fi
    printf '\nOVERALL: %s\n' "$VERDICT"
    printf 'Files: patterns.log stress.log burn.log combined-*.log bitfade.log telemetry.csv telemetry-summary.txt\n'
    printf '       kernel-since-test.log gpu-errors-during-run.log ecc-before/after.txt nvidia-smi-before/after.txt pci-detail-*.txt\n'
    printf 'An absence of errors is strong evidence but not proof that every physical VRAM cell is good.\n'
  } > "$RUN_DIR/SUMMARY.txt"
}

cleanup() {
  local last_rc="$1" tar_rc=0 final_rc
  trap - EXIT INT TERM
  set +e
  stop_watchdog
  if [[ -n "$KEEP_PID" ]]; then kill "$KEEP_PID" 2>/dev/null; fi
  kill_children
  sleep 1
  if [[ -n "$CHILD_FILE" && -f "$CHILD_FILE" ]]; then
    local p
    while read -r p; do
      if [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; fi
    done < "$CHILD_FILE"
  fi

  "${SUDO[@]}" journalctl -k -b --since "$START_LOCAL" --no-pager > "$RUN_DIR/kernel-since-test.log" 2>&1 \
    || "${SUDO[@]}" dmesg > "$RUN_DIR/kernel-since-test.log" 2>&1
  "${SUDO[@]}" journalctl -k -b --no-pager > "$RUN_DIR/kernel-boot.log" 2>&1 \
    || "${SUDO[@]}" dmesg > "$RUN_DIR/kernel-boot.log" 2>&1
  grep -Ei 'NVRM|Xid|AER|PCIe|fallen off|GPU fault|GPU has fallen' "$RUN_DIR/kernel-since-test.log" \
    > "$RUN_DIR/gpu-errors-during-run.log" 2>/dev/null
  grep -Ei 'NVRM|Xid|AER|PCIe|fallen off|GPU fault|GPU has fallen' "$RUN_DIR/kernel-boot.log" \
    > "$RUN_DIR/gpu-errors-this-boot.log" 2>/dev/null
  XID_DURING="$(grep -Eci "$KERNEL_RE" "$RUN_DIR/kernel-since-test.log" 2>/dev/null)"
  AER_DURING="$(grep -Eci 'AER:|PCIe Bus Error' "$RUN_DIR/kernel-since-test.log" 2>/dev/null)"
  local xid_boot
  xid_boot="$(grep -Eci "$KERNEL_RE" "$RUN_DIR/kernel-boot.log" 2>/dev/null)"
  if [[ "$XID_DURING" =~ ^[0-9]+$ ]] && (( XID_DURING > 0 )); then
    FAILURES+=("$XID_DURING NVIDIA Xid / fallen-off-bus kernel message(s) appeared during the run")
  fi
  if [[ "$xid_boot" =~ ^[0-9]+$ && "$XID_DURING" =~ ^[0-9]+$ ]] && (( xid_boot > XID_DURING )); then
    WARNINGS+=("$(( xid_boot - XID_DURING )) NVIDIA Xid message(s) earlier in this boot (gpu-errors-this-boot.log)")
  fi
  if [[ "$AER_DURING" =~ ^[0-9]+$ ]] && (( AER_DURING > 0 )); then
    WARNINGS+=("$AER_DURING PCIe AER message(s) during the run (possible slot, riser or cable problem)")
  fi

  snapshot after
  ecc_snapshot "$RUN_DIR/ecc-after.txt"
  ecc_compare
  telemetry_stats
  telemetry_findings
  compute_verdict
  write_summary

  if [[ "$VERDICT" != PASSED ]] && command -v nvidia-bug-report.sh >/dev/null 2>&1; then
    info 'Collecting NVIDIA bug report (max 120 s)...'
    "${SUDO[@]}" timeout --signal=TERM 120 \
      nvidia-bug-report.sh --output-file "$RUN_DIR/nvidia-bug-report.log" \
      > "$RUN_DIR/bug-report-command.log" 2>&1
    "${SUDO[@]}" chown "$(id -u):$(id -g)" "$RUN_DIR"/nvidia-bug-report.log* 2>/dev/null
  fi
  if (( PERSIST_CHANGED )); then
    "${SUDO[@]}" nvidia-smi -i "$GPU" -pm 0 > "$RUN_DIR/persistence-restore.log" 2>&1
  fi

  tar -C "$(dirname "$RUN_DIR")" -czf "$ARCHIVE" "$(basename "$RUN_DIR")"
  tar_rc=$?
  printf '\n==== GPU DIAGNOSTICS ====\n'
  cat "$RUN_DIR/SUMMARY.txt"
  if (( tar_rc == 0 )); then
    printf '\nLOG DIRECTORY: %s\nARCHIVE: %s\n' "$RUN_DIR" "$ARCHIVE"
  else
    warn "Could not package archive (tar exit $tar_rc). Individual logs remain in $RUN_DIR"
  fi

  final_rc="$last_rc"
  case "$VERDICT" in
    FAILED*) final_rc=1 ;;
    INCONCLUSIVE*) if (( last_rc < 128 )); then final_rc=3; fi ;;
    *) if (( last_rc == 0 && tar_rc != 0 )); then final_rc="$tar_rc"; fi ;;
  esac
  exit "$final_rc"
}

# ----------------------------------------------------------------------------
# Phases
# ----------------------------------------------------------------------------
run_memtest_test() {
  # run_memtest_test IDX CAP ROUND -> MT_STATE (completed|timeout|failed|aborted)
  local idx="$1" cap="$2" round="$3" tmp="$RUN_DIR/.memtest-test.out" t0 t1 secs rc
  t0="$(date +%s)"
  launch "$tmp" "$cap" "$BIN" --device "$GPU" --noninteractive --verbose 1 \
    --disable_all --enable_test "$idx" --num_passes 1 --num_iterations 1 --exit_on_error
  wait_for "$LAUNCHED_PID"
  rc="$LAST_RC"
  forget_children
  t1="$(date +%s)"
  secs=$(( t1 - t0 ))
  { printf '\n==== round %s, test %s, time cap %ss ====\n' "$round" "$idx" "$cap"; cat "$tmp"; } >> "$RUN_DIR/patterns.log"
  if [[ -e "$ABORT_FILE" ]]; then
    MT_STATE=aborted
  elif grep -Eq "$MEMTEST_ERR_RE" "$tmp" 2>/dev/null; then
    MT_STATE=failed; PNOTE[patterns]="test $idx reported errors in round $round (see patterns.log)"
  elif [[ "$rc" == 0 ]] && grep -q 'Program exits' "$tmp"; then
    MT_STATE=completed
  elif [[ "$rc" == 124 || "$rc" == 137 ]]; then
    MT_STATE=timeout
  else
    MT_STATE=failed; PNOTE[patterns]="test $idx exited with code $rc in round $round (see patterns.log)"
  fi
  printf '%s,%s,%s,%s\n' "$round" "$idx" "$secs" "$MT_STATE" >> "$RUN_DIR/pattern-times.csv"
  info "patterns round $round test $idx: $MT_STATE in ${secs}s"
}

phase_patterns() {
  local budget="$1" end round=0 idx rem cap left
  local -a tests=(0 1 2 3 4 5 6 7 8) missing=()
  local -A done_ok=()
  end=$(( $(date +%s) + budget ))
  : > "$RUN_DIR/patterns.log"
  printf 'round,test,seconds,state\n' > "$RUN_DIR/pattern-times.csv"
  PRES[patterns]=PASS
  while :; do
    round=$(( round + 1 ))
    left=${#tests[@]}
    for idx in "${tests[@]}"; do
      rem=$(( end - $(date +%s) ))
      if (( rem < MIN_SLICE / 3 + 1 )); then break 2; fi
      cap=$(( rem / left ))
      if (( cap < MIN_SLICE )); then cap=$MIN_SLICE; fi
      if (( cap > rem )); then cap=$rem; fi
      left=$(( left - 1 ))
      run_memtest_test "$idx" "$cap" "$round"
      case "$MT_STATE" in
        completed) done_ok[$idx]=$(( ${done_ok[$idx]:-0} + 1 )) ;;
        failed) PRES[patterns]=FAIL; return 0 ;;
        aborted) PRES[patterns]=ABORTED; PNOTE[patterns]="stopped by watchdog"; return 0 ;;
        *) ;;
      esac
    done
  done
  for idx in "${tests[@]}"; do
    if (( ${done_ok[$idx]:-0} < 1 )); then missing+=("$idx"); fi
  done
  if (( ${#missing[@]} == 0 )); then
    PNOTE[patterns]="tests 0-8 each completed at least once over all free VRAM, no mismatches (rounds started: $round)"
  else
    PRES[patterns]=PARTIAL
    PNOTE[patterns]="no mismatches, but no complete run for test(s): ${missing[*]} within the budget"
    add_warning "Pattern coverage incomplete (tests ${missing[*]} never finished); use a longer --duration for full coverage"
  fi
}

phase_burn() {
  local budget="$1" secs=$(( $1 - BURN_MARGIN ))
  if (( secs < 10 )); then secs=10; fi
  burn_launch "$RUN_DIR/burn.log" $(( budget + 120 )) "$secs" "$BURN_MEM_PCT"
  wait_for "$LAUNCHED_PID"
  forget_children
  eval_burn "$RUN_DIR/burn.log" "$LAST_RC"
  PRES[burn]="$EV_STATE"; PNOTE[burn]="$EV_NOTE"
}

phase_stress() {
  local budget="$1"
  launch "$RUN_DIR/stress.log" "$budget" "$BIN" --device "$GPU" --noninteractive --verbose 1 \
    --stress --num_iterations "$STRESS_ITER"
  wait_for "$LAUNCHED_PID"
  forget_children
  eval_stress "$RUN_DIR/stress.log" "$LAST_RC"
  PRES[stress]="$EV_STATE"; PNOTE[stress]="$EV_NOTE"
}

phase_combined() {
  local budget="$1" start end total_mb used0 used i burn_pid mt_pid rem cap_blocks rc_burn rc_mt
  local secs=$(( $1 - BURN_MARGIN )) state_b state_m note_b note_m
  if (( secs < 10 )); then secs=10; fi
  start="$(date +%s)"; end=$(( start + budget ))
  total_mb="$(smi_value memory.total)"; used0="$(smi_value memory.used)"
  [[ "$total_mb" =~ ^[0-9]+$ ]] || total_mb=24000
  [[ "$used0" =~ ^[0-9]+$ ]] || used0=0

  burn_launch "$RUN_DIR/combined-burn.log" $(( budget + 120 )) "$secs" 35
  burn_pid="$LAUNCHED_PID"
  # Wait until gpu-burn has actually taken its share of VRAM so cuda_memtest sees the correct free memory.
  for (( i = 0; i < 60; i++ )); do
    used="$(smi_value memory.used)"
    if [[ "$used" =~ ^[0-9]+$ ]] && (( used >= used0 + total_mb / 5 )); then break; fi
    if ! kill -0 "$burn_pid" 2>/dev/null; then break; fi
    sleep 2
  done
  cap_blocks=$(( total_mb * 45 / 100 ))
  rem=$(( end - $(date +%s) ))
  if (( rem < 10 )); then rem=10; fi
  launch "$RUN_DIR/combined-stress.log" "$rem" "$BIN" --device "$GPU" --noninteractive --verbose 1 \
    --stress --num_iterations "$STRESS_ITER" --max_num_blocks "$cap_blocks"
  mt_pid="$LAUNCHED_PID"

  while kill -0 "$mt_pid" 2>/dev/null; do sleep 2; done
  wait_for "$mt_pid"; rc_mt="$LAST_RC"
  if grep -Eq "$MEMTEST_ERR_RE" "$RUN_DIR/combined-stress.log" 2>/dev/null || [[ -e "$ABORT_FILE" ]]; then
    kill -TERM "$burn_pid" 2>/dev/null || true
  fi
  wait_for "$burn_pid"; rc_burn="$LAST_RC"
  forget_children

  eval_stress "$RUN_DIR/combined-stress.log" "$rc_mt"; state_m="$EV_STATE"; note_m="$EV_NOTE"
  eval_burn "$RUN_DIR/combined-burn.log" "$rc_burn"; state_b="$EV_STATE"; note_b="$EV_NOTE"
  PRES[combined]="$(worst_state "$state_m" "$state_b")"
  PNOTE[combined]="memtest: $note_m; gpu-burn: $note_b"
}

phase_bitfade() {
  launch "$RUN_DIR/bitfade.log" 12600 "$BIN" --device "$GPU" --noninteractive --verbose 1 \
    --disable_all --enable_test 9 --num_passes 1 --exit_on_error
  wait_for "$LAUNCHED_PID"
  forget_children
  if [[ -e "$ABORT_FILE" ]]; then
    PRES[bitfade]=ABORTED; PNOTE[bitfade]="stopped by watchdog"
  elif grep -Eq "$MEMTEST_ERR_RE" "$RUN_DIR/bitfade.log" 2>/dev/null; then
    PRES[bitfade]=FAIL; PNOTE[bitfade]="bits changed during the retention wait (see bitfade.log)"
  elif [[ "$LAST_RC" == 0 ]] && grep -q 'Program exits' "$RUN_DIR/bitfade.log"; then
    PRES[bitfade]=PASS; PNOTE[bitfade]="both 90 minute retention checks passed"
  elif [[ "$LAST_RC" == 124 || "$LAST_RC" == 137 ]]; then
    PRES[bitfade]=PARTIAL; PNOTE[bitfade]="did not finish inside its time limit"
  else
    PRES[bitfade]=FAIL; PNOTE[bitfade]="cuda_memtest exited with code $LAST_RC"
  fi
}

run_phase() {
  local name="$1" budget="$2"
  printf '%s\n' "$name" > "$RUN_DIR/.phase"
  ensure_watchdog
  info "PHASE $name starting, budget $(fmt_dur "$budget")"
  "phase_$name" "$budget"
  info "PHASE $name finished: ${PRES[$name]}${PNOTE[$name]:+ (${PNOTE[$name]})}"
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
while (( $# )); do
  case "$1" in
    --quick) MODE=quick ;;
    --extended) MODE=extended ;;
    --burn-in) MODE=burn-in ;;
    --duration) [[ $# -ge 2 ]] || { echo 'Missing value for --duration' >&2; exit 2; }
      DURATION_S="$(parse_duration "$2")" || { echo "Bad duration: $2 (examples: 90m, 2h, 1h30m)" >&2; exit 2; }
      shift ;;
    --skip) [[ $# -ge 2 ]] || { echo 'Missing value for --skip' >&2; exit 2; }; SKIP_LIST="$2"; shift ;;
    --bit-fade) BIT_FADE_OVERRIDE=1 ;;
    --no-bit-fade) BIT_FADE_OVERRIDE=0 ;;
    --temp-limit) [[ $# -ge 2 ]] || { echo 'Missing value for --temp-limit' >&2; exit 2; }; TEMP_LIMIT="$2"; shift ;;
    --burn-mem) [[ $# -ge 2 ]] || { echo 'Missing value for --burn-mem' >&2; exit 2; }; BURN_MEM_PCT="$2"; shift ;;
    --gpu) [[ $# -ge 2 ]] || { echo 'Missing value for --gpu' >&2; exit 2; }; GPU="$2"; shift ;;
    --out) [[ $# -ge 2 ]] || { echo 'Missing value for --out' >&2; exit 2; }; OUTPUT_BASE="$2"; shift ;;
    --no-install) NO_INSTALL=1 ;;
    --no-inhibit) NO_INHIBIT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ -z "$DURATION_S" ]]; then
  case "$MODE" in
    quick) DURATION_S=1200 ;;
    standard) DURATION_S=7200 ;;
    extended) DURATION_S=21600 ;;
    burn-in) DURATION_S=43200 ;;
  esac
fi
if [[ "$MODE" == burn-in ]]; then BIT_FADE=1; fi
if [[ -n "$BIT_FADE_OVERRIDE" ]]; then BIT_FADE="$BIT_FADE_OVERRIDE"; fi
[[ "$GPU" =~ ^[0-9]+$ ]] || { echo "GPU must be a numeric index" >&2; exit 2; }
[[ "$BURN_MEM_PCT" =~ ^[0-9]+$ ]] && (( BURN_MEM_PCT >= 10 && BURN_MEM_PCT <= 95 )) \
  || { echo "--burn-mem must be 10-95" >&2; exit 2; }
[[ -z "$TEMP_LIMIT" || "$TEMP_LIMIT" =~ ^[0-9]+$ ]] || { echo "--temp-limit must be a number" >&2; exit 2; }
[[ -n "$OUTPUT_BASE" ]] || { echo "Output directory must not be empty" >&2; exit 2; }
(( DURATION_S >= 60 )) || { echo "Duration must be at least 60 seconds" >&2; exit 2; }
if [[ -n "$SKIP_LIST" ]]; then
  IFS=',' read -r -a _skips <<< "$SKIP_LIST"
  for _s in "${_skips[@]}"; do
    case "$_s" in patterns|burn|stress|combined) ;; *) echo "Unknown phase in --skip: $_s" >&2; exit 2 ;; esac
  done
fi
for _c in nvidia-smi timeout tar awk; do
  command -v "$_c" >/dev/null 2>&1 || { echo "$_c is required but missing." >&2; exit 1; }
done

# Block idle and sleep for the whole run (re-executes this script once under systemd-inhibit).
if (( NO_INHIBIT == 0 )) && [[ -z "${GPU_DIAG_INHIBITED:-}" ]] && command -v systemd-inhibit >/dev/null 2>&1; then
  if systemd-inhibit --what=sleep:idle --who=gpu-vram-diag --why=test --mode=block true >/dev/null 2>&1; then
    export GPU_DIAG_INHIBITED=1
    exec systemd-inhibit --what=sleep:idle:handle-lid-switch --who=gpu-vram-diag \
      --why="GPU stress test running" --mode=block bash "$0" "$@"
  fi
fi

# Make CUDA device numbering match nvidia-smi for every tool.
export CUDA_DEVICE_ORDER=PCI_BUS_ID

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || { echo "sudo required (or run as root)." >&2; exit 1; }
  SUDO=(sudo)
  SUDO_N=(sudo -n)
fi

mkdir -p -- "$OUTPUT_BASE"
RUN_DIR="$(cd -- "$OUTPUT_BASE" && pwd)/gpu-$(date '+%Y%m%d-%H%M%S')-$$"
mkdir -p -- "$RUN_DIR"
ARCHIVE="${RUN_DIR}.tar.gz"
RUN_LOG="$RUN_DIR/run.log"
ABORT_FILE="$RUN_DIR/ABORT"
CHILD_FILE="$RUN_DIR/.children"
: > "$CHILD_FILE"
START_LOCAL="$(date '+%F %T')"
START_EPOCH="$(date +%s)"

trap 'cleanup "$?"' EXIT
trap 'INTERRUPTED=1; exit 130' INT
trap 'INTERRUPTED=1; exit 143' TERM

if [[ -z "${TMUX:-}${STY:-}" && -n "${SSH_CONNECTION:-}" ]]; then
  warn 'Running over SSH outside tmux or screen: a dropped connection will stop the test. Consider tmux.'
fi

# ----------------------------------------------------------------------------
# Preflight
# ----------------------------------------------------------------------------
info "Output: $RUN_DIR"
info 'Validating GPU and collecting baseline'
if (( EUID != 0 )); then
  sudo -v || fatal 'Could not acquire sudo access.'
  start_sudo_keepalive
fi
nvidia-smi -i "$GPU" --query-gpu=name --format=csv,noheader > "$RUN_DIR/gpu-model.txt" 2>&1 || fatal "GPU index $GPU is not available"
if ! grep -qi 'Quadro M6000' "$RUN_DIR/gpu-model.txt"; then
  fatal "This script targets Quadro M6000 (sm_52); GPU $GPU is $(cat "$RUN_DIR/gpu-model.txt")."
fi
snapshot before
ecc_snapshot "$RUN_DIR/ecc-before.txt"
{
  date --iso-8601=seconds
  uname -a
  cat /etc/os-release
} > "$RUN_DIR/system.txt" 2>&1 || true
(command -v lspci >/dev/null && lspci -nnk) > "$RUN_DIR/pci.txt" 2>&1 || true
nvidia-smi -i "$GPU" --query-gpu=timestamp,name,driver_version,vbios_version,memory.total,memory.used,temperature.gpu,power.draw,power.limit,persistence_mode \
  --format=csv > "$RUN_DIR/baseline.csv" 2>&1 || true

# Thermal abort limit: below the card's own slowdown temperature if it reports one.
SLOWDOWN_T="$(nvidia-smi -i "$GPU" -q -d TEMPERATURE 2>/dev/null | awk -F: '/Slowdown Temp/ { gsub(/[^0-9]/, "", $2); print $2; exit }' || true)"
if [[ -z "$TEMP_LIMIT" ]]; then
  TEMP_LIMIT=90
  if [[ "$SLOWDOWN_T" =~ ^[0-9]+$ ]] && (( SLOWDOWN_T - 2 < TEMP_LIMIT )); then TEMP_LIMIT=$(( SLOWDOWN_T - 2 )); fi
fi
info "Thermal abort limit: ${TEMP_LIMIT}C (card slowdown temp: ${SLOWDOWN_T:-unknown}C)"

# Other users of the GPU would skew results and reduce the VRAM that can be tested.
apps="$(nvidia-smi -i "$GPU" --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || true)"
if [[ -n "${apps//[[:space:]]/}" ]]; then
  add_warning "Other compute processes are using the GPU, which reduces testable VRAM: $(printf '%s' "$apps" | tr '\n' ';')"
fi
used0="$(smi_value memory.used)"; total0="$(smi_value memory.total)"
if [[ "$used0" =~ ^[0-9]+$ && "$total0" =~ ^[0-9]+$ ]]; then
  info "VRAM before test: ${used0} MiB used of ${total0} MiB"
  if (( used0 * 100 > total0 * 5 )); then
    add_warning "${used0} MiB of VRAM is already in use (desktop or other processes); that part cannot be tested"
  fi
fi

PERSIST_ORIGINAL="$(nvidia-smi -i "$GPU" --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr -d '\r' | head -1 || true)"
if [[ "${PERSIST_ORIGINAL,,}" == disabled ]]; then
  if "${SUDO[@]}" nvidia-smi -i "$GPU" -pm 1 > "$RUN_DIR/persistence-enable.log" 2>&1; then
    PERSIST_CHANGED=1
  else
    warn 'Could not enable persistence mode.'
  fi
fi

DCGM_NOTE=""
if command -v dcgmi >/dev/null 2>&1; then
  info 'Running optional DCGM software preflight (informational, not part of the verdict)'
  if "${SUDO[@]}" dcgmi diag --run 1 -e "gpu:${GPU}" > "$RUN_DIR/dcgm-level1.log" 2>&1; then DCGM_NOTE=PASS; else DCGM_NOTE=FAILED/UNAVAILABLE; fi
  info "DCGM level 1: $DCGM_NOTE"
fi

# ----------------------------------------------------------------------------
# Build tools
# ----------------------------------------------------------------------------
# CUDA 13 cannot compile code for Maxwell. Look for a CUDA 12 compiler.
find_nvcc12() {
  local candidate version c
  for c in /usr/bin/nvcc /usr/local/cuda-12*/bin/nvcc "$(command -v nvcc 2>/dev/null || true)"; do
    candidate="$c"
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    version="$("$candidate" --version 2>/dev/null | sed -nE 's/.*release ([0-9]+)\..*/\1/p' | tail -1)"
    if [[ "$version" == 12 ]]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

DEPS=()
for binary in git cmake make gcc-12 g++-12; do
  command -v "$binary" >/dev/null 2>&1 || DEPS+=("$binary")
done
if (( ${#DEPS[@]} )); then
  (( NO_INSTALL == 0 )) || fatal "Missing build tools: ${DEPS[*]}; rerun without --no-install."
  info 'Installing Ubuntu build dependencies (not GPU drivers)'
  "${SUDO[@]}" apt-get update > "$RUN_DIR/apt-update.log" 2>&1 || fatal 'apt-get update failed (see apt-update.log)'
  "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git cmake build-essential gcc-12 g++-12 pciutils \
    > "$RUN_DIR/apt-build.log" 2>&1 || fatal 'Build dependencies failed (see apt-build.log)'
fi

NVCC="$(find_nvcc12 || true)"
if [[ -z "$NVCC" ]]; then
  (( NO_INSTALL == 0 )) || fatal 'CUDA 12.x nvcc missing; rerun without --no-install.'
  info 'Installing CUDA 12.x compiler from Ubuntu nvidia-cuda-toolkit (may require multiverse)'
  "${SUDO[@]}" apt-get update > "$RUN_DIR/apt-cuda-update.log" 2>&1 || fatal 'apt-get update failed'
  "${SUDO[@]}" apt-get -s install --no-install-recommends nvidia-cuda-toolkit \
    > "$RUN_DIR/apt-cuda-plan.log" 2>&1 || fatal 'Cannot resolve CUDA toolkit dependencies (see apt-cuda-plan.log)'
  if grep -Eq '^Remv (nvidia|libnvidia)|^Inst nvidia-driver' "$RUN_DIR/apt-cuda-plan.log"; then
    fatal 'CUDA toolkit install would change/remove NVIDIA driver components; refusing. See apt-cuda-plan.log'
  fi
  "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nvidia-cuda-toolkit \
    > "$RUN_DIR/apt-cuda.log" 2>&1 || fatal 'CUDA toolkit installation failed. See apt-cuda.log; enable Ubuntu multiverse if needed.'
  NVCC="$(find_nvcc12 || true)"
  [[ -n "$NVCC" ]] || fatal 'CUDA 12.x compiler not found after installation; see apt-cuda.log'
fi
"$NVCC" --version > "$RUN_DIR/cuda-compiler.txt" 2>&1
CUDA_ROOT="$(dirname "$(dirname "$NVCC")")"
info "Using CUDA compiler: $NVCC (root $CUDA_ROOT)"

mkdir -p "$CACHE_DIR"
if [[ ! -d "$MEMTEST_SRC/.git" ]]; then
  info 'Downloading upstream cuda_memtest source'
  git clone --depth 1 --branch dev "$MEMTEST_URL" "$MEMTEST_SRC" \
    > "$RUN_DIR/git-clone-memtest.log" 2>&1 || fatal 'cuda_memtest clone failed (see git-clone-memtest.log)'
fi
git -C "$MEMTEST_SRC" rev-parse HEAD > "$RUN_DIR/cuda-memtest-revision.txt"
info 'Compiling cuda_memtest for Maxwell sm_52'
cmake -S "$MEMTEST_SRC" -B "$MEMTEST_BUILD" \
  -DCMAKE_CUDA_ARCHITECTURES=52 \
  -DCMAKE_CUDA_COMPILER="$NVCC" \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-12 \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 \
  -DCMAKE_C_COMPILER=/usr/bin/gcc-12 \
  > "$RUN_DIR/cmake-configure.log" 2>&1 || fatal 'CMake configure failed (see cmake-configure.log)'
cmake --build "$MEMTEST_BUILD" --parallel 2 \
  > "$RUN_DIR/cmake-build.log" 2>&1 || fatal 'cuda_memtest build failed (see cmake-build.log)'
BIN="$MEMTEST_BUILD/cuda_memtest"
[[ -x "$BIN" ]] || fatal "Compiled binary not found: $BIN"
"$BIN" --list_tests > "$RUN_DIR/tests-available.txt" 2>&1 || true

# gpu-burn is optional: if it cannot be built, the burn and combined phases are skipped with a warning.
build_gpu_burn() {
  if [[ ! -d "$BURN_SRC/.git" ]]; then
    git clone --depth 1 "$BURN_URL" "$BURN_SRC" > "$RUN_DIR/git-clone-burn.log" 2>&1 || return 1
  fi
  git -C "$BURN_SRC" rev-parse HEAD > "$RUN_DIR/gpu-burn-revision.txt" 2>&1 || true
  # The driver package may not ship the libcuda.so development symlink; provide one for linking only.
  local real
  real="$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1 / { print $NF; exit }')"
  mkdir -p "$BURN_STUB"
  if [[ -n "$real" ]]; then ln -sf "$real" "$BURN_STUB/libcuda.so"; fi
  make -C "$BURN_SRC" clean > /dev/null 2>&1 || true
  make -C "$BURN_SRC" -j2 COMPUTE=52 CUDAPATH="$CUDA_ROOT" \
    NVCCFLAGS="-ccbin /usr/bin/g++-12" LDFLAGS="-L$BURN_STUB" \
    > "$RUN_DIR/gpu-burn-build.log" 2>&1 || return 1
  [[ -x "$BURN_SRC/gpu_burn" && -f "$BURN_SRC/compare.fatbin" ]]
}
info 'Compiling gpu-burn for Maxwell compute_52'
if build_gpu_burn; then
  BURN_OK=1
else
  add_warning 'gpu-burn could not be built (see gpu-burn-build.log); the burn and combined phases are skipped'
fi

# ----------------------------------------------------------------------------
# Smoke tests: prove the tools work before committing hours to the run
# ----------------------------------------------------------------------------
info 'Smoke test: cuda_memtest on a small slice of VRAM'
if ! timeout 300 "$BIN" --device "$GPU" --noninteractive --verbose 1 --stress --num_passes 1 --num_iterations 5 --max_num_blocks 512 \
  > "$RUN_DIR/smoke-memtest.log" 2>&1 || grep -Eq "$MEMTEST_ERR_RE" "$RUN_DIR/smoke-memtest.log"; then
  fatal 'cuda_memtest smoke test failed (a build or driver problem, or a real GPU fault); see smoke-memtest.log'
fi
if (( BURN_OK )); then
  info 'Smoke test: gpu-burn for 10 seconds'
  if ! (cd "$BURN_SRC" && timeout 120 ./gpu_burn -m 10% -i "$GPU" 10) > "$RUN_DIR/smoke-burn.log" 2>&1 \
    || ! tr '\r' '\n' < "$RUN_DIR/smoke-burn.log" | grep -Eq 'GPU [0-9]+: OK'; then
    BURN_OK=0
    add_warning 'gpu-burn smoke test failed (see smoke-burn.log); the burn and combined phases are skipped'
  fi
fi

# ----------------------------------------------------------------------------
# Plan the phases and run
# ----------------------------------------------------------------------------
declare -A WEIGHT=([patterns]=35 [burn]=25 [stress]=25 [combined]=15)
ENABLED=()
for p in patterns burn stress combined; do
  if [[ ",$SKIP_LIST," == *",$p,"* ]]; then PRES[$p]=SKIPPED; PNOTE[$p]="skipped by --skip"; continue; fi
  if [[ ( "$p" == burn || "$p" == combined ) && "$BURN_OK" != 1 ]]; then PRES[$p]=SKIPPED; PNOTE[$p]="gpu-burn unavailable"; continue; fi
  ENABLED+=("$p")
done
(( ${#ENABLED[@]} > 0 )) || fatal 'No phases left to run.'
if (( BIT_FADE == 0 )); then PRES[bitfade]=SKIPPED; PNOTE[bitfade]="not requested"; fi

wsum=0
for p in "${ENABLED[@]}"; do wsum=$(( wsum + WEIGHT[$p] )); done
declare -A BUDGET=()
assigned=0
for i in "${!ENABLED[@]}"; do
  p="${ENABLED[$i]}"
  if (( i == ${#ENABLED[@]} - 1 )); then BUDGET[$p]=$(( DURATION_S - assigned )); else BUDGET[$p]=$(( DURATION_S * WEIGHT[$p] / wsum )); fi
  assigned=$(( assigned + BUDGET[$p] ))
done

total_eta=$DURATION_S
if (( BIT_FADE )); then total_eta=$(( total_eta + 10800 )); fi
info "Plan: ${ENABLED[*]} over $(fmt_dur "$DURATION_S")$( (( BIT_FADE )) && echo ' plus bit-fade (about 3h)' ); expected finish around $(date -d "@$(( $(date +%s) + total_eta ))" '+%F %T')"

KERNEL_BASE="$(count_kernel_events "$KERNEL_RE")"
[[ "$KERNEL_BASE" =~ ^[0-9]+$ ]] || KERNEL_BASE=0
probe_telemetry_fields
info "Telemetry fields: ${TEL_FIELDS[*]}"
info "Starting watchdog (sample every ${SAMPLE_INTERVAL}s: temperature, GPU responsiveness, Xid, throttling, PCIe)"
start_watchdog
sleep "$SAMPLE_INTERVAL"

for p in "${ENABLED[@]}"; do
  if [[ -e "$ABORT_FILE" ]]; then break; fi
  if [[ "${PRES[patterns]}" == FAIL || "${PRES[burn]}" == FAIL || "${PRES[stress]}" == FAIL || "${PRES[combined]}" == FAIL ]]; then
    info 'Stopping after a failure; remaining phases not run.'
    break
  fi
  if (( BUDGET[$p] < MIN_PHASE )); then
    PRES[$p]=SKIPPED; PNOTE[$p]="budget $(fmt_dur "${BUDGET[$p]}") too small; use a longer --duration"
    continue
  fi
  run_phase "$p" "${BUDGET[$p]}"
done

if (( BIT_FADE )) && [[ ! -e "$ABORT_FILE" ]] \
  && [[ "${PRES[patterns]}" != FAIL && "${PRES[burn]}" != FAIL && "${PRES[stress]}" != FAIL && "${PRES[combined]}" != FAIL ]]; then
  run_phase bitfade 10800
fi

printf 'done\n' > "$RUN_DIR/.phase"
exit 0
