"""Accept a regression whose only failures are known ones that do not depend on the fix.

usage: known_failures.py <sim> <results.xml>
Exit status 0 if at least one test failed and every failed test is known for this simulator.
"""

import sys
import xml.etree.ElementTree as ET

# Failures that stock cocotb has too, with the same tools.
KNOWN = {
    # This GHDL reports a time precision of 1 fs (-15); the test expects 1 ps (-12).
    "ghdl": {"test_timer_with_units"},
}

sim, path = sys.argv[1:3]
failed = {
    c.get("name")
    for c in ET.parse(path).getroot().iter("testcase")
    if c.find("failure") is not None or c.find("error") is not None
}
known = KNOWN.get(sim, set())
if failed and failed <= known:
    print(f"    only known failures ({', '.join(sorted(failed))}), not caused by the fix: accepted")
    sys.exit(0)
sys.exit(1)
