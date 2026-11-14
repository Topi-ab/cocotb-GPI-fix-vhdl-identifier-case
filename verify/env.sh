# Common settings for the scripts in verify/. Sourced, not run. Used inside the container.

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$SRC/work
[ -d "$SRC/cocotb-fix/src" ] && [ -d "$SRC/cocotb-upstream/src" ] ||
    { echo "the submodules are missing: git submodule update --init" >&2; exit 2; }

# The two cocotb trees.
tree_dir() {
    case $1 in
        fix) echo "$SRC/cocotb-fix" ;;
        upstream) echo "$SRC/cocotb-upstream" ;;
        *) echo "unknown tree '$1' (fix or upstream)" >&2; exit 2 ;;
    esac
}

# The tests come from the fix tree; with tree=upstream they run against stock cocotb.
TESTS=$SRC/cocotb-fix/tests/test_cases

# ccache for the cocotb build and for Verilator. The compiler version is part of the hash.
export CCACHE_DIR=$WORK/ccache
export CCACHE_COMPILERCHECK='%compiler% -v'
export CCACHE_BASEDIR=$SRC
export CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-2G}
export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache
export OBJCACHE=ccache
export PATH=/usr/lib/ccache:$PATH

export PIP_CACHE_DIR=$WORK/pip-cache
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONDONTWRITEBYTECODE=1

# Language and VHDL interface of each simulator.
sim_lang() {
    case $1 in
        nvc | ghdl) echo vhdl ;;
        icarus | verilator) echo verilog ;;
        *) echo "unknown simulator '$1' (nvc, ghdl, icarus or verilator)" >&2; exit 2 ;;
    esac
}
sim_env() {
    unset VHDL_GPI_INTERFACE
    case $1 in
        nvc) export VHDL_GPI_INTERFACE=vhpi ;;
        ghdl) export VHDL_GPI_INTERFACE=vpi ;;
    esac
}

activate() {
    local venv=$WORK/venv/$1
    [ -x "$venv/bin/python" ] || { echo "tree '$1' is not built: run verify/build.sh $1" >&2; exit 2; }
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
}
