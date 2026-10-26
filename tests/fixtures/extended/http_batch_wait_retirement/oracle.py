"""A synthetic Driver error must free a batch slot before another blocking poll.

The Driver wraps actual HTTP Exchanges. Existing h11 peers, response readers and
the strict raw syscall resource ledger are imported read-only from http_batch.
No native syscall is faulted and no elapsed speed ratio proves progress.
"""
import importlib.util
import os
from pathlib import Path
import re
import select
import struct
import subprocess
import sys
import tempfile
import time

BASE = Path(__file__).resolve().parents[1] / "http_batch"
sys.path.insert(0, str(BASE))
SPEC = importlib.util.spec_from_file_location("raw_http_batch_oracle", BASE / "oracle.py")
raw = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = raw
SPEC.loader.exec_module(raw)

MARKERS = b"held-read-pending\nwait-retired\nqueued-admitted\nowners-released\n"


class RetirementPeers(raw.Peers):
    def gate(self, index):
        if index == 0:
            # The held request can finish only after the formerly queued job
            # really finishes and the product closes that peer's connection.
            return self.wait(lambda: 2 in self.closed)
        if index == 2:
            # Job 1 sends no response bytes; its EOF proves the retiring
            # wrapper really released its transport before queued completion.
            return self.wait(lambda: 1 in self.closed)
        assert index == 1
        return True


def marker_index(lines, value):
    count = len(value) + 1
    pattern = re.compile(r'^\[[0-9a-fA-Fx]+\]\s+write\(2, "' + re.escape(value) + r'\\n", ' + str(count) + r'\)\s+=\s+' + str(count) + r'$')
    positions = [index for index, line in enumerate(lines) if pattern.fullmatch(line)]
    assert len(positions) == 1, (value, positions, lines)
    return positions[0]


def verify_trace(trace, report):
    ledger = raw.analyze(trace)
    assert ledger["max_sockets"] == 2, ledger
    assert ledger["calls"].get("socket") == 3, ledger
    assert report["stats"]["polls"] == ledger["calls"].get("poll", 0), (report, ledger)
    assert not any(event["injected"] for events in ledger["attempts"].values() for event in events), ledger
    lines = Path(trace).read_text(encoding="utf-8").splitlines()
    held = marker_index(lines, "held-read-pending")
    retired = marker_index(lines, "wait-retired")
    admitted = marker_index(lines, "queued-admitted")
    assert held < retired < admitted, lines
    sockets = ledger["attempts"]["socket"]
    socket_positions = [index for index, line in enumerate(lines) if re.match(r"^\[[0-9a-fA-Fx]+\]\s+socket\(", line)]
    assert len(socket_positions) == 3, lines
    assert socket_positions[1] < held < retired < socket_positions[2] < admitted, lines
    retired_fd = int(sockets[1]["result"].split()[0])
    close_pattern = re.compile(r'^\[[0-9a-fA-Fx]+\]\s+close\(' + str(retired_fd) + r'\)\s+=\s+0$')
    assert any(close_pattern.fullmatch(line) for line in lines[socket_positions[1] + 1:retired]), lines
    # A spurious ready result must not hide the old bug: issuing a positive
    # timeout before admission already violates this scheduling contract.
    for position, line in enumerate(lines):
        event = re.match(r"^\[[0-9a-fA-Fx]+\]\s+poll\((.*)\)\s+=\s+(.+)$", line)
        if event is None:
            continue
        if retired < position < admitted:
            timeout = re.search(r", \d+, (-?\d+)$", event.group(1))
            assert timeout and int(timeout.group(1)) == 0, ("blocking poll before refill", line, lines)
    return ledger


def run(executable):
    jobs = [raw.Job(raw.fixed(b"held\x00\xff", 201)), raw.Job(b""), raw.Job(raw.fixed(b"queued\x00\xff", 202))]
    peers = RetirementPeers(jobs, 2).start()
    process = None
    with tempfile.TemporaryDirectory(prefix="http-batch-wait-retirement-") as directory:
        trace = Path(directory) / "syscalls.log"
        try:
            process = subprocess.Popen([
                "strace", "--kill-on-exit", "-qq", "-i", "-o", str(trace), "-e",
                "trace=mmap,munmap,socket,close,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write",
                executable,
            ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
            process.stdin.write(struct.pack("<3i", *(job.port for job in jobs)))
            process.stdin.flush()
            until = time.monotonic() + 7

            def read(count):
                data = bytearray()
                while len(data) < count:
                    remaining = until - time.monotonic()
                    assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "protocol deadline"
                    part = os.read(process.stdout.fileno(), count - len(data))
                    assert part, ("premature protocol EOF", process.poll(), bytes(data))
                    data.extend(part)
                return bytes(data)

            report = raw.parse(read)
            assert struct.unpack("<i", read(4))[0] == raw.CHECKPOINT
            with open("/proc/%d/task/%d/children" % (process.pid, process.pid), encoding="utf-8") as source:
                children = source.read().split()
            assert len(children) == 1, children
            child = int(children[0])
            assert set(os.listdir("/proc/%d/fd" % child)) == {"0", "1", "2"}, ("fds survived destroy", child)
            # Analyze the complete syscall prefix through the explicit release
            # marker, before sending the exit ACK. The later blocking ACK read
            # may be an unfinished strace line at this point; no malformed line
            # inside the checked owner-lifetime prefix is ignored.
            lines = trace.read_text(encoding="utf-8").splitlines()
            released = marker_index(lines, "owners-released")
            before = raw.analyze("\n".join(lines[:released + 1]) + "\n")
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            stdout, stderr = process.communicate(timeout=3)
            assert process.returncode == 0 and not stdout and stderr == MARKERS, (process.returncode, stdout, stderr)
            assert report["cause"] == 0 and [item["kind"] for item in report["outcomes"]] == [1, 2, 1], report
            counts = report["stats"]
            assert (counts["jobs"], counts["started"], counts["complete"], counts["failed"], counts["aborted"], counts["discarded"], counts["peak_active"], counts["pending"]) == (3, 3, 2, 1, 0, 0, 2, 0), report
            assert counts["io_calls"] == sum(item["io"] for item in report["outcomes"]), report
            assert counts["work"] == sum(item["work"] for item in report["outcomes"]), report
            assert 0 < counts["operations"] <= 100000 and 0 < counts["work"] <= 32000000, report
            for index in (0, 2):
                item = report["outcomes"][index]
                assert item["sent"] == item["request"] > 0 and item["wire"] == jobs[index].wire, item
                status, body = raw.decoded(jobs[index].wire)
                assert (item["status"], item["body"]) == (status, body), item
            failure = report["outcomes"][1]
            assert (failure["cause"], failure["stage"], failure["errno"], failure["cleanup"], failure["received"]) == (4, 8, 9001, 0, 0), failure
            assert failure["sent"] == failure["request"] > 0, failure
            # Wait only for peer observation of causal EOF, never substitute
            # elapsed time for EOF or for a fully parsed request.
            deadline = time.monotonic() + 2
            with peers.condition:
                while peers.closed != {0, 1, 2} and time.monotonic() < deadline:
                    peers.condition.wait(.02)
            assert peers.seen == peers.closed == {0, 1, 2}, peers.events
            assert peers.events.index(("request", 1)) < peers.events.index(("closed", 1)) < peers.events.index(("response", 2)) < peers.events.index(("closed", 2)) < peers.events.index(("response", 0)), peers.events
            ledger = verify_trace(trace, report)
            assert before["allocations"] == ledger["allocations"] and before["max_sockets"] == 2, (before, ledger)
            print("http-batch-wait-retirement cases=1 synthetic-driver-error=9001 before-exit-cleanup=1")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate()
            peers.finish()


if __name__ == "__main__":
    assert len(sys.argv) == 2
    run(sys.argv[1])
