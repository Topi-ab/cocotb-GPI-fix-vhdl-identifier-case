#!/usr/bin/env bash
# Build both cocotb trees and run the case tests with every simulator.
#
#   verify/all.sh
#
# Expected: with tree=fix every test passes; with tree=upstream some fail (see doc/README.md).
# Exit status 0 if every fix run passed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
SIMS=(nvc ghdl icarus verilator)

# the tool check without the ccache compiler links of env.sh
PATH=${PATH#/usr/lib/ccache:} versions || exit 1
for tree in fix upstream; do
    "$SRC/verify/build.sh" "$tree" || exit 1
done

status=0
for tree in fix upstream; do
    echo
    echo "== cocotb $tree"
    for sim in "${SIMS[@]}"; do
        if ! "$SRC/verify/test.sh" "$tree" "$sim"; then
            [ "$tree" = fix ] && status=1
        fi
    done
done
echo
if [ $status = 0 ]; then
    echo "fix: every test passed"
else
    echo "fix: some tests FAILED"
fi
exit $status
