"""Bounded raw TLS state cases using native OpenSSL peers and test observers."""
import importlib.util
from pathlib import Path
import select
import socket
import ssl
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("duplex_edge_peer", BASE / "openssl_tls" / "peer.py")
PEER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PEER)
EXE = None
CERTS = None
CASES = 0


def payload(count):
    return bytes((index * 73 + 11) & 255 for index in range(count))


def marker(process, expected):
    ready, _, _ = select.select([process.stderr], [], [], 4)
    assert ready, ("missing product phase", expected, process.poll())
    actual = process.stderr.readline(16)
    assert actual == expected, ("wrong product phase", expected, actual, process.poll())


def invoke(mode, version=ssl.TLSVersion.TLSv1_3):
    global CASES
    transports, inherited = [], []
    for _ in range(2 if mode == 2 else 1):
        parent, child = socket.socketpair()
        child.setblocking(False)
        if mode == 0:
            child.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
            parent.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        transports.append(parent)
        inherited.append(child)
    descriptors = [item.fileno() for item in inherited]
    command = [str(EXE), str(descriptors[0]), str(descriptors[-1]),
               str(CERTS / "root.pem"), str(mode)]
    process = subprocess.Popen(command, pass_fds=descriptors, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for item in inherited:
        item.close()
    try:
        peers = [PEER.Connection(item, PEER.context(CERTS, version=version)) for item in transports]
        for peer in peers:
            peer.handshake()
            assert peer.tls.version() == ("TLSv1.3" if version == ssl.TLSVersion.TLSv1_3 else "TLSv1.2")
        peer = peers[0]
        if mode == 0:
            # No application read occurs before the product proves a real
            # native WANT_WRITE and verifies its exclusive-operation guards.
            marker(process, b"W\n")
            assert peer.read_exact(262144) == payload(262144)
            peer.write(payload(1))
            peer.shutdown()
        elif mode == 1:
            # Exactly one native SSLObject.write fits in one application record.
            # No close alert or later write can create fd readiness before B.
            assert not peer.outgoing.pending
            assert peer.tls.write(payload(1024)) == 1024
            assert peer.outgoing.pending > 1024
            peer.flush()
            marker(process, b"B\n")
            peer.shutdown()
        elif mode == 2:
            # The second session must retry its own distinct staged request
            # first. Its acknowledgement releases the first session's retry.
            assert peers[1].read_exact(11) == b"two-request"
            peers[1].write(payload(17))
            assert peer.read_exact(7) == b"one-req"
            peer.write(payload(17))
            peers[1].shutdown()
            peer.shutdown()
        elif mode == 6:
            peer.cut_record(payload(257), 7)
        elif mode >= 7:
            # For mode9, the peer has deliberately withheld its alert until
            # the product reaches a real full-shutdown WANT_READ after Sent.
            # Modes7/8 label their first WANT as explicitly injected controls.
            marker(process, b"S\n")
            peer.shutdown()
        # Fatal-operation modes3/4/5 manufacture only a native negative result.
        # No positive plaintext or successful shutdown is supplied by a shim.
        out, err = process.communicate(timeout=6)
        assert process.returncode == 0 and len(out) == 320 and err == b"", (command, process.returncode, out, err)
        values = struct.unpack("<40Q", out)
        assert values[0] == mode and values[3] > 0 and 0 < values[8] < 20000, values
        assert values[9:12] == (0, 0, 0) and values[25] == 0, values
        if mode == 0:
            assert values[1:3] == (262144, 1) and values[4] > 0, values
            assert values[22] > 0 and values[26] > 0 and values[21] == 0, values
        elif mode == 1:
            assert values[1:3] == (0, 1024) and values[5:8] == (0, 0, 0), values
        elif mode == 2:
            assert values[1:3] == (18, 34) and values[22] > 0 and values[33] > 0, values
            assert values[21] == values[32] == 1 and values[36] == 0, values
        elif mode <= 6:
            assert values[5] == (2 if mode == 6 else 1), values
            assert values[6] == {3: 1, 4: 2, 5: 3, 6: 1}[mode], values
            assert values[21] == (0 if mode == 6 else 1), values
            if mode != 6:
                assert values[7] != 0, values
        else:
            assert values[4] > 0 and values[18] >= 2, values
            assert values[21] == (0 if mode == 9 else 1), values
        CASES += 1
        return values
    finally:
        for item in transports:
            item.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=1)
        process.stdout.close()
        process.stderr.close()


def backpressure():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        invoke(0, version)


def buffered():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        invoke(1, version)


def owners():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        invoke(2, version)


def failures():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for mode in (3, 4, 5, 6):
            invoke(mode, version)


def shutdown():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for mode in (7, 8, 9):
            invoke(mode, version)


if __name__ == "__main__":
    group, EXE, directory = sys.argv[1:]
    EXE, CERTS = Path(EXE), Path(directory)
    {"backpressure": backpressure, "buffered": buffered, "owners": owners,
     "failures": failures, "shutdown": shutdown}[group]()
    print(f"openssl-tls-duplex edges-{group} cases={CASES}")
