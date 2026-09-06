#!/usr/bin/env python3
"""Focused isolation and trust checks for the fresh-module batch driver."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
PREFIX = "Lanius.Extraction.VerifiedFrontend.BatchFixture"


class BatchTests(unittest.TestCase):
    def run_batch(self, sources, final_name):
        with tempfile.TemporaryDirectory(prefix="lanius-batch-test-") as directory:
            root = Path(directory)
            for name, source in sources.items():
                path = root / (name.replace(".", "/") + ".lean")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            config = root / "manifest.json"
            config.write_text(json.dumps({
                "root": str(root), "shared": ["Lean"], "modules": list(sources),
                "finalName": final_name, "output": str(root / "objects"),
            }))
            result = subprocess.run(
                ["lake", "env", "lean", "-M", "12000", "--run",
                 "Lanius/Tools/SurfaceBatch.lean", str(config)],
                cwd=ROOT, capture_output=True, text=True, timeout=60)
            records = []
            for line in result.stdout.splitlines():
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
            return result, records

    def test_pristine_import_environment_isolation(self):
        a, b, c, d, final = [f"{PREFIX}.{name}" for name in "ABCDF"]
        result, records = self.run_batch({
            a: """import Lean
private def helper : Nat := 1
def batchValueA := helper
syntax "batch_lit" : term
macro_rules | `(batch_lit) => `(7)
""",
            b: """import Lean
run_cmd do
  if (← Lean.getEnv).contains `batchValueA then
    throwError "declaration leaked from previous module"
private def helper : Nat := 2
def batchValueB := helper
""",
            c: f"""import {a}
private def helper : Nat := 3
def batchValueC : Nat := batch_lit + helper
""",
            d: f"""import {a}
run_cmd do
  if (← Lean.getEnv).contains `batchValueC then
    throwError "declaration leaked into cached imported environment"
private def helper : Nat := 4
def batchValueD : Nat := batch_lit + helper
""",
            final: f"""import {a}
import {b}
import {c}
import {d}
theorem batchFinal : batchValueA + batchValueB + batchValueC + batchValueD = 24 := rfl
""",
        }, "batchFinal")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        timings = {row["module"]: row for row in records if "module" in row}
        self.assertTrue(timings[b]["import_env_cache_hit"])
        self.assertTrue(timings[d]["import_env_cache_hit"])
        self.assertFalse(timings[c]["import_env_cache_hit"])
        self.assertTrue(records[-1]["complete"])
        self.assertEqual(records[-1]["axioms"], [])

    def test_cache_hit_does_not_bypass_axiom_audit(self):
        a, b, final = [f"{PREFIX}.{name}" for name in ("Seed", "Bad", "Audit")]
        result, records = self.run_batch({
            a: "import Lean\ndef batchSeed : Nat := 0\n",
            b: "import Lean\naxiom batchUntrusted : False\n",
            final: f"import {b}\ntheorem batchBadFinal : False := batchUntrusted\n",
        }, "batchBadFinal")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected axiom: batchUntrusted", result.stdout + result.stderr)
        self.assertTrue(next(row for row in records if row.get("module") == b)
                        ["import_env_cache_hit"])
        self.assertFalse(any(row.get("complete") for row in records))


if __name__ == "__main__":
    unittest.main()
