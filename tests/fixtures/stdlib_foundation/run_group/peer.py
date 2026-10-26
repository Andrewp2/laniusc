#!/usr/bin/env python3
"""Test-only process peers; production supervision runs in Lanius."""
import os
import signal
import sys
import time


def mark(path, role, event):
    record = f"{role},{os.getpid()},{os.getpgrp()},{os.getppid()},{event}\n".encode()
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        assert os.write(descriptor, record) == len(record)
    finally:
        os.close(descriptor)


def quiet():
    # Escaped/orphan peers must not hold the independent oracle's output pipes.
    for descriptor in (0, 1, 2):
        try:
            os.close(descriptor)
        except OSError:
            pass


def wait_forever():
    while True:
        time.sleep(0.02)


def main():
    mode, path = sys.argv[1:3]
    if mode == "identity":
        assert os.read(0, 1) == b""
        os.write(1, f"{os.getpid()},{os.getpgrp()},{os.getppid()}\n".encode())
        return int(sys.argv[3])
    if mode == "arguments":
        assert os.read(0, 1) == b""
        os.write(1, b"\x00".join(os.fsencode(value) for value in sys.argv[3:]))
        os.write(2, os.environ["RUN_GROUP_TEST"].encode())
        return 0
    if mode == "solo":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        mark(path, "leader", "ready")
        quiet()
        wait_forever()

    ready_read, ready_write = os.pipe()
    leader = os.getpid()

    def handler(role, code):
        def terminate(number, frame):
            mark(path, role, "term")
            os._exit(code)

        return terminate

    if mode == "cooperate":
        signal.signal(signal.SIGTERM, handler("leader", 0))
    elif mode == "leader-exits":
        signal.signal(signal.SIGTERM, handler("leader", 23))
    else:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = os.fork()
    if child == 0:
        os.close(ready_read)
        if mode == "escape":
            os.setsid()
        if mode == "cooperate":
            signal.signal(signal.SIGTERM, handler("member", 0))
        else:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        mark(path, "member", "ready")
        quiet()
        assert os.write(ready_write, b"R") == 1
        os.close(ready_write)
        wait_forever()
    os.close(ready_write)
    assert os.read(ready_read, 1) == b"R"
    os.close(ready_read)
    if mode == "moved-leader":
        # The oracle opens this gate only after the supervisor's first normal
        # WNOHANG wait, which proves launch/group confirmation has returned.
        while not os.path.exists(sys.argv[3]):
            time.sleep(0.001)
        os.setpgid(0, os.getpgid(os.getppid()))
    mark(path, "leader", "ready")
    quiet()
    if mode == "normal-orphan":
        return 7
    assert os.getpid() == leader
    wait_forever()


if __name__ == "__main__":
    sys.exit(main())
