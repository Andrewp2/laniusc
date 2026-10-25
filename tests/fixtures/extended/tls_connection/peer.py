"""Test-only wire peer: real OpenSSL certificates, libsodium DHE/signatures,
and OpenSSL AEAD plus hashlib/hmac check every emitted handshake/record byte.
It observes two Lanius engines; independent TCP/OpenSSL interoperability is a
separate gate. This diagnostic protocol deliberately exposes test secrets.
"""
import calendar
import datetime
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


def expand(secret, label, context=b'', length=None, *, algorithm):
    digest = getattr(hashlib, algorithm)
    if length is None:
        length = digest().digest_size
    info = U16(length)+bytes([len(label)+6])+b'tls13 '+label+bytes([len(context)])+context
    result, previous, counter = b'', b'', 1
    while len(result) < length:
        previous = hmac.new(secret, previous+info+bytes([counter]), digest).digest()
        result += previous
        counter += 1
    return result[:length]


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
crypto.EVP_aes_256_gcm.restype = P
crypto.EVP_chacha20_poly1305.restype = P


def aead(key, nonce, aad, message, tag, suite):
    ctx = crypto.EVP_CIPHER_CTX_new()
    assert ctx
    try:
        assert suite in (4865, 4866, 4867)
        cipher = {4865: crypto.EVP_aes_128_gcm, 4866: crypto.EVP_aes_256_gcm, 4867: crypto.EVP_chacha20_poly1305}[suite]()
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


# Independent resource-policy arithmetic; these are finite credit formulas,
# separate from the byte-level hashlib/OpenSSL cryptographic oracle.
def sha384_hash_cost(n): return 16384*((n+144)//128)+8192+32*(n+48)
def sha384_hmac_cost(n): return 16384*(3+(n+144)//128)+12288+32*(1024+n)
def sha384_expansion_cost(label, context, output):
    count = (output+47)//48
    compressions = 0 if count == 0 else 2+(11+label+context+144)//128+1+(count-1)*((59+label+context+144)//128+1)
    return 16384*compressions+4096*(count+2)+32*(1024+label+context+count*(10+label+context+97)+output)


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


def offered_policies(profile):
    proofs = (2055,1027,2052) if profile in (1,3,8) else (1027,) if profile==4 else (2055,)
    certificates = None if profile in (2,3,10) else (2055,1027,2052,1025) if profile in (1,4,8) else (1025,) if profile==6 else (1027,) if profile==7 else (2055,)
    return proofs,certificates


def check_offers(ch, profile):
    proofs, certificates = offered_policies(profile)
    encode=lambda ns:U16(2*len(ns))+b''.join(U16(n) for n in ns)
    assert ch['extensions'][13]==encode(proofs)
    if certificates is None:
        assert 50 not in ch['extensions']
    else:
        assert ch['extensions'][50]==encode(certificates)


class MixedChain:
    # OpenSSL is an independent certificate/issuer-signature oracle. The real
    # local leaf remains the RFC8032 Ed25519 seed; issuer family is unrelated.
    openssl=material.Chain.openssl
    def __init__(self,folder,family):
        self.folder=folder; folder.mkdir(); config=folder/'config.ini'
        config.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=TLS mixed issuer\n[root]\nbasicConstraints=critical,CA:TRUE,pathlen:8\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n[leaf]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\nsubjectAltName=DNS:server.example\n')
        key=folder/'issuer.key'; root=folder/'root.pem'; leafkey=folder/'leaf.key'; leaf=folder/'leaf.pem'; csr=folder/'leaf.csr'
        if family=='ecdsa':
            material.command(['genpkey','-algorithm','EC','-pkeyopt','ec_paramgen_curve:prime256v1','-out',key])
        else:
            material.command(['genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',key])
        options=['-sha256']
        if family=='pss':options+=['-sigopt','rsa_padding_mode:pss','-sigopt','rsa_pss_saltlen:32','-sigopt','rsa_mgf1_md:sha256']
        material.command(['req','-new','-x509','-key',key,'-config',config,'-extensions','root','-subj','/CN=Mixed issuer root','-days','2','-set_serial','100','-out',root]+options)
        raw=folder/'leaf.key.der'; raw.write_bytes(bytes.fromhex('302e020100300506032b657004220420')+material.LEAF_SEED)
        material.command(['pkey','-inform','DER','-in',raw,'-out',leafkey])
        material.command(['req','-new','-key',leafkey,'-config',config,'-subj','/CN=server.example','-out',csr])
        material.command(['x509','-req','-in',csr,'-CA',root,'-CAkey',key,'-set_serial','400','-days','2','-extfile',config,'-extensions','leaf','-out',leaf]+options)
        self.root=material.command(['x509','-in',root,'-outform','DER'])
        self.chain=[material.command(['x509','-in',leaf,'-outform','DER'])]
        dates=[]
        for pem in [root,leaf]:
            text=material.command(['x509','-in',pem,'-startdate','-noout']).decode().strip().split('=',1)[1]
            dates.append(calendar.timegm(datetime.datetime.strptime(text,'%b %d %H:%M:%S %Y %Z').timetuple()))
        self.now=max(dates)+1; self.checked_paths={}
        assert self.openssl(self.chain,self.root,b'server.example',self.now)
        # Independent subject key bytes, without assuming the issuer family.
        public=material.command(['pkey','-in',leafkey,'-pubout','-outform','DER'])
        assert public==bytes.fromhex('302a300506032b6570032100')+material.PUBLIC


class Peer:
    def __init__(self, chain, suite, retry, client_policy, server_policy, initial, client_suites, server_suites, profile=0):
        self.chain, self.retry = chain, retry
        self.profile = profile
        self.client_suites, self.server_suites = client_suites, server_suites
        self.suite = next(s for s in server_suites if s in client_suites)
        assert self.suite == (4867, 4865, 4866)[suite]
        self.algorithm = 'sha384' if self.suite == 4866 else 'sha256'
        self.hashlen = 48 if self.suite == 4866 else 32
        self.H = lambda b: getattr(hashlib, self.algorithm)(b).digest()
        self.MAC = lambda k, b: hmac.new(k, b, getattr(hashlib, self.algorithm)).digest()
        self.EMPTY, self.ZERO = self.H(b''), bytes(self.hashlen)
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

    def expand(self, secret, label, context=b'', length=None):
        return expand(secret, label, context, length, algorithm=self.algorithm)

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
            expected = b''.join(U16(s) for s in self.client_suites)
            assert ch['suite'] == expected
            ext = ch['extensions']
            assert ext[43] == b'\x02\x03\x04' and ext[10] == U16(2*len(self.client_policy))+b''.join(U16(g) for g in self.client_policy)
            check_offers(ch,self.profile)
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
            assert sh['session'] == b'' and sh['suite'] == self.suite
            assert sh['extensions'][43] == b'\x03\x04'
            if sh['random'] == HRR:
                assert self.retry in (1, 2) and self.hrr is None and self.ch2 is None
                self.hrr = sh
                if self.retry == 1:
                    assert sh['extensions'][51] == U16(self.group)
                else:
                    assert 51 not in sh['extensions'] and sh['extensions'][44] == b'\0\x20'+SERVER_ENTROPY[:32]
                self.transcript = bytes([254])+U24(self.hashlen)+self.H(self.transcript)+frame
            else:
                assert sh['random'] == SERVER_ENTROPY[:32]
                assert sh['extensions'][51] == U16(self.group)+U16(len(self.server_public))+self.server_public
                assert (self.retry == 0) == (self.hrr is None)
                self.transcript += frame
                early = self.MAC(self.ZERO, self.ZERO)
                hs = self.MAC(self.expand(early, b'derived', self.EMPTY), self.shared)
                self.hs = [self.expand(hs, b'c hs traffic', self.H(self.transcript)), self.expand(hs, b's hs traffic', self.H(self.transcript))]
                self.master = self.MAC(self.expand(hs, b'derived', self.EMPTY), self.ZERO)
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
            signed = b' '*64+b'TLS 1.3, server CertificateVerify\0'+self.H(self.transcript)
            assert len(signed) == 98+self.hashlen and material.verify(material.PUBLIC, signed, body[4:])
            self.transcript += frame
        elif kind == 20:
            assert not self.finished[side] and (side == 1 or self.finished[1])
            assert body == self.MAC(self.expand(self.hs[side], b'finished'), self.H(self.transcript))
            self.transcript += frame
            self.finished[side] = True
            if side == 1:
                self.app = [self.expand(self.master, b'c ap traffic', self.H(self.transcript)), self.expand(self.master, b's ap traffic', self.H(self.transcript))]
                self.exporter = self.expand(self.master, b'exp master', self.H(self.transcript))
            self.secrets[side] = self.app[side]
            self.sequences[side] = 0
            self.generations[side] = 1
        elif kind == 24:
            assert self.finished[side] and len(body) == 1 and body[0] in (0, 1)
            expected = 1 if side == 0 else 0
            assert body[0] == expected
            self.secrets[side] = self.expand(self.secrets[side], b'traffic upd')
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
            key = self.expand(self.secrets[side], b'key', length=16 if self.suite == 4865 else 32)
            iv = self.expand(self.secrets[side], b'iv', length=12)
            nonce = bytes(a ^ b for a, b in zip(iv, bytes(4)+self.sequences[side].to_bytes(8, 'big')))
            content = aead(key, nonce, packet[:5], packet[5:-16], packet[-16:], self.suite)
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
            if self.profile in (12,13):
                assert side == 1 and content == b'\x02\x50' and self.finished == [False, False]
                assert self.messages == [[1], [2, 8, 11]] and self.partial == [b'', b'']
            else:
                assert content == b'\x01\0' and self.finished == [True, True]
            self.closed[side] = True
        else:
            raise AssertionError(('unexpected inner type', kind))

    def finish(self, key, exporter, published_groups, published_suites, maximum_export, update_cost, zero_cost, quota_rejected, stats, witness):
        assert self.finished == self.closed == [True, True]
        assert self.partial == [b'', b''] and self.generations == [2, 2]
        assert self.data == [PAYLOAD+PAYLOAD[:31], PAYLOAD+PAYLOAD[:17]]
        assert published_groups == [self.group, self.group], (published_groups, self.group)
        assert published_suites == [self.suite, self.suite], (published_suites, self.suite)
        assert key == material.PUBLIC
        derived = self.expand(self.exporter, b'exchange', self.EMPTY)
        assert exporter == self.expand(derived, b'exporter', self.H(b'\0\xff\x01'), length=32)
        expected_update_cost = 4096+32*5+1024+8*5+32768
        if self.hashlen == 48:
            expected_update_cost += 2*131072+sha384_expansion_cost(11,0,48)+sha384_expansion_cost(3,0,32)+sha384_expansion_cost(2,0,12)+196608
            assert maximum_export == self.expand(derived, b'exporter', self.H(b'\0\xff\x01'), length=12240)
            assert zero_cost == 32768+128*3+sha384_hash_cost(0)+sha384_expansion_cost(8,48,48)+sha384_hash_cost(3)+sha384_expansion_cost(8,48,0), zero_cost
            assert quota_rejected == 1
        else:
            assert maximum_export == b'' and zero_cost == quota_rejected == 0
        assert update_cost == expected_update_cost, (update_cost, expected_update_cost)
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
        elif mode == 'hashes':
            cases = [(short,2,0,layout,1,(group,),(group,),group,(4866,),(4866,)) for group in (29,23) for layout in (0,1)]
        elif mode == 'hash-retries':
            # Client preference deliberately has a different hash from actual SH.
            cases = [(short,2,1,layout,1,(29,23),(23,29),29,(4867,4866,4865),(4866,)) for layout in (0,1)]
            cases += [(short,2,2,layout,1,(group,),(group,),group,(4865,4866),(4866,4865)) for layout,group in [(0,29),(1,23)]]
        elif mode == 'signing-limits':
            # The endpoint caps its existing shared verification allowance only
            # after the real Certificate record has fully reached its peer.
            # Exact credit signs a full proof; one less emits only a fatal alert.
            cases = [(short,suite,0,layout,1,(29,),(29,),29,(suite_id,),(suite_id,),profile)
                     for suite,suite_id in [(0,4867),(2,4866)]
                     for layout in (0,1) for profile in (11,12)]
        elif mode == 'signing-protocol-limits':
            cases = [(short,suite,0,layout,1,(29,),(29,),29,(suite_id,),(suite_id,),profile)
                     for suite,suite_id in [(0,4867),(2,4866)]
                     for layout in (0,1) for profile in (13,14,15)]
        elif mode in ('signatures','signature-policies'):
            rsa=MixedChain(base/'rsa','rsa'); ec=MixedChain(base/'ec','ecdsa'); pss=MixedChain(base/'pss','pss')
            if mode=='signatures':
                cases=[(chain,suite,0,layout,1,(29,),(29,),29,((4867,4865) if suite==0 else (4865,4867) if suite==1 else (4866,)),((4867,4865) if suite==0 else (4865,4867) if suite==1 else (4866,)),1) for chain,suite in [(rsa,0),(ec,1),(pss,2)] for layout in (0,1)]
            else:
                cases=[(short,0,0,layout,1,(29,),(29,),29,(4867,),(4867,),2) for layout in (0,1)]
                cases += [(rsa,0,0,0,1,(29,),(29,),29,(4867,),(4867,),6),(ec,1,0,1,1,(29,),(29,),29,(4865,),(4865,),7),(ec,0,0,0,1,(29,),(29,),29,(4867,),(4867,),3),(rsa,0,0,1,1,(29,),(29,),29,(4867,),(4867,),8)]
                cases += [(chain,0,0,layout,1,(29,),(29,),29,(4867,),(4867,),profile) for chain,profile in [(short,4),(rsa,5),(rsa,10),(ec,5)] for layout in (0,1)]
        else:
            raise AssertionError(mode)
        cases = [(*case, ((4867, 4865) if case[1] == 0 else (4865, 4867)), ((4867, 4865) if case[1] == 0 else (4865, 4867))) if len(case)==8 else case for case in cases]
        cases=[(*case,0) if len(case)==10 else case for case in cases]
        source = Q(len(cases))
        for chain, suite, retry, layout, split, cp, sp, initial, cs, ss, profile in cases:
            source += Q(layout, suite, retry, split, chain.now, len(chain.root), len(chain.chain), int(chain is not short), cp[0], cp[1] if len(cp)>1 else 0, sp[0], sp[1] if len(sp)>1 else 0, initial, *(cs+(4867,)*3)[:3], len(cs), *(ss+(4867,)*3)[:3], len(ss),profile)
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
        for number, (chain, suite, retry, layout, split, cp, sp, initial, cs, ss, profile) in enumerate(cases):
            tag=reader.word(); assert reader.word()==number
            if profile in (4,5,10):
                assert tag==20
                packet,alert=reader.block(),reader.block(); assert packet[:3]==b'\x16\x03\x01' and int.from_bytes(packet[3:5],'big')==len(packet)-5
                check_offers(hello(packet[5:]),profile)
                assert alert==b'\x15\x03\x03\x00\x02\x02\x2f' and reader.word()==10
                continue
            assert tag==10
            peer, witness = Peer(chain, suite, retry, cp, sp, initial, cs, ss,profile), 0
            signing_witness = 0
            while True:
                tag = reader.word()
                if tag == 1:
                    side, packet = reader.word(), reader.block()
                    assert side in (0, 1)
                    peer.record(side, packet)
                elif tag == 3:
                    assert reader.word() > 0
                    witness += 1
                elif tag == 4:
                    assert profile in (11,12) and signing_witness == 0
                    allowance, remaining, before, after = [reader.word() for _ in range(4)]
                    assert before > 0 and peer.messages == [[1], [2,8,11]]
                    if profile == 11:
                        assert allowance == 67108864 and remaining == 0 and after == before-1
                    else:
                        assert allowance == remaining == 67108863 and after == before
                        peer.record(1,reader.block())
                    signing_witness += 1
                elif tag == 5:
                    assert profile in (12,13,14,15) and signing_witness == 1 and witness == 0
                    assert peer.finished == [False,False] and peer.closed == [False,profile in (12,13)]
                    assert peer.messages == [[1], [2,8,11]] and peer.data == [b'',b'']
                    break
                elif tag == 6:
                    assert profile in (13,14,15) and signing_witness == 0
                    allowance, remaining, before_work, after_work, before_attempts, after_attempts = [reader.word() for _ in range(6)]
                    proof, alert = reader.block(), reader.block()
                    assert before_work > 67108864 and before_attempts > 0
                    assert peer.messages == [[1], [2,8,11]]
                    required = 1048576 + (2*16384+12288+32*(128+48)+8768 if peer.hashlen == 48 else 0)
                    assert allowance == required+profile-14
                    if profile == 13:
                        fatal_cost = 1040+(262144 if peer.hashlen == 48 else 0)
                        assert remaining == allowance-fatal_cost and after_work == before_work and after_attempts == before_attempts and proof == b''
                        peer.record(1,alert)
                    else:
                        assert remaining == profile-14 and after_work == before_work-67108864 and after_attempts == before_attempts-1 and alert == b''
                        assert proof[:8] == b'\x0f\x00\x00\x44\x08\x07\x00\x40' and len(proof) == 72
                        signed = b' '*64+b'TLS 1.3, server CertificateVerify\0'+peer.H(peer.transcript)
                        assert material.verify(material.PUBLIC,signed,proof[8:]) and proof[8:] == material.sign(signed)
                    signing_witness += 1
                else:
                    assert tag == 0
                    key, exporter = reader.block(), reader.block()
                    published_groups = [reader.word(), reader.word()]
                    published_suites = [reader.word(), reader.word()]
                    maximum_export, update_cost, zero_cost, quota_rejected = reader.block(), reader.word(), reader.word(), reader.word()
                    stats = [reader.word() for _ in range(6)]
                    assert reader.word() == witness
                    peer.finish(key, exporter, published_groups, published_suites, maximum_export, update_cost, zero_cost, quota_rejected, stats, witness)
                    assert signing_witness == (1 if profile == 11 else 0)
                    break
        assert reader.at == len(reader.data)
    print(f'tls connection {mode}: accepted')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
