#!/usr/bin/env python3
"""Loopback oracle for engine_driver.lani (ext::http2 over cleartext h2).

usage: engine_oracle.py nghttp2|raw|all DRIVER

nghttp2  The driver against libnghttp2's server session (h2server.Server):
         concurrency, the peer's MAX_CONCURRENT_STREAMS, large downloads and
         uploads under flow control (including a server that acknowledges
         data slowly with a 1000-byte window), larger peer frames, a zero
         peer header table, CONTINUATION from large header blocks, trailers,
         1xx, HEAD and 204, RST_STREAM, GOAWAY, PING both ways, cancel, and
         200 sequential requests on one connection. nghttp2 validates the
         client's frames, HPACK, flow control and messaging itself.
raw      The driver against hand-built server frames (h2server.RawServer):
         every connection and stream error the client must detect, with the
         GOAWAY or RST_STREAM code it sends, plus valid padding, priority,
         CONTINUATION, unknown frames and settings, GOAWAY last-stream
         refusal, and server PING.
Prints: http2-engine-GROUP cases=N
"""
import os
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h2server  # noqa: E402
from h2server import (ACK, CONTINUATION, DATA, END_HEADERS, END_STREAM, GOAWAY, HEADERS, PADDED, PING,  # noqa: E402
                      PRIORITY_FLAG, PUSH_PROMISE, RST_STREAM, SETTINGS, WINDOW_UPDATE, frame, gen, literal_block,
                      settings_frame)

EXE = None


class Failure(Exception):
    pass


def expect(ok, what):
    if not ok:
        raise Failure(repr(what)[:3000])


def fnv(b):
    h = 2166136261
    for c in b:
        h = ((h ^ c) * 16777619) & 0xffffffff
    return "%08x" % h


def drive(port, script, args=(), timeout=60):
    r = subprocess.run([EXE, str(port)] + [str(a) for a in args], input=("\n".join(script) + "\n").encode(), capture_output=True, timeout=timeout)
    expect(r.returncode == 0, ("driver exit", r.returncode, r.stdout[-500:], r.stderr[-500:]))
    return [l for l in r.stdout.decode().splitlines()]


def resp(label, status, body, fields, trailers=0):
    return "resp %s %d %d %s fields=%d trailers=%d" % (label, status, len(body), fnv(body), fields, trailers)


def responses(lines):
    return [l for l in lines if l.startswith(("resp ", "fail ", "start ", "conn ", "timeout", "pong ", "peer ", "eof", "more-failed"))]


def nghttp2_cases():
    out = []

    def case(fn):
        out.append(fn)
        return fn

    def server(**kw):
        return h2server.Server(**kw)

    @case
    def concurrent_streams_complete_out_of_order():
        s = server()
        script = ["drive 100"] + ["req r%d GET /delay/%d" % (i, 400 - i * 15) for i in range(20)] + ["wait all 5000"]
        lines = drive(s.port, script)
        expect(sorted(responses(lines)) == sorted(resp("r%d" % i, 200, b"/delay/%d" % (400 - i * 15), 0) for i in range(20)), lines)
        s.settle()
        expect(len(s.conns) == 1 and s.conns[0].max_open == 20, (len(s.conns), s.conns[0].max_open))
        # Completion follows the server's delays, not submission order.
        order = [l.split(" ")[1] for l in lines if l.startswith("resp ")]
        expect(order[0] == "r19" and order[-1] == "r0", order)

    @case
    def peer_concurrency_limit():
        s = server(settings=[(3, 2)])
        lines = drive(s.port, ["drive 100", "peer", "req a GET /delay/200", "req b GET /delay/100", "req c GET /hello", "wait all 3000", "req d GET /hello", "req e GET /hello", "wait all 3000"])
        r = responses(lines)
        expect(r[:4] == ["peer streams=2 window=65535 frame=16384 table=4096", "start c busy",
                         resp("b", 200, b"/delay/100", 0), resp("a", 200, b"/delay/200", 0)], lines)
        expect(sorted(r[4:]) == [resp("d", 200, b"hello world\n", 1), resp("e", 200, b"hello world\n", 1)], lines)
        s.settle()
        expect(s.conns[0].max_open == 2, s.conns[0].max_open)

    @case
    def large_download_flow_control():
        s = server()
        lines = drive(s.port, ["req a GET /size/5000000", "wait a 20000"], args=(65535, 65535))
        expect(responses(lines) == [resp("a", 200, gen(5000000), 1)], lines)
        s.settle()
        # A 64 KiB stream and connection window needs ~150 WINDOW_UPDATEs.
        expect(s.conns[0].window_updates >= 100, s.conns[0].window_updates)

    @case
    def large_upload_respects_server_window():
        s = server()
        lines = drive(s.port, ["req a POST /echo gen:3000000", "wait a 20000"])
        expect(responses(lines) == [resp("a", 200, gen(3000000), 1)], lines)
        s.settle()
        expect(s.conns[0].requests[0]["body"] == gen(3000000) and s.conns[0].max_data_frame <= 16384, s.conns[0].max_data_frame)

    @case
    def slow_acknowledging_server():
        # 1000-byte stream window, data acknowledged 20 ms after arrival.
        s = server(settings=[(3, 100), (4, 1000)], consume_ms=20)
        lines = drive(s.port, ["drive 100", "req a POST /echo gen:30000", "req b POST /echo text:short", "wait all 20000"])
        expect(sorted(responses(lines)) == sorted([resp("a", 200, gen(30000), 1), resp("b", 200, b"short", 1)]), lines)
        s.settle()
        expect(s.conns[0].max_data_frame <= 1000, s.conns[0].max_data_frame)

    @case
    def streamed_body_in_parts():
        s = server()
        lines = drive(s.port, ["req a POST /echo open", "more a gen:50000", "drive 50", "more a text:tail end", "wait a 5000"])
        expect(responses(lines) == [resp("a", 200, gen(50000) + b"tail", 1)], lines)

    @case
    def larger_peer_frames():
        s = server(settings=[(3, 100), (5, 65536), (4, 1048576)])
        lines = drive(s.port, ["drive 100", "req a POST /echo gen:200000", "wait a 10000"])
        expect(responses(lines) == [resp("a", 200, gen(200000), 1)], lines)
        s.settle()
        expect(16384 < s.conns[0].max_data_frame <= 65536, s.conns[0].max_data_frame)

    @case
    def zero_peer_header_table():
        s = server(settings=[(3, 100), (1, 0)])
        lines = drive(s.port, ["drive 100", "h x-a value-a", "req a GET /hello", "wait a 3000", "h x-a value-a", "req b GET /hello", "wait b 3000", "peer"])
        expect(responses(lines)[:2] == [resp("a", 200, b"hello world\n", 1), resp("b", 200, b"hello world\n", 1)], lines)
        expect(responses(lines)[2] == "peer streams=100 window=65535 frame=16384 table=0", lines)
        s.settle()
        expect([dict(q["headers"]).get(b"x-a") for q in s.conns[0].requests] == [b"value-a", b"value-a"], s.conns[0].requests)

    @case
    def continuation_from_large_header_block():
        s = server()
        lines = drive(s.port, ["req a GET /headers/40/1000", "wait a 5000"])
        expect(responses(lines)[0] == resp("a", 200, b"ok", 40), lines)
        fields = [l for l in lines if l.startswith("f ")]
        expect(fields[0].startswith("f x-h-0 0-") and fields[39].startswith("f x-h-39 39-"), fields[:2])

    @case
    def trailers_and_interim_responses():
        s = server()
        lines = drive(s.port, ["req t GET /trailers", "req e GET /early-hints", "wait all 3000"])
        expect(sorted(responses(lines)) == sorted([resp("t", 200, b"abc", 1, 2), resp("e", 200, b"final", 1)]), lines)
        expect("f x-checksum 900150983cd24fb0" in lines and not any(l.startswith("f link") for l in lines), lines)

    @case
    def head_and_no_content():
        s = server()
        lines = drive(s.port, ["req h HEAD /head", "req n GET /status/204", "req m GET /status/304", "wait all 3000"])
        expect(sorted(responses(lines)) == sorted([resp("h", 200, b"", 1), resp("n", 204, b"", 0), resp("m", 304, b"", 0)]), lines)

    @case
    def reset_streams():
        s = server()
        lines = drive(s.port, ["req a GET /rst/8", "req b GET /rst/7", "req c GET /hello", "wait all 3000"])
        expect(sorted(responses(lines)) == sorted(["fail a peer 8", "fail b refused 7", resp("c", 200, b"hello world\n", 1)]), lines)

    @case
    def server_goaway_stops_new_streams():
        s = server()
        lines = drive(s.port, ["req a GET /goaway", "wait a 3000", "drive 100", "req b GET /hello", "eof 3000"])
        expect(responses(lines) == [resp("a", 200, b"bye", 0), "start b closed", "eof"], lines)

    @case
    def ping_both_ways():
        s = server()
        lines = drive(s.port, ["ping 3000", "req a GET /ping", "wait a 3000", "ping 3000"])
        expect(responses(lines)[0] == "pong 1" and responses(lines)[1] == resp("a", 200, b"pinged", 1) and responses(lines)[2] == "pong 2", lines)
        expect("f x-ping-acks 1" in lines, lines)

    @case
    def client_goaway_and_cancel():
        s = server()
        lines = drive(s.port, ["req a GET /delay/2000", "drive 100", "cancel a", "wait a 1000", "req b GET /hello", "wait b 3000", "goaway", "req c GET /hello"])
        expect(responses(lines) == ["fail a cancelled 8", resp("b", 200, b"hello world\n", 1), "start c closed"], lines)
        s.settle()
        c = s.conns[0]
        expect((1, 8) in c.resets and c.client_goaway == 0, (c.resets, c.client_goaway))

    @case
    def invalid_requests_refused_locally():
        s = server()
        lines = drive(s.port, ["h X-Upper v", "req a GET /hello", "h connection close", "req b GET /hello", "h te gzip", "req c GET /hello", "h te trailers", "req d GET /hello", "wait d 3000"])
        expect(responses(lines) == ["start a invalid-request", "start b invalid-request", "start c invalid-request", resp("d", 200, b"hello world\n", 1)], lines)

    @case
    def many_sequential_requests_one_connection():
        s = server()
        script = []
        for i in range(200):
            script += ["h x-seq %d" % (i % 7), "req s%d GET /hello" % i, "wait s%d 3000" % i]
        lines = drive(s.port, script)
        expect(responses(lines) == [resp("s%d" % i, 200, b"hello world\n", 1) for i in range(200)], responses(lines)[:3])
        s.settle()
        expect(len(s.conns) == 1 and len(s.conns[0].requests) == 200 and s.conns[0].requests[-1]["stream"] == 399, len(s.conns))

    return out


# ---------------------------------------------------------------- raw
def raw(script, client, args=()):
    srv = h2server.RawServer(script)
    lines = drive(srv.port, client, args=args)
    time.sleep(0.15)
    expect(not srv.errors, srv.errors)
    return lines, (srv.peers[0] if srv.peers else None)


def ok_response(stream, body=b"ok", extra=()):
    block = literal_block([(b":status", b"200")] + list(extra))
    return frame(HEADERS, END_HEADERS, stream, block) + frame(DATA, END_STREAM, stream, body)


def raw_cases():
    out = []

    def conn_error(name, server_frames, code, before=()):
        def fn():
            def script(p):
                p.handshake()
                p.wait_request()
                for f in before:
                    p.send(f)
                p.send(server_frames(p))
                p.read_frames(1.5, until=lambda f: f[0] == GOAWAY)
            lines, peer = raw(script, ["req a GET /x", "wait a 3000"])
            expect(responses(lines) == ["conn protocol %d" % code, "fail a protocol %d" % code], lines)
            expect(peer.codes(GOAWAY) == [code], peer.codes(GOAWAY))
        fn.__name__ = name
        out.append(fn)

    def stream_error(name, server_frames, cause, code, args=()):
        def fn():
            def script(p):
                p.handshake()
                p.wait_request()
                p.send(server_frames(p))
                p.read_frames(1.0, until=lambda f: f[0] == RST_STREAM)
                p.wait_request(2)
                p.send(ok_response(3))
                p.read_frames(0.3)
            lines, peer = raw(script, ["req a GET /x", "wait a 3000", "req b GET /y", "wait b 3000"], args)
            expect(responses(lines) == ["fail a %s %d" % (cause, code), resp("b", 200, b"ok", 0)], lines)
            expect(peer.codes(RST_STREAM) == [(1, code)] and peer.codes(GOAWAY) == [], (peer.codes(RST_STREAM), peer.codes(GOAWAY)))
        fn.__name__ = name
        out.append(fn)

    hdr = lambda fields, flags=END_HEADERS: lambda p: frame(HEADERS, flags, 1, literal_block(fields))

    conn_error("push_promise_with_push_disabled", lambda p: frame(PUSH_PROMISE, END_HEADERS, 1, struct.pack(">I", 2) + literal_block([(b":method", b"GET")])), 1)
    conn_error("settings_enable_push", lambda p: settings_frame([(2, 1)]), 1)
    conn_error("settings_window_too_large", lambda p: settings_frame([(4, 1 << 31)]), 3)
    conn_error("settings_frame_size_too_small", lambda p: settings_frame([(5, 100)]), 1)
    conn_error("settings_ack_with_payload", lambda p: frame(SETTINGS, ACK, 0, b"\0" * 6), 6)
    conn_error("settings_on_a_stream", lambda p: frame(SETTINGS, 0, 1, b""), 1)
    conn_error("frame_larger_than_max_frame_size", lambda p: frame(DATA, 0, 1, b"x" * 16385), 6)
    conn_error("ping_wrong_length", lambda p: frame(PING, 0, 0, b"1234567"), 6)
    conn_error("window_update_zero_on_connection", lambda p: frame(WINDOW_UPDATE, 0, 0, struct.pack(">I", 0)), 1)
    conn_error("connection_window_overflow", lambda p: frame(WINDOW_UPDATE, 0, 0, struct.pack(">I", 0x7fffffff)), 3)
    conn_error("padding_longer_than_payload", lambda p: frame(DATA, PADDED, 1, bytes([10]) + b"abc"), 1)
    conn_error("hpack_index_zero", lambda p: frame(HEADERS, END_HEADERS, 1, b"\x80"), 9)
    conn_error("headers_on_server_stream", lambda p: frame(HEADERS, END_HEADERS, 2, literal_block([(b":status", b"200")])), 1)
    conn_error("headers_on_idle_stream", lambda p: frame(HEADERS, END_HEADERS, 5, literal_block([(b":status", b"200")])), 1)
    conn_error("data_on_stream_zero", lambda p: frame(DATA, 0, 0, b"x"), 1)
    conn_error("continuation_interrupted", lambda p: frame(HEADERS, 0, 1, literal_block([(b":status", b"200")])) + frame(PING, 0, 0, b"12345678"), 1)
    conn_error("continuation_without_headers", lambda p: frame(CONTINUATION, END_HEADERS, 1, literal_block([(b"a", b"b")])), 1)
    conn_error("rst_stream_on_idle_stream", lambda p: frame(RST_STREAM, 0, 7, struct.pack(">I", 8)), 1)

    @out.append
    def server_preface_not_settings():
        def script(p):
            p.preface()
            p.read_frames(0.3)
            p.send(ok_response(1))
            p.read_frames(1.0, until=lambda f: f[0] == GOAWAY)
        lines, peer = raw(script, ["req a GET /x", "wait a 3000"])
        expect(responses(lines) == ["conn protocol 1", "fail a protocol 1"] and peer.codes(GOAWAY) == [1], (lines, peer.codes(GOAWAY)))

    stream_error("data_before_headers", lambda p: frame(DATA, END_STREAM, 1, b"x"), "malformed", 1)
    stream_error("uppercase_field_name", hdr([(b":status", b"200"), (b"X-Bad", b"1")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("connection_specific_field", hdr([(b":status", b"200"), (b"connection", b"keep-alive")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("missing_status", hdr([(b"server", b"x")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("request_pseudo_field_in_response", hdr([(b":status", b"200"), (b":path", b"/")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("pseudo_field_after_regular", hdr([(b"server", b"x"), (b":status", b"200")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("status_not_three_digits", hdr([(b":status", b"2000")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("field_value_with_newline", hdr([(b":status", b"200"), (b"x-a", b"a\nb")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("content_length_mismatch", lambda p: frame(HEADERS, END_HEADERS, 1, literal_block([(b":status", b"200"), (b"content-length", b"10")])) + frame(DATA, END_STREAM, 1, b"12345"), "malformed", 1)
    stream_error("data_beyond_content_length", lambda p: frame(HEADERS, END_HEADERS, 1, literal_block([(b":status", b"200"), (b"content-length", b"3")])) + frame(DATA, END_STREAM, 1, b"12345"), "malformed", 1)
    stream_error("trailers_without_end_stream", lambda p: ok_response(1)[:0] + frame(HEADERS, END_HEADERS, 1, literal_block([(b":status", b"200")])) + frame(HEADERS, END_HEADERS, 1, literal_block([(b"x-t", b"1")])), "malformed", 1)
    stream_error("interim_with_end_stream", hdr([(b":status", b"103")], END_HEADERS | END_STREAM), "malformed", 1)
    stream_error("status_101", hdr([(b":status", b"101")], END_HEADERS), "malformed", 1)
    stream_error("window_update_zero_on_stream", lambda p: frame(WINDOW_UPDATE, 0, 1, struct.pack(">I", 0)), "protocol", 1)
    stream_error("stream_window_overflow", lambda p: frame(WINDOW_UPDATE, 0, 1, struct.pack(">I", 0x7fffffff)), "protocol", 3)
    stream_error("stream_flow_control_exceeded", lambda p: frame(HEADERS, END_HEADERS, 1, literal_block([(b":status", b"200")])) + frame(DATA, 0, 1, b"x" * 2000), "protocol", 3, args=(1000, 65535))
    stream_error("self_dependency", lambda p: frame(HEADERS, END_HEADERS | PRIORITY_FLAG | END_STREAM, 1, struct.pack(">IB", 1, 15) + literal_block([(b":status", b"200")])), "protocol", 1)
    stream_error("priority_frame_wrong_length", lambda p: frame(2, 0, 1, b"\0\0\0"), "protocol", 6)
    stream_error("body_over_limit", lambda p: frame(HEADERS, END_HEADERS, 1, literal_block([(b":status", b"200")])) + frame(DATA, END_STREAM, 1, b"x" * 101), "limit", 8, args=(1048576, 16777216, 100))
    stream_error("header_list_over_limit", hdr([(b":status", b"200"), (b"x-big", b"v" * 300)], END_HEADERS | END_STREAM), "limit", 8, args=(1048576, 16777216, 1000000, 200))

    @out.append
    def rst_stream_refused_is_retryable():
        def script(p):
            p.handshake()
            p.wait_request()
            p.send(frame(RST_STREAM, 0, 1, struct.pack(">I", 7)))
            p.read_frames(0.3)
        lines, _ = raw(script, ["req a GET /x", "wait a 3000"])
        expect(responses(lines) == ["fail a refused 7"], lines)

    @out.append
    def goaway_last_stream_refuses_later_streams():
        def script(p):
            p.handshake()
            p.wait_request(2)
            p.send(frame(GOAWAY, 0, 0, struct.pack(">II", 1, 0)) + ok_response(1))
            p.read_frames(0.3)
        lines, _ = raw(script, ["req a GET /x", "req b GET /y", "wait all 3000", "req c GET /z"])
        expect(sorted(responses(lines)) == sorted([resp("a", 200, b"ok", 0), "fail b refused 0", "start c closed"]), lines)

    @out.append
    def padding_priority_and_continuation_accepted():
        def script(p):
            p.handshake()
            p.wait_request()
            block = literal_block([(b":status", b"200"), (b"x-long", b"y" * 100), (b"x-two", b"2")])
            first = struct.pack(">B", 3) + struct.pack(">IB", 0x80000000 | 0, 200) + block[:20] + b"\0\0\0"
            p.send(frame(HEADERS, PADDED | PRIORITY_FLAG, 1, first) + frame(CONTINUATION, 0, 1, block[20:60]) + frame(CONTINUATION, END_HEADERS, 1, block[60:]))
            p.send(frame(DATA, PADDED, 1, bytes([5]) + b"hello" + b"\0" * 5) + frame(DATA, PADDED | END_STREAM, 1, bytes([0]) + b"!"))
            p.read_frames(0.3)
        lines, _ = raw(script, ["req a GET /x", "wait a 3000"])
        expect(responses(lines) == [resp("a", 200, b"hello!", 2)], lines)

    @out.append
    def unknown_frames_and_settings_ignored():
        def script(p):
            p.handshake([(0x99, 7), (3, 50)])
            p.wait_request()
            p.send(frame(0x42, 0xff, 1, b"opaque") + frame(0x42, 0, 0, b"") + ok_response(1))
            p.read_frames(0.3)
        lines, _ = raw(script, ["drive 100", "peer", "req a GET /x", "wait a 3000"])
        expect(responses(lines) == ["peer streams=50 window=65535 frame=16384 table=4096", resp("a", 200, b"ok", 0)], lines)

    @out.append
    def ignored_frames_keep_hpack_in_step():
        # A header block on a finished stream is still decoded (it adds a
        # dynamic table entry that the next response refers to).
        def script(p):
            p.handshake()
            p.wait_request()
            p.send(ok_response(1))
            p.wait_request(2)
            indexed = b"\x40" + bytes([5]) + b"x-tab" + bytes([3]) + b"one"
            p.send(frame(HEADERS, END_HEADERS | END_STREAM, 1, indexed))
            p.send(frame(HEADERS, END_HEADERS, 3, literal_block([(b":status", b"200")]) + b"\xbe") + frame(DATA, END_STREAM, 3, b"two"))
            p.read_frames(0.3)
        lines, _ = raw(script, ["req a GET /x", "wait a 3000", "req b GET /y", "wait b 3000"])
        expect(responses(lines) == [resp("a", 200, b"ok", 0), resp("b", 200, b"two", 1)] and "f x-tab one" in lines, lines)

    @out.append
    def server_ping_and_settings_acknowledged():
        def script(p):
            p.handshake([(4, 100000)])
            p.send(frame(PING, 0, 0, b"abcdefgh"))
            p.wait_request()
            p.send(ok_response(1))
            p.read_frames(0.5)
            acks = [f for f in p.frames if f[0] == PING and f[1] & ACK]
            sacks = [f for f in p.frames if f[0] == SETTINGS and f[1] & ACK]
            assert acks and acks[0][3] == b"abcdefgh", acks
            assert len(sacks) == 1, sacks
        lines, _ = raw(script, ["req a GET /x", "wait a 3000", "peer"])
        expect(responses(lines) == [resp("a", 200, b"ok", 0), "peer streams=2147483647 window=100000 frame=16384 table=4096"], lines)

    @out.append
    def initial_window_change_applies_to_open_streams():
        # The server shrinks the window to 10 bytes mid-upload; DATA must wait
        # for WINDOW_UPDATE and never exceed it.
        def script(p):
            p.handshake([(4, 10)])
            p.read_frames(0.5)
            got = sum(len(f[3]) for f in p.frames if f[0] == DATA)
            assert got <= 10, got
            p.send(frame(WINDOW_UPDATE, 0, 1, struct.pack(">I", 90)))
            p.read_frames(1.0, until=lambda f: f[0] == DATA and f[1] & END_STREAM)
            data = b"".join(f[3] for f in p.frames if f[0] == DATA)
            assert data == gen(100), data
            p.send(ok_response(1))
            p.read_frames(0.3)
        lines, _ = raw(script, ["drive 100", "req a POST /x gen:100", "wait a 3000"])
        expect(responses(lines) == [resp("a", 200, b"ok", 0)], lines)

    return out


def main():
    global EXE
    if len(sys.argv) != 3 or sys.argv[1] not in ("nghttp2", "raw", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    groups = {"nghttp2": nghttp2_cases, "raw": raw_cases}
    for group in (list(groups) if sys.argv[1] == "all" else [sys.argv[1]]):
        todo = groups[group]()
        for fn in todo:
            try:
                fn()
            except Failure as e:
                print("FAIL %s/%s: %s" % (group, fn.__name__, e), file=sys.stderr)
                return 1
            except subprocess.TimeoutExpired:
                print("FAIL %s/%s: driver timed out" % (group, fn.__name__), file=sys.stderr)
                return 1
        print("http2-engine-%s cases=%d" % (group, len(todo)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
