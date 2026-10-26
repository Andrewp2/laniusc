"""Direct shared server Protocol and plain Exchange acceptance, with real peers."""
import contextlib
from pathlib import Path
import re
import select
import sys
import time

from support import Session, events, injected, parse_response, record_marker, request
from controls import run as guard_controls

COUNT = 0
ALLOCATION_POSITIONS = 0
BODY = bytes(range(256)) * 13 + b"\x00\xff\r\n"
CONTINUE = b"HTTP/1.1 100 Continue\r\n\r\n"


@contextlib.contextmanager
def case(executable, label, **options):
    global COUNT
    value = Session(executable, label, **options)
    try:
        yield value
    except BaseException as error:
        value.close(error)
    else:
        value.close()
        COUNT += 1


def pending(value):
    return value.until(lambda row: row[7] or row[2] != 0 or not row[4] & 4)


def head(value, wire, fragment=0):
    header, body = wire.split(b"\r\n\r\n", 1)
    header += b"\r\n\r\n"
    fragments = [header] if not fragment else [header[at:at + fragment] for at in range(0, len(header), fragment)]
    released = 0
    for block in fragments:
        value.send(block)
        released += len(block)
        value.until(lambda row: row[7] or row[5] in (1, 3) or (row[11] == released and not row[4] & 4))
        assert value.last[11] == released, (released, value.last)
        if value.last[7] or value.last[5] == 3:
            return body
    value.until(lambda row: row[7] or row[5] in (1, 3))
    return body


def body(value, wire_body, fragment=1024):
    released = value.last[11]
    for at in range(0, len(wire_body), fragment):
        block = wire_body[at:at + fragment]
        value.send(block)
        released += len(block)
        value.until(lambda row: row[7] or row[5] in (2, 3) or (row[11] == released and not row[4] & 4))
        assert value.last[11] == released, (released, value.last)
        if value.last[7] or value.last[5] == 3:
            return
    value.until(lambda row: row[7] or row[5] in (2, 3))


def terminal(value, collect=True):
    value.until(lambda row: row[7] or row[2] != 0, collect=collect)
    return value.last


def await_eof(value):
    value.collect()
    deadline = time.monotonic() + 2
    while not value.eof:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([value.conn], [], [], remaining)[0], ("missing actual server EOF", value.last)
        value.collect()


def complete(value, expected=200, content=b"", interims=0, method=b"POST"):
    last = terminal(value)
    assert last[2] == 1 and last[5] in (4, 5) and last[7] == 0, last
    assert last[3] == -1 and last[24] & 8 and last[22] == 1 and last[23] == 0, last
    if last[5] == 5:
        assert last[17] == last[16] and last[24] & 3 == 3, last
    await_eof(value)
    if last[5] != 4:
        parse_response(bytes(value.evidence.peer_wire), method, expected, content, interims)
        assert b"x-owned: stable\r\n" in bytes(value.evidence.peer_wire).lower()
    else:
        assert not value.evidence.peer_wire, value.evidence.peer_wire
    for _ in range(3):
        repeated = value.step(15)
        assert repeated[2] == last[2] and repeated[5] == 0 and repeated[11:29] == last[11:29], (last, repeated)
    return value.finish()


def echo(executable, fragment=0, chunked=False, fault=None):
    wire = request(b"POST", b"/echo?q=stable", BODY, extra=b"X-Head: frozen\r\n", chunked=chunked)
    with case(executable, "echo", fault=fault) as value:
        content = head(value, wire, fragment)
        assert value.last[5] == 1 and value.last[7] == 0, value.last
        saved_head = value.last[25]
        for _ in range(3):
            inspected = value.command(23)
            assert inspected[5] == 1 and inspected[25] == saved_head and inspected[6] == 2, inspected
            paused = value.step()
            assert paused[5] == 0 and paused[25] == saved_head, paused
        assert value.command(17)[7] == 0
        body(value, content, 127 if fragment else 1024)
        assert value.last[5] == 2 and value.last[25] == saved_head and value.last[13] == len(BODY), value.last
        assert value.payloads[-1][1] == BODY
        assert value.command(19, 200, -1)[7] == 0
        value.half_close()
        text, epochs = complete(value, content=BODY)
        assert any(tag == 1 and any(e["name"] == "recvfrom" for e in calls) for tag, _, calls, _ in epochs)
        return text, epochs


def steps(executable):
    for fragment, chunked in ((0, False), (7, False), (11, True)):
        echo(executable, fragment, chunked)
    with case(executable, "hangup-is-not-eof") as value:
        # An invented HUP can wake one attempt, but recv must establish EOF.
        before = pending(value)
        assert before[6] == 1 and before[4] == 1 and before[11] == 0 and not before[24] & 2, before
        first = value.step(4)
        assert not first[24] & 2 and first[2] == 0 and first[19] == before[19] + 1, (before, first)
        value.half_close()
        last = terminal(value)
        assert last[5] == 4 and last[11] == 0 and last[17] == 0, last
        complete(value)


def pure_input(value, data):
    offset = 0
    while offset < len(data):
        value.until(lambda row: row[6] == 1 or row[7] or row[5] in (1, 2, 3))
        assert value.last[6] == 1, value.last
        block = data[offset:offset + 127]
        assert value.command(28, payload=block)[7] == 0
        offset += len(block)
    value.until(lambda row: row[5] in (1, 2, 3) or row[7] or row[6] == 1)


def decisions(executable):
    echo(executable, 3, True)
    wire = request(b"POST", b"/echo", b"abcd", extra=b"Expect: 100-continue\r\n")
    with case(executable, "expect-real") as value:
        content = head(value, wire)
        assert value.last[5] == 1
        before = value.last
        assert value.command(17)[7] == 11 and value.last[2] == 0
        assert value.last[11] == before[11] and value.last[18] == 0
        assert value.command(18)[7] == 0
        value.until(lambda row: row[18] == 25 or row[7])
        value.collect()
        assert bytes(value.evidence.peer_wire) == CONTINUE
        body(value, content)
        assert value.last[5] == 2
        assert value.command(19, 200, -1)[7] == 0
        value.half_close()
        complete(value, content=b"abcd", interims=1)
    with case(executable, "expect-preloaded") as value:
        value.send(wire)
        value.until(lambda row: row[5] == 1 or row[7])
        assert value.last[5] == 1 and value.command(17)[7] == 11
        assert value.command(18)[7] == 0
        value.until(lambda row: row[5] == 2 or row[7])
        assert value.last[5] == 2 and value.last[18] == 25 and value.payloads[-1][1] == b"abcd", value.last
        value.command(19, 200, -1)
        value.half_close()
        complete(value, content=b"abcd", interims=1)
    with case(executable, "unsupported-expect") as value:
        head(value, request(b"POST", b"/echo", b"abcd", extra=b"Expect: unsupported\r\n"))
        assert value.last[5] == 1
        assert value.command(17)[7] == 11 and value.command(18)[7] == 11
        assert value.last[18] == 0 and value.last[2] == 0
        value.command(19, 417, 0)
        value.half_close()
        complete(value, expected=417)
    with case(executable, "partial-continue-protocol", mode=1) as value:
        pure_input(value, wire.split(b"\r\n\r\n", 1)[0] + b"\r\n\r\n")
        assert value.last[5] == 1
        assert value.command(17)[7] == 11
        assert value.command(18)[7] == 0
        value.until(lambda row: row[6] == 3 or row[7])
        assert value.command(30)[7] == 0 and value.payloads[-1][1] == CONTINUE
        assert value.command(19, 400, 0)[7] == 2
        assert value.command(31, 7)[7] == 0 and value.last[18] == 7
        value.until(lambda row: row[6] == 3 or row[7])
        assert value.command(30)[7] == 0 and value.payloads[-1][1] == CONTINUE[7:]
        assert value.command(32)[7] == 0
        assert value.command(30)[7] == 0 and value.payloads[-1][1] == CONTINUE[7:]
        assert value.command(31, 18)[7] == 0 and value.last[18] == 25
        pure_input(value, b"abcd")
        assert value.last[5] == 2 and value.payloads[-1][1] == b"abcd"
        value.command(21)
        value.finish()
    for invalid in (1, 2):
        with case(executable, "atomic-response-%d" % invalid) as value:
            content = head(value, request(b"POST", b"/echo", b"sample"))
            value.command(17)
            body(value, content)
            failed = value.command(19, 200, -1, invalid)
            assert failed[7] in (7, 10) and failed[2] == 0 and failed[17] == 0 and failed[6] == 2, failed
            assert value.command(19, 200, -1)[7] == 0
            value.half_close()
            complete(value, content=b"sample")
    for malformed, status, options in (
        (b"POST /echo HTTP/1.1\r\nHost: x\r\nHost: x\r\nContent-Length: 0\r\n\r\n", 400, {}),
        (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nExpect: 100-continue\r\n\r\n", 413, {"body_cap": 1}),
        (b"POST /" + b"x" * 1050 + b" HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n", 414, {}),
    ):
        with case(executable, "handled-rejection-%d" % status, **options) as value:
            head(value, malformed)
            assert value.last[5] == 3 and value.last[27] != 0 and value.last[18] == 0, value.last
            original = value.last[27:29]
            assert value.command(17)[7] == 2
            assert value.command(19, status, 0)[7] == 0
            value.half_close()
            terminal(value)
            assert value.last[27:29] == original
            complete(value, expected=status)
    with case(executable, "rejection-then-send-error", fault="sendto:error=EIO:when=1") as value:
        head(value, b"POST /echo HTTP/1.1\r\nHost: x\r\nHost: x\r\nContent-Length: 0\r\n\r\n")
        assert value.last[5] == 3
        original = value.last[27:29]
        value.command(19, 400, 0)
        value.half_close()
        failed = terminal(value)
        assert failed[7] == 6 and failed[9] == 5 and failed[27:29] == original, failed
        text, _ = value.finish()
        injected(text, "sendto", 1, "EIO")


def rejection(value, amount):
    wire = b"POST /reject HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\nExpect: 100-continue\r\n\r\n"
    head(value, wire)
    assert value.last[5] == 1
    assert value.command(19, 413, amount)[7] == 0


def drain(executable):
    for cap, sent, failure in ((0, 0, False), (17, 17, False), (17, 18, True)):
        with case(executable, "exact-drain-%d-%d" % (cap, sent), drain_cap=cap) as value:
            rejection(value, 0)
            value.until(lambda row: row[24] & 1 or row[7])
            await_eof(value)
            assert value.last[18] == 0
            value.send(bytes(range(sent)))
            value.half_close()
            last = terminal(value)
            assert last[15] == sent and bool(last[7]) == failure, last
            if failure:
                assert last[7] == 17 and last[2] == 2
                text, _ = value.finish()
            else:
                text, _ = complete(value, expected=413)
            reads = [e for e in events(text) if e["name"] == "recvfrom"]
            assert reads[-1]["args"].split(", ")[2] == "1", reads[-1]
            assert reads[-1]["result"].split()[0] == ("1" if failure else "0"), reads[-1]
    with case(executable, "duplex-backpressure", timeout=12000) as value:
        rejection(value, 1048576)
        # Withhold reads until the actual server send buffer reaches EAGAIN.
        # Send an unread upload concurrently in bounded peer attempts.
        upload = memoryview(bytes(range(256)) * 256)
        eagain = False
        for _ in range(20000):
            if upload:
                count = value.send_some(upload[:1024])
                upload = upload[count:]
            value.progress(collect=False)
            text = value.trace.read_text()
            eagain = bool(re.search(r"sendto\([^\n]* = -1 EAGAIN", text))
            if eagain and value.last[15] > 0:
                break
            assert not value.last[7], value.last
        else:
            raise AssertionError(("missing real send backpressure and drain", value.last))
        assert eagain and value.last[17] < value.last[16] and value.last[15] > 0
        for _ in range(20000):
            value.collect()
            if upload:
                upload = upload[value.send_some(upload[:1024]):]
            if not upload:
                value.half_close()
                break
            value.progress()
        else:
            raise AssertionError("upload did not finish")
        complete(value, expected=413, content=bytes(range(256)) * 4096)


def lifecycle(executable):
    with case(executable, "abort-stable-head") as value:
        head(value, request(b"POST", b"/echo", BODY))
        saved = value.last[25]
        first = value.command(21)
        assert first[2] == 3 and first[3] == -1 and first[25] == saved and first[22] == 1, first
        for _ in range(3):
            again = value.command(21)
            assert again[22] == first[22] and again[25] == saved, again
        value.command(22)
        repeated = value.command(22)
        assert repeated[22] == first[22] and repeated[2] == 3
        value.finish()
    with case(executable, "sticky-send-error", fault="sendto:error=EIO:when=1") as value:
        content = head(value, request(b"POST", b"/echo", BODY))
        value.command(17)
        body(value, content)
        value.command(19, 200, -1)
        value.half_close()
        failed = terminal(value)
        assert failed[7] == 6 and failed[9] == 5 and failed[2] == 2 and failed[3] == -1, failed
        for _ in range(3):
            again = value.step(15)
            assert again[7:29] == failed[7:29], (failed, again)
        text, _ = value.finish()
        injected(text, "sendto", 1, "EIO")
    with case(executable, "application-pause-timeout", timeout=250) as value:
        head(value, request(b"POST", b"/echo", b""))
        assert value.last[5] == 1
        time.sleep(.3)
        failed = value.command(16)
        assert failed[7] == 4 and failed[2] == 2 and failed[3] == -1, failed
        value.finish()
    for count in (0, 26):
        with case(executable, "invalid-confirmed-count-%d" % count, mode=1) as value:
            pure_input(value, b"POST /echo HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: 4\r\n\r\n")
            assert value.last[5] == 1
            value.command(18)
            value.until(lambda row: row[6] == 3 or row[7])
            value.command(30)
            failed = value.command(31, count)
            assert failed[7] == 6 and failed[2] == 2 and failed[18] == 0, failed
            for _ in range(2):
                again = value.step()
                assert again[7:29] == failed[7:29], (failed, again)
            value.finish()


def faults(executable):
    global ALLOCATION_POSITIONS
    for syscall in ("recvfrom", "sendto", "shutdown"):
        text, _ = echo(executable, fault=syscall + ":error=EINTR:when=1")
        injected(text, syscall, 1, "EINTR")
    with case(executable, "fatal-receive", fault="recvfrom:error=EIO:when=1") as value:
        value.send(request(b"POST", b"/echo", b""))
        failed = terminal(value)
        assert failed[7] == 6 and failed[9] == 5 and failed[11] == 0 and failed[22] == 1, failed
        text, _ = value.finish()
        injected(text, "recvfrom", 1, "EIO")
    with case(executable, "fatal-shutdown", fault="shutdown:error=EIO:when=1") as value:
        content = head(value, request(b"POST", b"/echo", BODY))
        value.command(17)
        body(value, content)
        value.command(19, 200, -1)
        value.half_close()
        failed = terminal(value)
        assert failed[7] == 6 and failed[9] == 5 and failed[17] == failed[16] > 0 and failed[22] == 1, failed
        text, _ = value.finish()
        injected(text, "shutdown", 1, "EIO")
    with case(executable, "exhausted-active-io", quota=1) as value:
        failed = terminal(value)
        assert failed[7] == 18 and failed[19] == 1 and failed[11] == 0 and failed[22] == 1, failed
        value.finish()
    baseline, _ = echo(executable)
    all_maps = [entry for entry in events(baseline) if entry["name"] == "mmap"]
    positions = []
    ordinal, epoch = 0, None
    for entry in events(baseline):
        marker = record_marker(entry)
        if marker is not None:
            epoch = marker[1] if marker[1] in (1, 5) else None
        if entry["name"] == "mmap":
            ordinal += 1
            if epoch is not None and entry["result"].startswith("0x"):
                positions.append(ordinal)
    assert positions, "baseline reached no library-owned source allocation"
    clocks = [entry for entry in events(baseline) if entry["name"] == "clock_gettime"]
    first_step = next(entry for entry in events(baseline) if (record_marker(entry) or (0, 0))[1] == 1)
    after_step = events(baseline)[events(baseline).index(first_step) + 1:]
    clock_site = next(entry for entry in after_step if entry["name"] == "clock_gettime")
    clock_ordinal = clocks.index(clock_site) + 1
    with case(executable, "fatal-observed-clock", fault="clock_gettime:error=EIO:when=%d" % clock_ordinal) as value:
        failed = terminal(value)
        assert failed[7] == 5 and failed[2] == 2 and failed[22] == 1, failed
        text, _ = value.finish()
        injected(text, "clock_gettime", clock_ordinal, "EIO")
    for ordinal in positions:
        with case(executable, "allocation-%d" % ordinal, fault="mmap:error=ENOMEM:when=%d" % ordinal) as value:
            content = head(value, request(b"POST", b"/echo?q=stable", BODY, extra=b"X-Head: frozen\r\n"))
            if value.last[5] == 1:
                assert value.command(17)[7] == 0
                body(value, content)
            if value.last[5] == 2:
                value.command(19, 200, -1)
            failed = value.last
            if failed[5] == 3:
                assert failed[27] in (3, 7) and failed[2] == 0, failed
            else:
                assert failed[7] == 3 or (failed[7] == 7 and failed[31] == 2), failed
            assert failed[17] == 0, ("allocation failure published final bytes", failed)
            value.command(21)
            text, _ = value.finish()
            injected(text, "mmap", ordinal, "ENOMEM")
            observed = [entry for entry in events(text) if entry["name"] == "mmap"]
            assert len(observed) >= ordinal
            for index in range(ordinal):
                first, second = all_maps[index], observed[index]
                assert first["ip"] == second["ip"] and first["args"] == second["args"], ("allocation prefix drift", ordinal, index, first, second)
                if index + 1 < ordinal:
                    assert first["result"].startswith("0x") == second["result"].startswith("0x"), (first, second)
    ALLOCATION_POSITIONS = len(positions)


if __name__ == "__main__":
    assert len(sys.argv) == 3
    executable, group = sys.argv[1:]
    controls = guard_controls()
    {"steps": steps, "decisions": decisions, "drain": drain,
     "lifecycle": lifecycle, "faults": faults}[group](executable)
    print("http-server-exchange-%s cases=%d source-allocation-positions=%d cpu-guard-controls=%d owners-and-step-boundaries-checked=1" % (group, COUNT, ALLOCATION_POSITIONS, controls))
