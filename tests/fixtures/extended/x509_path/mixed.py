"""Independent OpenSSL signatures and explicit ordered-path expectations.

This is a CPU test corpus, never a production implementation. Real OpenSSL
verification checks the common-profile complete paths. Cache, local policy,
ordered candidate and resource controls have explicit separate expectations.
"""
import base64
import dataclasses
import importlib.util
import pathlib
import struct
import subprocess
import sys
import tempfile
import model as ed

U64 = (1 << 64) - 1
MAX_WORK = 1073741824
MESSAGE = b'owned x509 leaf key after all source retirement'
PKCS = ed.seq(ed.oid(1, 2, 840, 113549, 1, 1, 11), b'\x05\0')
EC = ed.seq(ed.oid(1, 2, 840, 10045, 4, 3, 2))
SHA = ed.seq(ed.oid(2, 16, 840, 1, 101, 3, 4, 2, 1), b'\x05\0')
PSS = ed.seq(ed.oid(1, 2, 840, 113549, 1, 1, 10), ed.seq(ed.tlv(160, SHA), ed.tlv(161, ed.seq(ed.oid(1, 2, 840, 113549, 1, 1, 8), SHA)), ed.tlv(162, ed.integer(32))))
UNKNOWN = ed.seq(ed.oid(1, 2, 3, 4))

# Reuse the independently exercised foundation tariff oracle, not production
# source or observed native counters. The path composition below uses host DER
# facts and the explicit storage/handoff contract.
_spec = importlib.util.spec_from_file_location('path_signature_tariffs', pathlib.Path(__file__).parent.parent / 'signature/model.py')
shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shared)
SLOT_STORAGE_WORK = 524288
KEY_COPY_WORK = 131072


def command(*args):
    got = subprocess.run(['openssl', *map(str, args)], capture_output=True, timeout=10)
    assert got.returncode == 0, (args, got.stdout, got.stderr)
    return got.stdout


@dataclasses.dataclass
class Key:
    path: pathlib.Path
    spki: bytes
    kind: int

    def sign(self, message, pss=False):
        source = self.path.with_suffix('.message')
        source.write_bytes(message)
        if self.kind == 0:
            result = command('pkeyutl', '-sign', '-rawin', '-inkey', self.path, '-in', source)
        else:
            args = ['dgst', '-sha256', '-sign', self.path]
            if self.kind == 2 and pss:
                args += ['-sigopt', 'rsa_padding_mode:pss', '-sigopt', 'rsa_pss_saltlen:32']
            result = command(*args, source)
        return result

    def proof(self):
        return (2055 if self.kind == 0 else 1027 if self.kind == 1 else 2052), self.sign(MESSAGE, self.kind == 2)


def key(folder, label, kind):
    path = folder / (label + '.pem')
    if kind == 0:
        seed = folder / (label + '.der')
        seed.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + ed.hashlib.sha256(('mixed-path:' + label).encode()).digest())
        path.write_bytes(command('pkey', '-inform', 'DER', '-in', seed))
    elif kind == 1:
        path.write_bytes(command('genpkey', '-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256'))
    else:
        path.write_bytes(command('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048'))
    return Key(path, command('pkey', '-in', path, '-pubout', '-outform', 'DER'), kind)


def cert(subject, issuer, public, signer, ca=False, pss=False, spki=None, algorithm=None):
    algorithm = algorithm or (ed.ED if signer.kind == 0 else EC if signer.kind == 1 else PSS if pss else PKCS)
    extensions = [ed.extension(19, ed.seq(*([b'\x01\x01\xff', ed.integer(4)] if ca else [])), True),
                  ed.extension(15, ed.usage((5, 6) if ca else (0,)), True)]
    if not ca:
        extensions += [ed.extension(37, ed.seq(ed.oid(1, 3, 6, 1, 5, 5, 7, 3, 1))),
                       ed.extension(17, ed.seq(ed.tlv(130, b'path.example')))]
    serial = int.from_bytes(ed.hashlib.sha256((subject + issuer).encode()).digest()[:8], 'big') or 1
    tbs = ed.seq(ed.tlv(160, ed.integer(2)), ed.integer(serial), algorithm, ed.name(issuer),
                 ed.seq(ed.utc(ed.NOW - 86400), ed.utc(ed.NOW + 86400)), ed.name(subject),
                 spki or public.spki, ed.tlv(163, ed.seq(*extensions)))
    return ed.seq(tbs, algorithm, ed.bitstring(signer.sign(tbs, pss)))


def rewrite_algorithm(value, algorithm):
    outer = ed.children(ed.one(value)[1])
    fields = ed.children(outer[0][1])
    fields[2] = (48, b'', algorithm)
    return ed.seq(ed.seq(*(field[2] for field in fields)), algorithm, outer[2][2])


def pem(value):
    return b'-----BEGIN CERTIFICATE-----\n' + base64.encodebytes(value) + b'-----END CERTIFICATE-----\n'


def oracle(folder, chain, anchor, accepted):
    root, leaf, extra = [folder / name for name in ['anchor.pem', 'leaf.pem', 'extra.pem']]
    root.write_bytes(pem(anchor)); leaf.write_bytes(pem(chain[0])); extra.write_bytes(b''.join(map(pem, chain[1:])))
    args = ['openssl', 'verify', '-no-CAfile', '-no-CApath', '-no-CAstore', '-trusted', str(root),
            '-attime', str(ed.NOW), '-purpose', 'sslserver', '-verify_hostname', 'path.example']
    if len(chain) > 1:
        args += ['-untrusted', str(extra)]
    got = subprocess.run([*args, str(leaf)], capture_output=True, timeout=10)
    assert (got.returncode == 0) == accepted, (got.stdout, got.stderr)


def corpus(folder):
    er, el, ec = [key(folder, label, 0) for label in ['ed-root', 'ed-leaf', 'ed-ca']]
    pr, pc = [key(folder, label, 1) for label in ['ec-root', 'ec-ca']]
    rr, rc = [key(folder, label, 2) for label in ['rsa-root', 'rsa-ca']]
    eroot = cert('Ed Root', 'Ed Root', er, er, True)
    proot = cert('EC Root', 'EC Root', pr, pr, True)
    rroot = cert('RSA Root', 'RSA Root', rr, rr, True)
    pca = cert('EC CA', 'RSA Root', pc, rr, True)
    rca = cert('RSA CA', 'EC Root', rc, pr, True)
    eleaf = cert('Ed leaf', 'Ed Root', el, er)
    cases = []

    def add(label, chain, anchors, leaf_key, code=0, attempts=None, mode=0, policy=0, index=0, count=None, external=None, app=True):
        if external is not None:
            oracle(folder, chain, anchors[index], external)
        proof_id, proof = leaf_key.proof()
        cases.append(dict(label=label, chain=chain, anchors=anchors, kind=leaf_key.kind, code=code,
                          attempts=attempts, mode=mode, policy=policy, index=index,
                          count=len(chain) if count is None else count, proof_id=proof_id, proof=proof, app=app))

    mixed = [cert('Ed under EC', 'EC CA', el, pc), pca]
    reverse = [cert('Ed under RSA', 'RSA CA', el, rc, pss=True), rca]
    rsa_leaf = cert('RSA leaf', 'Ed Root', rc, er)
    ec_leaf = cert('EC leaf', 'Ed Root', pc, er)
    pss_leaf = cert('Ed PSS leaf', 'RSA Root', el, rr, pss=True)
    pkcs_leaf = cert('Ed PKCS leaf', 'RSA Root', el, rr)
    add('rsa-root-ec-ca-ed-leaf', mixed, [rroot], el, attempts=2, external=True)
    add('ec-root-rsa-ca-ed-leaf', reverse, [proot], el, attempts=2, external=True)
    add('ed-root-rsa-leaf', [rsa_leaf], [eroot], rc, attempts=1, external=True)
    add('ed-root-ec-leaf', [ec_leaf], [eroot], pc, attempts=1, external=True)
    add('rsa-pss-certificate', [pss_leaf], [rroot], el, attempts=1, external=True)
    add('rsa-pkcs-certificate', [pkcs_leaf], [rroot], el, attempts=1, external=True)
    add('ec-signs-rsa-leaf', [cert('RSA under EC', 'EC Root', rc, pr)], [proot], rc, attempts=1, external=True)
    add('mixed-exact-root-copy', [*mixed, rroot], [rroot], el, attempts=2, count=2, external=True)
    add('ed-policy-allows-rsa-subject', [rsa_leaf], [eroot], rc, attempts=1, policy=1, app=False)
    add('ecdsa-policy-rejects-rsa-edge', mixed, [rroot], el, 14, attempts=1, policy=2, app=False)
    add('pss-only-policy', [pss_leaf], [rroot], el, attempts=1, policy=3, app=False)
    add('pkcs-only-policy', [pkcs_leaf], [rroot], el, attempts=1, policy=4, app=False)
    add('proof-policy-excludes-pkcs-certificate', [pkcs_leaf], [rroot], el, 14, attempts=0, policy=5, app=False)
    for policy in [6, 7, 8, 9]:
        add('invalid-local-policy-' + str(policy), [eleaf], [eroot], el, 14, attempts=0, mode=1, policy=policy, app=False)
    weird_root = rewrite_algorithm(eroot, PKCS)
    add('anchor-self-signature-policy-exception', [eleaf], [weird_root], el, attempts=1, policy=1, app=False)
    add('anchor-copy-self-signature-policy-exception', [eleaf, weird_root], [weird_root], el, attempts=1, policy=1, count=1, app=False)
    unsupported_spki = ed.seq(UNKNOWN, ed.bitstring(bytes(32)))
    unused = cert('Unused', 'Unused', ec, ec, True, spki=unsupported_spki)
    add('unlinked-key-never-imported', [eleaf], [unused, eroot], el, attempts=1, mode=2, index=1)
    bad_linked = cert('Ed Root', 'Ed Root', ec, ec, True, spki=unsupported_spki)
    add('linked-import-failure-then-valid', [eleaf], [bad_linked, eroot], el, attempts=1, index=1)
    wrong_key = cert('Ed Root', 'Ed Root', ec, ec, True)
    add('failed-linked-signature-then-valid', [eleaf], [wrong_key, eroot], el, attempts=2, mode=3, index=1)
    add('failed-linked-exhausts-shared-signatures', [eleaf], [wrong_key, eroot], el, 12, attempts=1, mode=4, app=False)
    add('poisoned-cache-cleared', mixed, [rroot], el, attempts=2, mode=1)
    add('same-scratch-fresh-validation', [rsa_leaf], [eroot], rc, attempts=1, mode=5)
    add('bad-metadata-keeps-scratch', [eleaf], [eroot], el, 1, attempts=0, mode=6, app=False)
    add('initial-work-denial-keeps-scratch', [eleaf], [eroot], el, 11, attempts=0, mode=7, app=False)
    add('parse-failure-clears-every-cache', [eleaf], [eroot, b'\x30\x81'], el, 9, attempts=0, mode=8, app=False)
    tampered = bytearray(mixed[0]); tampered[-1] ^= 1
    add('mixed-ecdsa-signature-tamper', [bytes(tampered), pca], [rroot], el, 17, attempts=1, external=False)
    tampered = bytearray(pss_leaf); tampered[-1] ^= 1
    add('mixed-rsa-signature-tamper', [bytes(tampered)], [rroot], el, 17, attempts=1, external=False)
    add('unsupported-child-algorithm', [rewrite_algorithm(eleaf, UNKNOWN)], [eroot], el, 14, attempts=0)
    boundary = dict(cases[0], label='issuer-import-work-limit-index', code=11, attempts=0, app=False, error_indices=(1, -1))
    boundary['work'] = exact_path_work(boundary, stop_import=1)
    cases.append(boundary)
    return cases


def certificate_facts(value):
    outer = ed.children(ed.one(value)[1])
    fields = ed.children(outer[0][1])
    spki = fields[6][2]
    key_fields = ed.children(fields[6][1])
    algorithm_oid = ed.children(key_fields[0][1])[0][1]
    kind = 0 if algorithm_oid == bytes.fromhex('2b6570') else 1 if algorithm_oid == bytes.fromhex('2a8648ce3d0201') else 2
    key = dict(kind=kind, spki=spki)
    if kind == 2:
        # Unknown algorithms are not silently treated as RSA by the cost peer.
        if algorithm_oid != bytes.fromhex('2a864886f70d010101'):
            raise ValueError('unsupported SPKI')
        integers = ed.children(ed.one(key_fields[1][1][1:])[1])
        key.update(n=int.from_bytes(integers[0][1], 'big'), e=int.from_bytes(integers[1][1], 'big'))
    extensions = ed.children(ed.one(fields[7][1])[1])
    return dict(encoded=value, tbs=outer[0][2], algorithm=fields[2][2], issuer=fields[3][2], subject=fields[5][2], key=key,
                oid_length=len(algorithm_oid), extensions=extensions, signature=outer[2][1][1:])


class ImportBoundary(Exception):
    pass


def exact_path_work(c, stop_import=None):
    """Published abstract allowance over independent parsed certificate facts.

    This oracle covers successful generated paths, including failed-signature
    candidate continuation. Unsupported-key candidates keep explicit outcome
    expectations without asserting an unrelated successful-import formula.
    """
    peers = [certificate_facts(v) for v in c['chain']]
    roots = [certificate_facts(v) for v in c['anchors']]
    all_certs = peers + roots
    cached = set()
    work = (len(all_certs) * (SLOT_STORAGE_WORK + 1)) + 1

    def compare(a, b):
        nonlocal work
        work += len(a) + len(b) + 1
        return a == b

    def authority(a, b):
        return compare(a['subject'], b['subject']) and compare(a['key']['spki'], b['key']['spki'])

    def imported(index):
        nonlocal work
        work += KEY_COPY_WORK
        if index not in cached:
            cert = all_certs[index]
            work += cert['oid_length'] + 1
            if index == stop_import:
                raise ImportBoundary(work)
            work += shared.import_work(cert['key']) + 2 * KEY_COPY_WORK
            cached.add(index)

    def policy(index):
        nonlocal work
        cert = all_certs[index]
        work += 19
        imported(index)
        path = None
        for extension in cert['extensions']:
            parts = ed.children(extension[1])
            oid = parts[0][1]
            work += len(oid) + 1
            if oid == bytes.fromhex('551d25'):
                for purpose in ed.children(ed.one(parts[-1][1])[1]):
                    work += len(purpose[1]) + 1
            if oid == bytes.fromhex('551d11'):
                work += len(ed.children(ed.one(parts[-1][1])[1]))
            if oid == bytes.fromhex('551d13'):
                values = ed.children(ed.one(parts[-1][1])[1])
                path = next((item[1] for item in values if item[0] == 2), None)
        if path is not None:
            work += len(path) + 1

    def signature(child, issuer):
        nonlocal work
        algorithm = child['algorithm']
        oid = ed.children(ed.one(algorithm)[1])[0][1]
        scheme = {bytes.fromhex('2b6570'): 0, bytes.fromhex('2a8648ce3d040302'): 1,
                  bytes.fromhex('2a864886f70d01010b'): 2, bytes.fromhex('2a864886f70d01010a'): 3}[oid]
        work += len(oid) + 1 + shared.common(algorithm) * (2 if scheme >= 2 else 1)
        work += len(child['tbs']) + 97 + 2 * KEY_COPY_WORK
        if scheme == 1:
            work += shared.common(child['signature'])
        work += shared.verify_work(issuer['key'], scheme, child['tbs'])

    try:
        for values in [peers, roots]:
            for index, cert in enumerate(values):
                for earlier in values[:index]:
                    assert not authority(cert, earlier)
        for index, cert in enumerate(peers):
            policy(index)
            if index:
                compare(cert['subject'], cert['issuer'])
            if index + 1 < len(peers):
                assert compare(cert['issuer'], peers[index + 1]['subject'])
                imported(index + 1)
                signature(cert, peers[index + 1])
        for anchor_index, anchor in enumerate(roots):
            count = len(peers)
            stripped = count > 1 and compare(peers[-1]['encoded'], anchor['encoded'])
            if stripped:
                count -= 1
            tail = peers[count - 1]
            if not compare(tail['issuer'], anchor['subject']):
                continue
            policy(len(peers) + anchor_index)
            for cert in peers[1:count]:
                compare(cert['subject'], cert['issuer'])
            for cert in peers[:count]:
                assert not authority(cert, anchor)
            if not stripped:
                signature(tail, anchor)
            if anchor_index == c['index']:
                return work + 2 * KEY_COPY_WORK
        raise AssertionError('missing expected anchor')
    except ImportBoundary as boundary:
        return boundary.args[0]



def record(c, layout, work=MAX_WORK, signatures=64):
    work = c.get('work', work)
    if c['mode'] == 4:
        signatures = 1
    if c['mode'] == 7:
        work = 0
    fields = [layout, c['mode'], c['policy'], work, signatures, len(c['chain']), len(c['anchors']), c['proof_id'], len(c['proof'])]
    wire = struct.pack('<9Q', *fields)
    for data in c['chain'] + c['anchors']:
        wire += struct.pack('<Q', len(data)) + data
    wire += c['proof']
    ci, ai = c.get('error_indices', (None, None))
    expected = [c['code'], U64 if c['attempts'] is None else c['attempts'], U64 if ci is None else ci + 1, U64 if ai is None else ai + 1]
    if not c['code']:
        try:
            work_expected = exact_path_work(c)
        except (ValueError, KeyError):
            work_expected = U64
        expected += [c['kind'], c['index'], c['count'], work_expected]
    return wire, expected


def main():
    with tempfile.TemporaryDirectory(prefix='x509_mixed_openssl_') as temporary:
        cases = corpus(pathlib.Path(temporary))
        if sys.argv[1] == 'app':
            for c in cases:
                if not c['app'] or c['mode'] != 0 or c['policy'] != 0 or len(c['anchors']) != 1 or 'work' in c:
                    continue
                values = [c['label'].encode(), c['anchors'][c['index']], b''.join(c['chain']), b'dns', b'path.example', str(ed.NOW).encode()]
                status = 0 if c['code'] == 0 else 5
                sys.stdout.buffer.write(struct.pack('<7I', *(len(v) for v in values), status) + b''.join(values))
            return
        if sys.argv[1] == 'seams':
            names = {'rsa-root-ec-ca-ed-leaf', 'ec-root-rsa-ca-ed-leaf', 'ed-root-rsa-leaf', 'failed-linked-signature-then-valid'}
            cases = [c for c in cases if c['label'] in names]
        else:
            assert sys.argv[1] == 'models'
        records = [record(c, layout) for c in cases for layout in [0, 1]]
        output = bytearray(struct.pack('<Q', len(records)))
        for wire, expected in records:
            output += struct.pack('<Q', len(wire)) + wire + struct.pack('<Q', len(expected)) + struct.pack('<' + 'Q' * len(expected), *expected)
        sys.stdout.buffer.write(output)


if __name__ == '__main__':
    main()
