#!/usr/bin/env python3
"""Test-only caller-controlled HTTP Exchange driver and independent wire oracle."""
import http.client
import io
import os
from pathlib import Path
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import h11

EXE, GROUP = sys.argv[1:]
MAGIC = 0x48545831
COUNT = 0
LEAVES = ('connect', 'getsockopt', 'getpeername', 'recvfrom', 'sendto', 'shutdown')
TRACE = 'mmap,munmap,socket,close,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write,rt_sigaction'
BODY = b'\x00\xff\r\n'


def exact(stream, count):
    data = b''
    end = time.monotonic() + 3
    while len(data) < count:
        left = end - time.monotonic()
        assert left > 0 and select.select([stream], [], [], left)[0], ('stalled public call', len(data), count)
        part = os.read(stream.fileno(), count - len(data))
        assert part, ('premature fixture exit', len(data), count)
        data += part
    return data


def fixed(body=BODY, status=200):
    return b'HTTP/1.1 ' + str(status).encode() + b' Result\r\nContent-Length: ' + str(len(body)).encode() + b'\r\nX-Raw: \x80\xff\r\n\r\n' + body


def chunks(body=BODY):
    return b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2;tag="a\\b"\r\n' + body[:2] + b'\r\n2\r\n' + body[2:] + b'\r\n0\r\nX-End: yes\r\n\r\n'


def decoded(wire):
    class Peer:
        def makefile(self, *args): return io.BytesIO(wire)
    response = http.client.HTTPResponse(Peer())
    response.begin()
    return response.read()


def marker(body):
    match = re.match(r'write\(1, "((?:\\x[0-9a-f]{2})+)", 96\) += 96(?: |$)', body)
    if not match: return None
    raw = bytes.fromhex(match[1].replace('\\x', ''))
    words = struct.unpack('<24i', raw)
    return words if words[0] == MAGIC else None


def audit(text, prepared_only=False):
    """Address generations and public-call epochs, independently of private phases."""
    live, fds, calls, allocations, epochs = {}, set(), {}, [], []
    epoch = None
    for line in text.splitlines():
        name = line.split('(', 1)[0]
        calls[name] = calls.get(name, 0) + 1
        words = marker(line)
        if words is not None:
            tag = words[1]
            if tag in (100, 1, 5, 7):
                assert epoch is None, (epoch, words)
                epoch = [tag, words, []]
            elif tag in (0, 2, 3, 4, 6, 8, 11):
                assert epoch is not None, words
                epochs.append((*epoch, words)); epoch = None
        elif epoch is not None:
            epoch[2].append(line)
        match = re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+|-1)(?: |$)', line)
        if match:
            length, address = int(match[1]), match[2]
            allocations.append((length, epoch is not None))
            if address != '-1':
                assert address not in live, line
                live[address] = length
        match = re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0', line)
        if match: assert live.pop(match[1], None) == int(match[2]), (line, live)
        match = re.match(r'socket\(.*\) += (\d+)(?: |$)', line)
        if match:
            fd = int(match[1]); assert fd not in fds; fds.add(fd)
        match = re.match(r'close\((\d+)\) += ', line)
        if match:
            # Linux owner invalidation is required even when close reports an
            # injected error. A failed direct close must never be retried.
            fd = int(match[1]); assert fd in fds, (line, fds); fds.remove(fd)
    assert epoch is None and not live and not fds, (epoch, live, fds, text)
    for tag, before, body, after in epochs:
        active = [line for line in body if line.startswith(tuple(name + '(' for name in LEAVES))]
        assert not any(line.startswith('poll(') for line in body), (tag, body)
        assert len(active) <= (1 if tag == 1 else 0), (tag, active)
        if tag == 100:
            sockets = [line for line in body if line.startswith('socket(')]
            assert len(sockets) <= (0 if prepared_only else 1), sockets
        elif tag in (1, 5):
            assert after[13] - before[13] == len(active), (tag, before, after, active)
        elif tag == 7:
            assert after[13] - before[13] in (0, 1), (before, after)
        for line in active:
            if line.startswith(('recvfrom(', 'sendto(')):
                match = re.match(r'(?:recvfrom|sendto)\(\d+, (?:"(?:\\x[0-9a-f]{2})*"|0x[0-9a-f]+), (\d+),', line)
                assert match and 0 < int(match[1]) <= 1024, line
    participations = sum(after[13] - before[13] for tag, before, _body, after in epochs if tag == 7)
    assert epochs[-1][3][13] == calls.get('socket', 0) + sum(calls.get(name, 0) for name in LEAVES) + participations, (epochs[-1][3], calls, participations)
    for syscall, index in (('sendto', 9), ('recvfrom', 10)):
        confirmed = 0
        for line in text.splitlines():
            if line.startswith(syscall + '('):
                result = line.rsplit(' = ', 1)[1].split()[0]
                if result.isdecimal(): confirmed += int(result)
        assert epochs[-1][3][index] == confirmed, (syscall, epochs[-1][3], confirmed)
    return calls, allocations, epochs


def injected(text, syscall, error, ordinal):
    lines = [line for line in text.splitlines() if line.startswith(syscall + '(')]
    marked = [line for line in lines if 'INJECTED' in line]
    assert len(marked) == 1 and marked[0] == lines[ordinal - 1], (syscall, ordinal, lines)
    assert marked[0].rsplit(' = ', 1)[1].split()[:2] == ['-1', error], marked


class Session:
    def __init__(self, directory, mode=0, timeout=4000, quota=100000, work=100000000,
                 raw_cap=65536, body_cap=4194304, interims=8, fault=None, listener=None):
        self.listener = listener or socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.owns_listener = listener is None
        if self.owns_listener:
            self.listener.bind(('127.0.0.1', 0)); self.listener.listen()
        self.listener.setblocking(False)
        self.conn = None
        self.request = b''
        self.eof = False
        self.records = []
        self.wire = self.body = b''
        self.trace = Path(directory) / 'trace'
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '4096', '-o', str(self.trace), '-e', 'signal=none', '-e', 'trace=' + TRACE]
        for expression in ([] if fault is None else ([fault] if isinstance(fault, str) else fault)):
            command += ['-e', 'inject=' + expression]
        command += [EXE, '127.0.0.1:' + str(self.listener.getsockname()[1]), str(mode), str(timeout), str(quota), str(work), str(raw_cap), str(body_cap), str(interims)]
        self.started = time.monotonic()
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            first = self.record(); assert first[1] == 100, first
            self.last = self.record(); assert self.last[1] in (0, 6, 11), self.last
        except BaseException:
            self.cleanup()
            raise

    def record(self):
        words = struct.unpack('<24i', exact(self.process.stdout, 96))
        assert words[0] == MAGIC, words
        self.records.append(words)
        if words[1] == 3:
            self.wire = exact(self.process.stdout, words[17]); self.body = exact(self.process.stdout, words[18])
        return words

    def command(self, value):
        self.process.stdin.write(bytes([value])); self.process.stdin.flush()
        first = self.record(); assert first[1] == {17:7, 18:5}.get(value, 1), first
        self.last = self.record()
        if self.last[1] == 8: self.last = self.record(); assert self.last[1] == 20, self.last
        self.collect()
        return self.last

    def collect(self):
        if self.conn is None and select.select([self.listener], [], [], 0)[0]:
            self.conn, _ = self.listener.accept(); self.conn.setblocking(False)
        if self.conn is not None:
            while True:
                try: data = self.conn.recv(65536)
                except BlockingIOError: break
                except ConnectionResetError: self.eof = True; break
                if not data: self.eof = True; break
                self.request += data

    def send(self, value):
        assert self.conn is not None
        self.conn.setblocking(True); self.conn.settimeout(2); self.conn.sendall(value); self.conn.setblocking(False)

    def step(self, ready=15): return self.command(ready)

    def drive(self, wire=None, partition=0, close=False, early=False, max_steps=20000):
        fragments = [] if wire is None else ([wire] if not partition else [wire[i:i+partition] for i in range(0, len(wire), partition)])
        sent, pending, stop_seen, released = 0, 0, None, 0
        for _ in range(max_steps):
            if self.last[1] in (3, 4, 6, 11): break
            self.collect()
            request_ready = b'\r\n\r\n' in self.request if early else request_complete(self.request)
            if fragments and request_ready and (sent == 0 or (self.last[1] == 2 and not self.last[4] & 4)):
                assert self.last[10] == released, ('next permission before confirmed prefix', self.last, released)
                fragment = fragments.pop(0); self.send(fragment); released += len(fragment); sent += 1
                if not fragments and close: self.conn.shutdown(socket.SHUT_WR)
            if early and self.last[15]:
                if stop_seen is None: stop_seen = self.last[9]
                assert self.last[9] == stop_seen, (stop_seen, self.last)
            if early and not fragments and self.eof and wire is not None:
                # The peer withholds the body until the abandoned upload has
                # actually reached EOF, rather than merely trusting a flag.
                self.send(BODY); wire = None
            if not self.last[4] & 4:
                pending += 1
                polled = self.command(17)
                if polled[1] == 4: break
                self.step(max(0, polled[23]))
            else:
                self.step(0)
        else: raise AssertionError(('step bound', self.last))
        return pending

    def finish(self, expected=3, cause=None, prepared_only=False):
        global COUNT
        assert self.last[1] == expected, (expected, self.last, self.trace.read_text())
        if cause is not None: assert self.last[5] == cause, self.last
        output, errors = self.process.communicate(timeout=4)
        assert self.process.returncode == 0 and not output and not errors, (self.process.returncode, output, errors, self.trace.read_text())
        self.collect()
        text = self.trace.read_text()
        result = audit(text, prepared_only)
        values = [word for word in self.records if word[1] in (0, 2, 3, 4, 6, 8, 11, 20)]
        for before, after in zip(values, values[1:]):
            assert all(after[index] >= before[index] for index in (9, 10, 11, 13, 14)), (before, after)
        COUNT += 1
        return text, result

    def cleanup(self):
        if self.process.poll() is None: self.process.kill()
        self.process.communicate(timeout=4)
        if self.conn is not None: self.conn.close()
        if self.owns_listener: self.listener.close()


def request_complete(wire):
    if b'\r\n\r\n' not in wire: return False
    head, body = wire.split(b'\r\n\r\n', 1)
    match = re.search(rb'(?im)^Content-Length: (\d+)\r?$', head)
    return match is not None and len(body) == int(match[1])


def check_request(wire, early=False):
    parser = h11.Connection(h11.SERVER); parser.receive_data(wire)
    head = parser.next_event(); assert isinstance(head, h11.Request), head
    assert head.method == b'POST' and head.target == b'/exchange?q=x'
    fields = list(head.headers)
    for name, value in [(b'host', b'virtual.example:8080'), (b'connection', b'close'), (b'x-owned', b'caller-data')]:
        assert [v for k, v in fields if k == name] == [value], fields
    body = b''
    while True:
        event = parser.next_event()
        if event is h11.NEED_DATA: assert early; break
        if isinstance(event, h11.Data): body += event.data
        elif isinstance(event, h11.EndOfMessage): assert not early; break
        else: raise AssertionError(event)
    if early: assert (BODY + b'X' * (4194304 - 4)).startswith(body) and len(body) < 4194304
    else: assert body == BODY, body


def run(wire=fixed(), partition=0, close=False, **options):
    with tempfile.TemporaryDirectory(prefix='http-exchange-') as directory:
        value = Session(directory, **options)
        try:
            pending = value.drive(wire, partition, close)
            text, evidence = value.finish()
            check_request(value.request)
            assert value.body == decoded(wire) and value.wire == wire, (value.last, value.wire)
            assert value.last[9] == len(value.request) == value.last[8]
            assert value.last[10] == len(wire) and value.last[12] == 0
            return value.last, pending, text, evidence
        finally: value.cleanup()


def steps():
    last, pending, text, _ = run(partition=7)
    assert pending > 1 and text.count('poll(') > 1
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory)
        try:
            saved = value.last[13]; observed = value.command(17)
            assert observed[23] == -1 and observed[13] == saved
            value.command(18); value.finish(6)
        finally: value.cleanup()
    # A fabricated EINPROGRESS does not connect the socket. SO_ERROR=0 alone
    # must not prove success: getpeername must detect ENOTCONN and stay pending.
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory, fault='connect:error=EINPROGRESS:when=1')
        try:
            first = value.step(0); assert first[1] == 2 and first[9] == 0
            saved = first[13]
            for _ in range(4): assert value.step(0)[13] == saved
            for _ in range(4): value.step(15)
            assert value.last[1] == 2 and value.last[9] == 0
            value.command(18); text, _ = value.finish(6)
            injected(text, 'connect', 'EINPROGRESS', 1)
            assert 'getsockopt(' in text and 'getpeername(' in text and 'ENOTCONN' in text
            assert 'sendto(' not in text and 'recvfrom(' not in text
        finally: value.cleanup()


def framing():
    info = b'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nX-Link: /next\r\n\r\n'
    vectors = [(fixed(), False), (chunks(), False), (b'HTTP/1.0 200 OK\r\nX: y\r\n\r\n' + BODY, True)]
    for wire, close in vectors:
        for partition in (0, 1, 7): run(wire, partition, close)
    for partition in (1, 7):
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory)
            try:
                value.drive(info + chunks(), partition); value.finish(); check_request(value.request)
                assert value.wire == chunks() and value.body == BODY and value.last[20:23] == (2, 100, 103) and value.last[23] == 1
            finally: value.cleanup()
    for wire in (b'HTTP/1.1 204 No Content\r\n\r\n', fixed(b'', 404)):
        run(wire, 1)
    for suffix in (b'x', b'HTTP/1.1 200 Extra\r\nContent-Length: 1\r\n\r\nz'):
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory)
            try:
                value.drive(fixed() + suffix); value.finish(); assert value.wire == fixed() and value.body == BODY
                assert value.last[12] == value.last[10] - len(fixed()) and 0 <= value.last[12] <= len(suffix)
            finally: value.cleanup()
    close_wire = b'HTTP/1.0 200 OK\r\n\r\n' + BODY
    for options in ({'raw_cap':len(close_wire)}, {'body_cap':len(BODY)}):
        _last, _pending, text, _evidence = run(close_wire, 1, True, **options)
        received = [line for line in text.splitlines() if line.startswith('recvfrom(')]
        assert re.search(r', 1, 0, NULL, NULL\) += 0$', received[-1]), received[-1]
    run(fixed(), raw_cap=len(fixed()))
    for options, expected in (({'raw_cap':len(close_wire)}, 7), ({'body_cap':len(BODY)}, 8)):
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory, **options)
            try:
                value.drive(close_wire + b'x', 1, close=True); value.finish(4, expected)
                assert value.last[10] == len(close_wire) + 1, value.last
            finally: value.cleanup()


def early():
    head = b'HTTP/1.1 413 Too Large\r\nContent-Length: 4\r\nConnection: close\r\n\r\n'
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory, mode=1)
        try:
            value.drive(head, early=True); text, _ = value.finish(); check_request(value.request, True)
            assert value.eof and value.body == BODY and value.wire == head + BODY
            assert value.last[15:17] == (1, 1) and value.last[9] < value.last[8]
            stopped = [line for line in text.splitlines() if line.startswith('shutdown(')]
            assert len(stopped) == 1 and 'SHUT_WR' in stopped[0] and stopped[0].endswith('= 0')
        finally: value.cleanup()
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory, mode=1, fault='shutdown:error=EIO:when=1')
        try:
            value.drive(head, early=True); text, _ = value.finish(4, 4)
            injected(text, 'shutdown', 'EIO', 1)
            assert value.last[6] == 5 and value.last[15:17] == (1, 0)
        finally: value.cleanup()


def lifecycle():
    for mode in (2, 3):
        if mode == 3: run(mode=3); continue
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory, mode=2)
            try:
                text, _ = value.finish(6, prepared_only=True)
                assert 'socket(' not in text and 'connect(' not in text
            finally: value.cleanup()
    for after_steps in (0, 1, 5):
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory)
            try:
                for _ in range(after_steps): value.step(15)
                value.command(18); value.finish(6)
            finally: value.cleanup()
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory, fault='close:error=EIO:when=1')
        try:
            value.command(18); text, _ = value.finish(6, 4)
            injected(text, 'close', 'EIO', 1)
            assert value.last[2] == 3 and value.last[6] == 8
        finally: value.cleanup()
    with tempfile.TemporaryDirectory() as directory:
        value = Session(directory)
        try:
            # Every advisory bit is deliberately set while the peer remains
            # open: a hangup hint is never a substitute for actual recv EOF.
            wire = b'HTTP/1.0 200 OK\r\n\r\n' + BODY
            for _ in range(100):
                # Use each real readiness result once while uploading. A
                # replayed readable hint can correctly prioritize reads over
                # sends, so it is not an honest upload scheduling control.
                if value.last[4] & 4: value.step(0)
                else:
                    polled = value.command(17)
                    assert polled[1] == 20, polled
                    value.step(max(0, polled[23]))
                assert value.last[1] == 2, value.last
                if request_complete(value.request): break
            else: raise AssertionError('request did not complete')
            value.send(wire)
            for _ in range(30): assert value.step(15)[1] == 2
            assert value.last[10] == len(wire)
            value.conn.shutdown(socket.SHUT_WR); value.drive(); value.finish()
            assert value.body == BODY
        finally: value.cleanup()
    for wire in (b'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: test\r\n\r\n',
                 b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nabc',
                 b'HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nabc'):
        with tempfile.TemporaryDirectory() as directory:
            value = Session(directory)
            try:
                value.drive(wire, 1, close=True); value.finish(4, 12 if b'101' in wire else 5)
            finally: value.cleanup()


def faults():
    # All fault campaigns keep one listener/address and unchanged argv, so
    # argument mappings do not move baseline allocation ordinals or sizes.
    with tempfile.TemporaryDirectory() as directory:
        listener = socket.socket(); listener.bind(('127.0.0.1', 0)); listener.listen()
        try:
            for wire in (fixed(), b'HTTP/1.1 103 Hints\r\n\r\n' + chunks()):
                baseline = Session(directory, listener=listener)
                try:
                    baseline.drive(wire); baseline_text, (_, positions, _) = baseline.finish()
                finally: baseline.cleanup()
                reached = [index for index, (_length, inside) in enumerate(positions, 1) if inside]
                assert reached
                print('exchange-engine-allocation-positions', len(reached), flush=True)
                for point in reached:
                    value = Session(directory, listener=listener, fault=f'mmap:error=ENOMEM:when={point}')
                    try:
                        value.drive(wire); text, (_, attempted, _) = value.finish(11 if value.last[1] == 11 else 4)
                        assert (value.last[5], value.last[23]) in ((2, 0), (5, 2)), value.last
                        injected(text, 'mmap', 'ENOMEM', point)
                        assert [length for length, _ in attempted][:point] == [length for length, _ in positions][:point]
                    finally: value.cleanup()
            for syscall in ('socket', 'connect', 'getsockopt', 'getpeername', 'sendto', 'recvfrom', 'close'):
                expression = f'{syscall}:error=EIO:when=1'
                errors = ['connect:error=EINPROGRESS:when=1', expression] if syscall in ('getsockopt', 'getpeername') else expression
                value = Session(directory, listener=listener, fault=errors)
                try:
                    value.drive(fixed()); text, _ = value.finish(11 if value.last[1] == 11 else 4, 4)
                    injected(text, syscall, 'EIO', 1)
                    if isinstance(errors, list): injected(text, 'connect', 'EINPROGRESS', 1)
                finally: value.cleanup()
            for syscall in ('sendto', 'recvfrom'):
                value = Session(directory, listener=listener, fault=f'{syscall}:error=EINTR:when=1')
                try:
                    value.drive(fixed()); text, _ = value.finish(); injected(text, syscall, 'EINTR', 1)
                finally: value.cleanup()
            for quota in (1, 2, 5):
                value = Session(directory, listener=listener, quota=quota)
                try:
                    value.drive(fixed()); text, _ = value.finish(4, 10); assert value.last[13] == quota
                finally: value.cleanup()
            value = Session(directory, listener=listener, quota=12, fault='recvfrom:error=EINTR:when=1+')
            try:
                value.drive(fixed()); text, _ = value.finish(4, 10)
                interrupted = [line for line in text.splitlines() if line.startswith('recvfrom(')]
                assert len(interrupted) > 1 and all('INJECTED' in line and '= -1 EINTR' in line for line in interrupted)
                assert value.last[13] == 12
            finally: value.cleanup()
            malformed = b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nabc'
            value = Session(directory, listener=listener, fault='close:error=EIO:when=1')
            try:
                value.drive(malformed); text, _ = value.finish(4, 5)
                injected(text, 'close', 'EIO', 1); assert value.last[7] == 5
            finally: value.cleanup()
            for options, expected in [({'timeout':0}, 3), ({'work':0}, 11), ({'raw_cap':0}, 5), ({'body_cap':3}, 6), ({'interims':0}, 9)]:
                value = Session(directory, listener=listener, **options)
                try:
                    value.drive(b'HTTP/1.1 103 Hints\r\n\r\n' + fixed()); text, _ = value.finish(11 if value.last[1] == 11 else 4, expected)
                    if options.get('raw_cap') == 0:
                        # Canonical Cursor.need(0) exhausts a zero raw cap
                        # before the transport receive-capacity branch.
                        assert value.last[6] == 4 and value.last[23] == 3 and value.last[17:19] == (0, 0), value.last
                        assert value.last[9:11] == (0, 0) and 'recvfrom(' not in text and 'sendto(' not in text
                finally: value.cleanup()
            # A successful send remains in Stats after its delayed return has
            # crossed the original absolute deadline.
            value = Session(directory, listener=listener, timeout=80, fault='sendto:delay_exit=150ms:when=1')
            try:
                value.drive(fixed()); text, _ = value.finish(4, 3)
                sends = [line for line in text.splitlines() if line.startswith('sendto(')]
                assert len(sends) == 1 and int(sends[0].rsplit(' = ', 1)[1].split()[0]) == value.last[9] > 0
                assert time.monotonic() - value.started >= .12
            finally: value.cleanup()
        finally: listener.close()


if __name__ == '__main__':
    {'steps':steps, 'framing':framing, 'early':early, 'lifecycle':lifecycle, 'faults':faults}[GROUP]()
    print(f'http-exchange-{GROUP} cases={COUNT}; owners and step boundaries checked')
