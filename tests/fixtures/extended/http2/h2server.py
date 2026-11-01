"""Loopback HTTP/2 servers for the ext::http2 oracles.

Server: libnghttp2's server session (the HTTP/2 library curl uses), driven
with ctypes over a plain socket (prior knowledge) or TLS with ALPN "h2". It
routes requests by :path and records what the client did: frames, SETTINGS,
concurrency, frame sizes, WINDOW_UPDATEs, RST_STREAM and GOAWAY codes.

RawServer: a scripted peer that writes hand-built frames (for protocol
violations nghttp2 will not produce) and decodes the client's header blocks
with nghttp2's HPACK inflater.
"""
import ctypes
import select
import socket
import ssl
import struct
import threading
import time

lib = ctypes.CDLL("libnghttp2.so.14")
vp, sz, i32, u32, u8 = ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int32, ctypes.c_uint32, ctypes.c_uint8


class FrameHd(ctypes.Structure):
    _fields_ = [("length", sz), ("stream_id", i32), ("type", u8), ("flags", u8), ("reserved", u8)]


class GoawayFrame(ctypes.Structure):
    _fields_ = [("hd", FrameHd), ("last_stream_id", i32), ("error_code", u32), ("opaque_data", vp), ("opaque_data_len", sz), ("reserved", u8)]


class RstFrame(ctypes.Structure):
    _fields_ = [("hd", FrameHd), ("error_code", u32)]


class PingFrame(ctypes.Structure):
    _fields_ = [("hd", FrameHd), ("opaque_data", u8 * 8)]


class WindowFrame(ctypes.Structure):
    _fields_ = [("hd", FrameHd), ("window_size_increment", i32), ("reserved", u8)]


class SettingsEntry(ctypes.Structure):
    _fields_ = [("settings_id", i32), ("value", u32)]


class SettingsFrame(ctypes.Structure):
    _fields_ = [("hd", FrameHd), ("niv", sz), ("iv", ctypes.POINTER(SettingsEntry))]


class NV(ctypes.Structure):
    _fields_ = [("name", vp), ("value", vp), ("namelen", sz), ("valuelen", sz), ("flags", u8)]


READ_CB = ctypes.CFUNCTYPE(ctypes.c_ssize_t, vp, i32, ctypes.POINTER(u8), sz, ctypes.POINTER(u32), vp, vp)


class DataProvider(ctypes.Structure):
    _fields_ = [("source", vp), ("read_callback", READ_CB)]


FRAME_CB = ctypes.CFUNCTYPE(ctypes.c_int, vp, ctypes.POINTER(FrameHd), vp)
HEADER_CB = ctypes.CFUNCTYPE(ctypes.c_int, vp, ctypes.POINTER(FrameHd), ctypes.POINTER(u8), sz, ctypes.POINTER(u8), sz, u8, vp)
CHUNK_CB = ctypes.CFUNCTYPE(ctypes.c_int, vp, u8, i32, ctypes.POINTER(u8), sz, vp)
CLOSE_CB = ctypes.CFUNCTYPE(ctypes.c_int, vp, i32, u32, vp)

lib.nghttp2_session_callbacks_new.argtypes = [ctypes.POINTER(vp)]
for name, cb in (("on_begin_headers", FRAME_CB), ("on_frame_recv", FRAME_CB), ("on_header", HEADER_CB),
                 ("on_data_chunk_recv", CHUNK_CB), ("on_stream_close", CLOSE_CB)):
    getattr(lib, "nghttp2_session_callbacks_set_%s_callback" % name).argtypes = [vp, cb]
lib.nghttp2_session_server_new2.argtypes = [ctypes.POINTER(vp), vp, vp, vp]
lib.nghttp2_option_new.argtypes = [ctypes.POINTER(vp)]
lib.nghttp2_option_set_no_auto_window_update.argtypes = [vp, ctypes.c_int]
lib.nghttp2_session_mem_recv.argtypes = [vp, ctypes.c_char_p, sz]
lib.nghttp2_session_mem_recv.restype = ctypes.c_ssize_t
lib.nghttp2_session_mem_send.argtypes = [vp, ctypes.POINTER(vp)]
lib.nghttp2_session_mem_send.restype = ctypes.c_ssize_t
lib.nghttp2_submit_settings.argtypes = [vp, u8, ctypes.POINTER(SettingsEntry), sz]
lib.nghttp2_submit_response.argtypes = [vp, i32, ctypes.POINTER(NV), sz, ctypes.POINTER(DataProvider)]
lib.nghttp2_submit_headers.argtypes = [vp, u8, i32, vp, ctypes.POINTER(NV), sz, vp]
lib.nghttp2_submit_trailer.argtypes = [vp, i32, ctypes.POINTER(NV), sz]
lib.nghttp2_submit_rst_stream.argtypes = [vp, u8, i32, u32]
lib.nghttp2_submit_goaway.argtypes = [vp, u8, i32, u32, vp, sz]
lib.nghttp2_submit_ping.argtypes = [vp, u8, ctypes.c_char_p]
lib.nghttp2_session_consume.argtypes = [vp, i32, sz]
lib.nghttp2_session_want_read.argtypes = [vp]
lib.nghttp2_session_want_write.argtypes = [vp]
lib.nghttp2_session_del.argtypes = [vp]
lib.nghttp2_session_resume_data.argtypes = [vp, i32]

DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PUSH_PROMISE, PING, GOAWAY, WINDOW_UPDATE, CONTINUATION = range(10)
END_STREAM, ACK, END_HEADERS, PADDED, PRIORITY_FLAG = 1, 1, 4, 8, 32
EOF_FLAG, NO_END_STREAM = 1, 2
DEFERRED = -508


def nv_array(pairs, keep):
    arr = (NV * max(1, len(pairs)))()
    for i, (n, v) in enumerate(pairs):
        nb, vb = ctypes.create_string_buffer(n, len(n) or 1), ctypes.create_string_buffer(v, len(v) or 1)
        keep += [nb, vb]
        arr[i] = NV(ctypes.addressof(nb), ctypes.addressof(vb), len(n), len(v), 0)
    return arr, len(pairs)


def gen(n):
    return bytes(97 + (i * 7 + i // 251) % 26 for i in range(n))


class Conn:
    """One server connection: an nghttp2 session plus what the client did."""

    def __init__(self, server, sock):
        self.server, self.sock, self.keep, self.streams = server, sock, [], {}
        self.timers, self.events, self.open_streams, self.max_open = [], [], 0, 0
        self.client_settings, self.window_updates, self.max_data_frame, self.client_goaway, self.resets = {}, 0, 0, None, []
        self.ping_acks, self.closed_codes, self.requests, self.unconsumed = 0, {}, [], []
        cbs = vp()
        lib.nghttp2_session_callbacks_new(ctypes.byref(cbs))
        self.cb = [FRAME_CB(self.on_begin_headers), FRAME_CB(self.on_frame_recv), HEADER_CB(self.on_header),
                   CHUNK_CB(self.on_chunk), CLOSE_CB(self.on_close)]
        for name, cb in zip(("on_begin_headers", "on_frame_recv", "on_header", "on_data_chunk_recv", "on_stream_close"), self.cb):
            getattr(lib, "nghttp2_session_callbacks_set_%s_callback" % name)(cbs, cb)
        opt = vp()
        lib.nghttp2_option_new(ctypes.byref(opt))
        if server.consume_ms is not None:
            lib.nghttp2_option_set_no_auto_window_update(opt, 1)
        self.session = vp()
        assert lib.nghttp2_session_server_new2(ctypes.byref(self.session), cbs, None, opt) == 0
        iv = (SettingsEntry * max(1, len(server.settings)))(*[SettingsEntry(k, v) for k, v in server.settings])
        lib.nghttp2_submit_settings(self.session, 0, iv, len(server.settings))
        self.read_cb = READ_CB(self.read_data)

    # -- callbacks
    def on_begin_headers(self, session, frame, user):
        hd = frame.contents
        if hd.type == HEADERS and hd.stream_id not in self.streams:
            self.streams[hd.stream_id] = {"headers": [], "body": bytearray(), "out": b"", "sent": 0, "trailers": None, "deferred": False}
            self.open_streams += 1
            self.max_open = max(self.max_open, self.open_streams)
        return 0

    def on_header(self, session, frame, name, namelen, value, valuelen, flags, user):
        s = self.streams.get(frame.contents.stream_id)
        if s is not None:
            s["headers"].append((ctypes.string_at(name, namelen), ctypes.string_at(value, valuelen)))
        return 0

    def on_chunk(self, session, flags, stream_id, data, length, user):
        s = self.streams.get(stream_id)
        if s is not None:
            s["body"] += ctypes.string_at(data, length)
        if self.server.consume_ms is not None:
            self.timers.append((time.monotonic() + self.server.consume_ms / 1000.0, lambda sid=stream_id, n=length: lib.nghttp2_session_consume(self.session, sid, n)))
        return 0

    def on_frame_recv(self, session, frame, user):
        hd = frame.contents
        self.events.append((hd.type, hd.flags, hd.stream_id, hd.length))
        if hd.type == DATA:
            self.max_data_frame = max(self.max_data_frame, hd.length)
        if hd.type == SETTINGS and not hd.flags & ACK:
            f = ctypes.cast(frame, ctypes.POINTER(SettingsFrame)).contents
            for i in range(f.niv):
                self.client_settings[f.iv[i].settings_id] = f.iv[i].value
        if hd.type == WINDOW_UPDATE:
            self.window_updates += 1
        if hd.type == GOAWAY:
            self.client_goaway = ctypes.cast(frame, ctypes.POINTER(GoawayFrame)).contents.error_code
        if hd.type == RST_STREAM:
            self.resets.append((hd.stream_id, ctypes.cast(frame, ctypes.POINTER(RstFrame)).contents.error_code))
        if hd.type == PING and hd.flags & ACK:
            self.ping_acks += 1
        if hd.type in (HEADERS, DATA) and hd.flags & END_STREAM and hd.stream_id in self.streams:
            self.request(hd.stream_id)
        return 0

    def on_close(self, session, stream_id, code, user):
        self.closed_codes[stream_id] = code
        if stream_id in self.streams:
            self.open_streams -= 1
        return 0

    def read_data(self, session, stream_id, buf, length, flags, source, user):
        s = self.streams[stream_id]
        n = min(length, len(s["out"]) - s["sent"])
        ctypes.memmove(buf, s["out"][s["sent"]:s["sent"] + n], n)
        s["sent"] += n
        if s["sent"] == len(s["out"]):
            flags[0] |= EOF_FLAG
            if s["trailers"] is not None:
                flags[0] |= NO_END_STREAM
                arr, cnt = nv_array(s["trailers"], self.keep)
                lib.nghttp2_submit_trailer(self.session, stream_id, arr, cnt)
        return n

    # -- responses
    def respond(self, stream_id, status, headers=(), body=b"", trailers=None, no_body=False):
        s = self.streams[stream_id]
        s["out"], s["trailers"] = body, trailers
        arr, cnt = nv_array([(b":status", str(status).encode())] + list(headers), self.keep)
        if no_body:
            lib.nghttp2_submit_response(self.session, stream_id, arr, cnt, None)
        else:
            prd = DataProvider(None, self.read_cb)
            self.keep.append(prd)
            lib.nghttp2_submit_response(self.session, stream_id, arr, cnt, ctypes.byref(prd))

    def request(self, stream_id):
        s = self.streams[stream_id]
        h = dict(s["headers"])
        self.requests.append({"stream": stream_id, "method": h.get(b":method"), "path": h.get(b":path"), "headers": s["headers"], "body": bytes(s["body"])})
        self.server.route(self, stream_id, h.get(b":method", b""), h.get(b":path", b""), s)

    def later(self, ms, fn):
        self.timers.append((time.monotonic() + ms / 1000.0, fn))

    # -- I/O loop
    def run(self):
        try:
            while True:
                self.flush()
                if not lib.nghttp2_session_want_read(self.session) and not lib.nghttp2_session_want_write(self.session) and not self.timers:
                    break
                now = time.monotonic()
                due = [t for t in self.timers if t[0] <= now]
                self.timers = [t for t in self.timers if t[0] > now]
                for _, fn in due:
                    fn()
                if due:
                    continue
                wait = min([t[0] for t in self.timers], default=now + 0.05) - now
                r, _, _ = select.select([self.sock], [], [], max(0.0, min(wait, 0.05)))
                if r or (isinstance(self.sock, ssl.SSLSocket) and self.sock.pending()):
                    try:
                        data = self.sock.recv(65536)
                    except (ssl.SSLWantReadError, BlockingIOError):
                        continue
                    if not data:
                        break
                    if lib.nghttp2_session_mem_recv(self.session, data, len(data)) < 0:
                        break
        except (OSError, ssl.SSLError):
            pass
        finally:
            try:
                self.flush()
            except (OSError, ssl.SSLError):
                pass
            self.server.done(self)
            self.linger()

    def linger(self):
        # Close like a real server: FIN first, then read what the client
        # still sends for a moment, so closing with unread input does not
        # reset the connection and discard the last response in flight.
        try:
            self.sock.shutdown(socket.SHUT_WR)
            self.sock.settimeout(1.0)
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline and self.sock.recv(65536):
                pass
        except (OSError, ssl.SSLError, ValueError):
            pass
        try:
            self.sock.close()
        except OSError:
            pass

    def flush(self):
        while True:
            p = vp()
            n = lib.nghttp2_session_mem_send(self.session, ctypes.byref(p))
            if n <= 0:
                return
            self.sock.sendall(ctypes.string_at(p, n))


def default_route(conn, sid, method, path, s):
    p = path.decode()
    parts = p.split("/")
    if p == "/hello":
        conn.respond(sid, 200, [(b"content-type", b"text/plain")], b"hello world\n")
    elif p.startswith("/size/"):
        conn.respond(sid, 200, [(b"content-length", parts[2].encode())], gen(int(parts[2])))
    elif p.startswith("/delay/"):
        conn.later(int(parts[2]), lambda: conn.respond(sid, 200, [], path))
    elif p == "/echo":
        conn.respond(sid, 200, [(b"x-request-length", str(len(s["body"])).encode())], bytes(s["body"]))
    elif p.startswith("/headers/"):
        n, size = int(parts[2]), int(parts[3])
        conn.respond(sid, 200, [(b"x-h-%d" % i, (b"%d-" % i + gen(size))[:size]) for i in range(n)], b"ok")
    elif p == "/trailers":
        conn.respond(sid, 200, [(b"te-test", b"1")], b"abc", trailers=[(b"x-checksum", b"900150983cd24fb0"), (b"x-status", b"0")])
    elif p == "/early-hints":
        arr, cnt = nv_array([(b":status", b"103"), (b"link", b"</style.css>; rel=preload")], conn.keep)
        lib.nghttp2_submit_headers(conn.session, 0, sid, None, arr, cnt, None)
        conn.respond(sid, 200, [(b"x-final", b"1")], b"final")
    elif p.startswith("/status/"):
        conn.respond(sid, int(parts[2]), [], no_body=True)
    elif p == "/head":
        conn.respond(sid, 200, [(b"content-length", b"1234")], no_body=True)
    elif p.startswith("/rst/"):
        lib.nghttp2_submit_rst_stream(conn.session, 0, sid, int(parts[2]))
    elif p == "/goaway":
        conn.respond(sid, 200, [], b"bye")
        lib.nghttp2_submit_goaway(conn.session, 0, sid, 0, None, 0)
    elif p == "/ping":
        lib.nghttp2_submit_ping(conn.session, 0, b"srvping!")
        conn.later(300, lambda: conn.respond(sid, 200, [(b"x-ping-acks", str(conn.ping_acks).encode())], b"pinged"))
    elif p == "/redirect":
        conn.respond(sid, 302, [(b"location", b"/hello")], b"")
    elif p == "/method":
        conn.respond(sid, 200, [], method + b" " + str(len(s["body"])).encode())
    else:
        conn.respond(sid, 404, [], b"not found")


class Server:
    def __init__(self, context=None, settings=((3, 100),), consume_ms=None, route=default_route):
        self.context, self.settings, self.consume_ms, self.route_fn = context, list(settings), consume_ms, route
        self.conns, self.lock, self.finished = [], threading.Lock(), threading.Condition()
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(64)
        self.port = self.listener.getsockname()[1]
        self.active = 0
        threading.Thread(target=self.accept_loop, daemon=True).start()

    def route(self, conn, sid, method, path, s):
        self.route_fn(conn, sid, method, path, s)

    def accept_loop(self):
        while True:
            try:
                sock, _ = self.listener.accept()
            except OSError:
                return
            try:
                if self.context is not None:
                    sock.settimeout(5)
                    sock = self.context.wrap_socket(sock, server_side=True)
                    sock.settimeout(None)
                    if sock.selected_alpn_protocol() != "h2":
                        sock.close()
                        continue
            except (OSError, ssl.SSLError):
                sock.close()
                continue
            conn = Conn(self, sock)
            with self.lock:
                self.conns.append(conn)
                self.active += 1
            threading.Thread(target=conn.run, daemon=True).start()

    def done(self, conn):
        with self.finished:
            self.active -= 1
            self.finished.notify_all()

    def settle(self, timeout=5):
        """Wait until every accepted connection has ended."""
        with self.finished:
            self.finished.wait_for(lambda: self.active == 0, timeout)

    def stop(self):
        self.listener.close()


# ---------------------------------------------------------------- raw peer
class Inflater:
    def __init__(self):
        lib.nghttp2_hd_inflate_new.argtypes = [ctypes.POINTER(vp)]
        lib.nghttp2_hd_inflate_hd2.argtypes = [vp, ctypes.POINTER(NV), ctypes.POINTER(ctypes.c_int), vp, sz, ctypes.c_int]
        lib.nghttp2_hd_inflate_hd2.restype = ctypes.c_ssize_t
        lib.nghttp2_hd_inflate_end_headers.argtypes = [vp]
        lib.nghttp2_hd_inflate_change_table_size.argtypes = [vp, sz]
        self.p = vp()
        lib.nghttp2_hd_inflate_new(ctypes.byref(self.p))

    def inflate(self, block):
        buf = ctypes.create_string_buffer(block, len(block) or 1)
        base, off, fields = ctypes.addressof(buf), 0, []
        while True:
            nv, flags = NV(), ctypes.c_int(0)
            rv = lib.nghttp2_hd_inflate_hd2(self.p, ctypes.byref(nv), ctypes.byref(flags), base + off, len(block) - off, 1)
            if rv < 0:
                return None
            off += rv
            if flags.value & 2:
                fields.append((ctypes.string_at(nv.name, nv.namelen), ctypes.string_at(nv.value, nv.valuelen)))
            if flags.value & 1:
                lib.nghttp2_hd_inflate_end_headers(self.p)
                return fields


def literal_block(fields):
    """HPACK literals without indexing and without Huffman (RFC 7541 6.2.2)."""
    out = bytearray()

    def integer(value, prefix, flags):
        mask = (1 << prefix) - 1
        if value < mask:
            out.append(flags | value)
            return
        out.append(flags | mask)
        value -= mask
        while value >= 128:
            out.append((value & 127) | 128)
            value >>= 7
        out.append(value)

    for n, v in fields:
        integer(0, 4, 0)
        integer(len(n), 7, 0)
        out += n
        integer(len(v), 7, 0)
        out += v
    return bytes(out)


def frame(kind, flags, stream, payload=b""):
    return struct.pack(">I", len(payload))[1:] + bytes([kind, flags]) + struct.pack(">I", stream) + payload


def settings_frame(pairs=(), ack=False):
    return frame(SETTINGS, ACK if ack else 0, 0, b"".join(struct.pack(">HI", k, v) for k, v in pairs))


class RawPeer:
    """Reads client frames; script(peer) writes the server side."""

    def __init__(self, sock):
        self.sock, self.buf, self.frames, self.inflater, self.requests = sock, b"", [], Inflater(), []

    def send(self, data):
        self.sock.sendall(data)

    def read_frames(self, timeout=2.0, until=None):
        """Read client frames until until(frame) is true or the timeout."""
        end = time.monotonic() + timeout
        block, block_stream = b"", 0
        while time.monotonic() < end:
            while len(self.buf) >= 9:
                n = int.from_bytes(self.buf[:3], "big")
                if len(self.buf) < 9 + n:
                    break
                f = (self.buf[3], self.buf[4], int.from_bytes(self.buf[5:9], "big") & 0x7fffffff, self.buf[9:9 + n])
                self.buf = self.buf[9 + n:]
                self.frames.append(f)
                if f[0] in (HEADERS, CONTINUATION):
                    payload = f[3]
                    if f[0] == HEADERS:
                        if f[1] & PADDED:
                            payload = payload[1:len(payload) - payload[0]]
                        if f[1] & PRIORITY_FLAG:
                            payload = payload[5:]
                        block_stream = f[2]
                    block += payload
                    if f[1] & END_HEADERS:
                        self.requests.append((block_stream, dict(self.inflater.inflate(block) or [])))
                        block = b""
                if until and until(f):
                    return f
            r, _, _ = select.select([self.sock], [], [], 0.05)
            if r:
                try:
                    data = self.sock.recv(65536)
                except OSError:
                    return None
                if not data:
                    return None
                self.buf += data
        return None

    def preface(self):
        end = time.monotonic() + 2
        while len(self.buf) < 24 and time.monotonic() < end:
            r, _, _ = select.select([self.sock], [], [], 0.05)
            if r:
                self.buf += self.sock.recv(65536)
        assert self.buf[:24] == b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", self.buf[:24]
        self.buf = self.buf[24:]

    def handshake(self, pairs=()):
        """Consume the preface, send SETTINGS (and ACK the client's)."""
        self.preface()
        self.send(settings_frame(pairs))
        self.read_frames(until=lambda f: f[0] == SETTINGS and not f[1] & ACK)
        self.send(settings_frame(ack=True))

    def wait_request(self, count=1, timeout=2.0):
        self.read_frames(timeout, until=lambda f: len(self.requests) >= count)
        return self.requests[count - 1] if len(self.requests) >= count else None

    def codes(self, kind):
        """Error codes of client RST_STREAM or GOAWAY frames seen so far."""
        if kind == RST_STREAM:
            return [(f[2], int.from_bytes(f[3][:4], "big")) for f in self.frames if f[0] == RST_STREAM]
        return [int.from_bytes(f[3][4:8], "big") for f in self.frames if f[0] == GOAWAY]


class RawServer:
    def __init__(self, script):
        self.script, self.errors, self.peers = script, [], []
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(8)
        self.port = self.listener.getsockname()[1]
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        try:
            sock, _ = self.listener.accept()
        except OSError:
            return
        peer = RawPeer(sock)
        self.peers.append(peer)
        try:
            self.script(peer)
        except Exception as e:  # reported by the oracle
            self.errors.append(repr(e))
        finally:
            time.sleep(0.1)
            sock.close()
            self.listener.close()
