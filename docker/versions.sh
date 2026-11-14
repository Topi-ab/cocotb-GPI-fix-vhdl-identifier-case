#!/bin/bash
# Check that each tool is the expected one, found at the expected path.
set -u
fail=0
check() {  # check <command> <expected path> <expected version text> <version command...>
    local cmd=$1 path=$2 want=$3; shift 3
    local got_path got
    got_path=$(command -v "$cmd" || true)
    got=$("$@" 2>&1 | head -n 3 | tr '\n' ' ')
    if [ "$got_path" = "$path" ] && [[ $got == *"$want"* ]]; then
        printf 'ok    %-10s %s\n' "$cmd" "$want"
    else
        printf 'FAIL  %-10s want %s (%s), got %s (%s)\n' "$cmd" "$want" "$path" "$got_path" "$got"
        fail=1
    fi
}
check nvc       /usr/bin/nvc                    "nvc 1.23.0"                  nvc --version
check ghdl      /opt/ghdl/bin/ghdl              "GHDL 6.0.0"                  ghdl --version
check ghdl      /opt/ghdl/bin/ghdl              "llvm"                        ghdl --version
check iverilog  /opt/icarus/bin/iverilog         "s20250103-66-gd67d3323a"     iverilog -V
check vvp       /opt/icarus/bin/vvp              "s20250103-66-gd67d3323a"     vvp -V
check verilator /opt/oss-cad-suite/bin/verilator "Verilator 5.041"            verilator --version
check python3   /usr/bin/python3                "Python 3.12"                 python3 --version
check g++       /usr/bin/g++                    "13.3.0"                      g++ --version
check cmake     /usr/bin/cmake                  "cmake version 3.28"          cmake --version
exit $fail
