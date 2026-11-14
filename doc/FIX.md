# The fix: VHDL identifier case in the cocotb GPI

This document covers three things:

- what was wrong with how the cocotb GPI handled the case of VHDL names;
- how the fix in `cocotb-fix/` changes it;
- what the fix does differently for each simulator interface.

`cocotb-upstream/` is stock cocotb at `b157f586`, the commit the fix is based on.

- User documentation: `docs/source/writing_testbenches.rst` in the `cocotb-fix` submodule, section "Case of names" (label `writing_tbs_name_case`).
- How to run the tests: [README.md](README.md).

## The problem

### How stock cocotb identified an object

The GPI keeps one `GpiObjHdl` per object in a handle store (`GpiHandleStore` in `GpiCommon.cpp`). In stock cocotb, the key of that store was the object's full name (`get_fullname()`). The implementation built that full name from the parent's full name and **the name the caller asked for**, not from the name of the object:

- VHPI: `fully_qualified_name()` = parent full name + `"."` + requested name. The NVC build then upper-cased the whole path.
- VPI: parent full name + delimiter + requested name.
- FLI: parent full name + `/` (below a region) or `.` (below a record) + requested name.
- Iteration (VHPI): parent full name + `"."` + the name the simulator reports (`vhpiCaseNameP`), with no upper-casing.

So one VHDL object could get several keys, and so several handles. Each spelling of a basic identifier gave one key, and iteration could give one more.

The Python layer cannot repair this. `_make_sim_object()` maps each GPI handle to one Python object, so two GPI handles give two Python objects. The per-parent cache `_sub_handles` is keyed by the string the user typed, so it cannot merge spellings either.

### Failure modes

The examples below are failures of stock cocotb with the tests added by the fix, run by this repository on NVC and GHDL.

**One object, several handles.** Lookup and iteration built different keys, and each spelling built its own key.

- GHDL: `dut.DATA_IN is not dut.data_in`; `mixed_case is not Mixed_Case`.
- NVC: in `test_discovery`, a name lookup of `stream_in_data` gave a different handle than iteration did.

**Extended identifiers merged or swapped.** `\Ext_Sig\` and `\ext_sig\` are two objects (IEEE 1076-2019, 15.4.3).

- The NVC build upper-cased the whole key, extended identifiers included, and compared all names ignoring case. NVC itself also matches extended identifiers ignoring case and returns the first one declared. Result: `dut["\\ext_sig\\"]` returned `\Ext_Sig\` (test value 1, expected 2).
- GHDL looks names up in lower case, extended identifiers too, and stock cocotb did not check the name of what came back. Results: `dut["\\Ext_Sig\\"]` returned `\ext_sig\`; iterating the design gave the value 2 for both names; `dut["\\GL\\"]` found the generate `\gl\`.

**A region taken for a generate.** cocotb tells a region from a generate pseudo-region by comparing the requested name with the name the simulator reports. That comparison was case sensitive with VPI, with FLI, and with VHPI outside the NVC build. So a region looked up in another spelling became a pseudo-region.

- GHDL: `dut.U_SUB` was a `HierarchyArrayObject`, not the `HierarchyObject` `u_sub`, and then `'HierarchyArrayObject' object has no attribute 'SUB_SIG'`.
- cocotb's own `test_discovery` had this as known GHDL failures. The block `SAMPLE_BLOCK`, which GHDL reports in lower case, had `expect_error=AttributeError` for GHDL. Iteration found the block twice (`assert total_count == 10` for GHDL). The fix removes both special cases. The test now counts distinct objects, because iteration still lists an object once for each spelling it was looked up with (see [Python](#python)). With the updated tests, stock cocotb fails `access_block_vhdl` (`no attribute 'clk_inv'`) and `discover_all_in_component_vhdl` (`assert 10 == 9`).
- With VPI, when a name was not found, the generate fallback accepted any `vpiModule` with a matching name. GHDL represents a VHDL block as a `vpiModule`, so a block could be taken for a generate.

**A generate taken for its enclosing instance.** A pseudo-region borrows its parent's handle. The region/generate test compared the requested label with the name of that borrowed handle. Take a generate `U_SUB` inside the instance `u_sub`. The NVC build compared ignoring case, found the two names equal, and made the generate a region. NVC: `u_sub.U_SUB` was a `HierarchyObject`, not a `HierarchyArrayObject`.

**Names below a generate.** The pseudo-region holds the handle of the enclosing region, and the generate fallback cut the name at the index separator. So `gen(0)` below `gen` found an object, and `dut["gen(0)x"]` did not raise `KeyError` (NVC).

**Dotted names passed whole.** `dut["plain_blk.\\Foo\\"]` went to the simulator as one path, and the result was not checked. The simulator's own case rules applied to the whole path. Only `\foo\` and `\FOO\` exist there, yet the lookup did not raise `KeyError` (NVC and GHDL). The `_name` of the result was the whole dotted string.

**No check that the child is in the parent.** With VHPI, a child was looked up by its full path with no scope, and nothing checked that the result was declared in the parent. NVC resolves extended names along the path ignoring case, so a name looked up in `\BLK\` could return the child of its twin `\Blk\`. GHDL lowers the whole path, so a name looked up in `\Blk\` reaches the child of `\blk\` (see [GHDL](#ghdl-vpi-ghdl-build)).

**Backslashes on NVC.** In the source, a backslash inside an extended identifier is written twice (15.4.3). NVC writes it once, both in the names it reports and in the names it looks up. Stock cocotb passed names through unchanged. So the source name of one object (`\p\\q\`) was NVC's name for another (`\p\\\\q\`), and iteration reported names that are not source names. NVC examples:

- Iteration listed `\p\\q\` with the value of `\p\\\\q\`.
- `\G\\X\(1).X_Sig` gave the value from the generate `\G\\\\X\`.
- `\A\\B\` and `r.\M\\x\` were not found.

**Record fields.** Iteration and the record fallback took a field's name to be the text after the last `.` of its reported name. A field whose extended identifier contains `.` (`\f.x\`) became `x\`.

**Multi-dimensional arrays in records (VHPI).** A pseudo-handle read its pending indices after the length of the array's `vhpiCaseNameP`. For a record field that name includes the record (`r.m`), but the GPI name starts at the field (`m(0)`), so the indices were read at the wrong offset.

**Toplevel.** The toplevel name was compared with `strcmp` in VPI (GHDL) and FLI, and exactly in VHPI outside the NVC build. On GHDL, `get_root_handle(dut._name.upper())` returned `None`.

**Generate labels.** Outside the NVC build, label comparisons were case sensitive. The NVC build compared extended labels ignoring case. In Python, the `label__N` iteration pattern (used with the ALDEC build of VHPI) had no `re.IGNORECASE`, but the `label(N)` pattern next to it had. NVC: `dut["\\gen\\"]` matched the generate `\Gen\`, and `dut["\\GL\\"]` matched `\gl\`.

**Other failures.** On NVC, several tests that iterate the whole design failed with `maximum recursion depth exceeded`.

## The rules

The fix makes VHDL names follow four rules:

1. **Basic identifiers ignore case.** "Basic identifiers differing only in the use of corresponding uppercase and lowercase letters are considered the same" (IEEE 1076-2019, 15.4.2). Every spelling of a basic identifier gives the same object. The fix folds only ASCII letters. This is a deliberate limitation: non-ASCII letters in basic identifiers are compared exactly.
2. **Extended identifiers are exact.** `\Sig\` and `\SIG\` are distinct, and a backslash inside one is written twice (15.4.3). In cocotb, an extended identifier is written as in the source: `dut["\\a\\\\b\\"]` for `\a\\b\`.
3. **A name gives the object it names, or `KeyError`.** Never another object.
4. **One object, one handle.** This holds for every route: lookup in any spelling, a dotted name, or iteration of the parent.

With VHPI, the fix uses these properties:

- The Name property (`vhpiNameP`) keys objects and checks extended identifiers. It reports an extended identifier in its source form (19.4.3).
- CaseName (`vhpiCaseNameP`) is used for name comparisons: the region/generate test, generate labels, record fields and the toplevel.
- The full case name (`vhpiFullCaseNameP`) is used to check the parent. Its LRM form (19.4.7) is `:` region `:` ... `:` name.

Verilog names stay case sensitive. The fix does not change them.

## How the fix works

### Keys from the reported name

The handle store key of a VHDL object is now:

```
parent's key prefix + '\x1f' + the name the simulator reports for the object itself
```

`GpiHandleStore::set_key()` builds this key. It gets the reported name from the implementation through the new virtual `GpiImplInterface::get_key_name()`:

| Interface | Reported name |
|---|---|
| VHPI | `vhpiNameP` |
| VPI, GHDL build | `vpiName` |
| FLI | `mti_GetRegionName` / `mti_GetSignalName` / `mti_GetVarName`. For an index or field: the tail of the full name after the parent's, upper-cased unless it contains a backslash |
| other VPI builds | `""` (default): keep the full-name key |

The simulator reports one name per object, whatever spelling was used to reach it. So every spelling and every route give one key, and two distinct objects never share one. The root lookup passes no parent. Every other call that stores a handle passes the parent, so that the key can be built: lookup by name, from a raw handle, by index, and iteration.

The VHDL key is used for the root itself (no parent), and below a VHDL-keyed parent of the same implementation. In those cases the parent is the object the child is declared in. In all other cases the object and its children keep the full name as key, as in stock cocotb.

### Generate pseudo-regions

A pseudo-region has no name of its own. Its key is its label after a different separator, `'\x1e'`, and a basic label is upper-cased. A pseudo-region either borrows its parent's handle or owns one:

- **Borrowed handle** (VHPI, FLI, and GHDL when the label is not answered with an iteration). Its children are keyed under the parent's prefix, as if the pseudo-region were not there.
- **Own handle** (GHDL, when the label is answered with its first iteration). Its children are keyed under its own prefix: the parent's prefix + the reported name of that handle. They stay apart from the objects of the enclosing region.

A borrowed parent handle always makes a pseudo-region, whatever the names say (VHPI, FLI, GHDL). Without this rule, a generate label that is the parent's name in another case would look like the parent.

### Python

`handle.py` is almost unchanged. It relies on the GPI giving one `GpiObjHdl` per object. A `sim_obj` hashes and compares by that pointer. So two spellings that the GPI resolves to the same stored handle give the same Python object (`is`). `_sub_handles` is still keyed by the spelling. As a result:

- an object keeps `_name` and `_path` in the spelling it was first accessed with;
- an object first found by iteration has the name the simulator reports: as in the source, or in lower case for a basic identifier with GHDL;
- iterating a parent lists an object once for each spelling it has been looked up with, and every entry is the same object;
- a lookup with `GPIDiscovery.NATIVE` in a spelling not used before gives a separate handle of that object. The Python cache keeps that handle for that spelling, so a later lookup of the same name in that parent, also with `GPIDiscovery.AUTO`, returns it. Iterating the parent replaces it if the name is spelled as the simulator reports it. A dotted name is not replaced.

The only change in Python is that the `label__N` pattern now ignores case, like `label(N)`. It applies with every simulator, but it matters only where iterations are named `label__N` (the ALDEC build).

### Lookup

- **Dotted names** are split in the GPI (`gpi_get_handle_by_name()`) and resolved one name at a time, with both `GPIDiscovery.AUTO` and `GPIDiscovery.NATIVE`. A `.` inside an extended identifier does not separate names. An empty part gives no object. So `dut["blk.\\Sig\\"]` is the same object as `dut.blk["\\Sig\\"]`, and its `_name` is the last name. With `NATIVE`, the names in between are stored. The final result stays a separate handle, as before, but it gets a key, so its children are shared with `AUTO`.
- **Comparisons** use `vhdl_names_equal()`. For basic identifiers ASCII case is ignored. Names starting with `\` must be equal. Where it is used:
  - VHPI: `compare_names()`, on every build.
  - FLI: the toplevel, the region/generate test and generate labels.
  - GHDL's VPI: the toplevel and the region/generate test.
- **Generate labels** (VHPI and FLI): `compare_generate_labels(a, b)` now asks whether the region name `a`, without its index, is the label `b`. `b` is no longer cut at the index separator, so `gen(0)x` is not `gen`. The VPI version, which GHDL also uses, is unchanged.
- **Below a generate** no name is looked up (VHPI, FLI). Its iterations are reached by indexing it (`dut.gen[0]`), or by the iteration name in the enclosing region (`dut["gen(0)"]`). A name `label(i)` is accepted only if it is a generate iteration.
- **Array elements** are reached by indexing the array. With VHPI, `dut["data_in(0)"]` raises `KeyError`.

### Checking the simulator's answer

The fix does not trust the simulator's lookup. After the simulator returns an object, the GPI checks that it is the named object:

1. **Relative lookup (VHPI).** A child of a region is looked up relative to the region, with `vhpi_handle_by_name(leaf, region)`. The full name is used only if that fails.
2. **`declared_in` (VHPI).** The object's full name must be the region's full name + `:` + one more name. A `:` inside an extended identifier does not separate names. Only full names in the LRM form (starting with `:`) are checked. An object whose full name has another form is accepted without the check.
3. **`is_element` (VHPI).** For a name without a dot, the object must not be a selected or indexed name, that is, a part of another object.
4. **Record fields (VHPI).** A field is taken from the record's `vhpiSelectedNames` iterator and matched by its source field name. It is looked up by full name only when the fields cannot be iterated. Then its full name must start with the record's full name + `.` (`selected_from`). The same LRM-form rule as in `declared_in` applies.
5. **Exact extended identifiers (`vhdl_extended_mismatch()`).** For a requested extended identifier, the reported name must equal it. For record fields each interface does this differently:
   - VHPI compares the field name without the record prefix (`vhpi_field_name()`).
   - GHDL's VPI requires the reported name to end in `.` + the requested name.
   - FLI does not check record fields.

If a check fails, the GPI returns `NULL` and releases the VHPI or VPI handle. Python raises `KeyError`, or `AttributeError` for attribute access. The GPI does not fall back to another object. Iterating the parent finds such objects. After that, they are found by the name the simulator reports (for an extended identifier, its source name), one name at a time.

### Verilog names

Verilog behaviour is unchanged. Outside the GHDL build, the VPI code keeps the stock comparisons (`hdl_name != resolved_name`, and `strcmp` for the toplevel) and has no `get_key_name` override. So every Verilog object keeps its full-name key and is never VHDL-keyed, and a dotted Verilog name is never split. The `label[N]` pattern stays case sensitive. The new test `test_verilog_name_case` checks that `foo`/`FOO` and `sig`/`SIG` are distinct and that a name in the wrong case is not found.

## Design philosophy

**Exact object or `KeyError`.** A wrong object is worse than none. A test that reads or drives the wrong signal can pass silently. A `KeyError` is loud, and the user can work around it by iterating the parent or by indexing. So when the GPI cannot prove it has the named object, it returns none.

**The GPI checks the simulator's answer.** Simulators differ from the LRM in how they look names up (see below). The fix does not try to predict each one. Instead it checks the object that came back: where it is declared, whether it is a part of another object, and whether its reported name is the requested extended identifier. These checks (`declared_in`, `is_element`, the exact check) are generic. Simulator-specific branches remain in two cases. One is where a simulator reports names in another form (NVC backslashes, ALDEC iteration names). The other is where a result cannot be checked afterwards (GHDL's lower-case paths, and blocks reported as `vpiModule`).

**One key per object, from the simulator.** The key comes from the name the simulator reports for the object, not from the user's spelling. That name is unique among the objects of one parent. So the key is the same for every route, and the Python identity (`is`) follows from it. The case the simulator uses for a basic identifier in its Name property does not matter, as long as it is the same each time.

**No source parsing, no name guessing.** The GPI does not read the VHDL source. It does not try other spellings of a name the simulator did not find. It uses only what the simulator reports. Where a simulator writes names differently from the source (NVC backslashes), the GPI converts them to the source form.

**Scope kept to names.** The fix changes how names are keyed, compared and checked. It does not add access that the simulators lack (for example GHDL records or generate iterations). It does not change Verilog. In mixed-language designs, objects below an object of the other language keep the stock keys.

## Simulator-specific adjustments and exceptions

### NVC (VHPI, `NVC` build)

The fix removes both stock NVC branches: the case-insensitive `compare_names()` and the upper-casing in `fully_qualified_name()`. One NVC-specific behaviour is left: `vhpi_single_backslash()`, which is true only for NVC. All other NVC handling is generic code, or generic checks that catch NVC's behaviour.

**Extended identifiers matched ignoring case.**
- NVC: `vhpi_handle_by_name()` matches extended identifiers ignoring case and returns the first one declared (`\ext_sig\` gives `\Ext_Sig\`).
- Fix: the exact check rejects the result. The same check runs for generate iterations found by index.
- Limitation: if two extended identifiers in one region differ only in case (`\Foo\` and `\FOO\`), only the first one declared is found by name. The other one is found by iterating the parent, and after that by its name.

**Paths resolved ignoring case.**
- NVC: a full-name lookup matches extended names along the path ignoring case, so `:top:\BLK\:s` can give `s` of `\Blk\`.
- Fix: relative lookup in the region, then `declared_in`.

**A backslash written once.**
- NVC: it reports the source name `\a\\b\` as `\a\b\` and expects that form for lookup. So the reported name of one object can be the source name of another.
- Fix: two inverse conversions, active only for NVC. `vhpi_source_name()` doubles inner backslashes in reported names. `vhpi_lookup_name()` makes them single in names passed to `vhpi_handle_by_name()`. After that, all names are in source form, including the toplevel, generate labels and multi-dimensional array names.
- Limitation: a name written NVC's way (`\a\b\` meant as `\a\\b\`) raises `KeyError`, and as `COCOTB_TOPLEVEL` it is not found.
- A code comment says that NVC does this up to at least 1.23. A later release that writes the source form should be excluded by its version.

**Full names that look like record fields.**
- NVC: with one backslash, the full name of the signal `\r\\.\\f\` is `\r\.\f\`. That is also the full name of field `\f\` of record `\r\`, and NVC returns the field. Two fields can also get the same full name (`\x\\.\\in\` of a record, and `\in\` of its field `\x\`).
- Fix: for a name without a dot, `is_element` rejects a part of another object. Fields are taken from the field iterator and matched by source name. Iterated fields are named without the record prefix, also when the field name contains a `.`.
- Limitation: an object whose NVC name is the name of a record field raises `KeyError` until its parent is iterated.

**`:` or `.` inside an extended identifier.**
- NVC: it does not find such objects by name (a record field with `.` is found through the field iterator). It also does not find the iterations of a generate whose label contains `:` or `.`.
- Fix: no wrong object. A `:` or `.` inside an extended identifier is never taken as a separator (`declared_in`, `vhdl_is_dotted()`, `vhdl_is_label()`, the dotted-name split).
- Limitation: these objects are found only after iterating the parent.

**Case of basic identifiers.** All comparisons of basic identifiers ignore ASCII case, so the fix does not depend on the case NVC reports. A borrowed handle always makes a pseudo-region, whatever the names say.

**Tests.** `test_vhdl_handle_identity` lists the names NVC may miss before iteration (`NVC_NOT_FOUND`, and any name with `:`). The VHDL design uses a positional aggregate for one record, because NVC's analyser does not accept the field name `\x\\.\\in\` in a named aggregate.

### GHDL (VPI, `GHDL` build)

All GHDL branches are in `VpiImpl.cpp` / `VpiImpl.hpp` under `#ifdef GHDL`. This build supplies a key name (`vpiName`), so the shared code treats GHDL like any other VHDL interface. GHDL reports a basic identifier in lower case and an extended identifier as in the source.

**Region and toplevel names.** The region/generate test and the toplevel lookup use `vhdl_names_equal()` instead of a case-sensitive comparison. `dut.U_SUB` is the region `u_sub`, and the toplevel is found in any spelling.

**Lower-case lookup.**
- GHDL: `vpi_handle_by_name()` lowers the whole path, extended identifiers too, so `\Ext_Sig\` gives `\ext_sig\`.
- Fix: the exact check rejects a result whose `vpiName` is not the requested extended identifier. The parent part of the path is lowered too. So no name is looked up below a parent whose full name contains an extended identifier with an upper-case letter (`extended_upper()`). Otherwise `\Blk\.s` would give `\blk\.s`.
- Limitation: such an extended identifier, and the objects in it, are not found by name. After iteration, the objects in it are found by the name GHDL reports, one name at a time. A dotted name through them does not work.

**Blocks are `vpiModule`.** In the fallback for a name that is not found, only a `vpiGenScope` is taken for a generate. A name ending in `)` skips the fallback.

**Generates.**
- GHDL: it answers a generate label with the generate's first iteration, `label(i)`.
- Fix: for a label alone, that answer is accepted and made a pseudo-region that owns its handle. This also works for an extended label: `\gl\` is found, and `\GL\` raises `KeyError`.
- Exception to the general rule: a name below a generate is still looked up, and GHDL resolves it in the iteration it lists first. So `dut["gen.sig"]` is `sig` of `gen(0)`. With VHPI and FLI that lookup raises `KeyError`.
- Limitation: GHDL does not find generate iterations by name (`dut["gen(0)"]`), and it cannot access the iterations of a generate.

**Not changed by the fix.** GHDL does not give access to records or to the signals in generate iterations, and some two-dimensional arrays are not found. The tests skip those cases on GHDL. The GHDL path has the record-field form of the exact check, but the tests do not exercise it there.

### Other VHPI builds

The VHPI library is also built with the macros `ALDEC`, `MODELSIM` and `IUS`. This repository does not run these builds. The common VHPI changes apply to them too:

- `vhdl_names_equal()` in `compare_names()`, which was an exact comparison in these builds;
- the borrowed-handle pseudo-region rule;
- relative lookup, `declared_in` and `selected_from`;
- the field iterator;
- the exact check;
- the generate-label rules.

`vhpi_source_name()` and `vhpi_lookup_name()` do nothing in these builds.

ALDEC build (Riviera-PRO) only:

- The iteration separator is `__`, as in stock cocotb. Below a parent of this implementation, a basic `label__N` is an iteration name, so `dut["gen__0"]` is the iteration, not the generate. A basic VHDL identifier cannot contain `__`.
- A for-generate found by its own name is also kept as that iteration, and not made a pseudo-region, if the name is extended (`\Gen__0\`) or the parent is of another implementation.

The `MODELSIM` and `IUS` VHPI builds have no branch of their own in the fix.

### FLI

`FliImpl` (Questa/ModelSim FLI) applies the same rules. This repository only compiles it.

- The toplevel is matched with `vhdl_names_equal()`.
- A region is a pseudo-region if its name differs under VHDL rules, or if its handle is borrowed. The new `pseudo` flag marks a borrowed handle. It is set wherever the parent's handle is borrowed: in the name lookup and in the iterator.
- The key name is the reported leaf name. For an index or field, it is the tail of the full name after the parent's.
- No name is looked up below a pseudo-region of this implementation.
- The region search for a generate runs only for a label alone. An extended label must match exactly.
- A found object whose leaf name is not the requested extended identifier is rejected. A record field is the exception: it is not checked.

### Mixed-language designs

- Below an object of the other language, objects keep the stock full-name key, and so do their children. Another spelling can give a separate handle there.
- A dotted name is split only while the base is VHDL-keyed. Below a foreign parent the whole name goes to the implementation. With VHPI and FLI, a dotted name through a region (`inst["blk.sig"]`), or one starting with an extended identifier, can then raise `KeyError`. Look it up one name at a time (`inst.blk.sig`).
- Only a parent of the same implementation lends its handle to a generate pseudo-region. The record and generate fallbacks run only for such a parent.
- VHPI `get_child_from_handle()` is reached only for a foreign parent (during iteration). It converts the reported name with `vhpi_source_name()` (NVC backslashes).

### Verilog simulators

Unchanged; see [Verilog names](#verilog-names). Only the GHDL build of VPI has VHDL rules.

## What this repository runs

The tests run on free simulators, with both trees: `cocotb-fix/` and `cocotb-upstream/`.

| Simulator | Interface and build | Tests |
|---|---|---|
| NVC | VHPI, `NVC` build | `test_vhdl_handle_identity`, `test_discovery`, `test_vhdl_access` |
| GHDL | VPI, `GHDL` build | `test_vhdl_handle_identity`, `test_discovery`, `test_vhdl_access` |
| Icarus Verilog | VPI, `ICARUS` build | `test_verilog_name_case`, `test_discovery` |
| Verilator | VPI, `VERILATOR` build | `test_verilog_name_case`, `test_discovery` |

With the fix, all of these tests pass, and so does the rest of the cocotb regression (except one
GHDL test that also fails on stock cocotb). Icarus Verilog and Verilator give the same results on
both trees, as the code says: Verilog behaviour is unchanged. The numbers are in
[README.md](README.md#results).

This repository does not run the following parts of the fix, because no free simulator loads them. They are compiled with every cocotb build.

- the `ALDEC`, `MODELSIM` and `IUS` builds of VHPI;
- all of FLI;
- every branch for a parent of another implementation (mixed-language designs).

See [README.md](README.md) for how to run the tests.
