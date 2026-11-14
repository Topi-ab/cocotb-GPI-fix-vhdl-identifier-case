# cocotb GPI fix: VHDL identifier case

This repository collects what is needed to verify a fix to the cocotb GPI for the case of VHDL names:

- basic identifiers are case insensitive (IEEE 1076-2019, 15.4.2), so every spelling of a basic name gives the same handle;
- extended identifiers are exact (15.4.3), so `\Sig\` and `\SIG\` are distinct objects;
- a lookup by name gives the named object or raises `KeyError`, never another object;
- one object has one key, whichever way it is reached (lookup in any spelling, a dotted name, iteration).

Verilog names stay case sensitive.

The fix is one commit, [`3b1d0325`](https://github.com/Topi-ab/cocotb/commit/3b1d0325bd325cda48054f80d6ac7247d5f9ed6f), on top of cocotb `b157f586`, in the fork
Topi-ab/cocotb (branch `fix/vhdl-identifier-case`).

- [doc/README.md](doc/README.md): how to run the tests, the results, and what each test tells.
- [doc/FIX.md](doc/FIX.md): what the problem in the GPI was, how it is fixed, and the adjustments for each simulator.

## Quick start

Needs git and Docker on a Linux x86-64 host.

```sh
git clone --recurse-submodules https://github.com/Topi-ab/cocotb-GPI-fix-vhdl-identifier-case.git
cd cocotb-GPI-fix-vhdl-identifier-case
./run verify/all.sh
```

The run ends with `fix: every test passed`. The FAIL lines under `== cocotb upstream` are expected:
they are the failures of stock cocotb that the fix removes.

## Layout

| Path | Content |
|---|---|
| `cocotb-fix/` | cocotb with the fix (submodule, Topi-ab/cocotb at `3b1d0325`, branch `fix/vhdl-identifier-case`) |
| `cocotb-upstream/` | stock cocotb at the commit the fix is based on (submodule, `cocotb/cocotb` at `b157f586`) |
| `docker/` | the container image: NVC, GHDL, Icarus Verilog and Verilator |
| `run` | runs a command in the container, with this repository at `/src` |
| `verify/` | the scripts that build both cocotb trees and run the tests |
| `doc/` | the documentation |
| `.github/workflows/ci.yml` | builds the image and pushes it to `ghcr.io/topi-ab/cocotb-gpi-fix-vhdl-identifier-case`, then runs the tests in it |

The fix and its tests are in `cocotb-fix/`:

- the GPI changes in `src/cocotb/share/lib/gpi/` and `src/cocotb/handle.py`;
- the tests `tests/test_cases/test_vhdl_handle_identity/`, `tests/test_cases/test_verilog_name_case/` and the extended `tests/test_cases/test_discovery/`;
- the user documentation in `docs/source/writing_testbenches.rst` ("Case of names").

`cocotb-upstream/` is the baseline: the same tests run on it show the behaviour before the fix.

## Licenses

The files of this repository (the scripts, the container definition, the workflow and the
documentation) are under the BSD 3-Clause license, see [LICENSE](LICENSE). cocotb is under the
BSD-3-Clause license (see `LICENSE` in each submodule).

### Image sources

The image `ghcr.io/topi-ab/cocotb-gpi-fix-vhdl-identifier-case` contains free software under its
own licenses. Its components and where their source code is:

| Component | Version | License | Source |
|---|---|---|---|
| NVC | 1.23.0 | GPL-3.0-or-later | https://github.com/nickg/nvc/releases/tag/r1.23.0 |
| GHDL | 6.0.0, LLVM backend, from the image `ghdl/ghdl:6.0.0-llvm-ubuntu-24.04` (digest in [docker/Dockerfile](docker/Dockerfile)) | GPL-2.0-or-later | https://github.com/ghdl/ghdl/releases/tag/v6.0.0 |
| oss-cad-suite (Icarus Verilog, Verilator and the other tools in it) | 2025-09-07 | one per tool, in `/opt/oss-cad-suite/license/` in the image; Icarus Verilog GPL-2.0-or-later, Verilator LGPL-3.0-only or Artistic-2.0 | https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2025-09-07; the revision of each tool is in `/opt/oss-cad-suite/VERSION` and the README there |
| Ubuntu 24.04 packages (gcc, g++, Python, git, CMake and the others) | from the Ubuntu archive when the image was built | one per package, in `/usr/share/doc/<package>/copyright` in the image | the Ubuntu archive (`apt-get source <package>`) |

The license texts are in the image: NVC in `/usr/share/doc/nvc/copyright`, GHDL in
`/opt/ghdl/COPYING.md`. If you need the source code of a GPL component of the image and cannot get
it from the places above, open an issue in this repository and it will be provided.
