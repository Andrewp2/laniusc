#!/usr/bin/env python3
"""Test-only group peer. READY follows a real grandchild pipe barrier."""
import os
import signal
import struct
import sys

MAGIC = 0x47525031
ACK = 0x41434B31


def write(data):
    while data:
        n = os.write(1, data)
        assert n > 0
        data = data[n:]


def acknowledged(_signal, _frame):
    write(struct.pack("<2i", ACK, os.getpid()))


def main():
    mode = int(sys.argv[1])
    parent_group = os.getpgid(os.getppid())
    signal.alarm(20)
    signal.signal(signal.SIGUSR1, acknowledged)
    ready_read, ready_write = os.pipe()
    control_read, control_write = os.pipe()
    grandchild = os.fork()
    if grandchild == 0:
        os.close(ready_read)
        os.close(control_write)
        signal.alarm(20)
        os.write(ready_write, b"R")
        os.close(ready_write)
        # EOF after leader exit deliberately retains stdout, until signaled.
        if os.read(control_read, 1) == b"Q":
            os._exit(0)
        os.close(control_read)
        while True:
            signal.pause()
    os.close(ready_write)
    os.close(control_read)
    assert os.read(ready_read, 1) == b"R"
    os.close(ready_read)
    write(struct.pack("<6i", MAGIC, os.getpid(), os.getpgrp(), os.getsid(0), grandchild, os.getpgid(grandchild)))
    if mode == 7:
        os._exit(23)
    if mode == 8:
        os.write(control_write, b"Q")
        assert os.waitpid(grandchild, 0)[1] == 0
        os._exit(23)
    while True:
        command = os.read(0, 1)
        if command == b"M":
            os.setpgid(0, parent_group)
            write(struct.pack("<2i", MAGIC, os.getpgrp()))
        elif command == b"E":
            os._exit(23)
        elif command == b"Q":
            os.write(control_write, b"Q")
            assert os.waitpid(grandchild, 0)[1] == 0
            os._exit(0)
        elif not command:
            # Loss of the fixture must not create a permanent helper process.
            os.kill(grandchild, signal.SIGKILL)
            os.waitpid(grandchild, 0)
            os._exit(0)
        else:
            raise AssertionError(command)


if __name__ == "__main__":
    main()
