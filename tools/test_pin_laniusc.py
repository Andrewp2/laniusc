#!/usr/bin/env python3
"""Tests for tools/pin_laniusc.py with a fake compiler (no build, no GPU)."""
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from pin_laniusc import PinError, pin  # noqa: E402

# Reports the digest from $LANIUS_SHADER_ARTIFACT_ROOT/artifacts.env, falling back to the
# build directory baked into it, like the real `laniusc --version`.
FAKE_LANIUSC = """#!{python}
import os, pathlib, sys
root = {honor} and os.environ.get("LANIUS_SHADER_ARTIFACT_ROOT") or {build_root!r}
try:
    fields = dict(line.split("=", 1) for line in (pathlib.Path(root) / "artifacts.env").read_text().splitlines())
except OSError:
    fields = {{}}
print("laniusc 0.1.0")
print("shader-artifact-digest: " + fields.get("digest", "unknown"))
"""


class PinTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.target = pathlib.Path(self.tmp.name) / "target"
        self.shaders = self.target / "laniusc-shader-artifacts" / "release" / "shaders"
        (self.shaders / "type_checker").mkdir(parents=True)
        (self.shaders / "type_checker" / "a.spv").write_bytes(b"\x03\x02\x23\x07kernel-a")
        (self.shaders / "type_checker" / "a.reflect.json").write_text("{}")
        (self.shaders / "artifacts.env").write_text("digest=aaaa1111\ncount=1\n")
        self.out = pathlib.Path(self.tmp.name) / "pins"
        self.write_binary(honor=True)

    def tearDown(self):
        self.tmp.cleanup()

    def write_binary(self, honor: bool):
        binary = self.target / "release" / "laniusc"
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text(FAKE_LANIUSC.format(python=sys.executable, honor=honor, build_root=str(self.shaders)))
        binary.chmod(0o755)
        # The binary is linked after its kernels are written.
        later = time.time() + 5
        os.utime(binary, (later, later))

    def version(self, wrapper: pathlib.Path) -> str:
        env = {key: value for key, value in os.environ.items() if key != "LANIUS_SHADER_ARTIFACT_ROOT"}
        stdout = subprocess.run([str(wrapper), "--version"], capture_output=True, text=True, env=env).stdout
        return dict(line.split(": ", 1) for line in stdout.splitlines() if ": " in line)["shader-artifact-digest"]

    def test_wrapper_reports_the_snapshot_digest_after_a_rebuild(self):
        wrapper = pin(self.target, "release", self.out)
        self.assertEqual(wrapper, self.out / "aaaa1111" / "laniusc")
        self.assertEqual(self.version(wrapper), "aaaa1111")
        # A later build rewrites the shared kernels; the pin keeps its own.
        (self.shaders / "artifacts.env").write_text("digest=bbbb2222\ncount=1\n")
        self.assertEqual(self.version(self.target / "release" / "laniusc"), "bbbb2222")
        self.assertEqual(self.version(wrapper), "aaaa1111")

    def test_pinning_the_same_build_again_reuses_the_snapshot(self):
        first = pin(self.target, "release", self.out)
        self.assertEqual(pin(self.target, "release", self.out), first)
        self.assertEqual(sorted(path.name for path in self.out.iterdir()), ["aaaa1111"])

    def test_refuses_kernels_newer_than_the_binary(self):
        later = time.time() + 60
        os.utime(self.shaders / "type_checker" / "a.spv", (later, later))
        with self.assertRaisesRegex(PinError, "newer than"):
            pin(self.target, "release", self.out)

    def test_refuses_a_binary_that_ignores_the_override(self):
        self.write_binary(honor=False)
        with self.assertRaisesRegex(PinError, "ignores LANIUS_SHADER_ARTIFACT_ROOT"):
            pin(self.target, "release", self.out)
        self.assertFalse(any(self.out.iterdir()), "a refused pin leaves no snapshot")


if __name__ == "__main__":
    unittest.main()
