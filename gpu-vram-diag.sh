#!/usr/bin/env bash
# NVIDIA Quadro M6000 (Maxwell sm_52) VRAM integrity + driver diagnostics.
# Ubuntu 24.04, NVIDIA driver already installed.
# Repository: https://github.com/ComputationalRadiationPhysics/cuda_memtest
set -Eeuo pipefail
umask 077

GPU=0
MODE=standard
NO_INSTALL=0
OUTPUT_BASE="${HOME}/gpu-vram-logs"
REPO_URL="https://github.com/ComputationalRadiationPhysics/cuda_memtest.git"
SRC_DIR="${HOME}/.cache/gpu-vram-diag/cuda_memtest"
BUILD_DIR="${SRC_DIR}/build-sm52"
MON_PID=""
PERSIST_CHANGED=0
SUDO=()
RUN_DIR=""
ARCHIVE=""
START_LOCAL=""
PATTERN_RESULT="NOT RUN"
STRESS_RESULT="NOT RUN"
DCGM_RESULT="NOT RUN"

usage() {
  cat <<'EOF'
Usage: bash gpu-vram-diag.sh [--quick|--extended] [--gpu 0] [--no-install] [--out DIR]

  Default    1 pass of VRAM patterns (tests 0-8) + 1 stress pass (1000 iterations)
  --quick    Stress only, 100 iterations, 1 pass
  --extended 3 passes of VRAM patterns + 3 stress passes (1000 iterations each)
  --gpu N    Select GPU index (default: 0)
  --no-install  Do not install Ubuntu build dependencies or CUDA Toolkit
  --out DIR  Base directory for saved logs (default: ~/gpu-vram-logs)
  -h, --help Show help

Runs locally, using sudo only for required system operations. Stores a timestamped
log directory and a .tar.gz archive in the output directory. Uses CUDA Toolkit 12.x
and compiles cuda_memtest for NVIDIA Maxwell sm_52. Does not install/change drivers.
EOF
}

while (( $# )); do
  case "$1" in
    --quick) MODE=quick ;;
    --extended) MODE=extended ;;
    --gpu) [[ $# -ge 2 ]] || { echo 'Missing value for --gpu' >&2; exit 2; }; GPU="$2"; shift ;;
    --out) [[ $# -ge 2 ]] || { echo 'Missing value for --out' >&2; exit 2; }; OUTPUT_BASE="$2"; shift ;;
    --no-install) NO_INSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ "$GPU" =~ ^[0-9]+$ ]] || { echo "GPU must be a numeric index" >&2; exit 2; }
[[ -n "$OUTPUT_BASE" ]] || { echo "Output directory must not be empty" >&2; exit 2; }
command -v nvidia-smi >/dev/null 2>&1 || { echo "nvidia-smi missing; install/fix the NVIDIA driver first." >&2; exit 1; }
command -v git >/dev/null 2>&1 || true

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || { echo "sudo required (or run as root)." >&2; exit 1; }
  SUDO=(sudo)
fi

info() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fatal() { warn "$*"; exit 1; }

mkdir -p -- "$OUTPUT_BASE"
RUN_DIR="$(cd -- "$OUTPUT_BASE" && pwd)/gpu-$(date '+%Y%m%d-%H%M%S')-$$"
mkdir -p -- "$RUN_DIR"
ARCHIVE="${RUN_DIR}.tar.gz"
START_LOCAL="$(date '+%F %T')"

snapshot() {
  local stage="$1"
  nvidia-smi -q -i "$GPU" > "$RUN_DIR/nvidia-smi-${stage}.txt" 2>&1 || true
  nvidia-smi -q -i "$GPU" -d ECC > "$RUN_DIR/ecc-${stage}.txt" 2>&1 || true
  nvidia-smi -L > "$RUN_DIR/gpu-list-${stage}.txt" 2>&1 || true
}

cleanup() {
  local last_rc="$1"
  trap - EXIT INT TERM
  set +e
  if [[ -n "$MON_PID" ]]; then
    kill "$MON_PID" 2>/dev/null
    wait "$MON_PID" 2>/dev/null
  fi

  # Gather both run-specific and full-boot kernel logs, including previous Xids.
  "${SUDO[@]}" journalctl -k -b --since "$START_LOCAL" --no-pager > "$RUN_DIR/kernel-since-test.log" 2>&1
  "${SUDO[@]}" journalctl -k -b --no-pager > "$RUN_DIR/kernel-boot.log" 2>&1
  grep -Ei 'NVRM|Xid|AER|PCIe|fallen off|GPU fault|GPU has fallen' \
    "$RUN_DIR/kernel-since-test.log" > "$RUN_DIR/gpu-errors-during-run.log" 2>/dev/null || true
  grep -Ei 'NVRM|Xid|AER|PCIe|fallen off|GPU fault|GPU has fallen' \
    "$RUN_DIR/kernel-boot.log" > "$RUN_DIR/gpu-errors-this-boot.log" 2>/dev/null || true

  snapshot after
  if command -v nvidia-bug-report.sh >/dev/null 2>&1; then
    info 'Collecting NVIDIA bug report (max 120 s)...'
    "${SUDO[@]}" timeout --signal=TERM 120 \
      nvidia-bug-report.sh --output-file "$RUN_DIR/nvidia-bug-report.log" \
      > "$RUN_DIR/bug-report-command.log" 2>&1 || true
    # Bug report may be root-owned; make the archive/user files readable.
    "${SUDO[@]}" chown "$(id -u):$(id -g)" "$RUN_DIR"/nvidia-bug-report.log* 2>/dev/null || true
  fi

  if (( PERSIST_CHANGED )); then
    "${SUDO[@]}" nvidia-smi -i "$GPU" -pm 0 \
      > "$RUN_DIR/persistence-restore.log" 2>&1 || true
  fi

  local verdict='INCONCLUSIVE'
  if [[ "$PATTERN_RESULT" == 'PASS' && "$STRESS_RESULT" == 'PASS' ]] || \
     [[ "$MODE" == quick && "$STRESS_RESULT" == 'PASS' ]]; then
    verdict='NO ERRORS DETECTED IN COMPLETED TESTS'
  fi
  if [[ "$PATTERN_RESULT" == 'FAIL' || "$STRESS_RESULT" == 'FAIL' ]]; then
    verdict='VRAM TEST FAILURE OR RUNTIME ERROR'
  fi
  if grep -Eiq 'NVRM: Xid|Xid \([0-9]+\)' "$RUN_DIR/kernel-since-test.log" 2>/dev/null; then
    verdict="$verdict; NVIDIA Xid EVENT(S) DURING RUN"
  fi
  {
    printf 'GPU VRAM diagnostic report\n'
    printf 'Started: %s\nFinished: %s\nGPU index: %s\nMode: %s\n' \
      "$START_LOCAL" "$(date '+%F %T')" "$GPU" "$MODE"
    printf 'VRAM pattern tests: %s\nVRAM stress test: %s\nDCGM software check: %s\n' \
      "$PATTERN_RESULT" "$STRESS_RESULT" "$DCGM_RESULT"
    printf 'Overall: %s\nScript exit code: %s\n' "$verdict" "$last_rc"
    printf 'See patterns.log, stress.log, telemetry.csv, kernel-since-test.log, gpu-errors-during-run.log, and nvidia-bug-report.log.gz\n'
    printf 'An absence of errors is not proof that every physical VRAM cell is good.\n'
  } > "$RUN_DIR/SUMMARY.txt"

  tar -C "$(dirname "$RUN_DIR")" -czf "$ARCHIVE" "$(basename "$RUN_DIR")"
  local tar_rc=$?
  printf '\n==== GPU VRAM DIAGNOSTICS ====\n'
  cat "$RUN_DIR/SUMMARY.txt"
  if (( tar_rc == 0 )); then
    printf '\nLOG DIRECTORY: %s\nARCHIVE: %s\n' "$RUN_DIR" "$ARCHIVE"
  else
    warn "Could not package archive (tar exit $tar_rc). Individual logs remain in $RUN_DIR"
  fi
  if (( last_rc == 0 && tar_rc != 0 )); then last_rc="$tar_rc"; fi
  # Failed tests must return nonzero, regardless of whether tar succeeded.
  if [[ "$PATTERN_RESULT" == FAIL || "$STRESS_RESULT" == FAIL ]]; then last_rc=1; fi
  exit "$last_rc"
}
trap 'cleanup "$?"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

info "Output: $RUN_DIR"
info 'Validating GPU and collecting baseline'
if (( EUID != 0 )); then
  sudo -v || fatal 'Could not acquire sudo access.'
fi
nvidia-smi -i "$GPU" --query-gpu=name --format=csv,noheader > "$RUN_DIR/gpu-model.txt" 2>&1 || fatal "GPU index $GPU is not available"
if ! grep -qi 'Quadro M6000' "$RUN_DIR/gpu-model.txt"; then
  fatal "This script targets Quadro M6000 (sm_52); GPU $GPU is $(cat "$RUN_DIR/gpu-model.txt")."
fi
snapshot before
{
  date --iso-8601=seconds
  uname -a
  cat /etc/os-release
} > "$RUN_DIR/system.txt" 2>&1 || true
(command -v lspci >/dev/null && lspci -nnk) > "$RUN_DIR/pci.txt" 2>&1 || true
nvidia-smi -i "$GPU" --query-gpu=timestamp,name,driver_version,memory.total,memory.used,temperature.gpu,power.draw,persistence_mode \
  --format=csv > "$RUN_DIR/baseline.csv" 2>&1 || true

PERSIST_ORIGINAL="$(nvidia-smi -i "$GPU" --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr -d '\r' | head -1)"
if [[ "${PERSIST_ORIGINAL,,}" == disabled ]]; then
  if "${SUDO[@]}" nvidia-smi -i "$GPU" -pm 1 > "$RUN_DIR/persistence-enable.log" 2>&1; then
    PERSIST_CHANGED=1
  else
    warn 'Could not enable persistence mode; DCGM may fail its software check.'
  fi
fi

if command -v dcgmi >/dev/null 2>&1; then
  info 'Running optional DCGM software preflight'
  if "${SUDO[@]}" dcgmi diag --run 1 -e "gpu:${GPU}" > "$RUN_DIR/dcgm-level1.log" 2>&1; then
    DCGM_RESULT='PASS'
  else
    DCGM_RESULT='FAILED/UNAVAILABLE (see dcgm-level1.log)'
  fi
fi

# CUDA 13 cannot compile code for Maxwell. Look for a CUDA 12 compiler.
find_nvcc12() {
  local candidate version
  for candidate in /usr/bin/nvcc /usr/local/cuda-12*/bin/nvcc "$(command -v nvcc 2>/dev/null || true)"; do
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
info "Using CUDA compiler: $NVCC"

mkdir -p "$(dirname "$SRC_DIR")"
if [[ ! -d "$SRC_DIR/.git" ]]; then
  info 'Downloading upstream cuda_memtest source'
  git clone --depth 1 --branch dev "$REPO_URL" "$SRC_DIR" \
    > "$RUN_DIR/git-clone.log" 2>&1 || fatal 'cuda_memtest clone failed (see git-clone.log)'
fi
git -C "$SRC_DIR" rev-parse HEAD > "$RUN_DIR/cuda-memtest-revision.txt"
info 'Compiling cuda_memtest for Maxwell sm_52'
cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_CUDA_ARCHITECTURES=52 \
  -DCMAKE_CUDA_COMPILER="$NVCC" \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-12 \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 \
  -DCMAKE_C_COMPILER=/usr/bin/gcc-12 \
  > "$RUN_DIR/cmake-configure.log" 2>&1 || fatal 'CMake configure failed (see cmake-configure.log)'
cmake --build "$BUILD_DIR" --parallel 2 \
  > "$RUN_DIR/cmake-build.log" 2>&1 || fatal 'cuda_memtest build failed (see cmake-build.log)'
BIN="$BUILD_DIR/cuda_memtest"
[[ -x "$BIN" ]] || fatal "Compiled binary not found: $BIN"
"$BIN" --list_tests > "$RUN_DIR/tests-available.txt" 2>&1 || true

# Start independent NVML telemetry recording. A GPU reset may interrupt this stream.
info 'Starting GPU telemetry collection (2-second interval)'
nvidia-smi -i "$GPU" \
  --query-gpu=timestamp,temperature.gpu,power.draw,utilization.gpu,utilization.memory,memory.used,memory.free \
  --format=csv --loop=2 > "$RUN_DIR/telemetry.csv" 2> "$RUN_DIR/telemetry-errors.log" &
MON_PID="$!"

run_test() {
  local output="$1"; shift
  local rc=0
  "$BIN" --device "$GPU" --noninteractive --verbose 1 "$@" > "$RUN_DIR/$output" 2>&1 || rc=$?
  cat "$RUN_DIR/$output"
  if (( rc != 0 )) || grep -Eiq 'ERROR:|[1-9][0-9]* errors found|mismatch|memory corruption' "$RUN_DIR/$output"; then
    return 1
  fi
  return 0
}

if [[ "$MODE" != quick ]]; then
  passes=1
  [[ "$MODE" == extended ]] && passes=3
  info "Running memory-pattern tests (passes: $passes)"
  if run_test patterns.log --num_passes "$passes" --exit_on_error; then
    PATTERN_RESULT='PASS'
  else
    PATTERN_RESULT='FAIL'
    warn 'Pattern test reported failure; skipping stress test for safety.'
  fi
fi

if [[ "$PATTERN_RESULT" != FAIL ]]; then
  passes=1
  iterations=1000
  if [[ "$MODE" == quick ]]; then iterations=100; fi
  if [[ "$MODE" == extended ]]; then passes=3; fi
  info "Running memory stress test ($passes pass(es), $iterations iterations per pass)"
  if run_test stress.log --stress --num_passes "$passes" --num_iterations "$iterations"; then
    STRESS_RESULT='PASS'
  else
    STRESS_RESULT='FAIL'
  fi
fi

if [[ "$PATTERN_RESULT" == FAIL || "$STRESS_RESULT" == FAIL ]]; then
  exit 1
fi
exit 0
