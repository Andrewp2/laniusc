# Independent byte peer for the composed fixture. Production imports none of this.
import ctypes
import hashlib
import hmac
import pathlib
import struct
import subprocess
import sys
import tempfile

sodium = ctypes.CDLL('libsodium.so.23')
assert sodium.sodium_init() >= 0
P = ctypes.c_void_p
U = ctypes.c_ulonglong
base = sodium.crypto_scalarmult_curve25519_base
base.argtypes = [P, P]
shared = sodium.crypto_scalarmult_curve25519
shared.argtypes = [P, P, P]
keypair = sodium.crypto_sign_seed_keypair
keypair.argtypes = [P, P, P]
sign = sodium.crypto_sign_detached
sign.argtypes = [P, ctypes.POINTER(U), P, U, P]
verify = sodium.crypto_sign_verify_detached
verify.argtypes = [P, P, U, P]
enc = sodium.crypto_aead_chacha20poly1305_ietf_encrypt
enc.argtypes = [P, ctypes.POINTER(U), P, U, P, U, P, P, P]
dec = sodium.crypto_aead_chacha20poly1305_ietf_decrypt
dec.argtypes = [P, ctypes.POINTER(U), P, P, U, P, U, P, P]

def q(*values):
    return struct.pack('<' + 'Q' * len(values), *values)

def pattern(length, salt):
    return bytes((i * 73 + salt) & 255 for i in range(length))

def digest(value):
    return hashlib.sha256(value).digest()

def mac(key, message):
    return hmac.new(key, message, hashlib.sha256).digest()

def expand(secret, label, context, length=32):
    label = b'tls13 ' + label
    info = struct.pack('>H', length) + bytes([len(label)]) + label + bytes([len(context)]) + context
    previous = b''
    result = b''
    for counter in range(1, (length + 31) // 32 + 1):
        previous = mac(secret, previous + info + bytes([counter]))
        result += previous
    return result[:length]

def derive(secret, label, transcript):
    return expand(secret, label, digest(transcript))

def public(scalar):
    output = ctypes.create_string_buffer(32)
    assert base(output, scalar) == 0
    return output.raw

def exchange(scalar, point):
    output = ctypes.create_string_buffer(32)
    assert shared(output, scalar, point) == 0
    return output.raw

seed = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
pk = ctypes.create_string_buffer(32)
sk = ctypes.create_string_buffer(64)
assert keypair(pk, sk, seed) == 0
assert pk.raw.hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'

def signature(message):
    output = ctypes.create_string_buffer(64)
    length = U()
    assert sign(output, ctypes.byref(length), message, len(message), sk) == 0
    assert length.value == 64
    return output.raw

def verified(message, sig):
    return verify(sig, message, len(message), pk) == 0

def der_one(data, at=0):
    start = at
    tag = data[at]
    at += 1
    length = data[at]
    at += 1
    if length & 128:
        count = length & 127
        assert 0 < count <= 4 and data[at] != 0
        length = int.from_bytes(data[at:at + count], 'big')
        assert length >= 128
        at += count
    assert at + length <= len(data)
    return tag, data[at:at + length], data[start:at + length], at + length

def members(data):
    result = []
    at = 0
    while at < len(data):
        tag, value, encoded, at = der_one(data, at)
        result.append((tag, value, encoded))
    assert at == len(data)
    return result

def certificate_checks(cert):
    tag, contents, _, end = der_one(cert)
    assert tag == 48 and end == len(cert)
    fields = members(contents)
    assert len(fields) == 3
    tbs = members(fields[0][1])
    assert tbs[0][0] == 160 and members(tbs[0][1])[0][1] == b'\x02'
    assert int.from_bytes(tbs[1][1], 'big', signed=True) == 128
    assert tbs[3][2] == tbs[5][2]
    assert members(fields[1][1]) == [(6, bytes.fromhex('2b6570'), bytes.fromhex('06032b6570'))]
    spki = members(tbs[6][1])
    assert members(spki[0][1]) == members(fields[1][1])
    assert spki[1][0] == 3 and spki[1][1] == b'\0' + pk.raw
    assert fields[2][0] == 3 and len(fields[2][1]) == 65 and fields[2][1][0] == 0
    assert verified(fields[0][2], fields[2][1][1:])
    # OpenSSL independently verifies the raw TBS signature. No certificate
    # trust-store, wall-clock validity or peer-identity acceptance is invoked.
    with tempfile.TemporaryDirectory(prefix='laniusc_tls_auth_') as folder:
        folder = pathlib.Path(folder)
        for name, data in [('spki.der', tbs[6][2]), ('tbs.der', fields[0][2]), ('sig.bin', fields[2][1][1:])]:
            (folder / name).write_bytes(data)
        result = subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-keyform', 'DER', '-inkey', str(folder / 'spki.der'), '-in', str(folder / 'tbs.der'), '-sigfile', str(folder / 'sig.bin')], capture_output=True, timeout=5)
        assert result.returncode == 0, (result.stdout, result.stderr)

def u16(value):
    return value.to_bytes(2, 'big')

def u24(value):
    return value.to_bytes(3, 'big')

def frame(kind, body):
    return bytes([kind]) + u24(len(body)) + body

def extension(kind, body):
    return u16(kind) + u16(len(body)) + body

def frames(content):
    result = []
    at = 0
    while at < len(content):
        length = int.from_bytes(content[at + 1:at + 4], 'big')
        assert at + 4 + length <= len(content)
        result.append(content[at:at + 4 + length])
        at += 4 + length
    assert at == len(content)
    return result

def record(secret, sequence, content, kind, padding):
    key = expand(secret, b'key', b'')
    iv = expand(secret, b'iv', b'', 12)
    nonce = bytes(a ^ b for a, b in zip(iv, bytes(4) + sequence.to_bytes(8, 'big')))
    plain = content + bytes([kind]) + bytes(padding)
    header = b'\x17\x03\x03' + u16(len(plain) + 16)
    output = ctypes.create_string_buffer(len(plain) + 16)
    length = U()
    assert enc(output, ctypes.byref(length), plain, len(plain), header, 5, None, nonce, key) == 0
    assert length.value == len(plain) + 16
    return header + output.raw[:length.value]

def open_record(secret, sequence, packet):
    assert packet[:3] == b'\x17\x03\x03' and int.from_bytes(packet[3:5], 'big') == len(packet) - 5
    key = expand(secret, b'key', b'')
    iv = expand(secret, b'iv', b'', 12)
    nonce = bytes(a ^ b for a, b in zip(iv, bytes(4) + sequence.to_bytes(8, 'big')))
    body = packet[5:]
    output = ctypes.create_string_buffer(len(body))
    length = U()
    if dec(output, ctypes.byref(length), None, body, len(body), packet[:5], 5, nonce, key) != 0:
        return None
    plain = output.raw[:length.value]
    at = len(plain) - 1
    while plain[at] == 0:
        at -= 1
    return plain[at], plain[:at]

def flipped(value, index=-1):
    value = bytearray(value)
    value[index] ^= 1
    return bytes(value)

def flight(cert, variant):
    fields = {}
    client_scalar = bytes((i * 7 + 3) & 255 for i in range(32))
    server_scalar = bytes((i * 11 + 17) & 255 for i in range(32))
    cp, sp = public(client_scalar), public(server_scalar)
    cs, ss = exchange(client_scalar, sp), exchange(server_scalar, cp)
    assert cs == ss
    fields.update({1: cp, 2: sp, 3: cs, 4: ss})
    ce = extension(43, b'\x02\x03\x04') + extension(13, b'\x00\x02\x08\x07') + extension(10, b'\x00\x02\x00\x1d') + extension(51, u16(36) + u16(29) + u16(32) + cp)
    se = extension(43, b'\x03\x04') + extension(51, u16(29) + u16(32) + sp)
    sid = bytes([1, 3, 3, 7])
    ch = frame(1, b'\x03\x03' + pattern(32, 41) + bytes([len(sid)]) + sid + u16(2) + b'\x13\x03\x01\x00' + u16(len(ce)) + ce)
    sh = frame(2, b'\x03\x03' + pattern(32, 91) + bytes([len(sid)]) + sid + b'\x13\x03\x00' + u16(len(se)) + se)
    transcript = ch + sh
    fields.update({5: ch, 6: digest(ch), 7: sh, 8: digest(transcript)})
    zero = bytes(32)
    early = mac(zero, zero)
    hs = mac(derive(early, b'derived', b''), cs)
    chs = derive(hs, b'c hs traffic', transcript)
    shs = derive(hs, b's hs traffic', transcript)
    master = mac(derive(hs, b'derived', b''), zero)
    fields.update({9: early, 10: hs, 11: chs, 12: shs, 13: master})
    ee = frame(8, b'\x00\x00')
    transcript += ee
    fields.update({14: ee, 15: digest(transcript)})
    entry = u24(len(cert)) + cert + b'\x00\x00'
    cert_frame = frame(11, b'\x00' + u24(len(entry)) + entry)
    transcript += cert_frame
    fields.update({16: cert_frame, 17: digest(transcript), 18: pk.raw})
    cv_input = b' ' * 64 + b'TLS 1.3, server CertificateVerify\0' + digest(transcript)
    sig = signature(cv_input)
    assert verified(cv_input, sig)
    if variant == 1:
        sig = flipped(sig, 17)
    cv = frame(15, b'\x08\x07' + u16(64) + sig)
    transcript += cv
    fields.update({19: cv_input, 20: cv, 21: digest(transcript)})
    sf_data = mac(expand(shs, b'finished', b''), digest(transcript))
    if variant == 2:
        sf_data = flipped(sf_data, 11)
    sf = frame(20, sf_data)
    transcript += sf
    fields.update({22: sf, 23: digest(transcript)})
    cas = derive(master, b'c ap traffic', transcript)
    sas = derive(master, b's ap traffic', transcript)
    exporter = derive(master, b'exp master', transcript)
    exported = expand(derive(exporter, b'test export', b''), b'exporter', digest(b'context'), 48)
    fields.update({24: cas, 25: sas, 26: exporter, 27: exported})
    cf_data = mac(expand(chs, b'finished', b''), digest(transcript))
    if variant == 3:
        cf_data = flipped(cf_data, 13)
    cf = frame(20, cf_data)
    transcript += cf
    resumption = derive(master, b'res master', transcript)
    nonce = b'\x01\x02\x03'
    psk = expand(resumption, b'resumption', nonce)
    ticket = frame(4, struct.pack('>II', 3600, 0x12345678) + bytes([len(nonce)]) + nonce + u16(6) + b'ticket' + b'\x00\x00')
    fields.update({28: cf, 29: digest(transcript), 30: resumption, 31: psk, 32: ticket})
    server_payload, client_payload = b'server application bytes', b'client application bytes'
    packets = [record(shs, 0, ee + cert_frame + cv + sf, 22, 3), record(chs, 0, cf, 22, 1), record(sas, 0, server_payload, 23, 2), record(cas, 0, client_payload, 23, 0), record(sas, 1, ticket, 22, 0)]
    if 4 <= variant <= 8:
        packets[variant - 4] = flipped(packets[variant - 4])
    fields.update(dict(zip(range(33, 38), packets)))
    # Independently consume the protected flight and authenticate each logical
    # checkpoint before changing the accepted transcript or publication bytes.
    rx = ch + sh
    count, status, shseq, chseq, saseq, caseq, poisoned = 2, 0, 0, 0, 0, 0, 0
    incoming = open_record(shs, 0, packets[0])
    if incoming is None:
        status, poisoned = 4, 1
    else:
        shseq = 1
        kind, content = incoming
        assert kind == 22
        parsed = frames(content)
        assert len(parsed) == 4 and [m[0] for m in parsed] == [8, 11, 15, 20]
        rx += parsed[0] + parsed[1]
        count = 4
        assert parsed[1] == cert_frame
        if not verified(b' ' * 64 + b'TLS 1.3, server CertificateVerify\0' + digest(rx), parsed[2][8:]):
            status = 1
        else:
            rx += parsed[2]
            count = 5
            expected = mac(expand(shs, b'finished', b''), digest(rx))
            if not hmac.compare_digest(expected, parsed[3][4:]):
                status = 2
            else:
                rx += parsed[3]
                count = 6
    if not status:
        incoming = open_record(chs, 0, packets[1])
        if incoming is None:
            status, poisoned = 5, 2
        else:
            chseq = 1
            kind, content = incoming
            assert kind == 22 and content[0] == 20
            expected = mac(expand(chs, b'finished', b''), digest(rx))
            if not hmac.compare_digest(expected, content[4:]):
                status = 3
            else:
                rx += content
                count = 7
    if not status:
        incoming = open_record(sas, 0, packets[2])
        if incoming is None:
            status, poisoned = 6, 4
        else:
            saseq = 1
            assert incoming == (23, server_payload)
    if not status:
        incoming = open_record(cas, 0, packets[3])
        if incoming is None:
            status, poisoned = 7, 8
        else:
            caseq = 1
            assert incoming == (23, client_payload)
    if not status:
        incoming = open_record(sas, 1, packets[4])
        if incoming is None:
            status, poisoned = 8, 4
        else:
            saseq = 2
            assert incoming == (22, ticket)
    published = b'' if status else server_payload + client_payload + nonce
    fields[38] = digest(rx)
    fields[39] = published + bytes([222]) * (128 - len(published))
    fields[40] = q(status, count, shseq, chseq, saseq, caseq, poisoned, len(published))
    assert status == variant
    assert set(fields) == set(range(1, 41))
    return fields

source = sys.stdin.buffer.read()
at = 0

def word():
    global at
    result, = struct.unpack_from('<Q', source, at)
    at += 8
    return result

length = word()
certificate = source[at:at + length]
at += length
certificate_checks(certificate)
count = word()
for _ in range(count):
    layout, variant = word(), word()
    sys.stdout.buffer.write(q(layout, variant))
    for field, value in sorted(flight(certificate, variant).items()):
        sys.stdout.buffer.write(q(field, len(value)) + value)
assert at == len(source)
