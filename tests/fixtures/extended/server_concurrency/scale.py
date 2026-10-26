"""One bounded traced scale observation of existing native service programs.

This does not compile programs, implement TLS, compare compiler speed, or
measure native/OpenSSL heap use. Invocation: scale.py plain|tls EXECUTABLE.
"""
import faulthandler
import os
from pathlib import Path
import queue
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import traceback

from oracle import (FIXTURES, Journal, Response, Service, TRACE_CALLS, binary,
                    helper, parse_reports, request, successful_report)
from scale_ledger import Ledger, verified_sites

COUNT, BODY, WIDTH, DEMAND = 64, 65536, 4, 8
OVERALL_SECONDS = 85


class Observation:
    def __init__(self, executable, directory, tls, journal):
        self.directory, self.tls = directory, tls
        self.journal, self.lock = journal, threading.Lock()
        self.process, self.collected = None, False
        self.connections, self.results, self.errors, self.threads = set(), {}, [], []
        self.stop = threading.Event()
        self.context = None
        arguments = [str(executable), "127.0.0.1:0"]
        if tls:
            certificates = helper("server_scale_certificates", FIXTURES / "openssl_tls_server/certificates.py")
            certificates.generate(directory)
            clients = helper("server_scale_client_context", FIXTURES / "openssl_tls_server/client.py")
            self.context = clients.context(directory, version=ssl.TLSVersion.TLSv1_3)
            assert self.context.check_hostname and self.context.verify_mode == ssl.CERT_REQUIRED
            arguments += [str(directory / "valid.pem"), str(directory / "valid.key")]
        # Reuse the exact runtime-byte + sized-source instruction verifier.
        pairs, named = verified_sites(executable, directory)
        self.note("setup-complete", verified_pairs=len(pairs), verified_named=len(named))
        options = ["--requests", str(COUNT), "--concurrency", str(WIDTH),
                   "--timeout", "15000", "--service-timeout", "60000", "--report",
                   "--max-request", "131072", "--max-response", "131072",
                   "--max-body", str(BODY), "--max-head", "4096", "--max-headers", "16",
                   "--max-work", "67108864", "--max-io", "20000"]
        if tls:
            options += ["--max-tls", "20000"]
        self.trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96",
                   "-o", str(self.trace), "-e", "trace=" + TRACE_CALLS, *arguments, *options]
        (directory / "command.txt").write_text(repr(command) + "\n")
        self.ledger = Ledger(self.trace, pairs, named)
        # Credential generation and executable-site validation are excluded.
        # Native startup, client work, tracing and final report collection count.
        self.started = time.monotonic()
        self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.endpoint = Service.read_endpoint(self)
        self.note("native-started", endpoint=self.endpoint, pid=self.process.pid)

    def note(self, phase, **values):
        with self.lock:
            self.journal.note(phase, **values)

    def connect(self):
        raw = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        raw.settimeout(6)
        with self.lock:
            self.connections.add(raw)
        raw.connect(self.endpoint)
        self.note("peer-connected", port=raw.getsockname()[1],
                  receive_capacity=raw.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF))
        return raw

    def replace(self, old, new):
        with self.lock:
            self.connections.discard(old)
            self.connections.add(new)
        return new

    def echo(self, raw, index):
        port = raw.getsockname()[1]
        connection = raw
        try:
            if self.tls:
                connection = self.replace(raw, self.context.wrap_socket(
                    raw, server_hostname="localhost", do_handshake_on_connect=False,
                    suppress_ragged_eofs=False))
                connection.do_handshake()
                assert connection.getpeercert() and connection.version() == "TLSv1.3"
            body = binary(BODY, index * 7 + 3)
            wire, parser, expected = request(body)
            connection.sendall(wire)
            if not self.tls:
                connection.shutdown(socket.SHUT_WR)
            response = Response(connection, parser, expected,
                                lambda phase, **values: self.note(phase, job=index, port=port, **values))
            response.advance()
            if self.tls:
                connection = self.replace(connection, connection.unwrap())
                connection.settimeout(6)
            assert connection.recv(1) == b"", ("surplus bytes or missing TCP EOF", index)
            with self.lock:
                assert port not in self.results, ("source port identity reused", port)
                self.results[port] = (index, len(wire), len(response.wire))
            self.note("peer-complete", job=index, port=port, body=BODY,
                      request=len(wire), response=len(response.wire))
        finally:
            connection.close()
            with self.lock:
                self.connections.discard(connection)

    def run(self):
        initial = [self.connect() for _ in range(DEMAND)]
        until = time.monotonic() + 6
        while True:
            self.ledger.refresh()
            if len(self.ledger.accepted) == WIDTH:
                break
            assert self.process.poll() is None and time.monotonic() < until, (
                "initial four held admissions", self.process.poll(), self.ledger.accepted)
            time.sleep(.005)
        ports = [connection.getsockname()[1] for connection in initial]
        assert len(set(ports)) == DEMAND
        assert [record.port for record in self.ledger.accepted] == ports[:WIDTH]
        assert all(record.closed is None for record in self.ledger.accepted)
        self.note("initial-demand-proven", connected=DEMAND, accepted=WIDTH,
                  accepted_ports=ports[:WIDTH], queued_ports=ports[WIDTH:])
        # All eight clients are connected before any HTTP/TLS bytes are sent.
        # The first four hold every accepted slot; four more demand admission.
        pending = queue.Queue()
        for index in range(DEMAND, COUNT):
            pending.put(index)
        stop = self.stop

        def worker(first, index):
            try:
                self.echo(first, index)
                while not stop.is_set():
                    try:
                        index = pending.get_nowait()
                    except queue.Empty:
                        return
                    self.echo(self.connect(), index)
            except BaseException as error:
                with self.lock:
                    self.errors.append((index, repr(error), traceback.format_exc()))
                stop.set()
                self.note("peer-failed", job=index, error=repr(error))

        for index, connection in enumerate(initial):
            thread = threading.Thread(target=worker, args=(connection, index),
                                      name=f"scale-peer-{index}", daemon=True)
            self.threads.append(thread)
            thread.start()
        until = self.started + 70
        for thread in self.threads:
            thread.join(max(0, until - time.monotonic()))
        assert not any(thread.is_alive() for thread in self.threads), "client worker deadline"
        assert not self.errors and len(self.results) == COUNT, (self.errors, len(self.results))
        output, errors = self.process.communicate(timeout=6)
        self.collected = True
        elapsed = time.monotonic() - self.started
        (self.directory / "native.stdout").write_bytes(output)
        (self.directory / "native.stderr").write_bytes(errors)
        assert self.process.returncode == 0 and not output, (self.process.returncode, output, errors)
        reports = parse_reports(errors, self.tls)
        observed = self.ledger.finish(COUNT)
        assert len(reports) == COUNT and set(self.results) == {r.port for r in self.ledger.accepted}
        for record, report in zip(self.ledger.accepted, reports):
            _, request_bytes, response_bytes = self.results[record.port]
            successful_report(report, record.ordinal, request_bytes, response_bytes, self.tls)
        assert sum(report["received"] for report in reports) == sum(value[1] for value in self.results.values())
        assert sum(report["sent"] for report in reports) == sum(value[2] for value in self.results.values())
        observed.update(seconds=elapsed, body_bytes=COUNT * BODY)
        self.note("observation-complete", **observed)
        return observed

    def close(self):
        self.stop.set()
        with self.lock:
            connections = list(self.connections)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            if not self.collected:
                output, errors = self.process.communicate(timeout=2)
                (self.directory / "native.stdout").write_bytes(output)
                (self.directory / "native.stderr").write_bytes(errors)
            else:
                self.process.stdout.close()
                self.process.stderr.close()
        until = time.monotonic() + 1
        for thread in self.threads:
            thread.join(max(0, until - time.monotonic()))


def main():
    mode, executable = sys.argv[1:]
    assert mode in ("plain", "tls"), mode
    executable = Path(executable).resolve()
    directory = Path(tempfile.mkdtemp(prefix=f"lanius-server-scale-{mode}-"))
    journal = Journal(directory / "oracle-events.log")
    stacks = (directory / "oracle-stacks.log").open("w")
    observation, succeeded = None, False
    previous_alarm = signal.getsignal(signal.SIGALRM)

    def expired(signum, frame):
        journal.note("overall-deadline", last_phase=journal.phase)
        faulthandler.dump_traceback(file=stacks, all_threads=True)
        raise TimeoutError(f"scale oracle overall deadline after {OVERALL_SECONDS}s")

    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, OVERALL_SECONDS)
    faulthandler.dump_traceback_later(75, file=stacks)
    try:
        observation = Observation.__new__(Observation)
        observation.__init__(executable, directory, mode == "tls", journal)
        result = observation.run()
        print(f"server-scale-{mode} connections={COUNT} body-per-connection={BODY} "
              f"body-bytes={result['body_bytes']} demand={DEMAND} accepted={result['accepted']} "
              f"max-active={result['active']} max-sockets={result['sockets']} "
              f"source-allocations={result['source_allocations']} "
              f"source-peak-requested-bytes={result['source_peak_requested']} "
              f"traced-seconds={result['seconds']:.6f}")
        succeeded = True
    except BaseException as error:
        journal.note("oracle-failed", error=repr(error), previous_phase=journal.phase)
        traceback.print_exc(file=stacks)
        stacks.flush()
        faulthandler.dump_traceback(file=stacks, all_threads=True)
        (directory / "failure.txt").write_text(repr(error) + "\n")
        print(f"server scale failure artifacts: {directory}", file=sys.stderr)
        raise
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm)
        faulthandler.cancel_dump_traceback_later()
        try:
            if observation is not None:
                observation.close()
        finally:
            stacks.close()
            journal.close()
        if succeeded and not os.environ.get("LANIUS_KEEP_TEMP_ARTIFACTS"):
            shutil.rmtree(directory)


if __name__ == "__main__":
    main()
