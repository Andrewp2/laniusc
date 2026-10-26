"""Additional fault-only behavior around the unchanged positive peer oracle."""
import ssl
import socket
from peers import Pool


class ControlledPool(Pool):
    def request(self, connection, index, early=False):
        value = super().request(connection, index, early)
        if early:
            self.request_bodies[index] = value[1]
        return value

    def handle(self, connection, server, index):
        if self.peers[index].early:
            # Keep a large upload from fitting entirely in the receiver's
            # kernel queue before the final response can be observed.
            connection.transport.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        original = connection.read
        original_shutdown = connection.shutdown
        preludes = list(getattr(self.peers[index], "preludes", ()))
        def read(count=16384):
            # First application read occurs after native handshake, never in
            # SSL_do_handshake. Separate native writes create separate records.
            while preludes:
                connection.write(preludes.pop(0))
            return original(count)
        connection.read = read
        def shutdown():
            if self.peers[index].early and server.version == "TLSv1.2":
                # The final body has ALREADY been written. Drain the bounded
                # in-flight upload before asking native unwrap for its alert;
                # TLS1.2 must not require a pre-body half-close.
                uploaded = bytearray(self.request_bodies[index])
                while True:
                    part = original(16384)
                    if not part:
                        break
                    uploaded.extend(part)
                    assert len(uploaded) < len(self.peers[index].body)
                    assert self.peers[index].body[:len(uploaded)] == uploaded
                self.request_bodies[index] = bytes(uploaded)
                self.record("client-notify-after-body", index)
            return original_shutdown()
        connection.shutdown = shutdown
        try:
            super().handle(connection, server, index)
        except (ConnectionError, ssl.SSLError, EOFError):
            # A real reset/alert/EOF after the full request releases a fault
            # wave. A timeout is not evidence of termination and never releases.
            if index in self.requests:
                self.record("ended", index)
            raise
