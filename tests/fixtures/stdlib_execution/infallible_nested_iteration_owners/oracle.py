"""Narrow ordinary-adapter owner gate, reusing accepted raw owner machinery."""
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
OWNERS = load("accepted_try_nested_owner_helpers", HERE.parent / "nested_iteration_owners/oracle.py")
SOURCE, TRUSTED = OWNERS.SOURCE, OWNERS.TRUSTED
FIELDS = ("magic", "pid", "phase", "backend", "flavor", "mode", "status", "received", "outer", "inner",
          "retire", "maps", "active", "remaining", "held", "ready", "scratch_freed", "backing_freed", "label_freed",
          "outer_bytes", "inner_bytes", "reserved")
MAGIC, WORDS = 1313420322, 22


def owner_sizes(values):
    phase = values["phase"]
    if phase == 0:
        return sorted([values["outer_bytes"]] + [values["inner_bytes"]] * 3 + [5] * 3 + [8] * 6 + [4] * 3)
    if phase == 1 and values["mode"] == 1:
        return sorted([values["outer_bytes"]] + [values["inner_bytes"]] * 2 + [5] * 2 + [8] * 6 + [4])
    if phase == 1:
        return sorted([values["outer_bytes"], 8])
    return [8] if phase == 2 else []


def check_frame(values, phase, backend, flavor, mode):
    assert (values["magic"], values["phase"], values["backend"], values["flavor"], values["mode"], values["status"], values["ready"], values["reserved"]) == (MAGIC, phase, backend, flavor, mode, 0, 1, 0)
    assert values["inner_bytes"] > 0
    keys = ("received", "outer", "inner", "retire", "maps", "active", "remaining", "held", "scratch_freed", "backing_freed", "label_freed")
    if phase == 0:
        expected = (0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0)
    elif phase == 1 and mode == 1:
        expected = (1, 2, 2, 1, 2 if flavor else 0, 1, 1, 8, 1, 1, 2)
    else:
        expected = (6, 4, 6 if mode and phase >= 2 else 9, 3, 3 if flavor else 0, 0, 0, 0 if phase == 3 else 8, 3, 3, 3)
    assert tuple(values[key] for key in keys) == expected, (values, expected)
    assert (values["outer_bytes"] > 0) == (phase < 2)


def no_new_allocations(before, after):
    assert after["source"]["attempts"] == before["source"]["attempts"], "ordinary traversal/lifecycle/callback allocated after setup"


def run(executable):
    directory = Path(tempfile.mkdtemp(prefix="infallible-nested-owners-"))
    authority = OWNERS.profile(executable, directory)
    deadline, cases = time.monotonic() + 75, 0
    print(f"evidence={directory}", flush=True)
    for backend in (0, 1):
        for flavor in (0, 1):
            for mode in (0, 1):
                case = directory / f"b{backend}-f{flavor}-m{mode}"
                case.mkdir()
                trace = case / "syscalls.log"
                command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
                           "-e", "trace=" + OWNERS.TRACE, "-o", str(trace), str(Path(executable).resolve())]
                (case / "command.txt").write_text(repr(command) + "\n")
                request = struct.pack("<3I", backend, flavor, mode)
                (case / "request.bin").write_bytes(request)
                process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
                limit, output, snapshots, admitted = min(deadline, time.monotonic() + 8), bytearray(), [], set()
                try:
                    assert os.write(process.stdin.fileno(), request) == len(request)
                    for phase in range(4):
                        raw = OWNERS.read_exact(process.stdout, WORDS * 8, limit)
                        output.extend(raw)
                        values = dict(zip(FIELDS, struct.unpack("<22Q", raw)))
                        check_frame(values, phase, backend, flavor, mode)
                        pid = values["pid"]
                        assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(pid)]
                        parsed = OWNERS.analyze(OWNERS.prefix(trace, bytes(output), limit), authority, case, final=phase == 3)
                        live = parsed["source"]["live"]
                        assert sorted(live.values()) == owner_sizes(values), ("live owner partition", values, live)
                        maps = SOURCE.process_owners(pid, live)
                        admitted.update(live)
                        if phase:
                            no_new_allocations(snapshots[0], parsed)
                        if phase == 3:
                            assert all(not any(low <= pointer < high for low, high in maps) for pointer in admitted), "released source mapping persists before exit"
                        snapshots.append(parsed)
                        assert os.write(process.stdin.fileno(), b"A") == 1
                    process.stdin.close()
                    process.stdin = None
                    rest, stderr = process.communicate(timeout=max(0.01, limit - time.monotonic()))
                    final = OWNERS.analyze(trace.read_text(), authority, case, final=True)
                    assert process.returncode == 0 and not rest and stderr == final["markers"], (process.returncode, rest, stderr)
                    assert len(final["events"]) == len(snapshots[-1]["events"]) + 1 and final["events"][-1]["name"] == "read"
                    no_new_allocations(snapshots[0], final)
                    assert OWNERS.traversal(final) == OWNERS.source_order(flavor, 2 if mode else 0)
                    OWNERS.causal_empty_retirement(final)
                    assert sum(scope["name"] == "C" for scope in final["scopes"]) == 1
                    (case / "stdout.bin").write_bytes(output)
                    (case / "stderr.bin").write_bytes(stderr)
                    cases += 1
                except BaseException:
                    (case / "stdout-prefix.bin").write_bytes(output)
                    if process.poll() is None:
                        process.kill()
                    out, error = process.communicate(timeout=3)
                    (case / "remaining-stdout.bin").write_bytes(out)
                    (case / "stderr.bin").write_bytes(error)
                    raise
    assert cases == 8
    print(f"PASS infallible-nested-owners cases={cases} reached-oom=0")


def controls():
    count = SOURCE.controls()
    for phase, mode, owners in ((0, 0, 16), (1, 0, 2), (1, 1, 12), (2, 1, 1), (3, 0, 0)):
        values = dict(phase=phase, mode=mode, outer_bytes=321, inner_bytes=87)
        assert len(owner_sizes(values)) == owners
        count += 1
    before = dict(source=dict(attempts=[dict(ip=0x401002, length=8)]))
    no_new_allocations(before, before)
    count += 1
    for changed in ([dict(ip=0x401002, length=8), dict(ip=0x401002, length=5)], [dict(ip=0x401003, length=8)]):
        try:
            no_new_allocations(before, dict(source=dict(attempts=changed)))
        except AssertionError:
            count += 1
        else:
            raise AssertionError("ordinary owner oracle accepted post-setup heap/source mutation")
    print(f"PASS infallible-nested-owners CPU controls={count}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        assert len(sys.argv) == 2
        run(sys.argv[1])
