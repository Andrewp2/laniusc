"""Actual finite services, causal peer dependencies and independent HTTP readers.

No production parser, scheduler, TLS record code or cryptography lives here.
The only imported repository helpers are guarded certificate/context modules;
existing command-line oracle modules are never imported or executed.
"""
import email.utils
import faulthandler
import http.client
import importlib.util
import io
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import traceback

import h11

from trace_events import Trace

sys.dont_write_bytecode = True
FIXTURES = Path(__file__).resolve().parents[1]
TRACE_CALLS = ("socket,bind,listen,accept4,fcntl,getsockname,getsockopt,setsockopt,"
               "close,shutdown,sendto,recvfrom,poll,read,write,mmap,munmap,"
               "openat,open,clock_gettime,rt_sigaction")
REPORT_FIELDS = ("received", "sent", "response", "interim", "drain", "tail",
                 "io", "cleanup", "cleanup-errors", "work", "scan", "id",
                 "rejected", "shutdown", "eof", "closed", "code")
RESPONSE_SECONDS = 8
OVERALL_SECONDS = 30


class Journal:
    """Flush causal peer phases before a later wait can fail or be killed."""
    def __init__(self, path):
        self.output = Path(path).open("w", buffering=1)
        self.start = time.monotonic()
        self.phase = "created"

    def note(self, phase, **values):
        self.phase = phase
        fields = " ".join(f"{key}={value!r}" for key, value in values.items())
        self.output.write(f"{time.monotonic() - self.start:.6f} {phase} {fields}\n")
        self.output.flush()

    def close(self):
        self.output.close()


def parse_reports(errors, tls):
    assert errors.endswith(b"\n"), ("unterminated service report", errors)
    expected = set(REPORT_FIELDS) | {"failed"} | ({"tls"} if tls else set())
    records = []
    for line in errors.splitlines():
        assert line.startswith(b"received=") and line.split()[-1].startswith(b"failed="), (
            "unexpected service diagnostic/report framing", line)
        record = {}
        for item in line.split():
            match = re.fullmatch(rb"([a-z][a-z0-9-]*)=([0-9]+)", item)
            assert match and match[1].decode() not in record, line
            value = int(match[2])
            assert value <= 18446744073709551615, line
            record[match[1].decode()] = value
        assert set(record) == expected, ("missing/unknown service report field", record)
        records.append(record)
    return records


def successful_report(record, ordinal, request_bytes, response_bytes, tls):
    assert record["id"] == ordinal, record
    assert record["received"] == request_bytes, (record, request_bytes)
    assert record["sent"] == record["response"] == response_bytes, record
    assert record["interim"] == record["drain"] == record["tail"] == 0, record
    assert record["code"] == record["failed"] == record["rejected"] == record["cleanup-errors"] == 0, record
    assert record["shutdown"] == record["eof"] == record["closed"] == 1, record
    assert record["cleanup"] == 1 and record["io"] > 0 and record["work"] > 0, record
    if tls:
        assert record["tls"] > 0, record


def helper(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def binary(count, salt):
    block = bytes((index * 73 + salt) & 255 for index in range(256))
    return (block * ((count + 255) // 256))[:count]


def request(body=None):
    method, target = (b"GET", b"/health") if body is None else (b"POST", b"/echo")
    payload = b"" if body is None else body
    parser = h11.Connection(h11.CLIENT)
    wire = parser.send(h11.Request(method=method, target=target,
                                   headers=[(b"host", b"localhost"),
                                            (b"content-length", str(len(payload)).encode()),
                                            (b"connection", b"close")]))
    if payload:
        wire += parser.send(h11.Data(data=payload))
    wire += parser.send(h11.EndOfMessage())
    return wire, parser, b"ok\n" if body is None else body


class Response:
    def __init__(self, connection, parser, expected, note=None):
        self.connection, self.parser, self.expected = connection, parser, expected
        self.wire, self.body = bytearray(), bytearray()
        self.head, self.ended = None, False
        self.note = note or (lambda *args, **kwargs: None)

    def advance(self, head_only=False):
        until = time.monotonic() + RESPONSE_SECONDS
        next_progress = (len(self.wire) // 262144 + 1) * 262144
        self.note("response-start", head_only=head_only, wire=len(self.wire),
                  body=len(self.body), expected=len(self.expected))
        while not self.ended:
            remaining = until - time.monotonic()
            assert remaining > 0, (
                "absolute HTTP response deadline", head_only, len(self.wire),
                len(self.body), len(self.expected))
            event = self.parser.next_event()
            if event is h11.NEED_DATA:
                # An active trickle must not reset the whole response deadline.
                self.connection.settimeout(min(6, remaining))
                try:
                    data = self.connection.recv(65536)
                except OSError as error:
                    self.note("response-recv-failed", wire=len(self.wire),
                              body=len(self.body), expected=len(self.expected),
                              error=repr(error))
                    raise
                assert data, ("HTTP EOF before complete response", bytes(self.wire[:256]))
                self.wire.extend(data)
                if len(self.wire) >= next_progress:
                    self.note("response-progress", wire=len(self.wire),
                              body=len(self.body), expected=len(self.expected))
                    next_progress = (len(self.wire) // 262144 + 1) * 262144
                assert len(self.wire) <= len(self.expected) + 65536, len(self.wire)
                self.parser.receive_data(data)
            elif isinstance(event, h11.Response):
                assert self.head is None and event.status_code == 200 and event.http_version == b"1.1", event
                self.head = event
                fields = list(event.headers)
                assert [v for k, v in fields if k == b"connection"] == [b"close"], fields
                assert [v for k, v in fields if k == b"content-length"] == [str(len(self.expected)).encode()], fields
                assert not [v for k, v in fields if k == b"transfer-encoding"], fields
                dates = [v for k, v in fields if k == b"date"]
                assert len(dates) == 1 and len(dates[0]) == 29, dates
                date = email.utils.parsedate_to_datetime(dates[0].decode("ascii"))
                assert email.utils.format_datetime(date, usegmt=True).encode() == dates[0]
                self.note("response-head", wire=len(self.wire), expected=len(self.expected))
                if head_only:
                    return
            elif isinstance(event, h11.Data):
                self.body.extend(event.data)
                assert self.expected[:len(self.body)] == self.body, (
                    "wrong response prefix", len(self.body), len(self.expected))
            elif isinstance(event, h11.EndOfMessage):
                self.ended = True
            else:
                raise AssertionError(("unexpected HTTP event", event))
        assert self.head is not None and bytes(self.body) == self.expected
        assert self.parser.trailing_data[0] == b"", self.parser.trailing_data
        class Sock:
            def makefile(_, *args):
                return io.BytesIO(self.wire)
        independent = http.client.HTTPResponse(Sock())
        independent.begin()
        assert independent.status == 200 and independent.read() == self.expected
        independent.close()
        self.note("response-complete", wire=len(self.wire), body=len(self.body))


class Peer:
    def __init__(self, service, body=None, *, handshake=True, await_accept=True):
        self.service = service
        self.wire, self.parser, self.expected = request(body)
        raw = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        raw.settimeout(6)
        service.note("peer-connect-start", body=len(self.expected))
        raw.connect(service.endpoint)
        self.initial_receive_buffer = raw.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        self.port = raw.getsockname()[1]
        self.connection = raw
        service.note("peer-connected", port=self.port,
                     receive_initial=self.initial_receive_buffer)
        self.record = None
        try:
            if await_accept:
                self.record = service.trace.connection(self.port)
                self.note("peer-accepted")
            if service.tls:
                self.connection = service.context.wrap_socket(
                    raw, server_hostname="localhost", do_handshake_on_connect=False,
                    suppress_ragged_eofs=False)
                if handshake and await_accept:
                    self.handshake()
        except BaseException:
            self.connection.close()
            raise
        service.peers.append(self)
        self.response = Response(self.connection, self.parser, self.expected, self.note)
        self.sent = False
        self.half_closed = False

    def note(self, phase, **values):
        self.service.note(phase, port=self.port,
                          ordinal=None if self.record is None else self.record.ordinal,
                          fd=None if self.record is None else self.record.fd,
                          generation=None if self.record is None else self.record.generation,
                          **values)

    def activate(self):
        assert self.record is None
        self.record = self.service.trace.connection(self.port)
        self.note("peer-accepted")
        if self.service.tls:
            self.handshake()

    def handshake(self):
        self.note("tls-handshake-start")
        self.connection.do_handshake()
        assert self.connection.getpeercert() and self.connection.version() == "TLSv1.3"
        self.note("tls-handshake-complete")

    def send(self, partial=False, half_close=True):
        self.note("request-send-start", bytes=len(self.wire) - (2 if partial else 0), partial=partial)
        self.connection.sendall(self.wire[:-2] if partial else self.wire)
        self.note("request-send-complete", partial=partial)
        if not partial:
            self.sent = True
            if not self.service.tls and half_close:
                self.connection.shutdown(socket.SHUT_WR)
                self.half_closed = True

    def release_partial(self):
        assert not self.service.tls
        self.note("partial-head-release")
        self.connection.sendall(self.wire[-2:])
        self.sent = True
        self.connection.shutdown(socket.SHUT_WR)
        self.half_closed = True

    def finish(self):
        assert self.sent
        self.note("peer-finish-start")
        if not self.service.tls and not self.half_closed:
            self.connection.shutdown(socket.SHUT_WR)
            self.half_closed = True
        self.response.advance()
        if self.service.tls:
            # unwrap both sends and requires close_notify; ragged EOF is fatal.
            self.note("tls-unwrap-start")
            self.connection = self.connection.unwrap()
            self.connection.settimeout(6)
            self.note("tls-unwrap-complete")
        self.note("tcp-eof-wait")
        assert self.connection.recv(1) == b"", "surplus HTTP bytes or missing TCP EOF"
        self.service.trace.closed(self.record)
        self.note("peer-closed", close_event=self.record.closed)
        self.connection.close()
        return len(self.response.wire)

    def close(self):
        self.connection.close()


class Service:
    def __init__(self, executable, directory, tls, count, maximum_body, journal):
        self.directory, self.tls, self.count = Path(directory), tls, count
        self.note = journal.note
        self.peers = []
        self.context = None
        arguments = [str(executable), "127.0.0.1:0"]
        if tls:
            certificates = helper("server_concurrency_certificates",
                                  FIXTURES / "openssl_tls_server/certificates.py")
            certificates.generate(self.directory)
            clients = helper("server_concurrency_client_context",
                             FIXTURES / "openssl_tls_server/client.py")
            self.context = clients.context(self.directory, version=ssl.TLSVersion.TLSv1_3)
            assert self.context.check_hostname and self.context.verify_mode == ssl.CERT_REQUIRED
            arguments += [str(self.directory / "valid.pem"), str(self.directory / "valid.key")]
        options = ["--requests", str(count), "--concurrency", "2",
                   "--timeout", "12000", "--service-timeout", "20000", "--report",
                   "--max-request", str(maximum_body + 65536),
                   "--max-response", str(maximum_body + 65536),
                   "--max-body", str(maximum_body), "--max-head", "4096",
                   "--max-headers", "16", "--max-work", "268435456",
                   "--max-io", "200000"]
        if tls:
            options += ["--max-tls", "200000"]
        self.trace_path = self.directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96",
                   "-o", str(self.trace_path), "-e", "trace=" + TRACE_CALLS,
                   *arguments, *options]
        self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        bufsize=0)
        self.trace = Trace(self.trace_path, self.process)
        self.start = time.monotonic()
        self.collected = False
        self.note("service-start", pid=self.process.pid, tls=tls, requests=count)
        try:
            self.endpoint = self.read_endpoint()
            self.note("service-endpoint", endpoint=self.endpoint)
        except BaseException:
            self.close()
            raise

    def read_endpoint(self):
        until, line = time.monotonic() + 6, bytearray()
        while not line.endswith(b"\n"):
            remaining = until - time.monotonic()
            assert remaining > 0 and select.select([self.process.stdout], [], [], remaining)[0], "startup deadline"
            data = os.read(self.process.stdout.fileno(), 1)
            assert data and len(line) < 96, ("invalid startup endpoint", bytes(line), self.process.poll())
            line.extend(data)
        match = re.fullmatch(rb"127\.0\.0\.1:([0-9]+)\n", line)
        assert match and 0 < int(match[1]) <= 65535, line
        return "127.0.0.1", int(match[1])

    def finish(self, peers):
        self.note("service-collect-start")
        output, errors = self.process.communicate(timeout=6)
        self.collected = True
        (self.directory / "native.stdout").write_bytes(output)
        (self.directory / "native.stderr").write_bytes(errors)
        self.note("service-collected", status=self.process.returncode,
                  stdout=len(output), stderr=len(errors))
        assert self.process.returncode == 0 and output == b"", (
            "service completion", self.process.returncode, output, errors)
        records = parse_reports(errors, self.tls)
        assert len(records) == len(peers) == self.count, (records, errors)
        for ordinal, (record, peer) in enumerate(zip(records, peers)):
            assert ordinal == peer.record.ordinal, (records, peer.record)
            successful_report(record, ordinal, len(peer.wire), len(peer.response.wire), self.tls)
        observed = self.trace.finish(self.count)
        observed["seconds"] = time.monotonic() - self.start
        return observed

    def assert_reports_pending(self):
        assert self.process.poll() is None, "service exited while held peer remains active"
        assert not select.select([self.process.stderr], [], [], 0)[0], (
            "reports/diagnostics published before finite service run completed", self.directory)

    def close(self):
        self.note("cleanup-start", status=self.process.poll())
        for peer in self.peers:
            peer.close()
        if self.process.poll() is None:
            self.process.kill()  # --kill-on-exit also terminates its tracee.
        if self.collected:
            self.process.stdout.close()
            self.process.stderr.close()
            return
        output, errors = self.process.communicate(timeout=2)
        self.collected = True
        (self.directory / "native.stdout").write_bytes(output)
        (self.directory / "native.stderr").write_bytes(errors)
        self.note("cleanup-collected", status=self.process.returncode,
                  stdout=len(output), stderr=len(errors))


def refill(service):
    first = Peer(service, handshake=not service.tls)
    if not service.tls:
        first.send(partial=True)
        service.trace.received(first.record, len(first.wire) - 2)
    service.trace.assert_open(first.record)
    second = Peer(service, binary(17, 21))
    second.send(half_close=False)
    second.response.advance(head_only=True)
    # At capacity, establish the next TCP connection in the listener backlog
    # before retiring slot 1. No third accepted owner is permitted yet.
    third = Peer(service, binary(29, 34), await_accept=False)
    service.trace.assert_open(first.record)
    service.trace.assert_open(second.record)
    assert not any(record.port == third.port for record in service.trace.accepted)
    second.finish()
    service.trace.assert_open(first.record)
    third.activate()
    third.send()
    third.finish()
    service.trace.assert_open(first.record)
    service.assert_reports_pending()
    assert second.record.closed < third.record.opened < third.record.closed
    if service.tls:
        # No TLS bytes were sent by the held socket before both siblings ended.
        first.handshake()
        first.send()
    else:
        first.release_partial()
    first.finish()
    assert third.record.closed < first.record.closed
    return service.finish([first, second, third])


def reader(service):
    # Withholding body reads is the only imposed backpressure condition.
    # Keep the ordinary TCP buffer policy; actual EAGAIN remains mandatory.
    first = Peer(service, binary(4 * 1024 * 1024, 51))
    service.trace.refresh()
    after_handshake = len(service.trace.events)
    first.send()
    first.response.advance(head_only=True)
    blocked = service.trace.writer_blocked(first.record, after_handshake)
    first.note("writer-blocked", trace_event=blocked["index"])
    service.trace.assert_open(first.record)
    second = Peer(service, binary(31, 81))
    second.send()
    second.finish()
    service.trace.assert_open(first.record)
    service.assert_reports_pending()
    assert blocked["index"] < second.record.opened < second.record.closed
    resumed_buffer = first.connection.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
    first.note("reader-resume", receive_initial=first.initial_receive_buffer,
               receive_current=resumed_buffer, sibling_close_event=second.record.closed)
    first.finish()
    assert second.record.closed < first.record.closed
    result = service.finish([first, second])
    result["initial_receive_buffer"] = first.initial_receive_buffer
    result["resumed_receive_buffer"] = resumed_buffer
    return result


def main():
    mode, executable = sys.argv[1:]
    assert mode in ("plain-refill", "tls-refill", "plain-reader", "tls-reader"), mode
    tls, held_reader = mode.startswith("tls-"), mode.endswith("-reader")
    directory = Path(tempfile.mkdtemp(prefix="lanius-server-concurrency-"))
    journal = Journal(directory / "oracle-events.log")
    stacks = (directory / "oracle-stacks.log").open("w")
    service = None
    succeeded = False
    previous_alarm = signal.getsignal(signal.SIGALRM)

    def expired(signum, frame):
        journal.note("overall-deadline", last_phase=journal.phase)
        faulthandler.dump_traceback(file=stacks, all_threads=True)
        raise TimeoutError(f"oracle overall deadline after {OVERALL_SECONDS}s")

    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, OVERALL_SECONDS)
    faulthandler.dump_traceback_later(25, file=stacks)
    try:
        journal.note("oracle-start", mode=mode, overall_seconds=OVERALL_SECONDS)
        service = Service(executable, directory, tls, 2 if held_reader else 3,
                          4 * 1024 * 1024 if held_reader else 65536, journal)
        result = reader(service) if held_reader else refill(service)
        buffers = (f" receive-initial={result['initial_receive_buffer']}"
                   f" receive-resumed={result['resumed_receive_buffer']}" if held_reader else "")
        print(f"server-concurrency-{mode} cases=1 accepted={result['accepted']} "
              f"max-active={result['peak_active']} max-sockets={result['peak_sockets']} "
              f"traced-seconds={result['seconds']:.6f}{buffers}")
        succeeded = True
    except BaseException as error:
        journal.note("oracle-failed", error=repr(error), previous_phase=journal.phase)
        traceback.print_exc(file=stacks)
        stacks.flush()
        faulthandler.dump_traceback(file=stacks, all_threads=True)
        (directory / "failure.txt").write_text(repr(error) + "\n")
        print(f"server concurrency failure artifacts: {directory}", file=sys.stderr)
        raise
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm)
        faulthandler.cancel_dump_traceback_later()
        try:
            if service is not None:
                service.close()
        finally:
            stacks.close()
            journal.close()
        if succeeded and not os.environ.get("LANIUS_KEEP_TEMP_ARTIFACTS"):
            shutil.rmtree(directory)


if __name__ == "__main__":
    main()
