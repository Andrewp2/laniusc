#!/usr/bin/env python3
"""Compare a libtest log with tests/known_test_failures.txt.

usage: check_known_test_failures.py <test binary name> <log>...

Exits 1 when a test failed that the list does not name for that binary.
A listed test that passed is reported so its line can be removed; a listed
test that did not run is reported too, and neither changes the exit code.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIST = ROOT / "tests" / "known_test_failures.txt"


def known(binary):
    names = set()
    for line in LIST.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 2 and fields[0] == binary:
            names.add(fields[1])
    return names


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    binary = sys.argv[1]
    results = {}
    for path in sys.argv[2:]:
        for line in pathlib.Path(path).read_text(errors="replace").splitlines():
            match = re.search(r"\btest (\S+) \.\.\. (ok|FAILED|ignored)", line)
            if match:
                results[match.group(1)] = match.group(2)
    listed = known(binary)
    new = sorted(name for name, result in results.items() if result == "FAILED" and name not in listed)
    fixed = sorted(name for name in listed if results.get(name) == "ok")
    missing = sorted(name for name in listed if name not in results)
    for name in new:
        print(f"NEW FAILURE  {name}")
    for name in fixed:
        print(f"NOW PASSES   {name} (remove it from {LIST.name})")
    for name in missing:
        print(f"NOT RUN      {name}")
    failed = sum(result == "FAILED" for result in results.values())
    print(f"{binary}: {len(results)} results, {failed} failed, {len(new)} new, {len(fixed)} now pass")
    sys.exit(1 if new else 0)


if __name__ == "__main__":
    main()
