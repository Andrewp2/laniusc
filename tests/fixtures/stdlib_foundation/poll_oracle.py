"""Independent select.poll oracle; all storage and readiness production is Lanius."""
import os
import resource
import select
import socket
import struct
import subprocess
import sys
import tempfile

executable = sys.argv[1]
owned = []
sockets = []


def pipe():
    reader, writer = os.pipe2(os.O_CLOEXEC | os.O_NONBLOCK)
    owned.extend((reader, writer))
    return reader, writer


def close(fd):
    os.close(fd)
    owned.remove(fd)


def check(requests):
    expected = []
    for fd, events in requests:
        if fd < 0:
            expected.append(0)
        else:
            oracle = select.poll()
            oracle.register(fd, events)
            observed = oracle.poll(0)
            expected.append(observed[0][1] if observed else 0)
    payload = struct.pack("<I", len(requests)) + b"".join(
        struct.pack("<iI", *request) for request in requests
    )
    inherited = sorted({fd for fd, _ in requests if 0 <= fd < 2147483647})
    actual = subprocess.run(
        [executable], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        pass_fds=inherited, timeout=5, check=False,
    )
    assert actual.returncode == 0 and not actual.stderr, actual
    assert len(actual.stdout) == 4 * (len(requests) + 1), actual.stdout
    result = struct.unpack("<" + "I" * (len(requests) + 1), actual.stdout)
    assert result[0] == sum(value != 0 for value in expected), (result, expected)
    assert result[1:] == tuple(expected), (result, expected)


try:
    empty_r, empty_w = pipe()
    ready_r, ready_w = pipe()
    os.write(ready_w, b"buffered")
    close(ready_w)
    broken_r, broken_w = pipe()
    close(broken_r)
    left, right = socket.socketpair()
    sockets.extend((left, right))
    right.sendall(b"buffered")
    right.shutdown(socket.SHUT_WR)
    with tempfile.TemporaryFile() as regular:
        regular.write(b"regular")
        regular.flush()
        descriptors = [empty_r, empty_w, ready_r, broken_w, left.fileno(), right.fileno(), regular.fileno(), -1, -2147483648, 2147483647]
        requests = [(fd, mask) for mask in (0, 1, 2, 4, 8192, 8199) for fd in descriptors]
        check([])
        check(requests)
        # Thousands of duplicate entries check record indexing/counts without
        # depending on a large number of available host file descriptors.
        size = min(4096, resource.getrlimit(resource.RLIMIT_NOFILE)[0])
        check([requests[index % len(requests)] for index in range(size)])
finally:
    for connection in sockets:
        connection.close()
    for fd in owned:
        os.close(fd)
