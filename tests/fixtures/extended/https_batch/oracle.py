"""Finite native HTTPS acceptance; production work stays in Lanius/OpenSSL.

h11 checks emitted requests; http.client independently reads each returned final
message. Barriers establish causality, never a throughput/time-ratio heuristic.
"""
import dataclasses
import os
from pathlib import Path
import select
import re
import ssl
import struct
import subprocess
import sys
import time
import tempfile

from peers import BINARY, Peer, Pool, chunked, decoded, fixed

MAGIC = 1213415985
COUNT = 0


@dataclasses.dataclass
class Config:
    concurrency: int = 2
    timeout: int = 1800
    max_jobs: int = 16
    pending: int = 16_777_216
    wire: int = 1_048_576
    body: int = 1_048_576
    operations: int = 1_000_000
    work: int = 128_000_000
    call_work: int = 8_000_000
    call_io: int = 100_000
    response: int = 65_536
    response_body: int = 32_768
    interims: int = 8
    take: int = -1
    checkpoint: int = 1
    tls_calls: int = 100_000
    bytes_layout: int = 0
    jobs_layout: int = 0
    io_bytes: int = 1024
    credentials: int = 0
    native_fault: int = 0
    upref_fault: int = 0
    head: int = 4096
    line: int = 1024


def packet(pool, config):
    header = [len(pool.peers), config.concurrency, config.timeout, config.max_jobs,
              config.pending, config.wire, config.body, config.operations,
              config.work, config.call_work, config.call_io, config.response,
              config.response_body, config.interims, config.take, config.checkpoint,
              config.tls_calls, config.bytes_layout, config.jobs_layout, config.io_bytes,
              config.credentials, config.native_fault, config.upref_fault, 0,
              config.head, config.line] + [0] * 6
    records = []
    identities = {"fixture.test": 0, "wrong.invalid": 1, "127.0.0.1": 2,
                  "127.0.0.2": 3, "::1": 4}
    for index, peer in enumerate(pool.peers):
        if peer.request_bytes <= 4:
            peer.body = bytes((0, 255, index, 10))[:peer.request_bytes]
        else:
            peer.body = b"\x00\xff\x00\x0a" + b"X" * (peer.request_bytes - 4)
        mode = 1 if peer.method == "HEAD" else peer.request_mode
        records.extend((pool.servers[index].listener.getsockname()[1], peer.family,
                        mode, peer.request_bytes, identities[peer.identity], 0, 0, 0))
    return struct.pack("<%dI" % (32 + len(records)),
                       *((value & 0xffffffff) for value in header + records))


def u64(words, index):
    return (words[index] & 0xffffffff) | ((words[index + 1] & 0xffffffff) << 32)


def outcome(read):
    words = struct.unpack("<64i", read(256))
    assert 0 <= words[0] <= 5, words
    result = {"kind": words[0], "cause": words[1], "stage": words[2],
              "http_cause": words[3], "http_stage": words[4], "errno": words[5],
              "cleanup": words[6], "tls_cause": words[7], "tls_phase": words[8],
              "ssl_error": words[9], "system": words[10], "code": u64(words, 12),
              "verify": struct.unpack("<q", struct.pack("<Q", u64(words, 14)))[0],
              "tls_calls": u64(words, 16), "handshakes": u64(words, 18),
              "reads": u64(words, 20), "writes": u64(words, 22), "shutdowns": u64(words, 24),
              "request": words[26], "sent": words[27], "received": u64(words, 28),
              "interims": words[30], "discarded": words[31], "io": u64(words, 32),
              "work": u64(words, 34), "upload_stopped": words[36], "write_shutdown": words[37],
              "status": words[40], "trailers": words[41], "informational": words[42],
              "offset": words[44], "http_cleanup": words[45], "wire_error": words[46],
              "wire_offset": words[47], "wire": b"", "body": b""}
    if words[0] == 1:
        assert 0 <= words[38] <= 1_048_576 and 0 <= words[39] <= 1_048_576, words
        result["wire"], result["body"] = read(words[38]), read(words[39])
    return result


def report(read):
    words = struct.unpack("<80i", read(320))
    assert words[0] == MAGIC and 0 <= words[3] <= 8, words
    names = ("jobs", "started", "complete", "failed", "aborted", "discarded", "peak_active")
    stats = dict(zip(names, words[4:11]))
    for index, name in enumerate(("operations", "polls", "io", "work", "pending", "peak_pending", "wire", "body")):
        stats[name] = u64(words, 12 + index * 2)
    result = {"cause": words[2], "stats": stats,
              "native": [u64(words, 44 + index * 2) for index in range(7)],
              "forced": u64(words, 58), "stable_writes": u64(words, 60),
              "distinct_cells": u64(words, 62),
              "outcomes": [outcome(read) for _ in range(words[3])]}
    if words[28]:
        result["taken"] = outcome(read)
    return result


def tracee(process, traced):
    if not traced:
        return process.pid
    children = Path("/proc/%d/task/%d/children" % (process.pid, process.pid)).read_text().split()
    assert len(children) == 1, children
    return int(children[0])


def run(executable, directory, peers, config=None, schedule="ordinary", *,
        expected_failure=False, trace=None, faults=(), client="client-chain-full", pool_type=Pool):
    global COUNT
    config = config or Config()
    directory = Path(directory)
    command = [executable, str(directory / "root.pem"),
               str(directory / (client + ".pem")),
               str(directory / ("client-chain.key" if client == "client-chain-full" else client + ".key"))]
    if trace is not None:
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
                   "-e", "trace=mmap,munmap,openat,open,close,socket,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write",
                   *[part for fault in faults for part in ("-e", "inject=" + fault)], *command]
    with pool_type(directory, peers, config.concurrency, schedule, expected_failure) as pool:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, bufsize=0)
        until = time.monotonic() + 7
        try:
            process.stdin.write(packet(pool, config))
            process.stdin.flush()
            def read(count):
                data = bytearray()
                while len(data) < count:
                    remaining = until - time.monotonic()
                    assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "HTTPS packet deadline"
                    part = os.read(process.stdout.fileno(), count - len(data))
                    assert part, ("premature HTTPS protocol EOF", process.poll(), bytes(data), process.stderr.read())
                    data.extend(part)
                return bytes(data)
            assert struct.unpack("<4i", read(16)) == (MAGIC, 100, 0, 0)
            result = report(read)
            assert struct.unpack("<4i", read(16)) == (MAGIC, 101, 0, 0)
            if config.checkpoint:
                owner = tracee(process, trace is not None)
                assert set(os.listdir("/proc/%d/fd" % owner)) == {"0", "1", "2"}, (owner, os.listdir("/proc/%d/fd" % owner))
                process.stdin.write(b"!")
                process.stdin.flush()
            process.stdin.close()
            process.stdin = None
            output, errors = process.communicate(timeout=max(.1, until - time.monotonic()))
            assert process.returncode == 0 and not output and not errors, (process.returncode, output, errors)
            assert result["native"][:3] == [0, 0, 0], result
            result["events"] = list(pool.events)
            result["versions"] = [server.version for server in pool.servers]
            result["uploaded"] = dict(pool.request_bodies)
            result["client_certificates"] = dict(pool.client_certificates)
            result["seen"] = set(pool.requests)
            COUNT += 1
            return result
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=2)


def actual_outcomes(result, config):
    outcomes = list(result["outcomes"])
    if "taken" in result:
        assert config.take >= 0 and outcomes[config.take]["kind"] == 5
        outcomes[config.take] = result["taken"]
    return outcomes


def complete(result, peers, config):
    assert result["cause"] == 0 and result["stats"]["complete"] == len(peers), result
    assert result["seen"] == set(range(len(peers))), result
    assert result["stats"]["started"] == len(peers) and result["stats"]["pending"] == 0, result
    assert result["stats"]["peak_active"] <= config.concurrency, result
    outcomes = actual_outcomes(result, config)
    for index, (actual, peer) in enumerate(zip(outcomes, peers)):
        assert actual["kind"] == 1 and actual["cleanup"] == 0, (index, actual)
        # Interim bytes are separately retained by the API; independently read
        # only the final view returned by Response.as_view().
        status, body = decoded(actual["wire"], peer.method)
        assert (status, body) == (actual["status"], actual["body"]), (index, actual)
        assert actual["wire"] == peer.wire and actual["body"] == decoded(peer.wire, peer.method)[1], (index, actual)
        assert actual["received"] >= len(peer.wire) and actual["discarded"] == 0, actual
        if not peer.early:
            assert actual["sent"] == actual["request"], actual
    # Retained wire storage includes the informational prefix, while as_view()
    # deliberately starts at the final response. Strict mode discards no tail.
    assert result["stats"]["wire"] == sum(item["received"] for item in outcomes), result
    assert result["stats"]["body"] == sum(len(item["body"]) for item in outcomes), result
    return outcomes


def causal(result, count, concurrency, schedule):
    events = result["events"]
    if schedule == "waves":
        for start in range(0, count, concurrency):
            members = range(start, min(start + concurrency, count))
            for index in members:
                assert all(events.index(("accepted", other)) < events.index(("handshake-output", index)) for other in members), events
                assert all(events.index(("request", other)) < events.index(("response", index)) for other in members), events
                assert all(events.index(("ended", other)) < events.index(("response", index)) for other in members if other > index), events
    elif schedule == "fair":
        assert all(events.index(("accepted", other)) < events.index(("handshake-output", index)) for other in range(concurrency) for index in range(concurrency)), events
        assert events.index(("request", count - 1)) < events.index(("response", 0)), events


def socket_ledger(path):
    """Count kernel socket owners, independently of batch's peak counter."""
    live, peak, created = set(), 0, 0
    for line in Path(path).read_text().splitlines():
        opened = re.search(r"\bsocket\(.*\)\s+=\s+(\d+)$", line)
        closed = re.search(r"\bclose\((\d+)\)\s+=\s+0$", line)
        if opened:
            fd = int(opened[1])
            assert fd not in live, line
            live.add(fd)
            created += 1
            peak = max(peak, len(live))
        if closed:
            live.discard(int(closed[1]))
    assert not live, live
    return created, peak


def verified(executable, directory):
    for count, width, schedule, layout in ((4, 2, "waves", 0), (5, 3, "waves", 1),
                                           (4, 2, "fair", 1), (2, 1, "waves", 0)):
        peers = [Peer(wire=fixed(BINARY + bytes((index,))), fragment=7 if index == 0 else 0) for index in range(count)]
        config = Config(concurrency=width, take=count - 1, bytes_layout=layout, jobs_layout=layout)
        with tempfile.TemporaryDirectory(prefix="https_batch_verified_") as temporary:
            trace = Path(temporary) / "syscalls.log"
            result = run(executable, directory, peers, config, schedule, trace=trace)
            assert socket_ledger(trace) == (count, width), trace.read_text()
        complete(result, peers, config)
        causal(result, count, width, schedule)
        assert result["stats"]["peak_active"] == width, result
    peers = [Peer(wire=fixed(), family=6, identity="::1")]
    config = Config(concurrency=1, bytes_layout=1, jobs_layout=1)
    result = run(executable, directory, peers, config)
    complete(result, peers, config)


def framing(executable, directory):
    cases = [(fixed(), "framed", "POST", 1024),
             (chunked(), "framed", "POST", 3),
             (b"HTTP/1.0 200 OK\r\nX: y\r\n\r\n" + BINARY, "clean", "POST", 17),
             (b"HTTP/1.1 200 OK\r\nContent-Length: 999\r\n\r\n", "framed", "HEAD", 3)]
    for wire, ending, method, io_bytes in cases:
        peers = [Peer(wire=wire, ending=ending, method=method)]
        config = Config(concurrency=1, io_bytes=io_bytes, take=0, jobs_layout=1, bytes_layout=1)
        result = run(executable, directory, peers, config)
        complete(result, peers, config)


def policies(executable, directory):
    # Each failure must retain typed TLS details and remain per job. No peer
    # accepts HTTP before its own completed native verified handshake.
    for certificate, identity, verification in (("valid", "wrong.invalid", 62),
                                               ("valid", "127.0.0.2", 64),
                                               ("expired", "fixture.test", 10),
                                               ("chain", "fixture.test", 20),
                                               ("wrong-purpose", "fixture.test", 26)):
        peers = [Peer(wire=fixed(), certificate=certificate, identity=identity),
                 Peer(wire=fixed(b"sibling survives"))]
        result = run(executable, directory, peers, Config(concurrency=1), expected_failure=True)
        failed, completed = result["outcomes"]
        assert result["cause"] == 0 and [item["kind"] for item in result["outcomes"]] == [2, 1], result
        assert (failed["cause"], failed["stage"], failed["tls_cause"], failed["tls_phase"]) == (2, 5, 11, 6), failed
        assert failed["verify"] == verification and failed["code"] != 0 and failed["ssl_error"] == 1, failed
        assert failed["sent"] == 0 and failed["received"] == 0 and result["seen"] == {1}, result
        assert completed["body"] == b"sibling survives", completed
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        peers = [Peer(wire=fixed(), certificate="chain-full", require_client=True, version=version)]
        config = Config(concurrency=1, credentials=1)
        result = run(executable, directory, peers, config)
        complete(result, peers, config)
        assert set(result["client_certificates"]) == {0} and result["versions"] == [version.name.replace("TLSv1_", "TLSv1.")], result
    for client, credentials in (("client", 0), ("client-expired", 1), ("client-wrong-purpose", 1), ("client-untrusted", 1)):
        peers = [Peer(wire=fixed(), require_client=True, version=ssl.TLSVersion.TLSv1_2)]
        result = run(executable, directory, peers, Config(concurrency=1, credentials=credentials),
                     expected_failure=True, client=client)
        failure = result["outcomes"][0]
        assert result["cause"] == 0 and failure["kind"] == 2 and failure["cause"] == 2, result
        assert failure["tls_cause"] == 10 and failure["code"] != 0 and failure["verify"] == 0, failure
        assert not result["seen"] and not result["client_certificates"], result


def transport(executable, directory):
    from controlled import ControlledPool
    for version in (ssl.TLSVersion.TLSv1_3, ssl.TLSVersion.TLSv1_2):
        peer = Peer(wire=fixed(b"bounded early response", 413), early=True,
                    request_bytes=4_194_304, version=version)
        # wire.body_bytes is shared by canonical request/response policy.
        config = Config(concurrency=1, call_work=64_000_000, response_body=4_194_304)
        result = run(executable, directory, [peer], config, pool_type=ControlledPool)
        value = complete(result, [peer], config)[0]
        assert value["upload_stopped"] == 1 and 0 < value["sent"] < value["request"], value
        if version == ssl.TLSVersion.TLSv1_3:
            assert result["uploaded"][0] == peer.body[:len(result["uploaded"][0])], result
            assert len(result["uploaded"][0]) < len(peer.body) and ("client-notify", 0) in result["events"], result
            assert result["events"].index(("response", 0)) < result["events"].index(("client-notify", 0)), result
        else:
            assert ("client-notify", 0) not in result["events"], result
    for ending in ("abrupt", "cut"):
        peer = Peer(wire=b"HTTP/1.0 200 OK\r\nX: y\r\n\r\n" + BINARY, ending=ending)
        result = run(executable, directory, [peer], Config(concurrency=1), expected_failure=True)
        value = result["outcomes"][0]
        assert result["cause"] == 0 and (value["kind"], value["cause"], value["tls_cause"]) == (2, 2, 14), result
        assert value["tls_phase"] == 7 and value["ssl_error"] in (1, 5), value
    # A complete TLS record with extra plaintext is not a second response.
    # Reject already-buffered HTTP tail, preserving the nested HTTP diagnostic.
    peer = Peer(wire=fixed(b"ok") + b"unconsumed tail")
    result = run(executable, directory, [peer], Config(concurrency=1), expected_failure=True)
    value = result["outcomes"][0]
    assert result["cause"] == 0 and (value["kind"], value["cause"], value["http_cause"]) == (2, 1, 5), result
    assert value["received"] > len(fixed(b"ok")) and value["discarded"] == 0, value
    assert value["wire_error"] == 3 and value["wire_offset"] == len(fixed(b"ok")), value
    interim = b"HTTP/1.1 103 Hints\r\nLink: </r>\r\n\r\n"
    peer = Peer(wire=chunked())
    peer.preludes = (interim, interim)
    config = Config(concurrency=1)
    result = run(executable, directory, [peer], config, pool_type=ControlledPool)
    value = complete(result, [peer], config)[0]
    assert value["interims"] == value["informational"] == 2 and value["trailers"] == 1, value


def limits(executable, directory):
    from resources import analyze
    with tempfile.TemporaryDirectory(prefix="https_batch_limits_") as temporary:
        path = Path(temporary) / "trace"
        # Caller context/arguments exist outside the marked library epoch.
        config = Config(concurrency=1, work=0, operations=0, pending=0, wire=0, body=0)
        result = run(executable, directory, [], config, trace=path)
        ledger = analyze(path, executable)
        assert result["cause"] == 0 and not result["outcomes"] and not ledger["epoch_allocations"] and not ledger["calls"].get("socket"), result
        for change, expected in (({"operations": 0}, 7), ({"work": 0}, 8),
                                 ({"pending": 0}, 11), ({"concurrency": 0}, 2),
                                 ({"max_jobs": 0}, 2)):
            result = run(executable, directory, [Peer(wire=fixed())], dataclasses.replace(Config(), **change), trace=path)
            ledger = analyze(path, executable)
            assert result["cause"] == expected and not ledger["calls"].get("socket"), result
        peers = [Peer(wire=fixed()), Peer(wire=fixed(), request_mode=2)]
        result = run(executable, directory, peers, Config(), trace=path)
        ledger = analyze(path, executable)
        assert result["cause"] == 12 and [v["kind"] for v in result["outcomes"]] == [0, 2], result
        assert not ledger["calls"].get("socket") and result["native"][3] == 0 and not result["seen"], result
        for cap, expected in (("wire", 9), ("body", 10)):
            peers = [Peer(wire=fixed(b"retained")), Peer(wire=fixed(b"discarded candidate"))]
            config = Config(concurrency=1)
            baseline = run(executable, directory, peers, config)
            complete(baseline, peers, config)
            total = baseline["stats"][cap]
            for bound in (total, total - 1):
                limited = dataclasses.replace(config, **{cap: bound})
                result = run(executable, directory, peers, limited, trace=path)
                analyze(path, executable)
                if bound == total:
                    complete(result, peers, limited)
                else:
                    assert result["cause"] == expected and [v["kind"] for v in result["outcomes"]] == [1, 4], result
                    assert result["outcomes"][0]["body"] == b"retained", result
        for change, cause in (({"tls_calls": 1}, 5), ({"call_io": 1}, 1)):
            result = run(executable, directory, [Peer(wire=fixed()), Peer(wire=fixed())],
                         dataclasses.replace(Config(), **change), trace=path, expected_failure=True)
            analyze(path, executable)
            assert result["cause"] == 0 and all(v["kind"] == 2 and v["cause"] == cause for v in result["outcomes"]), result
            if cause == 1:
                assert all(v["http_cause"] == 10 for v in result["outcomes"]), result
        # One completed owner survives global deadline cancellation. Held and
        # queued peers cannot evade the same absolute deadline through TLS WANT.
        peers = [Peer(wire=fixed(b"survives cancellation")), Peer(stall="handshake"),
                 Peer(stall="response"), Peer(stall="handshake")]
        result = run(executable, directory, peers, Config(timeout=350), trace=path, expected_failure=True)
        analyze(path, executable)
        kinds = [v["kind"] for v in result["outcomes"]]
        assert result["cause"] == 4 and kinds[0] == 1 and kinds[3] == 0 and all(v in (2, 3) for v in kinds[1:3]), result
        assert result["outcomes"][0]["body"] == b"survives cancellation" and 3 not in result["seen"], result


def resources(executable, directory):
    from controlled import ControlledPool
    from resources import analyze, injected_at, prefix
    with tempfile.TemporaryDirectory(prefix="https_batch_owners_") as temporary:
        path = Path(temporary) / "trace"
        config = Config(concurrency=1)
        # Cross-direction WANTs are synthetic one-shot *errors*, never positive
        # counts. Every successful retry still invokes real native OpenSSL.
        interim = b"HTTP/1.1 103 Hints\r\nLink: </r>\r\n\r\n"
        for fault in (1, 2, 5, 6, 9):
            peer = Peer(wire=fixed(), ending="clean")
            if fault == 1:
                peer.preludes = (interim, interim)
            limited = dataclasses.replace(config, native_fault=fault)
            result = run(executable, directory, [peer], limited, trace=path, pool_type=ControlledPool)
            analyze(path, executable)
            complete(result, [peer], limited)
            assert result["forced"] == 1, result
            if fault == 1:
                assert result["stable_writes"] > 0, result
        for fault in (3, 4, 7, 8):
            limited = dataclasses.replace(config, native_fault=fault)
            result = run(executable, directory, [Peer(wire=fixed(), ending="clean")], limited,
                         trace=path, expected_failure=True, pool_type=ControlledPool)
            analyze(path, executable)
            failed = result["outcomes"][0]
            assert result["cause"] == 0 and (failed["kind"], failed["cause"], failed["tls_cause"]) == (2, 2, 10), result
            assert failed["code"] != 0 and failed["ssl_error"] == 1 and failed["verify"] == 0 and result["forced"] == 1, result
        limited = dataclasses.replace(config, upref_fault=1)
        result = run(executable, directory, [Peer(wire=fixed())], limited, trace=path, expected_failure=True)
        analyze(path, executable)
        failed = result["outcomes"][0]
        assert result["cause"] == 0 and (failed["kind"], failed["cause"], failed["stage"]) == (2, 2, 1), result
        assert failed["code"] != 0 and result["native"][5] == 1 and not result["seen"], result
        # Distinguish TCP/per-job failures from shared poll/clock cancellation.
        # Bind clock injection after the first socket owner is acquired, rather
        # than corrupting fixture deadline construction or native CA setup.
        ordinary = [Peer(wire=fixed(b"one")), Peer(wire=fixed(b"two"))]
        baseline = run(executable, directory, ordinary, Config(), trace=path)
        complete(baseline, ordinary, Config())
        native = analyze(path, executable)
        first_socket = native["attempts"]["socket"][0]["line_number"]
        clock = next(event for event in native["attempts"]["clock_gettime"]
                     if event["epoch"] and event["line_number"] > first_socket and event["ip"] < 0x80000000)
        for syscall, ordinal, expected in (("socket", 1, 0), ("connect", 1, 0),
                                           ("poll", 1, 6), ("clock_gettime", clock["ordinal"], 5)):
            result = run(executable, directory, ordinary, Config(), trace=path, expected_failure=True,
                         faults=("%s:error=EIO:when=%d" % (syscall, ordinal),))
            observed = analyze(path, executable)
            event = injected_at(observed, syscall, ordinal, "EIO")
            assert event["ip"] == native["attempts"][syscall][ordinal - 1]["ip"], (syscall, event)
            assert result["cause"] == expected and result["stats"]["polls"] == observed["calls"].get("poll", 0), result
            if expected == 0:
                failed = result["outcomes"][0]
                assert [v["kind"] for v in result["outcomes"]] == [2, 1] and failed["cause"] == 3 and failed["errno"] == 5, result
                assert failed["stage"] == (2 if syscall == "socket" else 3) and result["outcomes"][1]["body"] == b"two", result
        result = run(executable, directory, ordinary, Config(), trace=path,
                     faults=("poll:error=EINTR:when=1",))
        observed = analyze(path, executable)
        injected_at(observed, "poll", 1, "EINTR")
        complete(result, ordinary, Config())
        assert result["stats"]["polls"] == observed["calls"]["poll"], result
        peers = [Peer(wire=chunked(BINARY)), Peer(wire=chunked(BINARY[::-1]))]
        config = Config(concurrency=2, take=0)
        baseline = run(executable, directory, peers, config, "waves", trace=path, pool_type=ControlledPool)
        complete(baseline, peers, config)
        ledger = analyze(path, executable)
        positions = ledger["epoch_allocations"]
        assert positions and ledger["max_sockets"] == 2, ledger
        after_network = 0
        for allocation in positions:
            result = run(executable, directory, peers, config, "waves", trace=path,
                         faults=("mmap:error=ENOMEM:when=%d" % allocation["ordinal"],),
                         expected_failure=True, pool_type=ControlledPool)
            faulted = analyze(path, executable)
            event = injected_at(faulted, "mmap", allocation["ordinal"], "ENOMEM")
            assert event["ip"] == allocation["ip"] and int(event["args"].split(",")[1]) == allocation["length"], (allocation, event)
            prefix(ledger, faulted, "mmap", allocation["ordinal"])
            values = actual_outcomes(result, config)
            assert result["cause"] in (3, 12) or any(v["kind"] == 2 and ((v["cause"] == 1 and v["http_cause"] == 2) or (v["cause"] == 2 and v["tls_cause"] == 9)) for v in values), result
            after_network += int(bool(faulted["calls"].get("socket")))
        result = run(executable, directory, peers, config, "waves", trace=path, pool_type=ControlledPool)
        complete(result, peers, config)
        analyze(path, executable)
        print("source-allocation-positions=%d after-network=%d" % (len(positions), after_network))


if __name__ == "__main__":
    mode, executable, directory = sys.argv[1:4]
    {"verified": verified, "framing": framing, "policies": policies,
     "transport": transport, "limits": limits, "resources": resources}[mode](executable, directory)
    if mode == "resources":
        import direct
        with tempfile.TemporaryDirectory(prefix="https_direct_") as temporary:
            COUNT += direct.cases(sys.argv[4], directory, Path(temporary) / "trace")
    print("https-batch-%s cases=%d" % (mode, COUNT))
