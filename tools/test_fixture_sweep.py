import unittest

from fixture_sweep import failure_group, render_diff, render_stdlib_diff


def result(name: str, status: str, **fields) -> dict:
    return {"name": name, "status": status, "suite": "stdlib_foundation", "expected": {}, **fields}


def documents(digest: str) -> list:
    return [(None, {"laniusc_version": {"shader-artifact-digest": digest}})]


class FailureGroupTests(unittest.TestCase):
    def test_scalar_conversions_group_apart_from_other_type_errors(self):
        cast = result("a", "FAIL-COMPILE", code="LNC0006", source_line="let a: u32 = left as u32;")
        implicit = result("b", "FAIL-COMPILE", code="LNC0006", source_line="let byte: u8 = ascii;")
        other = result("c", "FAIL-COMPILE", code="LNC0006", source_line="return x;")

        self.assertEqual(failure_group(cast), "compile error LNC0006, scalar conversion: `as` cast")
        self.assertEqual(failure_group(implicit),
                         "compile error LNC0006, scalar conversion: implicit (let with scalar annotation)")
        self.assertEqual(failure_group(other), "compile error LNC0006")


class DiffTests(unittest.TestCase):
    def test_diff_counts_fixed_broken_and_changed_fixtures(self):
        base = {
            "fixed": result("fixed", "FAIL-COMPILE", code="LNC0006", source_line="let a: u32 = left as u32;"),
            "broken": result("broken", "PASS"),
            "moved": result("moved", "FAIL-EXIT", detail="got exit None signal 11, want exit 0"),
            "same": result("same", "FAIL-COMPILE", code="LNC0017"),
            "gone": result("gone", "PASS"),
        }
        new = {
            "fixed": result("fixed", "PASS"),
            "broken": result("broken", "FAIL-COMPILE", code="LNC0047", location="x.lani:1:1", message="boom"),
            "moved": result("moved", "FAIL-COMPILE", code="LNC0017"),
            "same": result("same", "FAIL-COMPILE", code="LNC0017"),
            "added": result("added", "SKIPPED"),
        }

        text = "\n".join(render_diff(base, new, documents("aaaa"), documents("bbbb")))

        self.assertIn("Base `aaaa` (5 fixtures), new `bbbb` (5 fixtures).", text)
        self.assertIn("Passing (pass, compiled only or skipped): 2 -> 2. Newly passing 1, newly failing 1, "
                      "failing differently 1, fixtures added 1, fixtures removed 1.", text)
        self.assertIn("### compile error LNC0006, scalar conversion: `as` cast -> ok (1)", text)
        self.assertIn("### ok -> compile error LNC0047 (1)", text)
        self.assertIn("- `broken` x.lani:1:1: boom", text)
        self.assertIn("### wrong exit status -> compile error LNC0017 (1)", text)
        self.assertIn("### absent -> ok (1)", text)
        self.assertIn("### ok -> absent (1)", text)
        self.assertNotIn("`same`", text)
        self.assertIn("| compile error LNC0017 | 1 | 2 | +1 |", text)

    def test_stdlib_diff_lists_modules_that_changed(self):
        def summary(ok: list[str], failing: list[str]) -> dict:
            return {"check_status": "FAIL (exit 1)",
                    "modules_checked": [{"module": m, "ok": True} for m in ok]
                    + [{"module": m, "ok": False} for m in failing]}

        lines = render_stdlib_diff(summary(["core::a", "core::b"], ["core::c"]),
                                   summary(["core::a", "core::c"], ["core::b"]))

        self.assertIn("Modules that compile on their own: 2/3 -> 2/3; `laniusc check` over all modules: "
                      "FAIL (exit 1) -> FAIL (exit 1).", lines)
        self.assertIn("Newly compiling: `core::c`.", lines)
        self.assertIn("No longer compiling: `core::b`.", lines)
        self.assertEqual(render_stdlib_diff(None, summary([], [])), [])


if __name__ == "__main__":
    unittest.main()
