"""Raw duplex oracle: Python ssl/MemoryBIO peers, never a TLS implementation."""
import importlib.util
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("duplex_peer", BASE / "openssl_tls" / "peer.py")
PEER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PEER)
EXE = None
CERTS = None
CASES = 0


def payload(count):
    return bytes((index * 73 + 11) & 255 for index in range(count))


def invoke(mode, version=ssl.TLSVersion.TLSv1_3, fragment=0):
    global CASES
    parent, inherited = socket.socketpair()
    inherited.setblocking(False)
    command = [str(EXE), str(inherited.fileno()), str(inherited.fileno()),
               str(CERTS / "root.pem"), str(mode), "0"]
    process = subprocess.Popen(command, pass_fds=(inherited.fileno(),),
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    inherited.close()
    try:
        peer = PEER.Connection(parent, PEER.context(CERTS, version=version), fragment)
        peer.handshake()
        assert peer.tls.version() == ("TLSv1.3" if version == ssl.TLSVersion.TLSv1_3 else "TLSv1.2")
        events = []
        if mode == 2:
            peer.write(payload(257)); events.append("response-before-request")
            assert peer.read_exact(7) == b"request"
        else:
            # Withholding the response until the complete request proves that
            # the product cannot wait for read readiness before making writes.
            assert peer.read_exact(7) == b"request"; events.append("request")
            if mode == 1:
                assert peer.read() == b""; events.append("authenticated-client-close")
            peer.write(payload(257)); events.append("response")
        peer.shutdown()
        out, err = process.communicate(timeout=6)
        assert process.returncode == 0 and len(out) == 320 and err == b"", (command, process.returncode, out, err)
        values = struct.unpack("<40Q", out)
        assert values[0] == mode and values[1] == (772 if version == ssl.TLSVersion.TLSv1_3 else 771), values
        assert values[2] >= 3 and values[3:5] == (7, 257) and values[7] == 1, values
        assert values[8:11] == (0, 0, 0) and values[12:14] == (3, 1), values
        assert values[24] == 0 and values[37] == 0 and values[39] == 1, values
        if mode == 0:
            assert values[5:7] == (0, 0) and values[22] > 0 and values[23] > 0, values
        elif mode == 1:
            assert values[5:7] == (2, 1) and events == ["request", "authenticated-client-close", "response"], (values, events)
        else:
            assert values[20] == 1, values  # exactly one explicitly forced rare WANT
        CASES += 1
        return values
    finally:
        parent.close()
        if process.poll() is None:
            process.kill(); process.wait(timeout=1)
        process.stdout.close(); process.stderr.close()


def causal():
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for fragment in (0, 7):
            invoke(0, version, fragment)


def notification():
    for fragment in (0, 7):
        invoke(1, fragment=fragment)


def rare_wants():
    for mode in (2, 3):
        for fragment in (0, 7):
            invoke(mode, fragment=fragment)


if __name__ == "__main__":
    group, EXE, directory = sys.argv[1:]
    EXE, CERTS = Path(EXE), Path(directory)
    {"causal": causal, "notification": notification, "rare-wants": rare_wants}[group]()
    print(f"openssl-tls-duplex {group} cases={CASES}")
