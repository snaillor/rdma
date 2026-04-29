#!/bin/bash
# run_sim.sh - Compile and run rdma_core simulation
# Usage: ./run_sim.sh [vcd|gui]

set -e

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="$PROJ_DIR/sim"
HDL_DIR="$PROJ_DIR/hdl"
WORK_DIR="/tmp/rdma_sim"

# Create work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "=== Collecting RTL source files ==="
find "$HDL_DIR" -name "*.v" ! -name "xpm_stubs.v" ! -name "xpm_stubs_logic.v" | sort > "$WORK_DIR/src_files.f"
echo "Found $(wc -l < "$WORK_DIR/src_files.f") source files"

echo "=== Compiling with iverilog (using xpm_stubs_logic.v) ==="
iverilog -g2005 \
  -DSIMULATION \
  -I "$HDL_DIR/common" \
  -f "$WORK_DIR/src_files.f" \
  "$HDL_DIR/common/xpm_stubs_logic.v" \
  "$SIM_DIR/axi_bfm.v" \
  "$SIM_DIR/rocev2_pkt_lib.v" \
  "$SIM_DIR/tb.v" \
  -o "$WORK_DIR/sim.vvp" \
  2>&1 | tee "$WORK_DIR/compile.log"

# Count errors and warnings
ERRORS=$(grep -c "error:" "$WORK_DIR/compile.log" 2>/dev/null || true)
WARNINGS=$(grep -c "warning:" "$WORK_DIR/compile.log" 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}
echo ""
echo "=== Compile result: $ERRORS errors, $WARNINGS warnings ==="

if [ "$ERRORS" -gt 0 ]; then
  echo "COMPILATION FAILED - check $WORK_DIR/compile.log"
  exit 1
fi

echo ""
echo "=== Running simulation ==="
if [ "$1" = "vcd" ]; then
  vvp "$WORK_DIR/sim.vvp" -lxt2 -M /usr/lib/ivl -M$(dirname $(which iverilog))/../lib/ivl \
    2>&1 | tee "$WORK_DIR/sim.log"
  echo ""
  echo "VCD dump: $WORK_DIR/sim.vcd"
elif [ "$1" = "gui" ]; then
  vvp "$WORK_DIR/sim.vvp" -fst \
    2>&1 | tee "$WORK_DIR/sim.log"
else
  vvp "$WORK_DIR/sim.vvp" 2>&1 | tee "$WORK_DIR/sim.log"
fi

echo ""
echo "=== Simulation complete ==="
echo "Log: $WORK_DIR/sim.log"

# Check results
if grep -q "ALL TESTS PASSED" "$WORK_DIR/sim.log" 2>/dev/null; then
  echo "RESULT: ALL TESTS PASSED"
  exit 0
elif grep -q "SOME TESTS FAILED" "$WORK_DIR/sim.log" 2>/dev/null; then
  echo "RESULT: SOME TESTS FAILED"
  exit 1
elif grep -q "TIMEOUT" "$WORK_DIR/sim.log" 2>/dev/null; then
  echo "RESULT: SIMULATION TIMED OUT"
  exit 1
else
  echo "RESULT: UNKNOWN - check log"
  exit 1
fi
