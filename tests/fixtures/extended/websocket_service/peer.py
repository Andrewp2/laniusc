"""A hand-written RFC 6455 client peer for the ws_echo_server oracle: raw
frames with any bits, masks and lengths, so framing errors can be sent."""
import base64
import hashlib
import os
import socket
import struct

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def accept_for(key):
    return base64.b64encode(hashlib.sha1(key + GUID).digest())


class Closed(Exception):
    pass


class Peer:
    def __init__(self, port, timeout=10.0):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        self.buf = b""
        self.headers = {}
        self.status = 0

    def raw(self, data):
        self.sock.sendall(data)

    def read_more(self):
        chunk = self.sock.recv(65536)
        if not chunk:
            raise Closed()
        self.buf += chunk

    def http(self, request):
        """Send a request head, return (status, headers lower-cased, body)."""
        self.raw(request)
        while b"\r\n\r\n" not in self.buf:
            self.read_more()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
        self.status = int(lines[0].split()[1])
        self.headers = {}
        for line in lines[1:]:
            name, value = line.split(b":", 1)
            self.headers.setdefault(name.strip().lower(), []).append(value.strip())
        size = int(self.headers.get(b"content-length", [b"0"])[0])
        while len(self.buf) < size:
            self.read_more()
        body, self.buf = self.buf[:size], self.buf[size:]
        return self.status, self.headers, body

    def handshake(self, path=b"/ws", extensions=None, extra=b"", first=b""):
        key = base64.b64encode(os.urandom(16))
        req = b"GET " + path + b" HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + b"\r\nSec-WebSocket-Version: 13\r\n"
        if extensions is not None:
            req += b"Sec-WebSocket-Extensions: " + extensions + b"\r\n"
        self.raw(req + extra + b"\r\n" + first)
        while b"\r\n\r\n" not in self.buf:
            self.read_more()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
        self.status = int(lines[0].split()[1])
        for line in lines[1:]:
            name, value = line.split(b":", 1)
            self.headers.setdefault(name.strip().lower(), []).append(value.strip())
        if self.status == 101:
            assert self.headers[b"sec-websocket-accept"] == [accept_for(key)], self.headers
            assert self.headers[b"upgrade"][0].lower() == b"websocket"
        return self.status

    def frame(self, opcode, payload=b"", fin=True, rsv=0, mask=True):
        b0 = (0x80 if fin else 0) | (rsv << 4) | opcode
        n = len(payload)
        m = 0x80 if mask else 0
        if n < 126:
            head = struct.pack(">BB", b0, m | n)
        elif n < 65536:
            head = struct.pack(">BBH", b0, m | 126, n)
        else:
            head = struct.pack(">BBQ", b0, m | 127, n)
        if not mask:
            return head + payload
        key = os.urandom(4)
        body = bytes(c ^ key[i % 4] for i, c in enumerate(payload)) if n < 4096 else _mask(payload, key)
        return head + key + body

    def send(self, opcode, payload=b"", fin=True, rsv=0, mask=True):
        self.raw(self.frame(opcode, payload, fin, rsv, mask))

    def recv(self):
        """One frame: (fin, rsv, opcode, payload). Raises Closed on EOF."""
        while True:
            if len(self.buf) >= 2:
                b0, b1 = self.buf[0], self.buf[1]
                assert b1 & 0x80 == 0, "server frames are unmasked"
                n = b1 & 0x7F
                at = 2
                if n == 126:
                    if len(self.buf) < 4:
                        self.read_more()
                        continue
                    n = struct.unpack(">H", self.buf[2:4])[0]
                    at = 4
                elif n == 127:
                    if len(self.buf) < 10:
                        self.read_more()
                        continue
                    n = struct.unpack(">Q", self.buf[2:10])[0]
                    at = 10
                if len(self.buf) >= at + n:
                    payload = self.buf[at:at + n]
                    self.buf = self.buf[at + n:]
                    return (b0 & 0x80 != 0, (b0 >> 4) & 7, b0 & 15, payload)
            self.read_more()

    def message(self):
        """A whole data message, skipping pongs: (opcode, rsv, payload)."""
        parts, first, rsv = [], None, 0
        while True:
            fin, r, op, payload = self.recv()
            if op == 10:
                continue
            if op == 8:
                return (8, 0, payload)
            if first is None:
                first, rsv = op, r
            parts.append(payload)
            if fin:
                return (first, rsv, b"".join(parts))

    def expect_close(self, codes):
        """Read until Close; check its code; answer it; then expect EOF."""
        while True:
            fin, rsv, op, payload = self.recv()
            if op == 8:
                break
        code = struct.unpack(">H", payload[:2])[0] if len(payload) >= 2 else None
        assert code in codes, ("close code", code, codes)
        try:
            self.send(8, payload[:2])
        except OSError:
            pass
        self.expect_eof()
        return code, payload[2:]

    def expect_eof(self):
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
        except ConnectionResetError:
            pass
        self.sock.close()

    def close(self):
        self.sock.close()


def _mask(payload, key):
    n = len(payload)
    k = int.from_bytes((key * ((n + 3) // 4))[:n], "little")
    return (int.from_bytes(payload, "little") ^ k).to_bytes(n, "little")
