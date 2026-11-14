# Testing the fix

This page describes how to verify the cocotb fix for the case of VHDL names, and what each test
tells. Everything runs in one container image with free simulators: NVC, GHDL, Icarus Verilog and
Verilator.

The fix makes cocotb follow these rules of IEEE 1076-2019:

1. A basic identifier is case insensitive (15.4.2): `dut.data_in`, `dut.DATA_IN` and
   `dut["Data_In"]` are one object with one handle.
2. An extended identifier is exact (15.4.3): `\Sig\` and `\SIG\` are two objects, and a backslash
   inside one is written twice (`\a\\b\`).
3. A lookup by name gives the object of that name or raises `KeyError`, never another object.
4. One object has one key, whichever way it is reached: a lookup in any spelling, a dotted name or
   iteration.

Verilog names stay case sensitive.

## What you need

- git and Docker on a Linux x86-64 host.
- The image `ghcr.io/topi-ab/cocotb-gpi-fix-vhdl-identifier-case:latest`. It is built from [docker/Dockerfile](../docker/Dockerfile)
  by the workflow [.github/workflows/ci.yml](../.github/workflows/ci.yml), which also runs the tests in it.
  `./run` uses the `latest` tag; `docker pull ghcr.io/topi-ab/cocotb-gpi-fix-vhdl-identifier-case:latest`
  updates it. You can also build the image yourself:

  ```sh
  docker build -t ghcr.io/topi-ab/cocotb-gpi-fix-vhdl-identifier-case:latest docker
  ```

The image has:

| Tool | Version | Source |
|---|---|---|
| NVC | 1.23.0 | release package from github.com/nickg/nvc |
| GHDL | 6.0.0, LLVM backend | image `ghdl/ghdl:6.0.0-llvm-ubuntu-24.04` |
| Icarus Verilog | 13.0 (devel) s20250103-66-gd67d3323a | oss-cad-suite 2025-09-07 |
| Verilator | 5.041 (v5.040-59-gd186dcdc3) | oss-cad-suite 2025-09-07 |
| Python, g++, CMake | 3.12, 13.3.0, 3.28 | Ubuntu 24.04 |

`versions` in the image checks these.

## Running the tests

```sh
git clone --recurse-submodules https://github.com/Topi-ab/cocotb-GPI-fix-vhdl-identifier-case.git
cd cocotb-GPI-fix-vhdl-identifier-case
./run verify/all.sh
```

[run](../run) starts the container with the repository mounted at `/src` and runs the command in it.
Everything the scripts write goes to `work/`. Set `COCOTB_GPI_FIX_IMAGE` to use another image.

`verify/all.sh` checks the tool versions, builds both cocotb trees, and runs the case tests with
every simulator, first with the fix and then with stock cocotb. It ends with exit status 0 when every
test passes with the fix. With stock cocotb some tests fail; that is expected, and it shows what the
fix changes.

The steps can also be run one at a time:

| Command | What it does |
|---|---|
| `./run verify/build.sh fix` | Builds `cocotb-fix/` into the venv `work/venv/fix` |
| `./run verify/build.sh upstream` | Builds `cocotb-upstream/` (stock cocotb, the commit the fix is based on) into `work/venv/upstream` |
| `./run verify/test.sh fix nvc` | Runs the case tests with the fix and NVC. The simulator is `nvc`, `ghdl`, `icarus` or `verilator`. Test names after the simulator run only those tests. |
| `./run verify/test.sh upstream nvc` | The same tests with stock cocotb |
| `./run verify/regression.sh fix nvc` | The whole cocotb regression (`run_tests.py`) of one tree with one simulator, with the environment of cocotb's CI |

The case tests are always the ones in `cocotb-fix/tests/test_cases`. With `upstream` they run against
stock cocotb, so both runs use the same tests and the same designs. Without a test list,
`verify/test.sh` runs:

- NVC and GHDL (VHDL): `test_vhdl_handle_identity`, `test_discovery`, `test_vhdl_access`;
- Icarus and Verilator (Verilog): `test_verilog_name_case`, `test_discovery`.

The results of each test are in `work/results/<tree>/<simulator>/<test>/`: `results.xml`, the log
and the simulator build. The build log of each tree is `work/logs/build-<tree>.log`, and the
regression writes `work/regression/<tree>/<simulator>/log` and `results.xml`.

## Results

Measured on 2026-11-14 with this repository: `cocotb-fix` at `3b1d0325`, `cocotb-upstream` at
`b157f586`, and the image built from [docker/Dockerfile](../docker/Dockerfile). Counts are tests /
passed / failed / skipped.

### Case tests (`verify/all.sh`)

| Test | Simulator | With the fix | Stock cocotb |
|---|---|---|---|
| `test_vhdl_handle_identity` | NVC | 40 / 39 / 0 / 1 | 40 / 11 / **28** / 1 |
| `test_vhdl_handle_identity` | GHDL | 36 / 25 / 0 / 11 | 36 / 6 / **19** / 11 |
| `test_discovery` (VHDL) | NVC | 35 / 21 / 0 / 14 | 35 / 20 / **1** / 14 |
| `test_discovery` (VHDL) | GHDL | 35 / 21 / 0 / 14 | 35 / 19 / **2** / 14 |
| `test_vhdl_access` | NVC | 3 / 3 / 0 / 0 | 3 / 3 / 0 / 0 |
| `test_vhdl_access` | GHDL | 3 / 3 / 0 / 0 | 3 / 3 / 0 / 0 |
| `test_verilog_name_case` | Icarus | 2 / 2 / 0 / 0 | 2 / 2 / 0 / 0 |
| `test_verilog_name_case` | Verilator | 2 / 2 / 0 / 0 | 2 / 2 / 0 / 0 |
| `test_discovery` (Verilog) | Icarus | 35 / 25 / 0 / 10 | 35 / 25 / 0 / 10 |
| `test_discovery` (Verilog) | Verilator | 35 / 25 / 0 / 10 | 35 / 25 / 0 / 10 |

What this shows:

- With the fix every case test passes on all four simulators.
- With stock cocotb, 28 of the VHDL identity tests fail on NVC and 19 on GHDL, and `test_discovery`
  fails where a lookup and iteration give two handles for one object (NVC) or where a region found
  in another spelling is taken for a generate (GHDL). Typical failures:
  - GHDL: `dut.DATA_IN is dut.data_in` is false; `dut.U_SUB` is a `HierarchyArrayObject` (a
    generate) instead of the instance `u_sub`; the toplevel is not found in another spelling.
  - NVC: `dut["\\ext_sig\\"]` gives the object `\Ext_Sig\`, which is declared first;
    `dut["plain_blk.\\Foo\\"]` gives an object although no `\Foo\` is declared; iterating the
    design fails with `RecursionError` ("maximum recursion depth exceeded").
- The Verilog results are the same with and without the fix: Verilog names stay case sensitive.
- `test_vhdl_access` is not changed by the fix. It passes on both trees and shows that ordinary VHDL
  access still works.

The skipped tests are skipped on both trees. With NVC, `array_element_by_name_is_indexed_one` skips
itself because NVC does not find an array element by name. With GHDL, 11 identity tests are skipped:
five because GHDL cannot access records, three because GHDL looks a name up in lower case and finds
no extended identifier with an upper case letter, and three because GHDL does not find a generate
iteration, an array element or the two-dimensional arrays by name. The skipped `test_discovery` tests are the Verilog-only tests on VHDL and
the VHDL-only tests on Verilog.

### Whole cocotb regression (`verify/regression.sh`)

This runs all of `tests/test_cases` and `examples` of each tree with `run_tests.py` and the
environment of cocotb's CI. Stock cocotb has fewer tests, because the fix adds
`test_vhdl_handle_identity` and `test_verilog_name_case`.

| Simulator | With the fix | Stock cocotb |
|---|---|---|
| NVC | 638 / 566 / 0 / 72 | 597 / 526 / 0 / 71 |
| GHDL | 630 / 505 / 1 / 124 | 593 / 478 / 1 / 114 |
| Icarus | 625 / 538 / 0 / 87 | 622 / 535 / 0 / 87 |
| Verilator | 692 / 587 / 0 / 105 | 689 / 584 / 0 / 105 |

The one failure on GHDL is `test_cocotb.test_timer_with_units` in both trees: this GHDL reports a
time precision of 1 fs (`-15`), and the test expects 1 ps (`-12`). It does not depend on the fix,
and `verify/regression.sh` accepts it ([verify/known_failures.py](../verify/known_failures.py)).
The regression shows that the fix breaks no other test.

## What each test tells

The results below are from the case-test run above.

### New: test_vhdl_handle_identity

These tests check that every way of reaching a VHDL object gives the same Python handle, that distinct objects stay distinct, and that a lookup by name gives the named object or raises KeyError. The design (vhdl_handle_identity.vhdl; the Makefile runs it only for VHDL) has mixed-case basic names, an instance, generates, blocks, records and two-dimensional arrays. It also has extended identifiers that differ only in case or in the number of backslashes. Each one has its own value, so a lookup that returns the wrong object fails. The tests share one dut and run in order. The tests before handle_identity_survives_discovery run before anything iterates the toplevel, so their lookups go to the simulator and not to a cache filled by iteration. That test (stage 1) iterates the whole design. The stage 2 tests check the design after that.

#### `root_lookup_matches_dut`

- **Checks:** Looks up the toplevel with its name in upper case. Checks that the handle exists and that the Python object made from it is the same object as dut.
- **Tells:** The toplevel name is a basic identifier, so it is case insensitive (IEEE 1076-2019 15.4.2). One object has one handle, however it is reached.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC pass; GHDL **fail**.

#### `case_lookup_before_discovery` (parametrized: spelling = data_in, Mixed_Case, u_sub, u_sub.sub_sig, rec_sig.field_a, gen, gen[0].g_sig)

- **Checks:** Runs before the toplevel is iterated. Resolves the path as written in the source, then resolves it in other spellings (for example DATA_IN and Data_In, U_SUB.SUB_SIG, Rec_Sig.Field_A, GEN[0].G_SIG). Checks that each spelling gives the very same handle object.
- **Tells:** Basic identifiers are case insensitive (15.4.2), for ports, signals, instances, record fields, generates and objects inside generate iterations. The lookup goes to the simulator, not to a cache filled by iteration, and still gives one handle per object.
- **Simulator notes:** On GHDL the rec_sig.field_a case is left out because GHDL cannot access record types. The gen[0].g_sig case is left out because GHDL cannot access signals in generate loops.
- **Result with the fix:** NVC 7 pass; GHDL 5 pass. **With stock cocotb:** NVC 7 pass; GHDL **5 fail**.

#### `extended_lookup_is_exact`

- **Checks:** Looks up the toplevel extended identifiers \\Ext_Sig\\, \\ext_sig\\, \\Back\\\\Slash\\, \\back\\\\slash\\, \\Back\\\\slash\\, \\p\\\\q\\, \\p\\\\\\\\q\\, \\a:b\\ and \\X_Rec\\\\.\\\\f\\. Each one must give the object with its own value. Then checks that names in another case (\\EXT_SIG\\, \\BACK\\\\SLASH\\, \\Back\\\\SLASH\\) and names written with a single backslash (\\p\\q\\, \\A\\B\\, \\G\\X\\, \\R\\x\\) raise KeyError.
- **Tells:** Extended identifiers are matched exactly (15.4.3): case matters and a backslash inside one is written twice. A lookup gives the named object or raises KeyError, never another object.
- **Simulator notes:** A name may give KeyError (but never a wrong object) where the simulator does not find it by name. NVC matches extended identifiers ignoring case and returns the first one declared, writes a backslash once, and does not find names with a ':' in them. GHDL looks a name up in lower case. These names are checked again after iteration.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `dotted_path_to_extended_names`

- **Checks:** Looks up plain_blk.\\foo\\ and plain_blk.\\FOO\\ as dotted names, with the basic block name in lower case. Checks that plain_blk.\\Foo\\ raises KeyError. Checks that the step-by-step lookup dut.Plain_Blk[name] gives each name's own value (0x8, 0x9), or nothing where the simulator does not find that name. The dotted lookup must give the same object as the step-by-step one, or nothing where the simulator does not find that name. It runs before anything else looks up Plain_Blk, and remembers the handles so stage 1 can check them again.
- **Tells:** In a dotted path the basic part is case insensitive (15.4.2) and the extended part is exact (15.4.3). A dotted name and a step-by-step lookup reach the same single handle.
- **Simulator notes:** \\FOO\\ may be missing by name with NVC, because NVC returns its twin \\foo\\, which is declared first. It may also be missing with GHDL, because GHDL looks a name up in lower case. Stage 2 checks both names again, and then they must be found.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `native_dotted_name_is_stepwise_one`

- **Checks:** Uses the low-level lookup with GPIDiscovery.NATIVE. Plain_Blk.\\foo\\ must be found with value 0x8. Its element at index 0 must equal the element at index 0 of the object found step by step. u_sub.sub_sig must have the same type as dut.u_sub.sub_sig, and gen(0).g_sig the same type as dut.gen[0].g_sig. gen.data_in and plain_blk.\\Foo\\ must give no object.
- **Tells:** A NATIVE dotted lookup gives the object that a lookup one name at a time gives, or nothing, never another object. Extended names stay exact (15.4.3).
- **Simulator notes:** On GHDL the element is not found by index, so the test compares the child g of the generate u_sub.U_Sub instead. The gen(0).g_sig check is skipped on GHDL because GHDL cannot access generate iterations by name.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `extended_region_keeps_identity`

- **Checks:** Looks up the block \\Blk\\ in Twins, then its signal as blk.b_sig. Checks that blk.B_SIG is the same object and has value 0xA. Checks that the dotted name Twins.\\Blk\\.\\Sig\\ gives the same object as blk["\\Sig\\"]. Remembers the handles for stage 1.
- **Tells:** Inside a region with an extended name, basic names are still case insensitive (15.4.2). The dotted lookup and the step-by-step lookup give one handle for one object.
- **Simulator notes:** Skipped on GHDL: GHDL looks a name up in lower case, so it finds no \\Blk\\.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC pass; GHDL skip.

#### `region_twins_keep_their_children`

- **Checks:** Gets the blocks \\Blk\\, \\BLK\\ and \\blk\\ from the simulator's iteration of Twins. In each block it looks up B_SIG, the field br.field_b, and T_Sig in iteration 1 of the generate tg. Each must have that block's own value (0xA, 0xB, 0xC). It also checks that \\Sig\\, which only exists in \\Blk\\, is not found in \\BLK\\. It runs before anything else looks up \\BLK\\ and \\blk\\.
- **Tells:** Regions whose extended names differ only in case are distinct objects (15.4.3), and so are their children. A name gives the object in the region it is looked up in, or nothing, never the one in a twin region.
- **Simulator notes:** On GHDL, B_SIG may not be found in a block whose extended name has an upper-case letter, because GHDL looks a name up in lower case. The rest of the checks for that block are then left out. On GHDL the record and generate checks are left out, because GHDL cannot access record types or generate iterations.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `extended_record_fields_by_name`

- **Checks:** For the records rx and \\X_Rec\\, each field \\f\\, \\g\\\\h\\, \\g\\\\\\\\h\\ and \\f.x\\ must be found with its own value. The name x\\ (the tail of \\f.x\\) must raise KeyError. In \\N\\, the name \\in\\\\.\\\\f\\ must raise KeyError. This is one extended identifier that, with each backslash written once, looks like the path \\in\\.\\f\\ to a field of the record inside \\N\\. rec_sig:field_a and rx:\\f\\ must raise KeyError.
- **Tells:** Extended field names are exact (15.4.3), including fields that differ only in the number of backslashes and a field with a '.' in its name. A '.' inside an extended name is not a path separator, and ':' is not one either. A lookup never gives another field.
- **Simulator notes:** Skipped on GHDL: GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `name_below_generate_is_not_found`

- **Checks:** Checks that gen.data_in, gen.gen_b and gen.\\Gen\\ raise KeyError. On the generate gen it checks that u_sub, gen(0), gen_b and GEN_B give no object.
- **Tells:** Names of the region that holds a generate are not found below the generate, and its iterations are not found by name there. They are reached by indexing. A lookup gives the named object or nothing.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL pass.

#### `generate_label_with_more_is_no_generate`

- **Checks:** Checks that gen(0)x, gen(, \\Gen\\(0)q and u_sub.U_Sub(0)x raise KeyError.
- **Tells:** A name that starts with a generate label but has more after it is not the generate. A lookup matches the whole name or raises KeyError. It never matches on a prefix.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL pass.

#### `name_below_generate_is_not_in_its_region`

- **Checks:** Looks up u_sub.U_Sub.g (inside the generate) and dut.u_sub.g (in the instance). The outer g must have value 0. If the inner name is found, it must be a different object with value 1. It runs before anything else looks up u_sub.g.
- **Tells:** A name found below a generate is never the object of the same name in the region around it. A lookup gives the named object or nothing, never another object.
- **Simulator notes:** The inner name may be found only on GHDL, which finds names in the first iteration of a generate.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC pass; GHDL pass.

#### `generate_in_instance_of_its_name`

- **Checks:** Looks up dut.u_sub.U_SUB. Inside u_sub there is a generate called U_Sub, so this must give that generate (an array object), not the instance. It checks that iteration 1 has g = 1 and that the generate has two iterations.
- **Tells:** A basic name is case insensitive (15.4.2) and is looked up in its parent. A child whose label is the parent's name in another case is the child, not the parent.
- **Simulator notes:** On GHDL the iteration checks are left out because GHDL cannot access generate iterations.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL pass.

#### `generate_iteration_by_name_is_indexed_one`

- **Checks:** Looks up gen(0) and GEN(0) by name with the low-level lookup. Each must equal the handle of dut.gen[0].
- **Tells:** A generate iteration found by name, in any case, is the same object as the one found by indexing (15.4.2, one object, one handle).
- **Simulator notes:** Skipped on GHDL: GHDL cannot access generate iterations by name.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC pass; GHDL skip.

#### `array_element_by_name_is_indexed_one`

- **Checks:** Looks up data_in(0) by name. If it is found, it must equal the handle of dut.data_in[0].
- **Tells:** An array element is reached by indexing. A lookup by name gives the same object or nothing, never another one.
- **Simulator notes:** Skipped at run time on any simulator that does not find the element by name.
- **Result with the fix:** NVC skip; GHDL skip. **With stock cocotb:** NVC skip; GHDL skip.

#### `extended_generate_label`

- **Checks:** Looks up the generate \\Gen\\. Checks that \\Gen\\[0].G_SIG and \\Gen\\[0].g_sig are the same object, with value 0. Checks that \\gen\\ raises KeyError. If \\GEN\\ is found, it must be a different object from \\Gen\\. If its iteration 1 can be reached, it must have G_Sig = 0xE. If \\GEN\\ or its iteration is not found, \\GEN\\ must be a name the simulator may miss, and the check is repeated after iteration.
- **Tells:** Generates whose extended labels differ only in case are distinct (15.4.3). An index reaches the iteration of the generate it is applied to. Basic names inside an iteration stay case insensitive (15.4.2).
- **Simulator notes:** Skipped on GHDL: GHDL looks names up in lower case, so it finds no generate with an upper-case letter in its extended label. With NVC, \\GEN\\ may be missing by name before iteration.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `extended_generate_label_with_backslash`

- **Checks:** Looks up the generates \\G\\\\X\\ and \\G\\\\\\\\X\\. Both must be found by name. Iteration 1 is taken by index through the low-level API and must be among the generate's children as the simulator iterates them. X_Sig must be 1 in \\G\\\\X\\ and 0 in \\G\\\\\\\\X\\, as declared. Iterating the generate must give two iterations with that value. \\g\\\\x\\ must raise KeyError. Both generates are remembered so that stage 1 checks their handles again.
- **Tells:** Extended labels that differ only in the number of backslashes are distinct and exact (15.4.3). The same label in lower case is another identifier, which is not declared. The iterations of these generates can be reached by index and by iteration.
- **Simulator notes:** Skipped on GHDL: GHDL looks names up in lower case, so it finds no generate with an upper-case letter in its extended label.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `extended_generate_label_in_lower_case`

- **Checks:** Looks up the generate \\gl\\ and checks that it is an array object. \\GL\\ must raise KeyError. On simulators other than GHDL, \\gl\\.s must raise KeyError and \\gl\\[1].S must be 0xF. The handle is remembered so that stage 1 checks it again.
- **Tells:** An extended label in lower case is found by its exact label. The same label in upper case is another identifier that is not declared (15.4.3).
- **Simulator notes:** Not skipped. On GHDL, \\gl\\.s is expected to give 0xF, because GHDL finds names in the first iteration of a generate.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `extended_generate_label_with_paren`

- **Checks:** Looks up the generate \\a(b\\. It must be an array object with two iterations, and iteration 1 must have P_Sig = 1. The check runs now and again after the design has been iterated.
- **Tells:** A '(' inside an extended label is part of the name, not an index (15.4.3). The generate is found and iterated by its exact label.
- **Simulator notes:** On GHDL the iteration checks are left out because GHDL cannot access generate iterations.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL pass.

#### `extended_two_dimensional_array`

- **Checks:** Looks up the two-dimensional arrays \\A\\\\B\\ (2x2) and \\C\\\\D\\\\)\\ (2x3). Both must be found by name. Checks their lengths, their row lengths and every element value. The handles are remembered, so stage 1 checks that they are the same objects afterwards and that they are in the simulator's iteration of the toplevel.
- **Tells:** Extended names with backslashes, and with a ')' in them, are exact (15.4.3). Indexing reaches the right elements.
- **Simulator notes:** Skipped on GHDL: GHDL does not find or iterate these arrays.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `record_fields_named_as_paths`

- **Checks:** Gets the signal \\N\\\\.\\\\in\\ from the simulator's iteration of Rec_Blk. Its field \\f\\ must be 0x5. Its name, with backslashes written once, looks like the path \\N\\.\\in\\.\\f\\, whose value is 0x1. In the record dp, the field \\x\\\\.\\\\in\\ and then \\f\\ must give 0xD, and the path \\x\\, \\in\\, \\f\\ must give 0x9. It runs before anything else iterates the records in Rec_Blk.
- **Tells:** A record, or a record field, whose name looks like a path to another field is its own object with its own fields (15.4.3). A lookup never gives the field that the name looks like.
- **Simulator notes:** Skipped on GHDL: GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `records_with_backslash`

- **Checks:** Looks up the records \\R\\\\x\\ and \\R\\\\\\\\x\\. Both must be found by name. Before any field is looked up, the simulator's iteration of each record must give exactly the fields field_a and field_b. A low-level lookup of each field must give its own value (0 and 0x1 in \\R\\\\x\\, 1 and 0x2 in \\R\\\\\\\\x\\). The handles are remembered so that stage 1 checks them again.
- **Tells:** Records whose names differ only in the number of backslashes are distinct (15.4.3), and each one has its own fields.
- **Simulator notes:** Skipped on GHDL: GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `two_dimensional_record_fields`

- **Checks:** Uses the records r, \\R2_Long_Name\\ and \\R\\\\y\\, and the field \\O\\\\p\\ of nr (a record inside a record). For their two-dimensional fields (m and \\M\\\\x\\, or \\m.x\\ and \\I\\\\n\\), it looks each field up with a dotted name and step by step. It checks lengths and every element value, and checks that the dotted lookup is the same object as the step-by-step one.
- **Tells:** Indexing a two-dimensional record field reaches the right elements, whether the field name is basic or extended. A dotted name and a step-by-step lookup give one handle.
- **Simulator notes:** Skipped on GHDL: GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `handle_identity_survives_discovery` (stage 1)

- **Checks:** First resolves every path in the spelling list. Then it looks up FIRST_OTHER, GEN_B and U_OTHER, using a spelling that differs from the source for the first lookup. It checks that U_OTHER is an instance, that U_OTHER.SUB_SIG is u_other.sub_sig, and that GEN_B[1].G_SIG is GEN_B[1].g_sig. Then it iterates the whole design. Every path, and every handle remembered by the earlier tests, must give the same object as before. Each remembered handle that has a parent region must be in the simulator's iteration of that parent. first_other and u_other must be in the toplevel iteration. dut.first_other, dut.u_other.sub_sig and dut.gen_b[1] in source spelling must be the objects first looked up in the other spelling. gen_b must be in the toplevel iteration and have two iterations.
- **Tells:** Iteration never replaces a handle that was looked up earlier, even when that first lookup used a spelling other than the source one. One object keeps one handle, however it is reached (15.4.2 for the basic names).
- **Simulator notes:** On GHDL the gen_b checks (GEN_B[1], gen_b in the toplevel iteration, and its two iterations) are left out because GHDL cannot access signals in generate loops.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `extended_lookup_after_discovery` (stage 2)

- **Checks:** Iterates the design. Then every toplevel extended identifier, and \\foo\\ and \\FOO\\ in Plain_Blk, must be found by its source name with its own value, and none may be missing. The names with a single backslash must still raise KeyError. The checks deferred by earlier tests run now.
- **Tells:** After iteration, every extended identifier is found by its exact name (15.4.3) and gives its own object, including those that NVC or GHDL do not find by name. Names that do not exist still raise KeyError.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

#### `extended_record_fields_after_discovery` (stage 2)

- **Checks:** Iterates the design. For rx and \\X_Rec\\, the simulator's iteration must report the fields by their source names with their own values, rec._keys() must hold exactly those names, and each name must give its own field. For \\R\\\\x\\ and \\R\\\\\\\\x\\, the iteration and _keys() must give exactly field_a and field_b with the right values.
- **Tells:** Each extended field has exactly one key, its exact source name (15.4.3). Fields that differ only in the number of backslashes are not merged.
- **Simulator notes:** Skipped on GHDL: GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL skip. **With stock cocotb:** NVC **fail**; GHDL skip.

#### `case_lookup_after_discovery` (stage 2, parametrized: spelling = data_in, Mixed_Case, u_sub, u_sub.sub_sig, rec_sig.field_a, gen, gen[0].g_sig)

- **Checks:** Iterates the design. Then it resolves the path as written in the source, the spellings already used, and new spellings that have not been used before (data_IN, mIXED_cASE, u_SUB, U_sUB.sub_SIG, rec_SIG.field_A, gEN, gEn[0].g_SIG). All of them must give the same handle object.
- **Tells:** After iteration, basic identifiers are still case insensitive (15.4.2), even for spellings looked up for the first time. They map to the one existing handle and do not create a new one.
- **Simulator notes:** On GHDL the rec_sig.field_a case is left out because GHDL cannot access record types. The gen[0].g_sig case is left out because GHDL cannot access signals in generate loops.
- **Result with the fix:** NVC 7 pass; GHDL 5 pass. **With stock cocotb:** NVC **7 fail**; GHDL **5 fail**.

#### `iterated_children_match_lookup` (stage 2)

- **Checks:** For the toplevel, u_sub and (except on GHDL) rec_sig, rx, \\X_Rec\\, \\R\\\\x\\ and \\R\\\\\\\\x\\, it takes every child from the simulator's iteration. It looks each child up by its reported name with the low-level lookup. The result must be the same object, or nothing where the simulator may not find that name.
- **Tells:** The name that iteration reports for a child leads back to that same child, never to another object. One object has one handle whether it is found by iteration or by name.
- **Simulator notes:** Children whose names start with '#' or look like s__N_N are skipped: some simulators add these to iteration, and they cannot be looked up by name. On GHDL, names that end in ')' are skipped because GHDL cannot access generate iterations by name, and the record parents are left out because GHDL cannot access record types.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL pass.

#### `iterated_extended_identifiers_stay_distinct` (stage 2)

- **Checks:** From the simulator's iteration of the toplevel, it collects the children whose names are the toplevel extended identifiers. The result must be exactly that set of names, each reported by its source name with its own value.
- **Tells:** Iteration gives one object per extended identifier, under its exact source name (15.4.3). Identifiers that differ only in case or in the number of backslashes are not merged.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC **fail**; GHDL **fail**.

### New: test_verilog_name_case

These tests check that Verilog names stay case sensitive. The VHDL case fix must not change Verilog. The design verilog_name_case.sv has signals foo, FOO and Bar in the top module and a sub-instance u_sub with signals sig and SIG. The Makefile runs the tests only when TOPLEVEL_LANG=verilog. For any other language it prints a skip message and runs nothing.

#### `names_differing_in_case_are_distinct`

- **Checks:** It runs in the top module (foo and FOO) and in the sub-instance u_sub (sig and SIG). For each pair it gets both handles by index lookup and checks that they are different objects. It then writes 1 to the lower-case signal and 0 to the upper-case signal, waits 1 ns, and checks that each signal kept its own value.
- **Tells:** In Verilog, two names that differ only in case are two separate objects. Each one has its own handle and its own value. The case rules for VHDL names (basic identifiers are case insensitive per IEEE 1076-2019 15.4.2) must not reach Verilog and merge these names into one object. The two spellings never give the same handle, and writing one signal does not change the other. This holds at the top level and inside a sub-instance.
- **Simulator notes:** No skip in the test code. The Makefile runs the test only when TOPLEVEL_LANG=verilog. For other languages it prints a skip message.
- **Result with the fix:** Icarus pass; Verilator pass. **With stock cocotb:** Icarus pass; Verilator pass.

#### `other_case_is_not_found`

- **Checks:** It checks that dut.Bar exists. It then checks that dut.bar and dut.BAR raise AttributeError, because the design only has Bar. It also checks that dut.U_SUB raises AttributeError, because the instance is named u_sub.
- **Tells:** In Verilog, a name only matches its exact spelling. A lookup with the wrong case does not fall back to an object that has the same name in another case. It gives the named object or raises an error, and never returns a different object. This holds for both signal names and instance names.
- **Simulator notes:** No skip in the test code. The Makefile runs the test only when TOPLEVEL_LANG=verilog. For other languages it prints a skip message.
- **Result with the fix:** Icarus pass; Verilator pass. **With stock cocotb:** Icarus pass; Verilator pass.

### Changed: test_discovery

The fix adds one test to test_discovery and changes two existing VHDL tests. All of them run on the sample_module design: the top level is sample_module, which holds the VHDL component instance isample_module1 of sample_module_1, and that holds the block SAMPLE_BLOCK and its signal clk_inv. The fix does not change the other tests in test_discovery. They check that object discovery works as it did before the fix.

#### `name_lookup_and_iteration_agree` (new)

- **Checks:** It uses the GPI iterator to walk all children of the top level, and it puts each raw simulator handle in a map, keyed by the lowercased name the simulator reports. Each checked name must be a key in that map. A direct GPI lookup by that name must then return a handle equal to the one from iteration, which means the same underlying GPI handle. The names are the port stream_in_data in both languages and, for VHDL only, the component instance isample_module1.
- **Tells:** One object has one handle, however it is reached: a lookup by name and a walk over the children give the same GPI handle. The lookup names are lowercase. A simulator may report a VHDL basic identifier in another case, and the lookup must still find the same object. This checks that basic identifiers are case insensitive (IEEE 1076-2019 15.4.2).
- **Simulator notes:** None. It runs for both VHDL and Verilog. The component instance is checked only when the language is VHDL.
- **Result with the fix:** NVC pass; GHDL pass; Icarus pass; Verilator pass. **With stock cocotb:** NVC **fail**; GHDL pass; Icarus pass; Verilator pass.

#### `access_block_vhdl` (changed)

- **Checks:** It looks up the block statement isample_module1.SAMPLE_BLOCK and the signal SAMPLE_BLOCK.clk_inv inside it.
- **Tells:** Before the fix, the test expected GHDL to raise AttributeError here, because GHDL could not find a signal in a block statement. That expectation has been removed, so on GHDL, as on every other simulator, both lookups must now succeed without an error. The label SAMPLE_BLOCK is a basic identifier and is written in upper case. The lookup must work even when the simulator reports the label in another case (IEEE 1076-2019 15.4.2).
- **Simulator notes:** Skipped when the language is Verilog, since a block statement exists only in VHDL. No simulator is expected to fail any more.
- **Result with the fix:** NVC pass; GHDL pass; Icarus skip; Verilator skip. **With stock cocotb:** NVC pass; GHDL **fail**; Icarus skip; Verilator skip.

#### `discover_all_in_component_vhdl` (changed)

- **Checks:** It walks the whole hierarchy below isample_module1 and counts the objects it finds. The expected count is 9: EXAMPLE_STRING, EXAMPLE_BOOL, EXAMPLE_WIDTH, clk, stream_in_data, stream_out_data_registered, stream_out_data_valid, SAMPLE_BLOCK and SAMPLE_BLOCK.clk_inv. The walk now keeps a set of the objects it has already seen and counts each object only once.
- **Tells:** Before the fix, GHDL found SAMPLE_BLOCK twice, and the test expected 10 on GHDL. That special case is removed, so GHDL must now also give 9. A comment in the code says that an object looked up before in another spelling (SAMPLE_BLOCK, by the earlier test access_block_vhdl) is listed once per spelling. The walk therefore counts distinct objects. If the simulator reports the label in another case, there are two entries. They count as one only when they are the same object, which happens when the lookup and the iteration gave the same handle. Getting 9 then shows that one object has one handle, however it is reached.
- **Simulator notes:** Skipped when the language is Verilog. NVC versions older than 1.16.0 still expect 10, because, as the code says, old NVC finds clk_inv twice. Only the formatting of that line changed.
- **Result with the fix:** NVC pass; GHDL pass; Icarus skip; Verilator skip. **With stock cocotb:** NVC pass; GHDL **fail**; Icarus skip; Verilator skip.

### Unchanged: test_vhdl_access

This is a regression check of VHDL object access. The test file, its Makefile and the shared design (tests/designs/viterbi_decoder_axi4s, VHDL only, toplevel dec_viterbi_ent) are unchanged by the fix. The tests look up ports, signals, a generic, instances and generate blocks by their declared names, and check the type of each handle. If they still pass, the new way of keying and looking up VHDL objects still gives the right kind of handle for an ordinary design.

#### `check_enum_object`

- **Checks:** Looks up dut.inst_ram_ctrl.write_ram_fsm, a signal of an enumerated type inside an instance. Checks that the handle is an EnumObject. Checks that the deprecated len(handle) and int(handle) still match handle.size and handle.value, and that both raise a DeprecationWarning.
- **Tells:** A name lookup through an instance (inst_ram_ctrl) still gives a handle of the right type, an EnumObject, for the enum signal. The new keying does not change the handle type that this lookup returns.
- **Simulator notes:** On GHDL the test is expected to fail. The code says GHDL discovers an enum as vpiNet, so the handle there is not an EnumObject.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC pass; GHDL pass.

#### `check_objects`

- **Checks:** Looks up many kinds of objects by name and checks each handle type: the instance inst_axi4s_buffer and inst_ram_ctrl (HierarchyObject), the generate block gen_branch_distance[0] and the instance inst_branch_distance inside it (HierarchyObject), the signal inbranch_tdata_low declared inside gen_acs[0] (LogicArrayObject), the port aclk (LogicObject), the port s_axis_input_tdata (LogicArrayObject), the integer signal current_active (IntegerObject) and the generic inst_axi4s_buffer.DATA_WIDTH (IntegerObject). Checks that DATA_WIDTH reads 32, and that writing 42 to it raises TypeError.
- **Tells:** Name lookups at the top level, below instances, and in generate blocks reached by index (gen_branch_distance[0], gen_acs[0]) give handles of the right type. The generic is reached as DATA_WIDTH. That is a basic identifier, written in upper case in the source and looked up with the same spelling, so an upper case name still resolves. The test does not try other spellings. The generic reads 32 and stays read-only.
- **Simulator notes:** On GHDL the test is expected to end with IndexError. The code says GHDL is unable to access signals in generate loops.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC pass; GHDL pass.

#### `port_not_hierarchy`

- **Checks:** Checks that dut.aclk is a LogicObject. Then iterates over all children of dut. Then checks again that dut.aclk is still a LogicObject.
- **Tells:** Walking all children of dut does not change how a port is seen afterwards. A name lookup after the walk still gives a LogicObject for the port, not a HierarchyObject. So the walk does not replace the port with an object of another kind. The test checks only the handle type. It does not check that the handle is the same one.
- **Simulator notes:** It runs on all simulators that run this VHDL design.
- **Result with the fix:** NVC pass; GHDL pass. **With stock cocotb:** NVC pass; GHDL pass.


## What is not run here

This repository runs only free simulators: NVC through VHPI, GHDL through VPI, Icarus Verilog and
Verilator. The fix also changes the code for other VHPI simulators, for FLI and for designs that
mix VHDL and Verilog. That code is compiled in every build, but none of the simulators here runs
it. See [FIX.md](FIX.md) for what it does.
