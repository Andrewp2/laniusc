"""Test-only wire peer: real OpenSSL certificates, libsodium DHE/signatures,
and OpenSSL AEAD plus hashlib/hmac check every emitted handshake/record byte.
It observes two Lanius engines; independent TCP/OpenSSL interoperability is a
separate gate. This diagnostic protocol deliberately exposes test secrets.
"""
import ctypes
import ctypes.util
import hashlib
import hmac
import importlib.util
import pathlib
import re
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
# Reuse the admitted real-chain generator, not its authentication state oracle.
spec = importlib.util.spec_from_file_location('certificate_material', HERE.parent/'tls_authentication'/'peer.py')
material = importlib.util.module_from_spec(spec)
spec.loader.exec_module(material)
Q = material.Q
H = lambda b: hashlib.sha256(b).digest()
MAC = lambda k, b: hmac.new(k, b, hashlib.sha256).digest()
U16 = lambda n: n.to_bytes(2, 'big')
U24 = lambda n: n.to_bytes(3, 'big')
EMPTY = H(b'')
ZERO = bytes(32)
HRR = bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
CLIENT_ENTROPY = bytes(range(1, 65))
SERVER_ENTROPY = bytes(range(101, 165))
P_SPEC = importlib.util.spec_from_file_location("p256_affine", HERE.parent/"p256"/"model.py")
P256 = importlib.util.module_from_spec(P_SPEC)
P_SPEC.loader.exec_module(P256)
PAYLOAD = bytes((i*71+9) % 256 for i in range(113))


def expand(secret, label, context=b'', length=32):
    return material.expand(secret, label, context, length)


crypto = ctypes.CDLL(ctypes.util.find_library('crypto'))
P, I = ctypes.c_void_p, ctypes.c_int
crypto.EVP_CIPHER_CTX_new.restype = P
crypto.EVP_CIPHER_CTX_free.argtypes = [P]
crypto.EVP_CIPHER_CTX_ctrl.argtypes = [P, I, I, P]
crypto.EVP_CIPHER_CTX_ctrl.restype = I
for direction in ('Encrypt', 'Decrypt'):
    init = getattr(crypto, 'EVP_'+direction+'Init_ex')
    init.argtypes = [P, P, P, P, P]
    init.restype = I
    update = getattr(crypto, 'EVP_'+direction+'Update')
    update.argtypes = [P, P, ctypes.POINTER(I), P, I]
    update.restype = I
    final = getattr(crypto, 'EVP_'+direction+'Final_ex')
    final.argtypes = [P, P, ctypes.POINTER(I)]
    final.restype = I
crypto.EVP_aes_128_gcm.restype = P
crypto.EVP_chacha20_poly1305.restype = P


def aead(key, nonce, aad, message, tag, chacha):
    ctx = crypto.EVP_CIPHER_CTX_new()
    assert ctx
    try:
        cipher = crypto.EVP_chacha20_poly1305() if chacha else crypto.EVP_aes_128_gcm()
        assert crypto.EVP_DecryptInit_ex(ctx, cipher, None, None, None) == 1
        assert crypto.EVP_CIPHER_CTX_ctrl(ctx, 9, len(nonce), None) == 1
        assert crypto.EVP_DecryptInit_ex(ctx, None, None, key, nonce) == 1
        n, total = I(), 0
        out = ctypes.create_string_buffer(len(message)+16)
        assert crypto.EVP_DecryptUpdate(ctx, None, ctypes.byref(n), aad, len(aad)) == 1
        if message:
            assert crypto.EVP_DecryptUpdate(ctx, out, ctypes.byref(n), message, len(message)) == 1
            total = n.value
        supplied = ctypes.create_string_buffer(tag, 16)
        assert crypto.EVP_CIPHER_CTX_ctrl(ctx, 17, 16, supplied) == 1
        assert crypto.EVP_DecryptFinal_ex(ctx, ctypes.byref(out, total), ctypes.byref(n)) == 1, 'record authentication failed independently'
        total += n.value
        assert total == len(message)
        return out.raw[:total]
    finally:
        crypto.EVP_CIPHER_CTX_free(ctx)


class Reader:
    def __init__(self, data):
        self.data, self.at = data, 0

    def take(self, n):
        assert 0 <= n <= len(self.data)-self.at, ('truncated', self.at, n, len(self.data))
        value = self.data[self.at:self.at+n]
        self.at += n
        return value

    def word(self):
        return int.from_bytes(self.take(8), 'little')

    def block(self):
        return self.take(self.word())


def extensions(data):
    result, at = {}, 0
    while at < len(data):
        assert len(data)-at >= 4
        kind, n = struct.unpack('>HH', data[at:at+4])
        at += 4
        assert n <= len(data)-at and kind not in result
        result[kind] = data[at:at+n]
        at += n
    return result


def hello(frame, server=False):
    body = frame[4:]
    assert body[:2] == b'\x03\x03'
    random, n = body[2:34], body[34]
    assert n <= 32
    session, at = body[35:35+n], 35+n
    if server:
        suite = int.from_bytes(body[at:at+2], 'big')
        assert body[at+2] == 0
        at += 3
    else:
        size = int.from_bytes(body[at:at+2], 'big')
        at += 2
        suite, at = body[at:at+size], at+size
        assert body[at:at+2] == b'\x01\0'
        at += 2
    n = int.from_bytes(body[at:at+2], 'big')
    at += 2
    assert at+n == len(body)
    return dict(random=random, session=session, suite=suite, extensions=extensions(body[at:]))


def entropy(policy, server=False):
    length = 96 if len(policy) == 2 else 64
    return bytes(range(101, 101+length)) if server else bytes(range(1, length+1))


def scalar(policy, group, server=False):
    data = entropy(policy, server)
    at = 64 if group == 23 and 29 in policy else 32
    return data[at:at+32]


def shared_key(group, client_policy, server_policy):
    a, b = scalar(client_policy, group), scalar(server_policy, group, True)
    if group == 29:
        client_public, server_public, shared = [ctypes.create_string_buffer(32) for _ in range(3)]
        sodium = material.SODIUM
        assert sodium.crypto_scalarmult_curve25519_base(client_public, a) == 0
        assert sodium.crypto_scalarmult_curve25519_base(server_public, b) == 0
        assert sodium.crypto_scalarmult_curve25519(shared, a, server_public) == 0
        reverse = ctypes.create_string_buffer(32)
        assert sodium.crypto_scalarmult_curve25519(reverse, b, client_public) == 0
        assert reverse.raw == shared.raw
        return client_public.raw, server_public.raw, shared.raw
    # Independent affine bigint peer, with every selected pair cross-checked
    # against OpenSSL public-key derivation and bidirectional raw ECDH.
    da, db = P256.private(a), P256.private(b)
    qa, qb = P256.encode(P256.mul(da)), P256.encode(P256.mul(db))
    shared = P256.be(P256.mul(da, P256.decode(qb))[0])
    assert shared == P256.be(P256.mul(db, P256.decode(qa))[0])
    prefix = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200')
    with tempfile.TemporaryDirectory(prefix='tls_p256_peer_') as directory:
        base = pathlib.Path(directory)
        for private, public, peer in [(a, qa, qb), (b, qb, qa)]:
            key = b'\x30\x31\x02\x01\x01\x04\x20'+private+bytes.fromhex('a00a06082a8648ce3d030107')
            (base/'key.der').write_bytes(key)
            (base/'peer.der').write_bytes(prefix+peer)
            def call(args):
                return subprocess.run(['openssl', *args], check=True, capture_output=True, timeout=8).stdout
            assert call(['pkey','-inform','DER','-in',str(base/'key.der'),'-pubout','-outform','DER']) == prefix+public
            assert call(['pkeyutl','-derive','-inkey',str(base/'key.der'),'-keyform','DER','-peerkey',str(base/'peer.der'),'-peerform','DER']) == shared
    return qa, qb, shared


def public_key(policy, group):
    key = scalar(policy, group)
    if group == 23:
        return P256.encode(P256.mul(P256.private(key)))
    public = ctypes.create_string_buffer(32)
    assert material.SODIUM.crypto_scalarmult_curve25519_base(public, key) == 0
    return public.raw


class Peer:
    def __init__(self, chain, suite, retry, client_policy, server_policy, initial):
        self.chain, self.suite, self.retry = chain, suite, retry
        self.client_policy, self.server_policy, self.initial = client_policy, server_policy, initial
        self.group = next(g for g in server_policy if g in client_policy)
        self.transcript, self.frames = b'', []
        self.partial = [b'', b'']
        self.secrets, self.sequences = [None, None], [0, 0]
        self.generations = [0, 0]
        self.records, self.messages = [0, 0], [[], []]
        self.closed, self.data = [False, False], [b'', b'']
        self.client_public, self.server_public, self.shared = shared_key(self.group, client_policy, server_policy)
        self.ch1, self.ch2, self.hrr = None, None, None
        self.finished = [False, False]

    def handshake(self, side, frame, at_record_end):
        kind, n = frame[0], int.from_bytes(frame[1:4], 'big')
        assert n == len(frame)-4
        if kind in (1, 2, 20, 24):
            assert at_record_end, 'epoch boundary message has a record tail'
        body = frame[4:]
        if kind == 1:
            assert side == 0
            ch = hello(frame)
            assert ch['random'] == CLIENT_ENTROPY[:32] and ch['session'] == b''
            expected = b'\x13\x03\x13\x01' if self.suite == 0 else b'\x13\x01\x13\x03'
            assert ch['suite'] == expected
            ext = ch['extensions']
            assert ext[43] == b'\x02\x03\x04' and ext[10] == U16(2*len(self.client_policy))+b''.join(U16(g) for g in self.client_policy)
            assert ext[13] == ext[50] == b'\0\x02\x08\x07'
            assert ext[16] == b'\0\x03\x02h2' and ext[0].endswith(b'server.example')
            if self.ch1 is None:
                assert 44 not in ext
                self.ch1 = ch
                if self.initial == 0:
                    assert ext[51] == b'\0\0'
                else:
                    first_public = self.client_public if self.initial == self.group else public_key(self.client_policy, self.initial)
                    entry = U16(self.initial)+U16(len(first_public))+first_public
                    assert ext[51] == U16(len(entry))+entry
            else:
                assert self.ch2 is None and self.hrr is not None
                self.ch2 = ch
                for key, value in self.ch1['extensions'].items():
                    if key != 51:
                        assert ext[key] == value
                entry = U16(self.group)+U16(len(self.client_public))+self.client_public
                assert ext[51] == U16(len(entry))+entry
                assert ext.get(44, b'') == self.hrr['extensions'].get(44, b'')
            self.transcript += frame
        elif kind == 2:
            assert side == 1
            sh = hello(frame, True)
            assert sh['session'] == b'' and sh['suite'] == (4867 if self.suite == 0 else 4865)
            assert sh['extensions'][43] == b'\x03\x04'
            if sh['random'] == HRR:
                assert self.retry in (1, 2) and self.hrr is None and self.ch2 is None
                self.hrr = sh
                if self.retry == 1:
                    assert sh['extensions'][51] == U16(self.group)
                else:
                    assert 51 not in sh['extensions'] and sh['extensions'][44] == b'\0\x20'+SERVER_ENTROPY[:32]
                self.transcript = bytes([254])+U24(32)+H(self.transcript)+frame
            else:
                assert sh['random'] == SERVER_ENTROPY[:32]
                assert sh['extensions'][51] == U16(self.group)+U16(len(self.server_public))+self.server_public
                assert (self.retry == 0) == (self.hrr is None)
                self.transcript += frame
                early = MAC(ZERO, ZERO)
                hs = MAC(expand(early, b'derived', EMPTY), self.shared)
                self.hs = [expand(hs, b'c hs traffic', H(self.transcript)), expand(hs, b's hs traffic', H(self.transcript))]
                self.master = MAC(expand(hs, b'derived', EMPTY), ZERO)
                self.secrets = list(self.hs)
                self.sequences = [0, 0]
        elif kind == 8:
            assert side == 1 and [f[0] for f in self.frames if f[0] in (8, 11, 15, 20)] == []
            assert int.from_bytes(body[:2], 'big') == len(body)-2
            assert extensions(body[2:]) == {0: b'', 16: b'\0\x03\x02h2'}
            self.transcript += frame
        elif kind == 11:
            assert side == 1 and body[0] == 0
            assert int.from_bytes(body[1:4], 'big') == len(body)-4
            at, certs = 4, []
            while at < len(body):
                n = int.from_bytes(body[at:at+3], 'big')
                at += 3
                certs.append(body[at:at+n])
                at += n
                assert body[at:at+2] == b'\0\0'
                at += 2
            assert certs == self.chain.chain
            assert self.chain.openssl(certs, self.chain.root, b'server.example', self.chain.now)
            self.transcript += frame
        elif kind == 15:
            assert side == 1 and body[:4] == b'\x08\x07\0\x40' and len(body) == 68
            signed = b' '*64+b'TLS 1.3, server CertificateVerify\0'+H(self.transcript)
            assert len(signed) == 130 and material.verify(material.PUBLIC, signed, body[4:])
            self.transcript += frame
        elif kind == 20:
            assert not self.finished[side] and (side == 1 or self.finished[1])
            assert body == MAC(expand(self.hs[side], b'finished'), H(self.transcript))
            self.transcript += frame
            self.finished[side] = True
            if side == 1:
                self.app = [expand(self.master, b'c ap traffic', H(self.transcript)), expand(self.master, b's ap traffic', H(self.transcript))]
                self.exporter = expand(self.master, b'exp master', H(self.transcript))
            self.secrets[side] = self.app[side]
            self.sequences[side] = 0
            self.generations[side] = 1
        elif kind == 24:
            assert self.finished[side] and len(body) == 1 and body[0] in (0, 1)
            expected = 1 if side == 0 else 0
            assert body[0] == expected
            self.secrets[side] = expand(self.secrets[side], b'traffic upd')
            self.sequences[side] = 0
            self.generations[side] += 1
        else:
            raise AssertionError(('unexpected handshake', side, kind))
        self.frames.append(frame)
        self.messages[side].append(kind)

    def record(self, side, packet):
        assert not self.closed[side]
        assert len(packet) >= 5 and int.from_bytes(packet[3:5], 'big') == len(packet)-5
        self.records[side] += 1
        kind, content = packet[0], packet[5:]
        if self.secrets[side] is not None:
            assert kind == 23 and packet[1:3] == b'\x03\x03'
            key = expand(self.secrets[side], b'key', length=32 if self.suite == 0 else 16)
            iv = expand(self.secrets[side], b'iv', length=12)
            nonce = bytes(a ^ b for a, b in zip(iv, bytes(4)+self.sequences[side].to_bytes(8, 'big')))
            content = aead(key, nonce, packet[:5], packet[5:-16], packet[-16:], self.suite == 0)
            self.sequences[side] += 1
            at = len(content)-1
            while at >= 0 and content[at] == 0:
                at -= 1
            assert at >= 0
            kind, content = content[at], content[:at]
        else:
            assert kind == 22 and len(content) <= 16384
        if kind == 22:
            self.partial[side] += content
            while len(self.partial[side]) >= 4:
                n = 4+int.from_bytes(self.partial[side][1:4], 'big')
                if n > len(self.partial[side]):
                    break
                frame, self.partial[side] = self.partial[side][:n], self.partial[side][n:]
                self.handshake(side, frame, not self.partial[side])
        elif kind == 23:
            assert self.finished == [True, True] and not self.partial[side]
            self.data[side] += content
        elif kind == 21:
            assert content == b'\x01\0' and self.finished == [True, True]
            self.closed[side] = True
        else:
            raise AssertionError(('unexpected inner type', kind))

    def finish(self, key, exporter, published_groups, stats, witness):
        assert self.finished == self.closed == [True, True]
        assert self.partial == [b'', b''] and self.generations == [2, 2]
        assert self.data == [PAYLOAD+PAYLOAD[:31], PAYLOAD+PAYLOAD[:17]]
        assert published_groups == [self.group, self.group], (published_groups, self.group)
        assert key == material.PUBLIC
        derived = expand(self.exporter, b'exchange', EMPTY)
        assert exporter == expand(derived, b'exporter', H(b'\0\xff\x01'))
        assert stats == self.records+[2, 2, 2, 2] and witness == 1
        assert self.messages[0] == ([1, 20, 24] if self.retry == 0 else [1, 1, 20, 24])
        assert self.messages[1] == ([2, 8, 11, 15, 20, 24] if self.retry == 0 else [2, 2, 8, 11, 15, 20, 24])


def run(mode, executable):
    with tempfile.TemporaryDirectory(prefix='laniusc_tls_connection_') as temp:
        base = pathlib.Path(temp)
        short = material.Chain(base/'short', 2)
        if mode == 'pairs':
            cases = [(short, suite, 0, layout, 0, (29,), (29,), 29) for suite in (0, 1) for layout in (0, 1)]
        elif mode == 'fragments':
            long = material.Chain(base/'long', 8, True)
            cases = [(short, 0, 1, 0, 1, (29,), (29,), 0), (short, 1, 2, 1, 1, (29,), (29,), 29), (long, 0, 0, 0, 1, (29,), (29,), 29), (long, 1, 0, 1, 1, (29,), (29,), 29)]
        elif mode == 'groups':
            cases = [(short, suite, 0, layout, 1, (23,), (23,), 23) for suite in (0, 1) for layout in (0, 1)]
            cases += [(short, 0, 1, 0, 1, (29, 23), (23, 29), 29), (short, 1, 1, 1, 1, (23, 29), (29, 23), 23)]
            cases += [(short, 0, 2, 1, 1, (23,), (23,), 23), (short, 1, 2, 0, 1, (23, 29), (23, 29), 23)]
        else:
            raise AssertionError(mode)
        source = Q(len(cases))
        for chain, suite, retry, layout, split, cp, sp, initial in cases:
            source += Q(layout, suite, retry, split, chain.now, len(chain.root), len(chain.chain), int(chain is not short), cp[0], cp[1] if len(cp)>1 else 0, sp[0], sp[1] if len(sp)>1 else 0, initial)
            source += chain.root+b''.join(Q(len(cert))+cert for cert in chain.chain)
        trace = base/'memory.trace'
        result = subprocess.run(['strace', '-qq', '-o', str(trace), '-e', 'trace=mmap,munmap,mremap,brk', '-e', 'signal=none', executable], input=source, capture_output=True, timeout=45)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, len(result.stdout), result.stdout[-64:].hex(), result.stderr)
        # Exactly one explicit caller arena owner. Engine lifecycle may not
        # add allocations or release/resize that owner. Match address AND size.
        lines = trace.read_text().splitlines()
        assert len(lines) == 2, lines
        allocated = re.fullmatch(r'mmap\(NULL, (\d+), PROT_READ\|PROT_WRITE, ([A-Z_0-9|]+), -1, 0\)\s+= (0x[0-9a-f]+)', lines[0])
        assert allocated and int(allocated[1]) == 3520000, lines
        flags = allocated[2].split('|')
        assert len(flags) == 3 and set(flags) == {'MAP_PRIVATE', 'MAP_ANONYMOUS', 'MAP_32BIT'}, lines
        released = re.fullmatch(r'munmap\((0x[0-9a-f]+), (\d+)\)\s+= 0', lines[1])
        assert released and released[1] == allocated[3] and released[2] == allocated[1], lines
        reader = Reader(result.stdout)
        for number, (chain, suite, retry, layout, split, cp, sp, initial) in enumerate(cases):
            assert reader.word() == 10 and reader.word() == number
            peer, witness = Peer(chain, suite, retry, cp, sp, initial), 0
            while True:
                tag = reader.word()
                if tag == 1:
                    side, packet = reader.word(), reader.block()
                    assert side in (0, 1)
                    peer.record(side, packet)
                elif tag == 3:
                    assert reader.word() > 0
                    witness += 1
                else:
                    assert tag == 0
                    key, exporter = reader.block(), reader.block()
                    published_groups = [reader.word(), reader.word()]
                    stats = [reader.word() for _ in range(6)]
                    assert reader.word() == witness
                    peer.finish(key, exporter, published_groups, stats, witness)
                    break
        assert reader.at == len(reader.data)
    print(f'tls connection {mode}: accepted')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
