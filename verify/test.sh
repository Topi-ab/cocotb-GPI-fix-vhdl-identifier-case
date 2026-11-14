#!/usr/bin/env bash
# Run the case tests of the fix with one cocotb tree and one simulator.
#
#   verify/test.sh fix|upstream nvc|ghdl|icarus|verilator [test ...]
#
# The tests are always the ones in cocotb-fix/tests/test_cases. With tree=upstream they run
# against stock cocotb, which shows the behaviour before the fix. Without a test list:
#   nvc, ghdl:          test_vhdl_handle_identity test_discovery test_vhdl_access
#   icarus, verilator:  test_verilog_name_case test_discovery
# Results, logs and build files go to work/results/<tree>/<sim>/<test>/.
# Exit status 0 if every test passed, 1 otherwise.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
TREE=${1:?usage: verify/test.sh fix|upstream <sim> [test ...]}
SIM=${2:?usage: verify/test.sh fix|upstream <sim> [test ...]}
shift 2
tree_dir "$TREE" >/dev/null
LANG_=$(sim_lang "$SIM")
if [ $# -gt 0 ]; then
    tests=("$@")
elif [ "$LANG_" = vhdl ]; then
    tests=(test_vhdl_handle_identity test_discovery test_vhdl_access)
else
    tests=(test_verilog_name_case test_discovery)
fi
activate "$TREE"
sim_env "$SIM"

status=0
for t in "${tests[@]}"; do
    out=$WORK/results/$TREE/$SIM/$t
    rm -rf "$out"
    mkdir -p "$out"
    timeout 900 make -C "$TESTS/$t" SIM="$SIM" TOPLEVEL_LANG="$LANG_" \
        SIM_BUILD="$out/sim_build" COCOTB_RESULTS_FILE="$out/results.xml" \
        >"$out/log" 2>&1
    rc=$?
    # GHDL writes its executable and object files into the test directory
    git -C "$SRC/cocotb-fix" clean -fdxq -- "tests/test_cases/$t"
    python3 "$SRC/verify/summary.py" "$TREE" "$SIM" "$t" "$out/results.xml" "$rc" || status=1
done
exit $status
