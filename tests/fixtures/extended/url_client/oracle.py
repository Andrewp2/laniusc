"""Finite connected URL clients against independent loopback HTTP peers.

The shared ELF verifier and live requested-byte ledger are imported unchanged.
Native loader/libc work is distinguished by verified raw instruction ranges;
all raw application syscalls remain visible under trace=all.
"""
import http.client
import importlib.util
import io
import os
from pathlib import Path
import re
import selectors
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOURCE = load("url_client_verified_live_source", HERE.parent / "archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
NATIVE = load("url_client_verified_native_sites", HERE.parents[1] / "native_c/source_allocations.py")
MAGIC, FRAME = 1431456844, 128
BODY = b"\x00\xff\r\n"
RAW_CALLS = {"mmap", "munmap", "rt_sigaction", "clock_gettime", "socket", "connect", "poll",
             "getsockopt", "getpeername", "fcntl", "close", "sendto", "recvfrom", "shutdown", "read", "write"}


def entries(text):
    result = []
    for line in SOURCE.completed(text).splitlines():
        match = TRUSTED.LINE.fullmatch(line)
        assert match, ("unsupported complete full-trace line", line)
        ip, name, args, answer = match.groups()
        result.append(dict(ip=int(ip, 16), name=name, args=args, result=answer, line=line, index=len(result)))
    return result


def raw_events(text, profile):
    ranges = profile[0].executable_ranges
    assert ranges and profile[0] and not profile[1], "verified raw source authority required"
    found = [item for item in entries(text) if NATIVE.classify(profile, item["ip"]) == "source"]
    assert all(item["name"] in RAW_CALLS for item in found), ("unexpected raw source effect", found)
    return found


def memory(text):
    return "".join(item["line"] + "\n" for item in entries(text) if item["name"] in ("mmap", "munmap"))


def exchange_events(found):
    begin = [item["index"] for item in found if item["name"] == "write" and item["args"] == '2, "\\x42", 1' and item["result"] == "1"]
    end = [item["index"] for item in found if item["name"] == "write" and item["args"] == '2, "\\x62", 1' and item["result"] == "1"]
    assert len(begin) == len(end) == 1 and begin[0] < end[0], (begin, end)
    return [item for item in found if begin[0] < item["index"] < end[0]]


def exact_read(stream, count, deadline):
    output = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(stream, selectors.EVENT_READ)
    try:
        while len(output) < count:
            left = deadline - time.monotonic()
            assert left > 0 and selector.select(left), ("probe checkpoint timeout", len(output), count)
            part = os.read(stream.fileno(), count - len(output))
            assert part, ("probe exited before checkpoint", len(output), count)
            output.extend(part)
    finally:
        selector.close()
    return bytes(output)


def request(connection, authority, target):
    connection.settimeout(5)
    pending = bytearray()
    while b"\r\n\r\n" not in pending:
        part = connection.recv(4096)
        assert part and len(pending) + len(part) <= 32768, pending
        pending.extend(part)
    head, body = bytes(pending).split(b"\r\n\r\n", 1)
    first, fields = head.split(b"\r\n", 1)
    assert first == b"POST " + target + b" HTTP/1.1", first
    headers = http.client.parse_headers(io.BytesIO(fields + b"\r\n\r\n"))
    assert headers.get_all("Host") == [authority.decode("ascii")], headers
    assert headers.get_all("Connection") == ["close"], headers
    assert headers.get_all("Content-Length") == ["4"], headers
    while len(body) < 4:
        part = connection.recv(4 - len(body))
        assert part
        body += part
    assert body == BODY, body
    return head + b"\r\n\r\n" + body


def connected_case(executable, directory, *, chunked=False):
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(6)
    port = listener.getsockname()[1]
    authority = b"127.0.0.1:0" + str(port).encode()
    target = b"/a/../%2f?x=1??"
    url = b"http://" + authority + target + b"#not-sent"
    response = b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n" + BODY
    if chunked:
        response = b"HTTP/1.1 103 Early Hints\r\nLink: </x>\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n" + BODY[:2] + b"\r\n2\r\n" + BODY[2:] + b"\r\n0\r\nX-End: yes\r\n\r\n"
    received, failures = [], []

    def peer():
        try:
            with listener.accept()[0] as connection:
                received.append(request(connection, authority, target))
                connection.sendall(response)
                connection.shutdown(socket.SHUT_WR)
                assert connection.recv(1) == b"", "client left socket open or sent extra request"
            listener.settimeout(0.1)
            try:
                unexpected, _ = listener.accept()
            except socket.timeout:
                pass
            else:
                unexpected.close()
                raise AssertionError("URL client reconnected after TCP selection")
        except BaseException as error:
            failures.append(error)

    worker = threading.Thread(target=peer, daemon=True)
    worker.start()
    trace = directory / "syscalls.log"
    profile = NATIVE.verified_sites(executable, directory)
    process = subprocess.Popen(["strace", "--kill-on-exit", "-qq", "-xx", "-s", "65536", "-i",
                                "-e", "signal=none", "-e", "trace=all", "-o", str(trace), str(executable), url, "0"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, restore_signals=True)
    observed = bytearray()
    deadline = time.monotonic() + 10
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
                    assert time.monotonic() < deadline, "checkpoint missing from causal trace"
                    time.sleep(0.005)
            source = SOURCE.source(memory(prefix), profile)
            child_ids = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
            assert len(child_ids) == 1, child_ids
            SOURCE.process_owners(int(child_ids[0]), source["live"])
            if tag == 0:
                assert source["live"], "URL must own backing before exchange"
            elif tag == 1:
                assert words[2:6] == (0, 0, 1, 1), words
                assert words[8] == words[9] == len(received[0]), (words, received)
                assert words[13:16] == (200, 4, 0), words
                assert source["live"], "borrowed response view has no live backing"
            else:
                assert not source["live"], ("source owners not released before final ACK", source)
            process.stdin.write(b"+")
            process.stdin.flush()
        process.stdin.close()
        process.wait(timeout=max(0.1, deadline - time.monotonic()))
        stderr, tail = process.stderr.read(), process.stdout.read()
        assert process.returncode == 0 and stderr == b"BbDd" and tail == b"", (process.returncode, stderr, tail)
        worker.join(timeout=1)
        assert not worker.is_alive() and not failures and len(received) == 1, failures
        full = trace.read_text()
        found = raw_events(SOURCE.output_prefix(full, bytes(observed)), profile)
        active = exchange_events(found)
        opened = [item for item in active if item["name"] == "socket"]
        connects = [item for item in active if item["name"] == "connect"]
        assert len(opened) == len(connects) == 1, (opened, connects)
        fd = int(opened[0]["result"])
        for item in active:
            if item["name"] in {"connect", "getsockopt", "getpeername", "fcntl", "close", "sendto", "recvfrom", "shutdown"}:
                assert int(TRUSTED.arguments(item["args"])[0]) == fd, ("selected fd replaced", item, fd)
        assert len([item for item in active if item["name"] == "getpeername"]) == 2
        assert len([item for item in active if item["name"] == "fcntl" and "F_GETFL" in item["args"]]) == 1
        closes = [item for item in active if item["name"] == "close"]
        assert len(closes) == 1 and closes[0]["result"] == "0", closes
        sent = b"".join(TRUSTED.quoted(TRUSTED.arguments(item["args"])[1])[:int(item["result"])]
                        for item in active if item["name"] == "sendto" and item["result"].isdecimal())
        assert sent == received[0], (sent, received)
        TRUSTED.source_maps(memory(full), profile, directory)
        return dict(source_allocations=len(source["attempts"]), requested_peak=source["peak"])
    except BaseException:
        process.kill()
        process.wait(timeout=2)
        raise
    finally:
        listener.close()
        worker.join(timeout=1)


def main():
    mode, executable = sys.argv[1:3]
    executable = Path(executable).resolve()
    assert mode == "plain", mode
    directory = Path(tempfile.mkdtemp(prefix="lanius-url-client-"))
    for index, chunked in enumerate((False, True)):
        case = directory / str(index)
        case.mkdir()
        connected_case(executable, case, chunked=chunked)
    print(f"url-client-plain cases=2 evidence={directory}")


if __name__ == "__main__":
    main()
