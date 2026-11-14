"""Summarize one results.xml: one line of counts, then one line per failed test.

usage: summary.py <tree> <sim> <test> <results.xml> <make exit status>
Exit status 0 if the file exists and no test failed.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

tree, sim, test, path, rc = sys.argv[1:6]
head = f"{tree:<8} {sim:<9} {test:<26}"
if not Path(path).is_file():
    print(f"{head} NO RESULT (make exit {rc}, see {Path(path).parent / 'log'})")
    sys.exit(1)

cases = list(ET.parse(path).getroot().iter("testcase"))
failed = [c for c in cases if c.find("failure") is not None or c.find("error") is not None]
skipped = [c for c in cases if c.find("skipped") is not None]
passed = len(cases) - len(failed) - len(skipped)
print(f"{head} {len(cases):3} tests  {passed:3} passed  {len(failed):3} failed  {len(skipped):3} skipped")
for c in failed:
    f = c.find("failure")
    if f is None:
        f = c.find("error")
    msg = " ".join((f.get("message") or "").split())
    print(f"    FAIL {c.get('name')}: {msg[:200]}")
sys.exit(1 if failed else 0)
