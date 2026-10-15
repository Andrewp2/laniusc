import shutil
import tempfile
import unittest
from pathlib import Path

from fixture_expectations import load_expectations
from fixture_sweep import check_jumps, failure_group, render_diff, render_stdlib_diff, run_elf
from x86_jump_check import jumps_leaving_function


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


class RunElfTests(unittest.TestCase):
    def test_each_program_runs_in_a_fresh_empty_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / "program"
            # Fails with exit 3 if it sees anything in its working directory.
            program.write_text("#!/bin/sh\n[ -z \"$(ls -A)\" ] || exit 3\nmkdir made\n")
            first, second = run_elf(program), run_elf(program)

            self.assertEqual((first["exit_code"], second["exit_code"]), (0, 0))
            self.assertEqual(sorted(p.name for p in Path(directory).iterdir()), ["program"])


@unittest.skipIf(shutil.which("objdump") is None, "needs objdump")
class JumpCheckTests(unittest.TestCase):
    def test_reports_a_jump_into_the_next_function_only(self):
        code = bytes.fromhex(
            "554889e5"  # 0x400078 function A: push rbp; mov rbp, rsp
            "7402"      # 0x40007c je 0x400080, inside A
            "9090"
            "740a"      # 0x400080 je 0x40008c, inside B
            "c9c3"
            "554889e5"  # 0x400084 function B
            "90909090"
            "c9c3")     # 0x40008c
        with tempfile.TemporaryDirectory() as directory:
            elf = Path(directory) / "program.elf"
            elf.write_bytes(bytes(0x78) + code)
            jumps = jumps_leaving_function(str(elf))

        self.assertEqual(jumps, [{"at": 0x400080, "op": "je", "target": 0x40008C, "function": 0x400078}])

    def test_a_bad_jump_fails_a_passing_fixture_and_annotates_a_failing_one(self):
        code = bytes.fromhex("554889e5" "740a" "c9c3" "554889e5" "90909090" "c9c3")
        with tempfile.TemporaryDirectory() as directory:
            elf = Path(directory) / "program.elf"
            elf.write_bytes(bytes(0x78) + code)
            passing, failing = result("a", "PASS"), result("b", "FAIL-EXIT", detail="got exit 3")
            check_jumps(elf, passing)
            check_jumps(elf, failing)

        self.assertEqual(passing["status"], "FAIL-JUMP")
        self.assertEqual(failure_group(passing), "jump leaves its function (run passed)")
        self.assertEqual((failing["status"], failing["bad_jumps"]), ("FAIL-EXIT", 1))

    def test_reports_a_frameless_leaf_jumping_to_its_own_entry(self):
        code = bytes.fromhex(
            "e807000000"    # 0x400078 call 0x400084 (main)
            "b83c000000"    # 0x40007d mov eax, 60
            "0f05"          # 0x400082 syscall
            "85ff"          # 0x400084 main, frameless: test edi, edi
            "74fc"          # 0x400086 je 0x400084, its own entry
            "7400"          # 0x400088 je 0x40008a, fine
            "c3")           # 0x40008a ret
        with tempfile.TemporaryDirectory() as directory:
            elf = Path(directory) / "program.elf"
            elf.write_bytes(bytes(0x78) + code)
            jumps = jumps_leaving_function(str(elf))

        self.assertEqual(jumps, [{"at": 0x400086, "op": "je", "target": 0x400084, "function": 0x400084,
                                  "entry": True}])


CLI_TEST = '''
fn laniusc_bin() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc")
}

fn traced_check(fixture: &str) -> (bool, String) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(fixture);
    let mut command = Command::new(laniusc_bin());
    command.arg("check").arg(&path).env("LANIUS_TRACE_CALL_INFERENCE", "1");
    let output = common::command_output_with_timeout(fixture, &mut command);
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    (output.status.success(), stderr)
}

#[test]
fn accepted() {
    let fixture = "tests/fixtures/stdlib_foundation/accepted.lani";
    let (passed, stderr) = traced_check(fixture);
    assert!(passed, "{fixture} failed to type check:\\n{stderr}");
}

#[test]
fn rejected() {
    let fixture = "tests/fixtures/stdlib_foundation/rejected.lani";
    let (passed, stderr) = traced_check(fixture);
    assert!(!passed, "{fixture} type checked:\\n{stderr}");
    assert!(stderr.contains("error[LNC0007]"), "expected an unknown type error:\\n{stderr}");
}
'''


class ExpectationTests(unittest.TestCase):
    def test_a_laniusc_check_command_test_owns_its_fixtures(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            fixtures = repo / "tests/fixtures/stdlib_foundation"
            fixtures.mkdir(parents=True)
            for name in ("accepted", "rejected", "unowned"):
                (fixtures / f"{name}.lani").write_text("fn main() -> i32 { return 0; }\n")
            (repo / "tests/cli_check.rs").write_text(CLI_TEST)
            expectations = {e.path.stem: e for e in load_expectations(repo)}

        accepted, rejected = expectations["accepted"], expectations["rejected"]
        self.assertEqual((accepted.kind, accepted.error_code), ("check_only", None))
        self.assertTrue(accepted.source.startswith("tests/cli_check.rs:"), accepted.source)
        self.assertEqual((rejected.kind, rejected.error_code), ("compile_error", "LNC0007"))
        self.assertEqual((expectations["unowned"].kind, expectations["unowned"].source), ("run", "default"))


if __name__ == "__main__":
    unittest.main()
