"""Test-only authenticated-record corruption against a real OpenSSL server.

The independent peer writes its test traffic secrets to a key log. We change
exactly one CertificateVerify signature or Finished MAC byte, preserving TLS
framing and recomputing record AEAD. Production never imports this module.
"""
import ctypes
import ctypes.util
import hashlib
import hmac
import pathlib
import socket
import threading
import time

crypto = ctypes.CDLL(ctypes.util.find_library('crypto'))
P, I = ctypes.c_void_p, ctypes.c_int
crypto.EVP_CIPHER_CTX_new.restype = P
crypto.EVP_CIPHER_CTX_free.argtypes = [P]
crypto.EVP_CIPHER_CTX_ctrl.argtypes = [P, I, I, P]
crypto.EVP_CIPHER_CTX_ctrl.restype = I
for direction in ['Encrypt', 'Decrypt']:
    getattr(crypto, 'EVP_' + direction + 'Init_ex').argtypes = [P, P, P, P, P]
    getattr(crypto, 'EVP_' + direction + 'Update').argtypes = [P, P, ctypes.POINTER(I), P, I]
    getattr(crypto, 'EVP_' + direction + 'Final_ex').argtypes = [P, P, ctypes.POINTER(I)]
for name in ['aes_128_gcm', 'aes_256_gcm', 'chacha20_poly1305']:
    getattr(crypto, 'EVP_' + name).restype = P


def expand(secret, label, length, algorithm):
    info = length.to_bytes(2, 'big') + bytes([6 + len(label)]) + b'tls13 ' + label + b'\0'
    return hmac.new(secret, info + b'\1', algorithm).digest()[:length]


def crypt(encrypt, suite, key, nonce, header, body, tag=b''):
    direction = 'Encrypt' if encrypt else 'Decrypt'
    init, update, final = [getattr(crypto, 'EVP_' + direction + suffix)
                           for suffix in ['Init_ex', 'Update', 'Final_ex']]
    cipher = getattr(crypto, 'EVP_' + ['chacha20_poly1305', 'aes_128_gcm', 'aes_256_gcm'][suite])()
    ctx = crypto.EVP_CIPHER_CTX_new()
    assert ctx
    try:
        assert init(ctx, cipher, None, None, None) == 1
        assert crypto.EVP_CIPHER_CTX_ctrl(ctx, 9, 12, None) == 1
        assert init(ctx, None, None, key, nonce) == 1
        n, output = I(), ctypes.create_string_buffer(len(body) + 32)
        assert update(ctx, None, ctypes.byref(n), header, len(header)) == 1
        assert update(ctx, output, ctypes.byref(n), body, len(body)) == 1
        count = n.value
        if not encrypt:
            supplied = ctypes.create_string_buffer(tag, 16)
            assert crypto.EVP_CIPHER_CTX_ctrl(ctx, 17, 16, supplied) == 1
        assert final(ctx, ctypes.byref(output, count), ctypes.byref(n)) == 1, 'independent record authentication'
        count += n.value
        assert count == len(body)
        if encrypt:
            supplied = ctypes.create_string_buffer(16)
            assert crypto.EVP_CIPHER_CTX_ctrl(ctx, 16, 16, supplied) == 1
            return output.raw[:count] + supplied.raw
        return output.raw[:count]
    finally:
        crypto.EVP_CIPHER_CTX_free(ctx)


class Mutation:
    def __init__(self, keylog, suite, target):
        assert suite in range(3) and target in [15, 20]
        self.keylog, self.suite, self.target = pathlib.Path(keylog), suite, target
        self.sequence, self.mutations, self.done = 0, 0, False
        self.header, self.remaining, self.kind = bytearray(), 0, None
        self.proof_prefix, self.proof_scheme = bytearray(), None
        self.errors = []
        self.secret = None

    def traffic_secret(self):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if self.keylog.exists():
                for line in self.keylog.read_text().splitlines():
                    fields = line.split()
                    if len(fields) == 3 and fields[0] == 'SERVER_HANDSHAKE_TRAFFIC_SECRET':
                        return bytes.fromhex(fields[2])
            time.sleep(0.001)
        raise AssertionError('real OpenSSL handshake secret not recorded')

    def packet(self, packet):
        if packet[0] != 23 or self.done:
            return packet
        if self.secret is None:
            self.secret = self.traffic_secret()
        algorithm = hashlib.sha384 if self.suite == 2 else hashlib.sha256
        assert len(self.secret) == algorithm().digest_size
        key = expand(self.secret, b'key', 16 if self.suite == 1 else 32, algorithm)
        iv = expand(self.secret, b'iv', 12, algorithm)
        nonce = bytes(a ^ b for a, b in zip(iv, bytes(4) + self.sequence.to_bytes(8, 'big')))
        self.sequence += 1
        plain = bytearray(crypt(False, self.suite, key, nonce, packet[:5], packet[5:-16], packet[-16:]))
        end = len(plain) - 1
        while end >= 0 and plain[end] == 0:
            end -= 1
        assert end >= 0 and plain[end] == 22, 'expected real server handshake content'
        for at in range(end):
            if self.remaining == 0:
                self.header.append(plain[at])
                if len(self.header) == 4:
                    self.kind = self.header[0]
                    self.remaining = int.from_bytes(self.header[1:], 'big')
                    assert self.remaining > 0
                    self.header.clear()
                    if self.kind == 15:
                        self.proof_prefix.clear()
                continue
            if self.kind == 15 and len(self.proof_prefix) < 2:
                self.proof_prefix.append(plain[at])
                if len(self.proof_prefix) == 2:
                    self.proof_scheme = int.from_bytes(self.proof_prefix, 'big')
                    assert self.proof_scheme in [1027, 2052]
            if self.remaining == 1 and self.kind == self.target:
                assert self.mutations == 0
                plain[at] ^= 1
                self.mutations += 1
            self.remaining -= 1
            if self.remaining == 0 and self.kind == 20:
                self.done = True
        return packet[:5] + crypt(True, self.suite, key, nonce, packet[:5], bytes(plain))


def start(client, server, keylog, suite, target, threads):
    mutation = Mutation(keylog, suite, target)
    def receive(source, count):
        parts = bytearray()
        while len(parts) < count:
            piece = source.recv(count - len(parts))
            if not piece:
                assert not parts, 'partial TLS record in mutation proxy'
                return None
            parts.extend(piece)
        return bytes(parts)
    def forward(source, destination, transform):
        source.settimeout(12)
        destination.settimeout(12)
        try:
            while True:
                if transform:
                    header = receive(source, 5)
                    if header is None:
                        break
                    size = int.from_bytes(header[3:], 'big')
                    assert 0 < size <= 16640
                    body = receive(source, size)
                    assert body is not None
                    data = mutation.packet(header + body)
                else:
                    data = source.recv(65536)
                    if not data:
                        break
                destination.sendall(data)
        except OSError:
            pass  # A failed native handshake deliberately closes its transport.
        except Exception as error:
            mutation.errors.append(repr(error))
        finally:
            try:
                destination.shutdown(socket.SHUT_WR)
            except OSError:
                pass
    for source, destination, transform in [(client, server, False), (server, client, True)]:
        thread = threading.Thread(target=forward, args=(source, destination, transform), daemon=True)
        thread.start()
        threads.append(thread)
    return mutation
