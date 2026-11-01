"""A libnghttp2 client session driven through ctypes.

The session never touches a socket: Client.output() returns the bytes
nghttp2 wants to send and Client.receive(data) hands it what arrived, so
the same client runs over a pipe to an engine harness or over TCP.
"""
import ctypes
from ctypes import (CFUNCTYPE, POINTER, Structure, Union, byref, c_char_p,
                    c_int, c_int32, c_size_t, c_ssize_t, c_uint8, c_uint32,
                    c_void_p, cast, create_string_buffer, string_at)

lib = ctypes.CDLL("libnghttp2.so.14")

DATA, HEADERS, RST_STREAM, SETTINGS, PING, GOAWAY, WINDOW_UPDATE = 0, 1, 3, 4, 6, 7, 8
INITIAL_WINDOW_SIZE, MAX_CONCURRENT_STREAMS, MAX_FRAME_SIZE = 4, 3, 5
DATA_FLAG_EOF = 1


class FrameHd(Structure):
    _fields_ = [("length", c_size_t), ("stream_id", c_int32), ("type", c_uint8),
                ("flags", c_uint8), ("reserved", c_uint8)]


class Nv(Structure):
    _fields_ = [("name", c_void_p), ("value", c_void_p), ("namelen", c_size_t),
                ("valuelen", c_size_t), ("flags", c_uint8)]


class SettingsEntry(Structure):
    _fields_ = [("settings_id", c_int32), ("value", c_uint32)]


class DataSource(Union):
    _fields_ = [("fd", c_int), ("ptr", c_void_p)]


READ_CB = CFUNCTYPE(c_ssize_t, c_void_p, c_int32, POINTER(c_uint8), c_size_t,
                    POINTER(c_uint32), POINTER(DataSource), c_void_p)


class DataProvider(Structure):
    _fields_ = [("source", DataSource), ("read_callback", READ_CB)]


SEND_CB = CFUNCTYPE(c_ssize_t, c_void_p, c_void_p, c_size_t, c_int, c_void_p)
FRAME_CB = CFUNCTYPE(c_int, c_void_p, POINTER(FrameHd), c_void_p)
CHUNK_CB = CFUNCTYPE(c_int, c_void_p, c_uint8, c_int32, c_void_p, c_size_t, c_void_p)
CLOSE_CB = CFUNCTYPE(c_int, c_void_p, c_int32, c_uint32, c_void_p)
HEADER_CB = CFUNCTYPE(c_int, c_void_p, POINTER(FrameHd), c_void_p, c_size_t,
                      c_void_p, c_size_t, c_uint8, c_void_p)

for name, res, args in [
    ("nghttp2_session_callbacks_new", c_int, [POINTER(c_void_p)]),
    ("nghttp2_session_callbacks_del", None, [c_void_p]),
    ("nghttp2_session_callbacks_set_send_callback", None, [c_void_p, SEND_CB]),
    ("nghttp2_session_callbacks_set_on_frame_recv_callback", None, [c_void_p, FRAME_CB]),
    ("nghttp2_session_callbacks_set_on_data_chunk_recv_callback", None, [c_void_p, CHUNK_CB]),
    ("nghttp2_session_callbacks_set_on_stream_close_callback", None, [c_void_p, CLOSE_CB]),
    ("nghttp2_session_callbacks_set_on_header_callback", None, [c_void_p, HEADER_CB]),
    ("nghttp2_option_new", c_int, [POINTER(c_void_p)]),
    ("nghttp2_option_del", None, [c_void_p]),
    ("nghttp2_option_set_no_auto_window_update", None, [c_void_p, c_int]),
    ("nghttp2_session_client_new2", c_int, [POINTER(c_void_p), c_void_p, c_void_p, c_void_p]),
    ("nghttp2_session_del", None, [c_void_p]),
    ("nghttp2_submit_settings", c_int, [c_void_p, c_uint8, POINTER(SettingsEntry), c_size_t]),
    ("nghttp2_submit_request", c_int32, [c_void_p, c_void_p, POINTER(Nv), c_size_t, POINTER(DataProvider), c_void_p]),
    ("nghttp2_submit_goaway", c_int, [c_void_p, c_uint8, c_int32, c_uint32, c_void_p, c_size_t]),
    ("nghttp2_submit_ping", c_int, [c_void_p, c_uint8, c_void_p]),
    ("nghttp2_session_send", c_int, [c_void_p]),
    ("nghttp2_session_mem_recv", c_ssize_t, [c_void_p, c_void_p, c_size_t]),
    ("nghttp2_session_want_read", c_int, [c_void_p]),
    ("nghttp2_session_want_write", c_int, [c_void_p]),
    ("nghttp2_session_consume", c_int, [c_void_p, c_int32, c_size_t]),
    ("nghttp2_session_get_remote_settings", c_uint32, [c_void_p, c_int]),
    ("nghttp2_strerror", c_char_p, [c_int]),
]:
    f = getattr(lib, name)
    f.restype = res
    f.argtypes = args


class Stream:
    def __init__(self):
        self.status = None
        self.headers = []
        self.body = bytearray()
        self.closed = False
        self.error = None


class Client:
    """settings: [(id, value)] sent in the client preface. manual_window:
    acknowledge received DATA only through consume()."""

    def __init__(self, settings=(), manual_window=False):
        self.out = bytearray()
        self.streams = {}
        self.frames = []          # (type, flags, stream) received
        self.goaway = None        # (last_stream, code) when received
        self.max_data_frame = 0
        self._keep = []
        self._cbs = [SEND_CB(self._send), FRAME_CB(self._frame), CHUNK_CB(self._chunk),
                     CLOSE_CB(self._close), HEADER_CB(self._header)]
        callbacks = c_void_p()
        assert lib.nghttp2_session_callbacks_new(byref(callbacks)) == 0
        lib.nghttp2_session_callbacks_set_send_callback(callbacks, self._cbs[0])
        lib.nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, self._cbs[1])
        lib.nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, self._cbs[2])
        lib.nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, self._cbs[3])
        lib.nghttp2_session_callbacks_set_on_header_callback(callbacks, self._cbs[4])
        option = c_void_p()
        assert lib.nghttp2_option_new(byref(option)) == 0
        lib.nghttp2_option_set_no_auto_window_update(option, 1 if manual_window else 0)
        self.session = c_void_p()
        assert lib.nghttp2_session_client_new2(byref(self.session), callbacks, None, option) == 0
        lib.nghttp2_option_del(option)
        lib.nghttp2_session_callbacks_del(callbacks)
        entries = (SettingsEntry * max(1, len(settings)))(*[SettingsEntry(i, v) for i, v in settings])
        assert lib.nghttp2_submit_settings(self.session, 0, entries, len(settings)) == 0

    # ---- callbacks ----
    def _send(self, session, data, length, flags, user):
        self.out += string_at(data, length)
        return length

    def _frame(self, session, hd, user):
        h = hd.contents
        self.frames.append((h.type, h.flags, h.stream_id))
        if h.type == DATA:
            self.max_data_frame = max(self.max_data_frame, h.length)
        if h.type == GOAWAY:
            # nghttp2_goaway: hd, int32 last_stream_id, uint32 error_code, ...
            base = ctypes.addressof(h) + ctypes.sizeof(FrameHd)
            base += (-base) % 4
            last = c_int32.from_address(base).value
            code = c_uint32.from_address(base + 4).value
            self.goaway = (last, code)
        return 0

    def _chunk(self, session, flags, stream_id, data, length, user):
        self.streams.setdefault(stream_id, Stream()).body += string_at(data, length)
        return 0

    def _close(self, session, stream_id, code, user):
        s = self.streams.setdefault(stream_id, Stream())
        s.closed = True
        s.error = code
        return 0

    def _header(self, session, hd, name, namelen, value, valuelen, flags, user):
        s = self.streams.setdefault(hd.contents.stream_id, Stream())
        n, v = string_at(name, namelen), string_at(value, valuelen)
        if n == b":status":
            s.status = int(v)
        else:
            s.headers.append((n, v))
        return 0

    # ---- API ----
    def request(self, method, path, headers=(), body=None, authority=b"localhost"):
        fields = [(b":method", method), (b":scheme", b"http"), (b":authority", authority),
                  (b":path", path)] + list(headers)
        keep = [create_string_buffer(x, len(x)) for f in fields for x in f]
        self._keep.append(keep)
        nva = (Nv * len(fields))()
        for i in range(len(fields)):
            nva[i] = Nv(cast(keep[2 * i], c_void_p), cast(keep[2 * i + 1], c_void_p),
                        len(fields[i][0]), len(fields[i][1]), 0)
        provider = None
        if body is not None:
            state = {"at": 0}

            def read(session, stream_id, buf, length, flags, source, user):
                n = min(length, len(body) - state["at"])
                ctypes.memmove(buf, body[state["at"]:state["at"] + n], n)
                state["at"] += n
                if state["at"] == len(body):
                    flags[0] |= DATA_FLAG_EOF
                return n
            cb = READ_CB(read)
            self._keep.append(cb)
            provider = DataProvider(DataSource(0), cb)
            self._keep.append(provider)
        sid = lib.nghttp2_submit_request(self.session, None, nva, len(fields),
                                         byref(provider) if provider else None, None)
        assert sid > 0, lib.nghttp2_strerror(sid)
        self.streams[sid] = Stream()
        return sid

    def goaway_submit(self, code=0):
        assert lib.nghttp2_submit_goaway(self.session, 0, 0, code, None, 0) == 0

    def ping(self):
        assert lib.nghttp2_submit_ping(self.session, 0, b"12345678") == 0

    def consume(self, stream_id, size):
        assert lib.nghttp2_session_consume(self.session, stream_id, size) == 0

    def remote_setting(self, ident):
        return lib.nghttp2_session_get_remote_settings(self.session, ident)

    def output(self):
        rv = lib.nghttp2_session_send(self.session)
        assert rv == 0, lib.nghttp2_strerror(rv)
        data, self.out = bytes(self.out), bytearray()
        return data

    def receive(self, data):
        buf = create_string_buffer(data, len(data))
        rv = lib.nghttp2_session_mem_recv(self.session, buf, len(data))
        if rv < 0:
            raise RuntimeError("nghttp2: %s" % lib.nghttp2_strerror(rv).decode())
        return rv

    def wants(self):
        return lib.nghttp2_session_want_read(self.session) or lib.nghttp2_session_want_write(self.session)

    def close(self):
        lib.nghttp2_session_del(self.session)
