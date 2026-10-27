"""Small ACK runner for the connected DNS/TLS probes; no ELF scanner fork."""
from collections import Counter
import os
from pathlib import Path
import struct
import subprocess
import time

from oracle import FRAME, MAGIC, NATIVE, SOURCE, TRUSTED, exact_read, exchange_events, memory, raw_events


def probe(executable, arguments, directory, inspect, *, environment=None):
    directory.mkdir()
    trace = directory / "syscalls.log"
    profile = NATIVE.verified_sites(executable, directory)
    env = dict(os.environ, **(environment or {}))
    process = subprocess.Popen(["strace", "--kill-on-exit", "-qq", "-xx", "-s", "65536", "-i",
                                "-e", "signal=none", "-e", "trace=all", "-o", str(trace), str(executable), *[os.fspath(value) if isinstance(value, os.PathLike) else value for value in arguments]],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, restore_signals=True)
    observed, frames = bytearray(), []
    deadline = time.monotonic() + 12
    try:
        for tag in range(3):
            frame = exact_read(process.stdout, FRAME, deadline)
            observed.extend(frame)
            words = struct.unpack("<16Q", frame)
            assert words[:2] == (MAGIC, tag), words
            while True:
                try:
                    prefix = SOURCE.output_prefix(trace.read_text(), bytes(observed))
                    break
                except SOURCE.CheckpointPending:
                    assert time.monotonic() < deadline, "checkpoint missing from full trace"
                    time.sleep(0.005)
            state = SOURCE.source(memory(prefix), profile)
            children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
            assert len(children) == 1, children
            SOURCE.process_owners(int(children[0]), state["live"])
            assert bool(state["live"]) == (tag != 2), (tag, state)
            inspect(tag, words, prefix, profile)
            frames.append(words)
            process.stdin.write(b"+")
            process.stdin.flush()
        process.stdin.close()
        process.wait(timeout=max(0.1, deadline - time.monotonic()))
        stderr, tail = process.stderr.read(), process.stdout.read()
        assert process.returncode == 0 and stderr == b"BbDd" and tail == b"", (process.returncode, stderr, tail)
        full = trace.read_text()
        TRUSTED.source_maps(memory(full), profile, directory)
        return frames, exchange_events(raw_events(SOURCE.output_prefix(full, bytes(observed)), profile))
    except BaseException:
        process.kill()
        process.wait(timeout=2)
        raise


def connection_chain(active, attempts, *, plaintext=None):
    """Bind fd generations, failed-attempt retirement and one selected owner."""
    generations, live, opened, connected, sent, closed, uses = Counter(), {}, [], [], [], [], []
    for item in active:
        name, answer = item["name"], item["result"].split()[0]
        if name == "socket":
            assert answer.isdecimal(), item
            fd = int(answer)
            assert fd not in live, (item, live)
            generations[fd] += 1
            key = fd, generations[fd]
            live[fd] = key
            opened.append((key, item))
        elif name in {"connect", "getpeername", "getsockopt", "fcntl", "close", "sendto", "recvfrom", "shutdown"}:
            fd = int(TRUSTED.arguments(item["args"])[0])
            assert fd in live, ("network use outside owned generation", item, live)
            key = live[fd]
            uses.append((key, item))
            if name == "connect":
                connected.append((key, item))
            elif name == "sendto":
                sent.append((key, item))
            elif name == "close":
                assert answer == "0", item
                closed.append((key, item))
                del live[fd]
    assert len(opened) == len(connected) == len(closed) == attempts and not live, (opened, connected, closed, live)
    assert [key for key, _ in opened] == [key for key, _ in connected] == [key for key, _ in closed]
    selected = opened[-1][0]
    for index in range(attempts - 1):
        assert closed[index][1]["index"] < opened[index + 1][1]["index"], "attempt fd not retired before fallback"
    assert all(key == selected for key, _ in sent), "request replayed to failed endpoint"
    assert len([item for key, item in uses if key == selected and item["name"] == "getpeername" and item["result"] == "0"]) >= 2
    assert len([item for key, item in uses if key == selected and item["name"] == "fcntl" and "F_GETFL" in item["args"] and item["result"].isdecimal()]) == 1
    if plaintext is not None:
        confirmed = b"".join(TRUSTED.quoted(TRUSTED.arguments(item["args"])[1])[:int(item["result"])]
                             for _, item in sent if item["result"].isdecimal())
        assert confirmed == plaintext, (confirmed, plaintext)
    return selected
