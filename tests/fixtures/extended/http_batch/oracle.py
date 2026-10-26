"""Real loopback peers and independent HTTP readers for ext::http_batch.

All production scheduling, requests, response framing and ownership are Lanius.
No wall-clock speed ratio is used as evidence of overlap or fairness.
"""
import dataclasses
import http.client
import io
import os
import re
import select
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

import h11
from resources import analyze

MAGIC = 1212301617
CHECKPOINT = MAGIC + 1
BINARY = bytes(range(256)) * 3 + b"\x00\xff\r\n"
COUNT = 0


@dataclasses.dataclass
class Config:
    concurrency: int = 2
    timeout: int = 1200
    max_jobs: int = 16
    pending: int = 1_048_576
    wire: int = 1_048_576
    body: int = 1_048_576
    operations: int = 100_000
    work: int = 32_000_000
    call_work: int = 1_000_000
    call_io: int = 10_000
    response: int = 8192
    response_body: int = 4096
    interims: int = 8
    take: int = -1
    start: int = 1
    length: int = -2
    checkpoint: int = 0
    head: int = 4096
    request: int = 8192
    jobs_layout: int = 0
    bytes_layout: int = 0
    line: int = 1024


@dataclasses.dataclass
class Job:
    wire: bytes = b""
    framing: str = "fixed"
    fragment: int = 0
    family: int = 4
    request_mode: int = 0
    request_body: int = 4
    behavior: str = "ordinary"
    port: int = 0


def fixed(body=BINARY, status=200):
    return b"HTTP/1.1 " + str(status).encode() + b" Result\r\nContent-Length: " + str(len(body)).encode() + b"\r\nX-Binary: \x80\xff\r\n\r\n" + body


def chunked(body=BINARY):
    parts = [b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"]
    for at in range(0, len(body), 29):
        block = body[at:at + 29]
        parts += [("%x;tag=ok\r\n" % len(block)).encode(), block, b"\r\n"]
    return b"".join(parts) + b"0\r\nX-Trailer: yes\r\n\r\n"


def close_body(body=BINARY):
    return b"HTTP/1.0 200 OK\r\nX: y\r\n\r\n" + body


def decoded(wire, method="POST"):
    class Sock:
        def makefile(self, *args):
            return io.BytesIO(wire)
    response = http.client.HTTPResponse(Sock(), method=method)
    response.begin()
    return response.status, response.read()


def packet(jobs, config):
    words = [len(jobs), config.concurrency, config.timeout, config.max_jobs,
             config.pending, config.wire, config.body, config.operations,
             config.work, config.call_work, config.call_io, config.response,
             config.response_body, config.interims, 0, config.take,
             config.start, config.length, config.checkpoint, config.head,
             config.request, config.jobs_layout, config.bytes_layout, config.line] + [0] * 8
    data = struct.pack("<32I", *(word & 0xffffffff for word in words))
    return data + b"".join(struct.pack("<4i", job.port, job.family, job.request_mode, job.request_body) for job in jobs)


class Peers:
    def __init__(self, jobs, concurrency, schedule="ordinary"):
        self.jobs = jobs
        self.concurrency = concurrency
        self.schedule = schedule
        self.stop = threading.Event()
        self.condition = threading.Condition()
        self.seen = set()
        self.closed = set()
        self.events = []
        self.errors = []
        self.listeners = []
        self.threads = []

    def record(self, kind, index):
        with self.condition:
            self.events.append((kind, index))
            if kind == "request":
                self.seen.add(index)
            elif kind == "closed":
                self.closed.add(index)
            self.condition.notify_all()

    def wait(self, predicate):
        with self.condition:
            while not predicate() and not self.stop.is_set():
                self.condition.wait(.05)
            return not self.stop.is_set()

    def gate(self, index):
        if self.schedule == "waves":
            start = index // self.concurrency * self.concurrency
            members = set(range(start, min(start + self.concurrency, len(self.jobs))))
            # No response before all full requests in this selected wave arrive.
            # Reverse release is causal: wait for each later connection's EOF.
            return self.wait(lambda: members <= self.seen and all(later in self.closed for later in members if later > index))
        if self.schedule == "fair":
            if index == 0:
                return self.wait(lambda: set(range(1, len(self.jobs))) <= self.closed)
            return self.wait(lambda: {0, 1} <= self.seen)
        if self.schedule == "failed-refill":
            if index == 0:
                return self.wait(lambda: {1, 4} <= self.closed)
            if index == 1:
                return self.wait(lambda: {0, 1} <= self.seen)
            if index == 4:
                return self.wait(lambda: 1 in self.closed)
            raise AssertionError(("injected begin failure unexpectedly connected", index))
        return True

    def start(self):
        for index, job in enumerate(self.jobs):
            family = socket.AF_INET6 if job.family == 6 else socket.AF_INET
            listener = socket.socket(family, socket.SOCK_STREAM)
            listener.bind(("::1" if job.family == 6 else "127.0.0.1", 0))
            job.port = listener.getsockname()[1]
            if job.behavior == "refused":
                listener.close()
                continue
            listener.listen(4)
            listener.settimeout(.05)
            self.listeners.append(listener)
            thread = threading.Thread(target=self.peer, args=(index, job, listener), daemon=True)
            thread.start()
            self.threads.append(thread)
        return self

    def peer(self, index, job, listener):
        conn = None
        try:
            while conn is None and not self.stop.is_set():
                try:
                    conn, _ = listener.accept()
                except TimeoutError:
                    pass
            if conn is None:
                return
            conn.settimeout(2)
            parser = h11.Connection(h11.SERVER)
            head, body = None, bytearray()
            while True:
                event = parser.next_event()
                if event is h11.NEED_DATA:
                    data = conn.recv(4096)
                    if not data:
                        return  # Valid for local/fault/cancellation cases.
                    parser.receive_data(data)
                elif isinstance(event, h11.Request):
                    head = event
                    assert head.method == (b"HEAD" if job.request_mode == 1 else b"POST"), head
                    assert head.target == ("/j%02d" % index).encode(), head
                    fields = list(head.headers)
                    assert [v for k, v in fields if k == b"host"] == [b"batch.example"], fields
                    assert [v for k, v in fields if k == b"connection"] == [b"close"], fields
                    assert [v for k, v in fields if k == b"content-length"] == [str(job.request_body).encode()], fields
                elif isinstance(event, h11.Data):
                    body.extend(event.data)
                elif isinstance(event, h11.EndOfMessage):
                    break
            assert head is not None and bytes(body) == bytes((0, 255, index, 10))[:job.request_body], (head, body)
            self.record("request", index)
            if not self.gate(index):
                return
            if job.behavior == "stall":
                self.stop.wait(3)
                return
            self.record("response", index)
            if job.fragment:
                for at in range(0, len(job.wire), job.fragment):
                    conn.sendall(job.wire[at:at + job.fragment])
            else:
                conn.sendall(job.wire)
            if job.framing == "close" or job.behavior == "truncate":
                conn.shutdown(socket.SHUT_WR)
            # Fixed/chunked peers keep their write side open: completion must
            # follow framing rather than a substituted connection EOF.
            while not self.stop.is_set():
                data = conn.recv(4096)
                if not data:
                    self.record("closed", index)
                    break
                assert False, ("unexpected request suffix", index, data)
        except (ConnectionResetError, BrokenPipeError):
            # A response allocation fault may close with unread peer bytes.
            # A reset/broken pipe proves termination and releases a fault-wave
            # dependency; a timeout never stands in for connection closure.
            if index in self.seen:
                self.record("closed", index)
        except (TimeoutError, ConnectionError, OSError):
            # The positive case asserts all requests and expected peer closes;
            # faults/abort can close or reset a partly written request.
            pass
        except BaseException as error:
            self.errors.append(error)
        finally:
            if conn is not None:
                conn.close()

    def finish(self):
        self.stop.set()
        with self.condition:
            self.condition.notify_all()
        for thread in self.threads:
            thread.join(2.2)
            assert not thread.is_alive(), "stranded test peer"
        for listener in self.listeners:
            listener.close()
        assert not self.errors, self.errors


def parse_outcome(read):
    words = struct.unpack("<16i", read(64))
    wire = read(words[12]) if words[0] == 1 else b""
    body = read(words[13]) if words[0] == 1 else b""
    return {"kind": words[0], "cause": words[1], "stage": words[2], "errno": words[3],
            "cleanup": words[4], "request": words[6], "sent": words[7], "received": words[8],
            "interims": words[9], "io": words[10], "work": words[11], "status": words[14],
            "trailers": words[15], "wire": wire, "body": body}


def parse(read):
    header = struct.unpack("<20i", read(80))
    assert header[0] == MAGIC and 0 <= header[2] <= 16, header
    names = ("jobs", "started", "complete", "failed", "aborted", "discarded", "peak_active",
             "operations", "polls", "io_calls", "work", "pending", "peak_pending", "wire", "body")
    report = {"cause": header[1], "stats": dict(zip(names, header[3:18])),
              "outcomes": [parse_outcome(read) for _ in range(header[2])]}
    if header[18]:
        report["taken"] = parse_outcome(read)
    return report


def run(executable, jobs, config=None, schedule="ordinary", trace=None, faults=()):
    global COUNT
    config = config or Config()
    peers = Peers(jobs, config.concurrency, schedule).start()
    command = [executable]
    if trace:
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-o", trace, "-e",
                   "trace=mmap,munmap,socket,close,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write",
                   *[item for fault in faults for item in ("-e", "inject=" + fault)], *command]
    process = None
    try:
        if not config.checkpoint:
            output = subprocess.run(command, input=packet(jobs, config), capture_output=True, timeout=6)
            assert output.returncode == 0 and not output.stderr, output
            stream = io.BytesIO(output.stdout)
            def read(count):
                data = stream.read(count)
                assert len(data) == count, (count, output)
                return data
            report = parse(read)
            assert not stream.read(), output
        else:
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
            process.stdin.write(packet(jobs, config))
            process.stdin.flush()
            until = time.monotonic() + 6
            def read(count):
                data = bytearray()
                while len(data) < count:
                    remaining = until - time.monotonic()
                    assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "protocol deadline"
                    part = os.read(process.stdout.fileno(), count - len(data))
                    assert part, ("premature protocol EOF", process.poll(), bytes(data))
                    data.extend(part)
                return bytes(data)
            report = parse(read)
            assert struct.unpack("<i", read(4))[0] == CHECKPOINT
            child = process.pid
            if trace:
                with open("/proc/%d/task/%d/children" % (child, child)) as source:
                    children = source.read().split()
                assert len(children) == 1, children
                child = int(children[0])
            assert set(os.listdir("/proc/%d/fd" % child)) == {"0", "1", "2"}, ("fds survived destroy", child)
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            stdout, stderr = process.communicate(timeout=3)
            assert process.returncode == 0 and not stdout and not stderr, (process.returncode, stdout, stderr)
        assert report["stats"]["peak_active"] <= config.concurrency, report
        assert 0 <= report["stats"]["operations"] <= config.operations, report
        assert 0 <= report["stats"]["work"] <= config.work, report
        assert report["stats"]["pending"] == 0 and report["stats"]["peak_pending"] <= config.pending, report
        assert report["stats"]["wire"] <= config.wire and report["stats"]["body"] <= config.body, report
        effective = report["outcomes"] + ([report["taken"]] if "taken" in report else [])
        assert report["stats"]["io_calls"] == sum(outcome["io"] for outcome in effective), report
        for name, kind in (("complete", 1), ("failed", 2), ("aborted", 3), ("discarded", 4)):
            assert report["stats"][name] == sum(outcome["kind"] == kind for outcome in effective), report
        if effective and all(outcome["kind"] in (1, 2, 5) for outcome in effective):
            assert report["stats"]["work"] == sum(outcome["work"] for outcome in effective), report
        ledger = analyze(trace) if trace else None
        if ledger:
            assert ledger["max_sockets"] <= config.concurrency, ledger
            assert report["stats"]["polls"] == ledger["calls"].get("poll", 0), (report, ledger)
        COUNT += 1
        return report, peers, ledger
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.communicate()
        peers.finish()


def complete(report, jobs, taken=-1):
    assert report["cause"] == 0 and len(report["outcomes"]) == len(jobs), report
    assert report["stats"]["complete"] == len(jobs) and report["stats"]["failed"] == 0, report
    for index, (outcome, job) in enumerate(zip(report["outcomes"], jobs)):
        if index == taken:
            assert outcome["kind"] == 5, outcome
            outcome = report["taken"]
        assert outcome["kind"] == 1 and outcome["sent"] == outcome["request"], outcome
        status, body = decoded(outcome["wire"], "HEAD" if job.request_mode == 1 else "POST")
        assert outcome["status"] == status and outcome["body"] == body, outcome
        # Associate with the independent expected bytes, not only a second
        # parser applied to whatever bytes the implementation chose to return.
        expected_wire = job.wire
        while expected_wire.startswith(b"HTTP/1.1 10"):
            expected_wire = expected_wire.split(b"\r\n\r\n", 1)[1]
        assert outcome["wire"] == expected_wire, (index, outcome, job)


def injected_at(ledger, syscall, ordinal, error, repeated=False):
    events = ledger["attempts"].get(syscall, [])
    injected = [event for event in events if event["injected"]]
    expected = list(range(ordinal, len(events) + 1)) if repeated else [ordinal]
    assert [event["ordinal"] for event in injected] == expected, (syscall, ordinal, error, ledger)
    assert injected and all(re.match(r"^-1 " + error + r"(?:\s|$)", event["result"]) for event in injected), injected
    all_markers = [event for name, attempts in ledger["attempts"].items() for event in attempts if event["injected"]]
    assert len(all_markers) == len(injected), (syscall, all_markers)
    return injected


def contracts(exe):
    with tempfile.TemporaryDirectory() as directory:
        path = directory + "/trace"
        empty, _, ledger = run(exe, [], Config(work=0, operations=0, pending=0, wire=0, body=0), trace=path)
        assert empty["cause"] == 0 and empty["outcomes"] == [] and not ledger["allocations"] and not ledger["calls"].get("socket"), empty
        for layout in range(2):
            for job_layout in range(2):
                jobs = [Job(fixed(bytes((i, 0, 255)) * 23)) for i in range(3)]
                config = Config(bytes_layout=layout, jobs_layout=job_layout, take=1)
                report, peers, _ = run(exe, jobs, config, trace=path)
                complete(report, jobs, taken=1)
                assert peers.seen == {0, 1, 2}
        # Each request is prepared before any socket, including late bad rows.
        for bad in (2, 3, 4):
            jobs = [Job(fixed(b"first")), Job(fixed(b"bad"), request_mode=bad)]
            report, peers, ledger = run(exe, jobs, trace=path)
            assert report["cause"] == 12 and [o["kind"] for o in report["outcomes"]] == [0, 2], report
            assert not peers.seen and not ledger["calls"].get("socket"), ledger
        for changes, expected in (({"start": -1}, 1), ({"start": 2147483647, "length": 1}, 1),
                                  ({"max_jobs": 0}, 2), ({"max_jobs": 4097}, 2),
                                  ({"concurrency": 0}, 2), ({"concurrency": 65}, 2),
                                  ({"max_jobs": 1, "concurrency": 2}, 2), ({"max_jobs": 1, "concurrency": 1}, 1)):
            report, peers, ledger = run(exe, [Job(fixed()), Job(fixed())], dataclasses.replace(Config(), **changes), trace=path)
            assert report["cause"] == expected and not peers.seen and not ledger["calls"].get("socket"), report
    print("http-batch-contracts cases=%d" % COUNT)


def overlap(exe):
    with tempfile.TemporaryDirectory() as directory:
        trace = directory + "/trace"
        for concurrency in (1, 2, 3, 4):
            jobs = [Job(fixed(bytes((index, 0, 255)) * 19)) for index in range(7)]
            report, peers, ledger = run(exe, jobs, Config(concurrency=concurrency), "waves", trace)
            complete(report, jobs)
            assert peers.seen == set(range(7)) and ledger["max_sockets"] == concurrency
            for kind, index in peers.events:
                if kind == "response":
                    preceding = peers.events[:peers.events.index((kind, index))]
                    first = index // concurrency * concurrency
                    assert {i for event, i in preceding if event == "request"} >= set(range(first, min(first + concurrency, 7)))
        jobs = [Job(fixed(bytes((index,)) * 67)) for index in range(5)]
        report, peers, ledger = run(exe, jobs, Config(concurrency=2), "fair", trace)
        complete(report, jobs)
        assert peers.events.index(("response", 0)) > max(peers.events.index(("closed", index)) for index in range(1, 5)), peers.events
        assert ledger["max_sockets"] == 2
    print("http-batch-overlap cases=%d" % COUNT)


def matrix(exe):
    wires = [(fixed(), "fixed"), (chunked(), "chunked"), (close_body(), "close")]
    for family in (4, 6):
        for fragment in (0, 1, 7):
            jobs = [Job(wire, framing, fragment, family) for wire, framing in wires]
            report, _, _ = run(exe, jobs)
            complete(report, jobs)
    interim = b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Hints\r\nLink: </x>\r\n\r\n"
    jobs = [Job(interim + chunked(), "chunked", 1), Job(b"HTTP/1.1 200 OK\r\nContent-Length: 99\r\n\r\n", request_mode=1), Job(fixed(b"no", 404))]
    report, _, _ = run(exe, jobs)
    complete(report, jobs)
    assert report["outcomes"][0]["interims"] == 2 and report["outcomes"][0]["trailers"] == 1
    bad = [b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nx",
           b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
           b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: x\r\n\r\n"]
    for position in range(3):
        jobs = [Job(fixed(bytes((i,)))) for i in range(5)]
        jobs[position] = Job(bad[position], behavior="truncate", framing="close")
        jobs[4] = Job(behavior="refused")
        report, _, _ = run(exe, jobs, Config(concurrency=3))
        assert report["cause"] == 0 and [o["kind"] for o in report["outcomes"]] == [2 if i in (position, 4) else 1 for i in range(5)], report
        assert report["outcomes"][4]["errno"] == 111 and report["stats"]["failed"] == 2, report
        assert report["outcomes"][position]["cause"] == (12 if position == 2 else 5), report
    print("http-batch-matrix cases=%d" % COUNT)


def limits(exe):
    with tempfile.TemporaryDirectory() as directory:
        trace = directory + "/trace"
        for change, expected in (({"operations": 0}, 7), ({"work": 0}, 8),
                                 ({"work": 999999}, 8), ({"pending": 0}, 11), ({"timeout": 0}, 4)):
            report, _, ledger = run(exe, [Job(fixed())], dataclasses.replace(Config(), **change), trace=trace)
            assert report["cause"] == expected and not ledger["calls"].get("socket"), report
            if change == {"pending": 0}:
                boundary = report["stats"]["operations"]
        # Deterministic pre-network operation threshold, independent of TCP
        # partitioning or the scheduler's private number of ready iterations.
        for budget, expected in ((boundary, 11), (boundary - 1, 7)):
            report, _, ledger = run(exe, [Job(fixed())], Config(pending=0, operations=budget), trace=trace)
            assert report["cause"] == expected and not ledger["calls"].get("socket"), report
        report, _, _ = run(exe, [Job(fixed())], Config(work=1_000_000), trace=trace)
        complete(report, [Job(fixed())])
        jobs = [Job(fixed(b"a" * 31)), Job(fixed(b"b" * 47))]
        baseline, _, _ = run(exe, jobs, Config(concurrency=1), trace=trace)
        complete(baseline, jobs)
        reserved, _, ledger = run(exe, jobs, Config(concurrency=2, work=1_000_000 + baseline["stats"]["work"]), trace=trace)
        complete(reserved, jobs)
        assert reserved["stats"]["peak_active"] == 1 and ledger["max_sockets"] == 1, reserved
        pending = sum(o["request"] + 4 for o in baseline["outcomes"])
        for cap, expected in ((pending, 0), (pending - 1, 11)):
            report, _, ledger = run(exe, jobs, Config(concurrency=1, pending=cap), trace=trace)
            assert report["cause"] == expected, (cap, report)
            if expected:
                assert not ledger["calls"].get("socket"), ledger
            else:
                complete(report, jobs)
        for name, expected in (("wire", 9), ("body", 10)):
            total = baseline["stats"][name]
            for cap in (total, total - 1):
                config = dataclasses.replace(Config(concurrency=1), **{name: cap})
                report, _, _ = run(exe, jobs, config, trace=trace)
                if cap == total:
                    complete(report, jobs)
                else:
                    assert report["cause"] == expected and [o["kind"] for o in report["outcomes"]] == [1, 4], report
        # Completed response survives cancellation; queued jobs are not opened.
        jobs = [Job(fixed(b"retained")), Job(behavior="stall"), Job(behavior="stall"), Job(behavior="stall")]
        report, peers, _ = run(exe, jobs, Config(concurrency=2, timeout=500, checkpoint=1), trace=trace)
        kinds = [o["kind"] for o in report["outcomes"]]
        assert report["cause"] == 4 and kinds[0] == 1 and kinds[3] == 0 and all(kind in (2, 3) for kind in kinds[1:3]), (report, peers.events)
        assert all(o["kind"] == 3 or o["cause"] == 3 for o in report["outcomes"][1:3]), report
        assert report["outcomes"][0]["body"] == b"retained" and 3 not in peers.seen
        # Per-job I/O quota failures do not become a shared cancellation.
        report, _, _ = run(exe, [Job(fixed()), Job(fixed()), Job(fixed())], Config(call_io=1), trace=trace)
        assert report["cause"] == 0 and all(o["kind"] == 2 and o["cause"] == 10 for o in report["outcomes"]), report
    print("http-batch-limits cases=%d" % COUNT)


def faults(exe):
    with tempfile.TemporaryDirectory() as directory:
        trace = directory + "/trace"
        jobs = [Job(fixed(b"one")), Job(chunked(b"two"), "chunked")]
        baseline, _, ledger = run(exe, jobs, Config(checkpoint=1), trace=trace)
        complete(baseline, jobs)
        for syscall in ("socket", "connect", "getsockopt", "getpeername", "sendto", "recvfrom", "poll", "clock_gettime"):
            if not ledger["calls"].get(syscall):
                continue
            # First clock belongs to fixture deadline construction. Fault the
            # first library observation instead, preserving valid test input.
            ordinal = 2 if syscall == "clock_gettime" else 1
            report, _, faulted = run(exe, jobs, Config(checkpoint=1), trace=trace, faults=("%s:error=EIO:when=%d" % (syscall, ordinal),))
            injected_at(faulted, syscall, ordinal, "EIO")
            assert report["cause"] in ((5,) if syscall == "clock_gettime" else (6,) if syscall == "poll" else (0,)), report
            if report["cause"] == 0:
                assert any(o["kind"] == 2 and o["cause"] == 4 for o in report["outcomes"]), report
        for syscall in ("sendto", "recvfrom", "poll"):
            report, _, faulted = run(exe, jobs, Config(checkpoint=1), trace=trace, faults=(syscall + ":error=EINTR:when=1",))
            injected_at(faulted, syscall, 1, "EINTR")
            complete(report, jobs)
        for syscall in ("recvfrom", "poll"):
            report, _, ledger2 = run(exe, jobs, Config(operations=1600, timeout=1000, checkpoint=1), trace=trace, faults=(syscall + ":error=EINTR:when=1+",))
            injected_at(ledger2, syscall, 1, "EINTR", repeated=True)
            assert report["cause"] in (4, 7) and ledger2["calls"].get(syscall, 0) > 1, report
    print("http-batch-faults cases=%d" % COUNT)


def allocations(exe):
    with tempfile.TemporaryDirectory() as directory:
        trace = directory + "/trace"
        interim = b"HTTP/1.1 103 Hints\r\nLink: </r>\r\n\r\n"
        jobs = [Job(interim + chunked(), "chunked"), Job(interim + chunked(BINARY[::-1]), "chunked")]
        config = Config(checkpoint=1, take=0)
        baseline, _, ledger = run(exe, jobs, config, "waves", trace=trace)
        complete(baseline, jobs, taken=0)
        allocations = ledger["allocations"]
        assert allocations and ledger["max_sockets"] == 2, ledger
        native_failures = 0
        for allocation in allocations:
            report, _, injected = run(exe, jobs, config, "waves", trace=trace,
                                     faults=("mmap:error=ENOMEM:when=%d" % allocation["ordinal"],))
            failed = injected_at(injected, "mmap", allocation["ordinal"], "ENOMEM")
            assert failed[0]["ip"] == allocation["ip"] and int(failed[0]["args"].split(",")[1]) == allocation["length"], (allocation, failed)
            # Bind each one-shot fault to this baseline's entire reached prefix.
            # A changed concurrent receive/coalescing schedule is a harness
            # discrepancy to diagnose, never evidence for an unvisited leaf.
            shape = lambda event: (event["ip"], int(event["args"].split(",")[1]))
            ordinal = allocation["ordinal"]
            assert [shape(e) for e in injected["attempts"]["mmap"][:ordinal]] == [shape(e) for e in ledger["attempts"]["mmap"][:ordinal]], (allocation, injected, ledger)
            outcomes = report["outcomes"] + ([report["taken"]] if "taken" in report else [])
            assert report["cause"] in (3, 12) or any(o["kind"] == 2 and o["cause"] == 2 for o in outcomes), report
            native_failures += int(bool(injected["calls"].get("socket")))
        # Same compiled module is usable after the campaign; each child also
        # reached the before-exit no-fd checkpoint with balanced owner maps.
        recovery, _, _ = run(exe, jobs, config, "waves", trace=trace)
        complete(recovery, jobs, taken=0)
        print("allocation-positions=%d after-network=%d" % (len(allocations), native_failures))
    print("http-batch-allocations cases=%d" % COUNT)


def refill_poll_timeout(line):
    match = re.match(r"^(?:\[[^]]+\]\s+)?poll\((.*)\)\s+=\s+", line)
    return int(match.group(1).rsplit(",", 1)[1]) if match else None


def refill_poll_controls():
    # Result annotations contain parentheses too; only syscall arguments carry
    # the timeout. Keep controls durable alongside the regression that uses it.
    samples = [
        ("[0000000000401234] poll([{fd=3, events=POLLIN}], 1, 0) = 0 (Timeout)", 0),
        ("poll([{fd=3, events=POLLIN}], 1, 0) = 1 ([{fd=3, revents=POLLIN}])", 0),
        ("poll([{fd=3, events=POLLIN}], 1, 1200) = 0 (Timeout)", 1200),
        ("poll([{fd=3, events=POLLIN}], 1, -1) = 1 ([{fd=3, revents=POLLIN}])", -1),
    ]
    for line, expected in samples:
        assert refill_poll_timeout(line) == expected, line
    assert refill_poll_timeout("close(4) = 0") is None


def refill_failures(exe):
    """Adjacent regression: consecutive failed begins cannot strand a free slot.

    Job0 holds one slot. Job1 finishes in the other; queued jobs2/3 fail socket
    creation, then job4 must finish before job0 can receive its response.
    The previous refill bug cannot complete this causal dependency.
    """
    refill_poll_controls()
    with tempfile.TemporaryDirectory() as directory:
        trace = directory + "/trace"
        jobs = [Job(fixed(bytes((index, 0, 255)) * 17)) for index in range(5)]
        report, peers, ledger = run(exe, jobs, Config(concurrency=2, checkpoint=1),
                                    "failed-refill", trace,
                                    faults=("socket:error=EIO:when=3..4",))
        assert report["cause"] == 0 and [o["kind"] for o in report["outcomes"]] == [1, 1, 2, 2, 1], report
        assert report["stats"]["started"] == 5 and report["stats"]["complete"] == 3 and report["stats"]["failed"] == 2, report
        assert report["stats"]["peak_active"] == 2 and ledger["max_sockets"] == 2, ledger
        for index in (0, 1, 4):
            outcome = report["outcomes"][index]
            status, body = decoded(jobs[index].wire)
            assert outcome["status"] == status and outcome["wire"] == jobs[index].wire and outcome["body"] == body, (index, outcome)
        for index in (2, 3):
            outcome = report["outcomes"][index]
            assert (outcome["cause"], outcome["stage"], outcome["errno"], outcome["cleanup"]) == (4, 1, 5, 0), outcome
            assert outcome["io"] == 1 and outcome["sent"] == 0 and outcome["received"] == 0, outcome
        sockets = ledger["attempts"]["socket"]
        assert len(sockets) == 5 and [event["ordinal"] for event in sockets if event["injected"]] == [3, 4], sockets
        assert all(re.match(r"^-1 EIO(?:\s|$)", sockets[index]["result"]) for index in (2, 3)), sockets
        assert all(not sockets[index]["injected"] and int(sockets[index]["result"].split()[0]) >= 0 for index in (0, 1, 4)), sockets
        assert all((event["ip"], event["args"]) == (sockets[0]["ip"], sockets[0]["args"]) for event in sockets), sockets
        markers = [(name, event) for name, events in ledger["attempts"].items() for event in events if event["injected"]]
        assert [name for name, _ in markers] == ["socket", "socket"], markers
        # Bind the failed-begin prefix to the successful sibling's real close,
        # rather than assuming ordinal3 must have happened after a response.
        with open(trace, encoding="utf-8") as source:
            lines = source.read().splitlines()
        socket_lines = [position for position, line in enumerate(lines) if re.match(r"^(?:\[[^]]+\]\s+)?socket\(", line)]
        sibling_fd = int(sockets[1]["result"].split()[0])
        close_lines = [position for position, line in enumerate(lines)
                       if re.match(r"^(?:\[[^]]+\]\s+)?close\(" + str(sibling_fd) + r"\)\s+=\s+0$", line)]
        assert len(socket_lines) == 5 and any(socket_lines[1] < position < socket_lines[2] for position in close_lines), (sockets, close_lines, lines)
        for line in lines[socket_lines[2] + 1:socket_lines[4]]:
            timeout = refill_poll_timeout(line)
            if timeout is not None:
                assert timeout == 0, ("blocked with eligible queued work after failed begin", line, lines)
        assert peers.seen == {0, 1, 4}, peers.events
        assert all(peers.events.index(("request", index)) < peers.events.index(("response", 1)) for index in (0, 1)), peers.events
        assert peers.events.index(("response", 4)) > peers.events.index(("closed", 1)), peers.events
        assert peers.events.index(("response", 0)) > peers.events.index(("closed", 4)), peers.events
    print("http-batch-refill-failures cases=%d" % COUNT)


if __name__ == "__main__":
    {"contracts": contracts, "overlap": overlap, "matrix": matrix,
     "limits": limits, "faults": faults, "allocations": allocations,
     "refill-failures": refill_failures}[sys.argv[1]](sys.argv[2])
