"""Test-only signed DER corpus: libsodium signatures, OpenSSL path differential.

The oracle represents names, purposes and constraints as host values. It never
calls Lanius and supplies no production implementation/backend. Fixed seeds are
public test data. Deliberately unsupported profiles have explicit expectations.
"""
import base64
import ctypes
import dataclasses
import datetime
import hashlib
import pathlib
import struct
import subprocess
import sys
import tempfile

NOW = 1792843200  # 2026-10-24T12:00:00Z
U64 = (1 << 64) - 1
CODES = {name: i + 1 for i, name in enumerate('Bounds EmptyChain EmptyAnchors ChainLimit AnchorLimit InputLimit ScratchTooSmall InvalidTime Parse ItemLimit WorkLimit SignatureLimit Duplicate UnsupportedAlgorithm IssuerMismatch Untrusted InvalidSignature Validity CaRequired KeyUsage ExtendedKeyUsage PathLength UnknownCritical UnsupportedConstraint UnsupportedCritical Identity'.split())}
lib = ctypes.CDLL('libsodium.so.23')
lib.sodium_init.restype = ctypes.c_int
assert lib.sodium_init() >= 0
kp = lib.crypto_sign_seed_keypair
kp.argtypes = [ctypes.c_void_p] * 3
kp.restype = ctypes.c_int
sign = lib.crypto_sign_detached
sign.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p]
sign.restype = ctypes.c_int
verify = lib.crypto_sign_verify_detached
verify.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p]
verify.restype = ctypes.c_int

def key(label):
    seed = hashlib.sha256(('x509-path-test-' + label).encode()).digest()
    pk, sk = ctypes.create_string_buffer(32), ctypes.create_string_buffer(64)
    assert kp(pk, sk, ctypes.create_string_buffer(seed)) == 0
    return pk.raw, sk.raw

def signed(message, secret):
    output = ctypes.create_string_buffer(64)
    assert sign(output, None, ctypes.create_string_buffer(message), len(message), ctypes.create_string_buffer(secret)) == 0
    return output.raw

def tlv(tag, body):
    n = len(body)
    size = (n.bit_length() + 7) // 8
    return bytes([tag]) + (bytes([n]) if n < 128 else bytes([128 + size]) + n.to_bytes(size, 'big')) + body

def seq(*items): return tlv(48, b''.join(items))
def integer(n): return tlv(2, n.to_bytes(max(1, (n.bit_length() + 8) // 8), 'big', signed=True))
def base128(n):
    digits = [n & 127]
    while n >> 7:
        n >>= 7
        digits.append((n & 127) | 128)
    return bytes(reversed(digits))
def oid(*arcs): return tlv(6, base128(40 * arcs[0] + arcs[1]) + b''.join(base128(n) for n in arcs[2:]))
ED = seq(oid(1, 3, 101, 112))
def bitstring(value): return tlv(3, b'\0' + value)
def name(text, tag=12): return seq(tlv(49, seq(oid(2, 5, 4, 3), tlv(tag, text.encode()))))
def extension(number, body, critical=False): return seq(oid(2, 5, 29, number), *( [b'\x01\x01\xff'] if critical else []), tlv(4, body))
def utc(seconds): return tlv(23, datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).strftime('%y%m%d%H%M%SZ').encode())
def usage(indices):
    last = max(indices)
    data = bytearray(last // 8 + 1)
    for n in indices: data[n // 8] |= 128 >> (n % 8)
    return tlv(3, bytes([7 - last % 8]) + data)

@dataclasses.dataclass
class Cert:
    subject: str
    issuer: str
    public: bytes
    signer: bytes
    ca: bool = False
    path: object = None
    ku: object = None
    eku: object = None
    before: int = NOW - 86400
    after: int = NOW + 86400
    sans: tuple = ((2, b'path.example'),)
    extra: tuple = ()
    subject_tag: int = 12
    issuer_tag: int = 12
    bc: bool = True
    critical_san: bool = False
    serial: int = 1
    tamper: bool = False
    algorithm: bytes = ED
    spki_algorithm: bytes = ED
    raw: object = None

    def encode(self):
        if self.raw is not None: return self.raw
        extensions = []
        if self.bc: extensions.append(extension(19, seq(*([b'\x01\x01\xff'] if self.ca else []), *([integer(self.path)] if self.path is not None else [])), True))
        if self.ku is not None: extensions.append(extension(15, usage(self.ku), True))
        if self.eku is not None: extensions.append(extension(37, seq(*(oid(2, 5, 29, 37, 0) if p == 'any' else oid(1, 3, 6, 1, 5, 5, 7, 3, 1 if p == 'server' else 2) for p in self.eku))))
        if self.sans: extensions.append(extension(17, seq(*(tlv(128 + t, b) for t, b in self.sans)), self.critical_san))
        extensions += list(self.extra)
        tbs = seq(tlv(160, integer(2)), integer(self.serial), self.algorithm, name(self.issuer, self.issuer_tag), seq(utc(self.before), utc(self.after)), name(self.subject, self.subject_tag), seq(self.spki_algorithm, bitstring(self.public)), tlv(163, seq(*extensions)))
        signature = bytearray(signed(tbs, self.signer))
        if self.tamper: signature[17] ^= 4
        return seq(tbs, self.algorithm, bitstring(bytes(signature)))

def changed(cert, **fields): return dataclasses.replace(cert, **fields)
ROOT_PK, ROOT_SK = key('root')
CA_PK, CA_SK = key('intermediate')
LEAF_PK, LEAF_SK = key('leaf')
OTHER_PK, OTHER_SK = key('other')
root = Cert('Root', 'Root', ROOT_PK, ROOT_SK, ca=True, path=3, ku=(5, 6), eku=('server',), sans=())
ca = Cert('CA', 'Root', CA_PK, ROOT_SK, ca=True, path=1, ku=(5, 6), eku=('server',), sans=())
leaf = Cert('Leaf', 'CA', LEAF_PK, CA_SK, ku=(0,), eku=('server',))

def semantic_accept(chain, anchor, now=NOW, reference=b'path.example', ip=False):
    """Independent supported-profile predicate over host certificate facts.

    Signature checks use the actually encoded TBS/signature parsed below. The
    finite semantic model separates counted non-self-issued intermediates from
    array depth; no capacities or work counters are copied from production.
    """
    peers = chain[:-1] if len(chain) > 1 and chain[-1].encode() == anchor.encode() else chain
    if not peers or not anchor.ca: return False
    authorities = [(name(c.subject, c.subject_tag), c.public) for c in chain]
    if len(set(authorities)) != len(authorities): return False
    anchor_authority = (name(anchor.subject, anchor.subject_tag), anchor.public)
    if any((name(c.subject, c.subject_tag), c.public) == anchor_authority for c in peers): return False
    # These generated DNS cases need no wildcard/IDNA implementation. The host
    # facts independently determine exact case-insensitive DNS or binary IP-ID.
    if ip:
        if not any(tag == 7 and value == reference for tag, value in peers[0].sans): return False
    else:
        expected = reference.lower().removesuffix(b'.')
        if not any(tag == 2 and value.lower().removesuffix(b'.') == expected for tag, value in peers[0].sans): return False
    for index, cert in enumerate(peers + [anchor]):
        if not cert.before <= now <= cert.after: return False
        is_ca = index > 0
        if is_ca and not (cert.bc and cert.ca): return False
        if cert.ku is not None and (5 if is_ca else 0) not in cert.ku: return False
        if cert.eku is not None and not ({'server', 'any'} & set(cert.eku)): return False
        if is_ca and cert.path is not None:
            count = sum(c.subject != c.issuer or c.subject_tag != c.issuer_tag for c in peers[1:index])
            if count > cert.path: return False
    for child, issuer in zip(peers, peers[1:] + [anchor]):
        if child.algorithm != ED: return False
        if name(child.issuer, child.issuer_tag) != name(issuer.subject, issuer.subject_tag): return False
        outer = children(one(child.encode())[1])
        signature = outer[2][1][1:]
        if verify(ctypes.create_string_buffer(signature), ctypes.create_string_buffer(outer[0][2]), len(outer[0][2]), ctypes.create_string_buffer(issuer.public)) != 0: return False
    return True

def children(data):
    out = []
    while data:
        tag, lead = data[:2]
        width = lead & 127 if lead & 128 else 0
        header = 2 + width
        size = int.from_bytes(data[2:header], 'big') if width else lead
        assert header + size <= len(data)
        out.append((tag, data[header:header + size], data[:header + size]))
        data = data[header + size:]
    return out
def one(data):
    items = children(data)
    assert len(items) == 1
    return items[0]

def case(label, chain=None, anchors=None, error=None, signatures=None, **options):
    return dict(label=label, chain=list(chain if chain is not None else [leaf, ca]), anchors=list(anchors if anchors is not None else [root]), code=CODES[error] if error else 0, signatures=signatures, options=options)

def models():
    cases = [case('normal', signatures=2), case('included exact root', chain=[leaf, ca, root], signatures=2),
             case('direct root signature', chain=[changed(leaf, issuer='Root', signer=ROOT_SK)], signatures=1),
             case('inclusive first', now=leaf.before, signatures=2), case('inclusive last', now=leaf.after, signatures=2),
             case('arbitrary huge pathLen', anchors=[changed(root, path=1 << 256)]),
             case('absent KU EKU unrestricted', chain=[changed(leaf, ku=None, eku=None), changed(ca, ku=None, eku=None)], anchors=[changed(root, ku=None, eku=None)]),
             case('any EKU', chain=[changed(leaf, eku=('any',)), ca]),
             case('DNS case and root dot', reference=b'PATH.EXAMPLE.'),
             case('binary IPv4', chain=[changed(leaf, sans=((7, bytes([192, 0, 2, 9])),)), ca], reference=bytes([192, 0, 2, 9]), ip=1),
             case('critical supported SAN', chain=[changed(leaf, critical_san=True), ca]),
             case('allowed offline metadata remains nonauthoritative', chain=[changed(leaf, extra=(extension(14, tlv(4, bytes(20))), extension(35, seq()), extension(31, seq()), extension(46, seq()), seq(oid(1, 3, 6, 1, 5, 5, 7, 1, 1), tlv(4, seq())))), ca]),
             case('matching SAN does not bypass later item failure', chain=[changed(leaf, sans=((2, b'path.example'), (2, b'later.example'))), ca], mode=7)]
    rollover = Cert('Root', 'Root', OTHER_PK, ROOT_SK, ca=True, path=0, ku=(5,), sans=())
    rollover_leaf = changed(leaf, issuer='Root', signer=OTHER_SK)
    cases += [case('selfissued rollover pathLen excludes it', chain=[rollover_leaf, rollover], anchors=[changed(root, path=0)], signatures=2),
              case('selfissued rollover with included configured root', chain=[rollover_leaf, rollover, changed(root, path=0)], anchors=[changed(root, path=0)], signatures=2),
              case('wrong issuer', chain=[changed(leaf, issuer='Other'), ca], error='IssuerMismatch'),
              case('byte exact DN restricted profile', chain=[changed(leaf, issuer_tag=19), ca], error='IssuerMismatch'),
              case('wrong intermediate public key', chain=[leaf, changed(ca, public=OTHER_PK)], error='InvalidSignature'),
              case('wellframed P256 issuer wrong key length has issuer index', chain=[leaf, changed(ca, spki_algorithm=seq(oid(1, 2, 840, 10045, 2, 1), oid(1, 2, 840, 10045, 3, 1, 7)))], error='UnsupportedAlgorithm', signatures=0, error_indices=(1, -1)),
              case('tampered signed TBS signature', chain=[changed(leaf, tamper=True), ca], error='InvalidSignature'),
              case('RSA algorithm mismatches Ed issuer key', chain=[changed(leaf, algorithm=seq(oid(1, 2, 840, 113549, 1, 1, 11), b'\x05\0')), ca], error='InvalidSignature', signatures=0),
              case('wrong root public key', anchors=[changed(root, public=OTHER_PK)], error='InvalidSignature'),
              case('untrusted root', anchors=[changed(root, subject='Other', issuer='Other', public=OTHER_PK, signer=OTHER_SK)], error='Untrusted'),
              case('selfsignature is not trust', chain=[changed(leaf, issuer='Leaf', signer=LEAF_SK)], error='Untrusted'),
              case('before validity', now=leaf.before - 1, error='Validity'),
              case('after validity', now=leaf.after + 1, error='Validity'),
              case('reversed interval', chain=[changed(leaf, before=leaf.after, after=leaf.before), ca], error='Validity'),
              case('expired configured anchor', anchors=[changed(root, after=NOW - 1)], error='Validity', error_indices=(-1, 0)),
              case('anchor must be CA', anchors=[changed(root, ca=False, path=None)], error='CaRequired'),
              case('intermediate must be CA', chain=[leaf, changed(ca, ca=False, path=None)], error='CaRequired'),
              case('missing intermediate BC', chain=[leaf, changed(ca, bc=False)], error='CaRequired'),
              case('leaf digitalSignature', chain=[changed(leaf, ku=(1,)), ca], error='KeyUsage'),
              case('intermediate keyCertSign', chain=[leaf, changed(ca, ku=(0,))], error='KeyUsage'),
              case('anchor keyCertSign', anchors=[changed(root, ku=(0,))], error='KeyUsage'),
              case('leaf EKU', chain=[changed(leaf, eku=('client',)), ca], error='ExtendedKeyUsage'),
              case('CA EKU', chain=[leaf, changed(ca, eku=('client',))], error='ExtendedKeyUsage'),
              case('anchor EKU', anchors=[changed(root, eku=('client',))], error='ExtendedKeyUsage'),
              case('configured anchor constraint is authoritative', anchors=[changed(root, extra=(extension(30, seq()),))], error='UnsupportedConstraint', error_indices=(-1, 0)),
              case('root pathLen zero excludes only leaf', anchors=[changed(root, path=0)], error='PathLength', error_indices=(-1, 0)),
              case('same authority peer duplicate', chain=[leaf, ca, ca], error='Duplicate'),
              case('same authority anchor duplicate', anchors=[root, changed(root, serial=2)], error='Duplicate'),
              case('nonexact same authority peer root cannot strip', chain=[leaf, ca, root], anchors=[changed(root, serial=2)], error='Duplicate'),
              case('wrong identity', reference=b'wrong.example', error='Identity'),
              case('critical unsupported SAN choice', chain=[changed(leaf, critical_san=True, sans=((6, b'https://path.example'), (2, b'path.example'))), ca], error='UnsupportedCritical'),
              case('critical unknown extension', chain=[changed(leaf, extra=(extension(123, seq(), True),)), ca], error='UnknownCritical'),
              case('unrecognized noncritical explicit rejection', chain=[changed(leaf, extra=(extension(123, seq()),)), ca], error='UnsupportedConstraint')]
    for n in [30, 32, 33, 36, 54]:
        cases.append(case(f'unsupported constraint {n} noncritical', chain=[changed(leaf, extra=(extension(n, seq()),)), ca], error='UnsupportedConstraint'))
    bad_anchor = changed(root, public=OTHER_PK)
    cases += [case('failed signature candidate then valid anchor', anchors=[bad_anchor, root], signatures=3),
              case('candidate shares exhausted signatures', anchors=[bad_anchor, root], max_signatures=2, error='SignatureLimit', signatures=2),
              case('signature quota zero', max_signatures=0, error='SignatureLimit', signatures=0),
              case('signature quota edgecount minus one', max_signatures=1, error='SignatureLimit', signatures=1),
              case('signature quota exact', max_signatures=2, signatures=2),
              case('signature quota above', max_signatures=3, signatures=2),
              case('first deterministic candidate error', anchors=[bad_anchor, changed(root, subject='Other', public=LEAF_PK)], error='InvalidSignature', signatures=2, error_indices=(1, 0)),
              case('all configured anchors parsed failclosed', anchors=[root, changed(root, raw=b'\x30\x81')], error='Parse', signatures=0),
              case('zero input quota', max_input=0, error='InputLimit', signatures=0),
              case('zero chain quota', max_chain=0, error='ChainLimit', signatures=0),
              case('zero anchor quota', max_anchors=0, error='AnchorLimit', signatures=0),
              case('zero parser items', max_items=0, error='ItemLimit', signatures=0),
              case('zero parser work', parse_work=0, error='WorkLimit', signatures=0),
              case('zero path work', max_work=0, error='WorkLimit', signatures=0),
              case('time below year1', now=-62135596801, error='InvalidTime', signatures=0),
              case('time after year9999', now=253402300800, error='InvalidTime', signatures=0)]
    for mode, error in [(1, 'Bounds'), (2, 'Bounds'), (3, 'ScratchTooSmall'), (4, 'EmptyAnchors'), (5, 'EmptyChain'), (6, 'Bounds')]:
        cases.append(case(f'preflight metadata mode{mode}', mode=mode, error=error, signatures=0))
    return cases

def openssl_cases():
    # Differential restricted to rules actually shared with OpenSSL's ordinary
    # offline sslserver verifier; unsupported policy/DN/anchor profiles stay out.
    cases = [case('OpenSSL valid'), case('OpenSSL exact root included', chain=[leaf, ca, root]),
             case('OpenSSL expired', now=leaf.after + 1, error='Validity'),
             case('OpenSSL wrong hostname', reference=b'bad.example', error='Identity'),
             case('OpenSSL signature tamper', chain=[changed(leaf, tamper=True), ca], error='InvalidSignature'),
             case('OpenSSL wrong issuer', chain=[changed(leaf, issuer='Other'), ca], error='IssuerMismatch'),
             case('OpenSSL leaf wrong EKU', chain=[changed(leaf, eku=('client',)), ca], error='ExtendedKeyUsage'),
             case('OpenSSL pathLen', anchors=[changed(root, path=0)], error='PathLength')]
    with tempfile.TemporaryDirectory(prefix='lanius_x509_path_') as folder:
        folder = pathlib.Path(folder)
        def pem(cert):
            body = base64.b64encode(cert.encode()).decode()
            return '-----BEGIN CERTIFICATE-----\n' + '\n'.join(body[i:i+64] for i in range(0, len(body), 64)) + '\n-----END CERTIFICATE-----\n'
        for c in cases:
            (folder / 'root.pem').write_text(pem(c['anchors'][0]))
            (folder / 'leaf.pem').write_text(pem(c['chain'][0]))
            (folder / 'untrusted.pem').write_text(''.join(pem(v) for v in c['chain'][1:]))
            command = ['openssl', 'verify', '-no-CApath', '-no-CAstore', '-CAfile', str(folder / 'root.pem'), '-attime', str(c['options'].get('now', NOW)), '-purpose', 'sslserver', '-verify_hostname', c['options'].get('reference', b'path.example').decode()]
            if len(c['chain']) > 1: command += ['-untrusted', str(folder / 'untrusted.pem')]
            command += [str(folder / 'leaf.pem')]
            actual = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
            assert (actual.returncode == 0) == (c['code'] == 0), (c['label'], actual.stdout, actual.stderr)
    return cases

def record(c, layout):
    o = c['options']
    accepted = lambda anchor: semantic_accept(c['chain'], anchor, o.get('now', NOW), o.get('reference', b'path.example'), o.get('ip', False))
    if c['code'] == 0:
        assert any(accepted(anchor) for anchor in c['anchors']), c['label']
    elif c['code'] in {CODES[k] for k in ['IssuerMismatch', 'Untrusted', 'InvalidSignature', 'Validity', 'CaRequired', 'KeyUsage', 'ExtendedKeyUsage', 'PathLength', 'Identity']}:
        assert not any(accepted(anchor) for anchor in c['anchors']), ('independent negative predicate', c['label'])
    chain, anchors = [v.encode() for v in c['chain']], [v.encode() for v in c['anchors']]
    reference = o.get('reference', b'path.example')
    fields = [layout, o.get('mode', 0), o.get('max_chain', 8), o.get('max_anchors', 8), o.get('max_input', 1048576), o.get('max_signatures', 64), o.get('max_work', 1073741824), o.get('max_items', 100000), o.get('parse_work', 16777216), o.get('now', NOW) & U64, o.get('ip', 0), len(reference), len(chain), len(anchors)]
    wire = b''.join(struct.pack('<Q', n) for n in fields) + reference
    for cert in chain + anchors: wire += struct.pack('<Q', len(cert)) + cert
    ci, ai = o.get('error_indices', (U64 - 1, U64 - 1))
    expected = [c['code'], U64 if c['signatures'] is None else c['signatures'], ci + 1, ai + 1]
    if c['code'] == 0:
        index = next(i for i, a in enumerate(c['anchors']) if accepted(a))
        count = len(chain) - int(len(chain) > 1 and chain[-1] == anchors[index])
        expected += [index, count, *c['chain'][0].public]
    return wire, expected

def main():
    mode = sys.argv[1]
    if mode == 'plain':
        certs = [leaf.encode(), ca.encode(), root.encode()]
        sys.stdout.buffer.write(b''.join(struct.pack('<Q', len(c)) + c for c in certs) + LEAF_PK)
        return
    cases = models() if mode == 'models' else openssl_cases()
    records = [record(c, layout) for c in cases for layout in [0, 1]]
    output = bytearray(struct.pack('<Q', len(records)))
    for wire, expected in records:
        output += struct.pack('<Q', len(wire)) + wire + struct.pack('<Q', len(expected)) + b''.join(struct.pack('<Q', n) for n in expected)
    sys.stdout.buffer.write(output)

if __name__ == '__main__': main()
