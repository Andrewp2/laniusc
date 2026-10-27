"""Real connected socket adoption, exact HTTP peer and pre-exit owner checks."""
import os
from pathlib import Path
import re
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

import h11

sys.dont_write_bytecode = True
from ledger import SOURCE, TRUSTED, analyze, close_target, controls

MAGIC = 1431456833
BODY = b"\x00\xff\r\n"
CONNECTED = {0, 3, 5, 6, 7}
# Cause, native detail, stage, charged adoption I/O calls. Inactive retains
# its original preparation stage; all active validation uses Connect.
FAILURES = {1: (4, 1107, 2, 2), 2: (4, 1, 2, 0), 3: (4, 1, 2, 1),
            4: (4, 1, 2, 0), 5: (13, 0, 0, 0), 6: (3, 0, 2, 0), 7: (10, 0, 2, 1)}


def exact(stream, count, captured):
    result = bytearray()
    deadline = time.monotonic() + 4
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], ("native checkpoint timeout", count, bytes(result))
        part = os.read(stream.fileno(), count - len(result))
        assert part, ("native checkpoint EOF", count, bytes(result))
        result.extend(part)
    captured.extend(result)
    return struct.unpack("<24Q", result)


def prefix(trace, captured):
    # strace may still be flushing the completed report write. The source
    # helper binds the actual stdout prefix, not an arbitrary line count.
    deadline = time.monotonic() + 2
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), captured)
        except SOURCE.CheckpointPending:
            assert time.monotonic() < deadline, "checkpoint absent from syscall trace"


def child_pid(tracer):
    children = Path(f"/proc/{tracer}/task/{tracer}/children").read_text().split()
    assert len(children) == 1, ("unexpected tracer children", children)
    return int(children[0])


def checkpoint(process, trace, captured, profile, executable, words, mode, tag, target=None):
    assert words[:3] == (MAGIC, tag, mode), words
    assert words[3] >= 3 and words[17] > 0 and words[18] < 1000000000, words
    result = analyze(prefix(trace, captured), profile, executable, target=target)
    pid = child_pid(process.pid)
    assert {int(item.name) for item in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2} | set(result["live"]), (words, result["live"])
    selected = result["sockets"][0]
    assert selected["fd"] == words[3] and selected["generation"] == 1, (words, selected)
    if tag == 0:
        assert words[4:6] == (int(mode != 5), int(mode != 2)), words
        assert bool(result["source"]["live"]) == (mode != 5), (words, result["source"])
        assert set(result["live"]) == (set() if mode == 2 else {words[3]}), result
    elif tag == 1:
        assert words[4:6] == (0, 0) and words[13:15] == (0, 0), words
        queries = [item for item in result["entries"] if item["phase"] == "A" and item["name"] in ("fcntl", "getpeername")]
        assert len(queries) == words[15], (words, queries)
        assert all((item["fd"], item["generation"]) == (words[3], 1) for item in queries), queries
        if mode == 0:
            assert words[6:12] == (words[3], 1, 0, 0, 0, 0) and words[15] == 2, words
            assert set(result["live"]) == {words[3]} and result["source"]["live"], result
        else:
            expected = FAILURES[mode]
            assert (words[8], words[9], words[10], words[15]) == expected, (words, expected)
            assert words[6:8] == (0, 0) and words[11] == (1005 if target else 0), words
            assert not result["source"]["live"], ("failure retained Prepared owners", result["source"])
            assert set(result["live"]) == ({words[3]} if target else set()), result
    else:
        assert words[4:7] == (0, 0, 0) and words[21] == 1, words
        assert not result["source"]["live"] and not result["live"], ("owners survived before final ACK", result)
    return result


def no_bytes(peer):
    peer.setblocking(False)
    try:
        data = peer.recv(1)
    except BlockingIOError:
        return
    raise AssertionError(("bytes/EOF before adoption or run", data))


def request_and_respond(peer):
    peer.setblocking(True)
    peer.settimeout(3)
    parser = h11.Connection(h11.SERVER)
    head, body = None, bytearray()
    while True:
        event = parser.next_event()
        if event is h11.NEED_DATA:
            part = peer.recv(1024)
            assert part, "client closed before complete selected-connection request"
            parser.receive_data(part)
        elif isinstance(event, h11.Request):
            assert head is None
            head = event
        elif isinstance(event, h11.Data):
            body.extend(event.data)
        elif isinstance(event, h11.EndOfMessage):
            break
        else:
            raise AssertionError(("unexpected independent HTTP event", event))
    assert head is not None and head.method == b"POST" and head.target == b"/adopt?q=x", head
    fields = list(head.headers)
    for name, value in ((b"host", b"adopt.example:8080"), (b"content-length", b"4"), (b"connection", b"close")):
        assert [item for key, item in fields if key == name] == [value], fields
    assert bytes(body) == BODY, body
    peer.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\n" + BODY)
    peer.shutdown(socket.SHUT_WR)


def invoke(executable, directory, mode, target=None):
    directory.mkdir()
    profile = TRUSTED.verified_sites(executable, directory)
    trace = directory / "native.trace"
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(3)
    command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
               "-e", "trace=all", "-o", str(trace)]
    if target:
        command += ["-e", "inject=close:error=EIO:when=%d" % target["ordinal"]]
    command += [str(executable), "127.0.0.1:%d" % listener.getsockname()[1], str(mode), str(int(target is not None))]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    captured, records, peer = bytearray(), [], None
    try:
        before = exact(process.stdout, 192, captured)
        records.append(before)
        checkpoint(process, trace, captured, profile, executable, before, mode, 0, target)
        if mode in CONNECTED:
            peer, _ = listener.accept()
            no_bytes(peer)
        if mode == 6:
            # Deliberate deadline exercise, independent of fixture scheduling:
            # both processes use Linux CLOCK_MONOTONIC. No deadline is reset.
            remaining = (before[17] * 1000000000 + before[18] - time.monotonic_ns() + 5000000) / 1000000000
            if remaining > 0:
                time.sleep(remaining)
        process.stdin.write(b"+")
        adopted = exact(process.stdout, 192, captured)
        records.append(adopted)
        checkpoint(process, trace, captured, profile, executable, adopted, mode, 1, target)
        assert adopted[12] == before[12] and adopted[16] == before[16] and adopted[22] == int(target is not None), records
        if mode == 0:
            no_bytes(peer)
        elif peer is not None:
            peer.setblocking(True)
            peer.settimeout(2)
            assert peer.recv(1) == b"", "failed adoption did not close the native-created connection before ACK"
        process.stdin.write(b"+")
        if mode == 0:
            request_and_respond(peer)
        done = exact(process.stdout, 192, captured)
        records.append(done)
        last = checkpoint(process, trace, captured, profile, executable, done, mode, 2, target)
        if mode == 0:
            assert done[7] == done[19] == 1 and done[12] == done[13] and done[14] > 4, done
            peer.settimeout(2)
            assert peer.recv(1) == b"", "selected socket not physically closed before final ACK"
        else:
            assert done[8:17] == adopted[8:17] and done[19] == 2, records
        # No second candidate connection is allowed during adoption/run.
        listener.setblocking(False)
        try:
            extra, _ = listener.accept()
        except BlockingIOError:
            pass
        else:
            extra.close()
            raise AssertionError("adoption/run opened another connection")
        process.stdin.write(b"+")
        process.stdin.close()
        process.stdin = None
        output, diagnostic = process.communicate(timeout=3)
        assert process.returncode == 0 and not output, (process.returncode, output, diagnostic, records)
        assert re.fullmatch(rb"[PpCcAaRrDdTtKk]+", diagnostic), diagnostic
        result = analyze(trace.read_text(), profile, executable, final=True, target=target)
        assert not last["source"]["live"] and not last["live"]
        if mode == 0:
            transfers = [item for item in result["entries"] if item["name"] in ("sendto", "recvfrom")]
            assert any(item["name"] == "sendto" and item["result"].split()[0].isdecimal() for item in transfers), transfers
            assert any(item["name"] == "recvfrom" and int(item["result"].split()[0]) > 0 for item in transfers
                       if item["result"].split()[0].isdecimal()), transfers
            assert all((item["fd"], item["generation"]) == (before[3], 1) for item in transfers), transfers
            assert len(result["closes"]) == 1 and result["closes"][0]["phase"] == "R", result["closes"]
        elif mode == 2:
            assert len(result["closes"]) == 1 and result["closes"][0]["phase"] == "C", result["closes"]
        else:
            assert len(result["closes"]) == (2 if target else 1), result["closes"]
            assert result["closes"][0]["phase"] == "A", result["closes"]
            if target:
                assert result["closes"][1]["phase"] == "K" and result["closes"][1]["result"] == "0", result["closes"]
        return result
    finally:
        if peer is not None:
            peer.close()
        listener.close()
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=2)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None:
                stream.close()


def main():
    if sys.argv[1:] == ["--self-test"]:
        print("url-adoption ledger CPU controls=%d" % controls())
        return
    executable, group = Path(sys.argv[1]).resolve(), sys.argv[2]
    assert group in ("success", "failures")
    directory = Path(tempfile.mkdtemp(prefix="url-adoption-"))
    try:
        if group == "success":
            invoke(executable, directory / "connected", 0)
            print("url-adoption success cases=1 same-generation=1 pre-exit-zero=1")
        else:
            target = None
            for mode in range(1, 8):
                result = invoke(executable, directory / ("mode-%d" % mode), mode)
                if mode == 1:
                    target = close_target(result)
            invoke(executable, directory / "mode-1-close-eio", 1, target)
            print("url-adoption failures cases=8 reached-close-eio=1 pre-exit-zero=8")
    except BaseException:
        print("adoption diagnostics retained at %s" % directory, file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
