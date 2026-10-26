"""Verified native TLS client with bounded transport control, for tests only.

OpenSSL creates every TLS record. The inherited transport helper may fragment
or cut a native-produced record, without implementing TLS or cryptography.
"""

from pathlib import Path
import importlib.util
import ssl
import sys
import time
import warnings


sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1] / "openssl_tls" / "peer.py"
SPEC = importlib.util.spec_from_file_location("tls_server_base_peer", BASE)
PEER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PEER)
Connection = PEER.Connection
binary = PEER.binary


def context(directory, identity="localhost", trust="root", version=None):
    result = ssl.create_default_context(cafile=Path(directory) / f"{trust}.pem")
    result.minimum_version = ssl.TLSVersion.TLSv1_2
    assert result.check_hostname and result.verify_mode == ssl.CERT_REQUIRED
    if version is not None:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", DeprecationWarning)
            result.minimum_version = version
            result.maximum_version = version
        if version < ssl.TLSVersion.TLSv1_2:
            result.set_ciphers("ALL:@SECLEVEL=0")
    # No client certificate is installed. Server authentication and client
    # authentication are separate policies.
    return result


class Client(Connection):
    def __init__(self, transport, configuration, identity="localhost", fragment=0):
        self.transport = transport
        self.incoming = ssl.MemoryBIO()
        self.outgoing = ssl.MemoryBIO()
        self.tls = configuration.wrap_bio(
            self.incoming, self.outgoing, server_side=False, server_hostname=identity,
        )
        self.fragment = fragment
        self.deadline = time.monotonic() + 5
        self.steps = 0


def self_check(directory):
    Server, server_context, handshake = PEER.Server, PEER.context, PEER.handshake

    def handler(connection, server):
        handshake(connection, server)
        assert connection.read_exact(1025) == binary(1025)
        connection.write(bytes(byte ^ 90 for byte in binary(1025)), chunk=251)
        connection.shutdown()

    import socket
    for identity in ("localhost", "127.0.0.1"):
        with Server(server_context(directory), handler) as server:
            raw = socket.create_connection(server.listener.getsockname()[:2], timeout=3)
            try:
                client = Client(raw, context(directory), identity, fragment=7)
                client.handshake()
                assert client.tls.getpeercert() and client.tls.version() in ("TLSv1.2", "TLSv1.3")
                client.write(binary(1025), chunk=293)
                assert client.read_exact(1025) == bytes(byte ^ 90 for byte in binary(1025))
                assert client.read() == b""
                client.shutdown()
            finally:
                raw.close()
    print("openssl-tls-server native client: DNS/IP verification and binary transfer passed")


if __name__ == "__main__":
    self_check(sys.argv[1])
