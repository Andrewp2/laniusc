#!/usr/bin/env python3
"""Build Surface certificates in dependency order, one Lean process at a time.

Lake's -Kjobs option is a package configuration value, not a concurrency limit.
Visiting local dependencies first prevents independent heavy certificates from
compiling concurrently. Existing Lake build artifacts are reused.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent
IMPORT = re.compile(r"^(?:(?:public|private)\s+)?import\s+([^\n]+)", re.MULTILINE)


def dependency_order(targets):
    ordered, visited, active = [], set(), set()

    def visit(module):
        if module in active:
            raise ValueError(f"cyclic local import: {module}")
        if module in visited:
            return
        path = ROOT / (module.replace(".", "/") + ".lean")
        if not path.is_file():
            return  # Lean and package dependencies are resolved by Lake.
        active.add(module)
        for imported in IMPORT.findall(path.read_text()):
            for dependency in imported.split("--", 1)[0].split():
                visit(dependency)
        active.remove(module)
        visited.add(module)
        ordered.append(module)

    for target in targets:
        visit(target)
    return ordered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="*", default=[
        "Lanius.Extraction.KernelReductionTests",
        "Lanius.Extraction.VerifiedFrontend.Surface.Data",
    ])
    parser.add_argument("--list", action="store_true", help="list the build order")
    args = parser.parse_args()
    modules = dependency_order(args.targets)
    if args.list:
        print("\n".join(modules))
        return 0
    # Include explicit targets even if they are not local modules, so a typo
    # fails through Lake instead of silently producing an empty successful run.
    for module in modules + [t for t in args.targets if t not in modules]:
        result = subprocess.run(["lake", "build", module], cwd=ROOT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            print(result.stdout, end="", flush=True)
            return result.returncode
        for line in result.stdout.splitlines():
            if "Built " in line:
                print(line, flush=True)
    print(f"Checked {len(modules)} local modules in dependency order.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
