"""Independent exact-byte peers for bounded protocol/error/counter seams.
Private high-counter/phase inputs in controls.lani are not authentication proof.
"""
import ctypes
import importlib.util
import hashlib
import hmac
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('connection_wire_peer', HERE/'peer.py')
wire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wire)
Q, U16, U24, H = wire.Q, wire.U16, wire.U24, wire.H
KEY = bytes(range(33, 65))
KEY384 = bytes(range(33,81))
INITIAL = b"\x01\0\0\0"
LIMIT = 16777216
UPDATED = wire.expand(KEY, b'traffic upd', algorithm='sha256')
DATA = b'\xaa\0\xff'


def seal(secret, seq, kind, content, *, algorithm='sha256'):
    key_length = 32 if algorithm == 'sha384' else 16
    key, iv = wire.expand(secret, b'key', length=key_length, algorithm=algorithm), wire.expand(secret, b'iv', length=12, algorithm=algorithm)
    nonce = bytes(a ^ b for a, b in zip(iv, bytes(4)+seq.to_bytes(8, 'big')))
    plain = content+bytes([kind])
    header = b'\x17\x03\x03'+U16(len(plain)+16)
    c, I, P = wire.crypto, wire.I, wire.P
    ctx = c.EVP_CIPHER_CTX_new()
    assert ctx
    try:
        cipher = c.EVP_aes_256_gcm if algorithm == 'sha384' else c.EVP_aes_128_gcm
        assert c.EVP_EncryptInit_ex(ctx, cipher(), None, None, None) == 1
        assert c.EVP_CIPHER_CTX_ctrl(ctx, 9, 12, None) == 1
        assert c.EVP_EncryptInit_ex(ctx, None, None, key, nonce) == 1
        n = I()
        assert c.EVP_EncryptUpdate(ctx, None, ctypes.byref(n), header, len(header)) == 1
        output = ctypes.create_string_buffer(len(plain)+16)
        assert c.EVP_EncryptUpdate(ctx, output, ctypes.byref(n), plain, len(plain)) == 1
        total = n.value
        assert c.EVP_EncryptFinal_ex(ctx, ctypes.byref(output, total), ctypes.byref(n)) == 1
        total += n.value
        assert total == len(plain)
        tag = ctypes.create_string_buffer(16)
        assert c.EVP_CIPHER_CTX_ctrl(ctx, 16, 16, tag) == 1
        return header+output.raw[:total]+tag.raw
    finally:
        c.EVP_CIPHER_CTX_free(ctx)


def decode(packet, secret, sequence, *, algorithm='sha256'):
    assert packet[:3] == b'\x17\x03\x03'
    key = wire.expand(secret, b'key', length=32 if algorithm == 'sha384' else 16, algorithm=algorithm)
    iv = wire.expand(secret, b'iv', length=12, algorithm=algorithm)
    nonce = bytes(a ^ b for a, b in zip(iv, bytes(4)+sequence.to_bytes(8, 'big')))
    return wire.aead(key, nonce, packet[:5], packet[5:-16], packet[-16:], 4866 if algorithm == 'sha384' else 4865)


def plain(kind, content, version=b'\xff\xff'):
    return bytes([kind])+version+U16(len(content))+content


def frame(kind, content):
    return bytes([kind])+U24(len(content))+content


def finished384(tamper=False):
    key = wire.expand(KEY384, b'finished', algorithm='sha384')
    tag = hmac.new(key, hashlib.sha384(INITIAL).digest(), hashlib.sha384).digest()
    if tamper:
        tag = tag[:-1]+bytes([tag[-1]^1])
    return frame(20, tag)


def inputs(op):
    if op in (23,24):
        finished = finished384(op == 24)
        return seal(KEY384,0,22,finished[:20],algorithm='sha384'), seal(KEY384,1,22,finished[20:],algorithm='sha384')
    cpub, spub, shared = wire.shared_key(29, (29,), (29,))
    ext = b'\0\x2b\0\x02\x03\x04'+b'\0\x33\0\x24\0\x1d\0\x20'+spub
    sh = frame(2, b'\x03\x03'+wire.SERVER_ENTROPY[:32]+b'\0\x13\x03\0'+U16(len(ext))+ext)
    ccs = plain(20, b'\x01')
    old_app = seal(KEY, LIMIT-1, 23, DATA)
    ticket = frame(4, bytes(8)+b'\0\0\x01x\0\0')
    bad0 = seal(KEY, 0, 23, DATA)
    bad0 = bad0[:-1]+bytes([bad0[-1]^1])
    bad1 = seal(KEY, 1, 23, DATA)
    bad1 = bad1[:-1]+bytes([bad1[-1]^1])
    return {
        0: (b'', b''),
        1: (ccs, ccs),
        2: (plain(22, sh), b''),
        3: (plain(22, sh+frame(8, b'\0\0')), b''),
        4: (plain(22, b'\x02\xff\xff\xff'), b''),
        5: (b'\x17\x03\x03\x41\x01', b''),
        6: (plain(22, b'\x02\0'), plain(21, b'\xff\0')),
        7: (ccs, b''),
        8: (plain(22, sh), b''),
        9: (plain(22, sh), b''),
        10: (old_app, old_app),
        11: (seal(KEY, LIMIT-1, 21, b'\xff\0'), old_app),
        12: (seal(KEY, LIMIT-1, 22, frame(24, b'\0')), seal(UPDATED, 0, 23, DATA)),
        13: (DATA, b''),
        14: (b'', b''),
        15: (bad0, DATA),
        16: (seal(KEY, 0, 22, ticket[:3]), seal(KEY, 1, 22, ticket[3:])),
        17: (seal(KEY, 0, 23, DATA), bad1),
        18: (seal(KEY, 0, 23, DATA), seal(KEY, 1, 21, b'\x01\0')),
        19: (seal(KEY, 0, 21, b'\x01\xff'), b''),
        20: (ccs, ccs),
        21: (b'\x16\xff\xff', b''),
        22: (seal(KEY, 0, 22, frame(24, b'\0')+frame(4, b'')), b''),
    }[op]


def check(op, a, b, first, second, words, result, outgoing):
    sa, ca, sb, cb, rs, rn, eof, failed, peerclose, localclose, held, rawheld, pending, sg, rg, ss, rx, hs, received, sent = words
    assert len(result) == 64
    expected_read = DATA if op in (10, 12, 18) else b''
    assert result == bytes([165])*3+expected_read+bytes([165])*(61-len(expected_read)), (op, result.hex())
    assert rn == len(expected_read) and rs == (3 if op == 17 else 5 if op == 21 else 0)
    expected = {
        0: (1, 0, 5, 0), 1: (6, len(a), 6, 0), 2: (0, len(a), 0, 0),
        3: (6, len(a), 6, 0), 4: (14, len(a), 14, 0), 5: (13, 5, 13, 0),
        6: (0, len(a), 6, len(b)), 7: (4, len(a), 4, 0),
        8: (4, len(a), 4, 0), 9: (4, 0, 4, 0),
        10: (0, len(a), 11, len(b)), 11: (0, len(a), 0, len(b)),
        12: (0, len(a), 0, len(b)), 13: (15, 0, 0, len(a)),
        14: (4, 0, 0, 0), 15: (10, len(a), 10, 0),
        16: (0, len(a), 0, len(b)), 17: (0, len(a), 10, len(b)),
        18: (0, len(a), 0, len(b)), 19: (9, len(a), 9, 0),
        20: (0, len(a), 6, len(b)), 21: (0, len(a), 5, 0),
        22: (6, len(a), 6, 0), 23: (0,len(a),0,len(b)), 24: (0,len(a),16,len(b)),
    }[op]
    assert (sa, ca, sb, cb) == expected, (op, words, expected)
    assert eof == int(op in (11, 18)) and peerclose == int(op in (11, 18))
    assert localclose == int(op == 16)
    assert failed == int(op not in (2, 11, 12, 13, 16, 18, 23))
    assert held == 0 and rawheld == (3 if op == 17 else 0)
    if op == 10:
        assert rx == LIMIT and received == 2 and rg == 1
    if op == 11:
        assert rx == LIMIT and received == 1 and rg == 1 and outgoing == b''
    if op == 12:
        assert rg == 2 and rx == 1 and received == 2
    if op == 13:
        assert decode(first, KEY, LIMIT-1) == frame(24, b'\0')+b'\x16'
        assert decode(second, UPDATED, 0) == DATA+b'\x17'
        assert outgoing == second and sg == 2 and ss == 1
    elif op == 15:
        assert decode(first, KEY, 0) == DATA+b'\x17' and second == b''
        assert outgoing == b'' and pending == len(first) and ss == 1 and rx == 0
    elif op == 16:
        assert decode(first, KEY, 0) == frame(24, b'\x01')+b'\x16'
        assert decode(second, UPDATED, 0) == b'\x01\0\x15'
        assert hs == 0 and sg == 2 and ss == 1 and rg == 1 and rx == 2 and outgoing == b''
    elif op in (23,24):
        assert first == hashlib.sha384(INITIAL).digest()
        assert second == (hashlib.sha384(INITIAL+finished384()).digest() if op == 23 else b'')
        assert received == 2 and rg == (1 if op == 23 else 0) and rx == (0 if op == 23 else 2)
        assert sg == 0 and held == 0 and hs == (0 if op == 23 else 52)
        if op == 23:
            assert outgoing == b'' and ss == sent == 0
        else:
            assert ss == sent == 1 and decode(outgoing,KEY384,0,algorithm='sha384') == b'\x02\x33\x15'
    else:
        assert first == second == b''
    if op == 0:
        assert outgoing == b'' and pending > 5 and sent == 1
    if op in (1, 8, 9, 19, 21):
        assert outgoing == b'', (op, outgoing.hex())
    if op in (3, 4, 5, 6, 7, 20):
        assert outgoing == plain(21, bytes([2, {3: 10, 4: 50, 5: 22, 6: 10, 7: 80, 20: 10}[op]]), b'\x03\x03')
    if op in (10, 14, 17):
        assert decode(outgoing, KEY, 0) == bytes([2, 50 if op == 10 else 80 if op == 14 else 20, 21])
    if op == 22:
        assert rg == sg == 1 and rx == ss == 1 and hs == 5
        assert received == sent == 1
        assert decode(outgoing, KEY, 0) == b'\x02\x0a\x15'


def run(executable):
    cases = [(op, layout, *inputs(op)) for op in range(25) for layout in (0, 1)]
    source = Q(len(cases))+b''.join(Q(op, layout, len(a), len(b))+a+b for op, layout, a, b in cases)
    with tempfile.TemporaryDirectory(prefix='laniusc_connection_controls_') as temp:
        trace = pathlib.Path(temp)/'memory'
        result = subprocess.run(['strace', '-qq', '-o', str(trace), '-e', 'trace=mmap,munmap,mremap,brk', '-e', 'signal=none', executable], input=source, capture_output=True, timeout=30)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, len(result.stdout), result.stdout[-80:].hex(), result.stderr)
        assert trace.read_bytes() == b''
    reader = wire.Reader(result.stdout)
    for op, layout, a, b in cases:
        assert reader.word() == op and reader.word() == layout
        first, second = reader.block(), reader.block()
        words = [reader.word() for _ in range(20)]
        observed, outgoing = reader.block(), reader.block()
        check(op, a, b, first, second, words, observed, outgoing)
    assert reader.at == len(reader.data)
    print('tls connection controls: 50 accepted')


if __name__ == '__main__':
    run(sys.argv[1])
