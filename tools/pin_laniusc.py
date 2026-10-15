#!/usr/bin/env python3
"""Pin a laniusc build: snapshot the binary together with the kernels it loads.

The compiler reads its SPIR-V kernels and their reflections from disk at run
time, from the directory its build wrote them to
(TARGET/laniusc-shader-artifacts/PROFILE/shaders). A copied binary therefore
runs whatever kernels a later build left there. This tool copies the binary and
that directory into OUT/DIGEST/ (DIGEST from the kernels' artifacts.env) and
writes OUT/DIGEST/laniusc, a wrapper that sets LANIUS_SHADER_ARTIFACT_ROOT to
the copied kernels and execs the copied binary. Use the wrapper wherever a
laniusc path is expected; its `--version` reports the snapshot's digest.

usage:
  tools/pin_laniusc.py [--target-dir DIR] [--profile release] [--out DIR]

It prints the wrapper's path. By default it pins this checkout's own build
(TARGET is ./target, OUT is TARGET/laniusc-pins); pass the main checkout's
target directory to pin its integration build. Pinning the same build again
reuses the snapshot.

It refuses when a kernel or artifacts.env is newer than the binary (a build is
running, or a later build changed only kernels), when the kernels change while
they are copied, and when the binary ignores LANIUS_SHADER_ARTIFACT_ROOT (it
was built before the override existed, so a snapshot would not hold).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
OVERRIDE_ENV = "LANIUS_SHADER_ARTIFACT_ROOT"


class PinError(RuntimeError):
    pass


def read_env(path: pathlib.Path) -> dict[str, str]:
    fields = {}
    for line in path.read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep:
            fields[key] = value
    return fields


def tree_state(root: pathlib.Path) -> dict[str, tuple[int, int]]:
    """Relative path -> (size, mtime_ns) of every file below root."""
    state = {}
    for path in root.rglob("*"):
        if path.is_file():
            stat = path.stat()
            state[path.relative_to(root).as_posix()] = (stat.st_size, stat.st_mtime_ns)
    return state


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def version_digest(command: list[str], env: dict[str, str]) -> str | None:
    completed = subprocess.run([*command, "--version"], capture_output=True, text=True, timeout=60, env=env)
    for line in completed.stdout.splitlines():
        key, sep, value = line.partition(":")
        if sep and key.strip() == "shader-artifact-digest":
            return value.strip()
    return None


def write_wrapper(path: pathlib.Path, binary: pathlib.Path, shaders: pathlib.Path, digest: str) -> None:
    def quote(value: pathlib.Path) -> str:
        return "'" + str(value).replace("'", "'\\''") + "'"

    path.write_text(
        "#!/bin/sh\n"
        f"# laniusc pinned by tools/pin_laniusc.py: this binary with the kernels it was built with ({digest}).\n"
        f"{OVERRIDE_ENV}={quote(shaders)}\n"
        f"export {OVERRIDE_ENV}\n"
        f"exec {quote(binary)} \"$@\"\n"
    )
    path.chmod(0o755)


def pin(target_dir: pathlib.Path, profile: str, out: pathlib.Path) -> pathlib.Path:
    binary = target_dir / profile / "laniusc"
    shaders = target_dir / "laniusc-shader-artifacts" / profile / "shaders"
    env_path = shaders / "artifacts.env"
    if not binary.is_file():
        raise PinError(f"no compiler binary at {binary}")
    if not env_path.is_file():
        raise PinError(f"no kernel metadata at {env_path}")
    digest = read_env(env_path).get("digest")
    if not digest:
        raise PinError(f"{env_path} names no digest")
    binary_mtime = binary.stat().st_mtime_ns
    before = tree_state(shaders)
    newer = sorted(name for name, (_, mtime) in before.items() if mtime > binary_mtime)
    if newer:
        raise PinError(f"{len(newer)} kernel files are newer than {binary} (a build is running, or a later "
                       f"build changed only kernels), e.g. {', '.join(newer[:3])}; rebuild or wait")
    binary_sha = sha256(binary)

    # Named by the kernels' digest; a different binary with the same kernels gets its hash appended.
    name = None
    for candidate in (digest, f"{digest}-{binary_sha[:12]}"):
        manifest = out / candidate / "pin.json"
        if manifest.is_file():
            if json.loads(manifest.read_text()).get("binary_sha256") == binary_sha:
                return out / candidate / "laniusc"
        elif not (out / candidate).exists():
            name = candidate
            break
    if name is None:
        raise PinError(f"{out / digest} and its hashed variant already hold other builds")
    final = out / name

    out.mkdir(parents=True, exist_ok=True)
    staging = pathlib.Path(tempfile.mkdtemp(prefix=f".{name}-", dir=out))
    try:
        (staging / "bin").mkdir()
        shutil.copy2(binary, staging / "bin" / "laniusc")
        shutil.copytree(shaders, staging / "shaders")
        if tree_state(shaders) != before or binary.stat().st_mtime_ns != binary_mtime:
            raise PinError("the build changed while it was being copied; try again")
        if sha256(staging / "bin" / "laniusc") != binary_sha:
            raise PinError("the copied binary differs from the source")

        # The binary must honor the override: pointed at an empty directory it
        # has no metadata to report. One built before the override reads the
        # build directory and would not stay pinned.
        with tempfile.TemporaryDirectory() as empty:
            ignored = version_digest([str(staging / "bin" / "laniusc")], {**os.environ, OVERRIDE_ENV: empty})
        if ignored not in (None, "unknown"):
            raise PinError(f"{binary} ignores {OVERRIDE_ENV} (it reports {ignored} with an empty override); "
                           "it predates the override, so its kernels cannot be pinned")

        pinned = version_digest([str(staging / "bin" / "laniusc")],
                                {**os.environ, OVERRIDE_ENV: str(staging / "shaders")})
        if pinned != digest:
            raise PinError(f"the copied binary reports {pinned} with the copied kernels, not {digest}")

        write_wrapper(staging / "laniusc", final / "bin" / "laniusc", final / "shaders", digest)
        (staging / "pin.json").write_text(json.dumps({
            "schema": "lanius.pin.v1",
            "digest": digest,
            "binary_sha256": binary_sha,
            "kernel_files": len(before),
            "source_binary": str(binary),
            "source_kernels": str(shaders),
            "source_binary_mtime": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(binary_mtime / 1e9)),
            "pinned_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }, indent=1) + "\n")
        staging.rename(final)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    wrapper = final / "laniusc"
    reported = version_digest([str(wrapper)], {key: value for key, value in os.environ.items() if key != OVERRIDE_ENV})
    if reported != digest:
        shutil.rmtree(final, ignore_errors=True)
        raise PinError(f"{wrapper} --version reports {reported}, not the snapshot's {digest}")
    return wrapper


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--target-dir", default=str(ROOT / "target"),
                        help="cargo target directory holding the build (default: this checkout's)")
    parser.add_argument("--profile", default="release")
    parser.add_argument("--out", help="snapshot directory (default: TARGET/laniusc-pins)")
    args = parser.parse_args()
    target_dir = pathlib.Path(args.target_dir).resolve()
    out = pathlib.Path(args.out).resolve() if args.out else target_dir / "laniusc-pins"
    try:
        print(pin(target_dir, args.profile, out))
    except PinError as error:
        print(f"pin_laniusc: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
