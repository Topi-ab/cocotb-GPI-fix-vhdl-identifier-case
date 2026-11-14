#!/usr/bin/env bash
# Run the whole cocotb regression (tests/test_cases and examples, through run_tests.py) of one
# tree with one simulator, with the environment of cocotb's CI.
#
#   verify/regression.sh fix|upstream nvc|ghdl|icarus|verilator
#
# This runs inside the cocotb tree and cleans the files the simulators leave there afterwards.
# The combined results and the log go to work/regression/<tree>/<sim>/.
# Exit status 0 if no test failed, or only the known failures in verify/known_failures.py.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
TREE=${1:?usage: verify/regression.sh fix|upstream <sim>}
SIM=${2:?usage: verify/regression.sh fix|upstream <sim>}
DIR=$(tree_dir "$TREE")
LANG_=$(sim_lang "$SIM")
activate "$TREE"
sim_env "$SIM"
out=$WORK/regression/$TREE/$SIM
rm -rf "$out"
mkdir -p "$out"

export COCOTB_PREVIEW=1 COCOTB_SCHEDULER_DEBUG=1 GPI_DEBUG=1 PYGPI_DEBUG=1
export PYTHONWARNINGS="error,ignore::DeprecationWarning:site,ignore:coroutine :RuntimeWarning"
cd "$DIR" || exit 2
SIM=$SIM TOPLEVEL_LANG=$LANG_ timeout 3600 python run_tests.py >"$out/log" 2>&1
rc=$?
grep -a '^Ran .* suites' "$out/log" || true
grep -a '^Failed regression suite' "$out/log" || true
status=1
if [ -f combined_results.xml ]; then
    mv combined_results.xml "$out/results.xml"
    python3 "$SRC/verify/summary.py" "$TREE" "$SIM" regression "$out/results.xml" "$rc" && status=0
    if [ $status != 0 ] && python3 "$SRC/verify/known_failures.py" "$SIM" "$out/results.xml"; then
        status=0
    fi
else
    echo "no combined results (exit $rc), see ${out#"$SRC"/}/log"
fi
SIM=$SIM TOPLEVEL_LANG=$LANG_ timeout 600 python run_tests.py --clean >/dev/null 2>&1
git -C "$DIR" clean -fdxq -- tests examples .pytest_cache
exit $status
