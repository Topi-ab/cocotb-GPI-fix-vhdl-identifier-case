#!/usr/bin/env bash
# Build and install one cocotb tree into its own venv: work/venv/<tree>.
#
#   verify/build.sh fix|upstream
#
# The build directory work/build/<tree> is kept, so a rebuild is incremental.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
TREE=${1:?usage: verify/build.sh fix|upstream}
DIR=$(tree_dir "$TREE")
VENV=$WORK/venv/$TREE
LOG=$WORK/logs/build-$TREE.log
mkdir -p "$WORK/logs"

[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q -c "$SRC/verify/constraints.txt" \
    scikit-build-core packaging dynamic-metadata find_libpython \
    pytest pytest-timeout ipython pexpect psutil

echo "building cocotb ($TREE) from ${DIR#"$SRC"/}, log in ${LOG#"$SRC"/}"
timeout 1800 pip install -v --no-build-isolation --no-deps \
    -Cbuild-dir="$WORK/build/$TREE" "$DIR" >"$LOG" 2>&1 || {
    tail -n 40 "$LOG"
    exit 1
}
grep -E 'warning:' "$LOG" | sort -u | head -n 20 || true
python -c 'import cocotb; print("cocotb", cocotb.__version__)'
