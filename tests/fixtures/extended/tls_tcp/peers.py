"""Independent OpenSSL peer setup shared by TLS adapter/application tests.

Only test code imports the signed DER fixture builder. All private seeds here
are public deterministic test data; production obtains ephemeral entropy from
the OS and never imports this module. No subprocess supplies production TLS.
"""
import base64
import importlib.util
import pathlib
import subprocess
import sys

def signed_model():
    path = pathlib.Path(__file__).parents[1] / 'x509_path' / 'model.py'
    spec = importlib.util.spec_from_file_location('lanius_tls_peer_certificates', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module

def pem(kind, data):
    body = base64.b64encode(data).decode('ascii')
    return f'-----BEGIN {kind}-----\n' + '\n'.join(body[i:i + 64] for i in range(0, len(body), 64)) + f'\n-----END {kind}-----\n'

def fixtures(directory):
    directory = pathlib.Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    m = signed_model()
    # UTCTime's upper unambiguous year is2049. Keep these ordinary real-peer
    # fixtures valid throughout2020..2049; expiry controls use explicit variants.
    dates = dict(before=1577836800, after=2524607999)
    root = m.changed(m.root, **dates)
    ca = m.changed(m.ca, **dates)
    leaf = m.changed(m.leaf, sans=((2, b'path.example'), (7, bytes([127, 0, 0, 1])), (7, bytes(15) + b'\1')), **dates)
    wrong = m.changed(root, subject='Untrusted', issuer='Untrusted', public=m.OTHER_PK, signer=m.OTHER_SK)
    seed = m.LEAF_SK[:32]
    values = {
        'root.der': root.encode(), 'ca.der': ca.encode(), 'leaf.der': leaf.encode(),
        'wrong-root.der': wrong.encode(), 'chain.der': leaf.encode() + ca.encode(),
        'seed.bin': seed,
        'root.pem': pem('CERTIFICATE', root.encode()).encode(),
        'wrong-root.pem': pem('CERTIFICATE', wrong.encode()).encode(),
        'ca.pem': pem('CERTIFICATE', ca.encode()).encode(),
        'leaf.pem': pem('CERTIFICATE', leaf.encode()).encode(),
        'key.pem': pem('PRIVATE KEY', bytes.fromhex('302e020100300506032b657004220420') + seed).encode(),
    }
    for name, data in values.items(): (directory / name).write_bytes(data)
    return directory

def signature_fixtures(directory):
    """Real RSA -> P256 -> {RSA,P256,Ed25519} chains, independently verified.

    DER framing reuses the host fixture builder; OpenSSL generates keys, signs
    the exact TBS bytes and verifies every resulting leaf path. Fixed validity
    dates cover the fixture's explicit time as well as ordinary host UTC.
    """
    directory = pathlib.Path(directory)
    target = directory / 'signature'
    target.mkdir()
    m = signed_model()
    def openssl(*arguments, data=None):
        result = subprocess.run(['openssl', *map(str, arguments)], input=data,
                                capture_output=True, timeout=10)
        assert result.returncode == 0, (arguments, result.stderr[-2000:])
        return result.stdout
    for name, algorithm in [('root', 'RSA'), ('ca', 'EC'), ('rsa', 'RSA'), ('p256', 'EC')]:
        options = ['-pkeyopt', 'rsa_keygen_bits:2048'] if algorithm == 'RSA' else ['-pkeyopt', 'ec_paramgen_curve:P-256']
        openssl('genpkey', '-algorithm', algorithm, *options, '-out', target / (name + '-key.pem'))
    (target / 'mixed-key.pem').write_bytes((directory / 'key.pem').read_bytes())
    public = {name: openssl('pkey', '-in', target / (name + '-key.pem'), '-pubout', '-outform', 'DER')
              for name in ['root', 'ca', 'rsa', 'p256', 'mixed']}
    rsa_algorithm = m.seq(m.oid(1, 2, 840, 113549, 1, 1, 11), b'\x05\0')
    ec_algorithm = m.seq(m.oid(1, 2, 840, 10045, 4, 3, 2))
    def certificate(name, issuer, serial, is_ca):
        algorithm = rsa_algorithm if issuer == 'root' else ec_algorithm
        extensions = [m.extension(19, m.seq(b'\x01\x01\xff', m.integer(3 if name == 'root' else 1)) if is_ca else m.seq(), True),
                      m.extension(15, m.usage((5, 6) if is_ca else (0,)), True),
                      m.extension(37, m.seq(m.oid(1, 3, 6, 1, 5, 5, 7, 3, 1)))]
        if not is_ca:
            extensions.append(m.extension(17, m.seq(m.tlv(130, b'path.example'), m.tlv(135, bytes([127, 0, 0, 1])))))
        tbs = m.seq(m.tlv(160, m.integer(2)), m.integer(serial), algorithm,
                    m.name('Signature-' + issuer), m.seq(m.utc(1577836800), m.utc(2524607999)),
                    m.name('Signature-' + name), public[name], m.tlv(163, m.seq(*extensions)))
        signed = openssl('dgst', '-sha256', '-sign', target / (issuer + '-key.pem'), data=tbs)
        encoded = m.seq(tbs, algorithm, m.bitstring(signed))
        (target / (name + '.der')).write_bytes(encoded)
        (target / (name + '.pem')).write_text(pem('CERTIFICATE', encoded))
    certificate('root', 'root', 101, True)
    certificate('ca', 'root', 102, True)
    for index, name in enumerate(['rsa', 'p256', 'mixed']):
        certificate(name, 'ca', 103 + index, False)
        openssl('verify', '-auth_level', '2', '-attime', '1792843200', '-purpose', 'sslserver',
                '-verify_hostname', 'path.example', '-CAfile', target / 'root.pem',
                '-no-CApath', '-no-CAstore', '-untrusted', target / 'ca.pem', target / (name + '.pem'))
        variant = target / name
        variant.mkdir()
        for source, destination in [('root.der', 'root.der'), ('root.pem', 'root.pem'),
                                    ('ca.der', 'ca.der'), ('ca.pem', 'ca.pem'),
                                    (name + '.der', 'leaf.der'), (name + '.pem', 'leaf.pem'),
                                    (name + '-key.pem', 'key.pem')]:
            (variant / destination).write_bytes((target / source).read_bytes())
        (variant / 'chain.der').write_bytes((variant / 'leaf.der').read_bytes() + (variant / 'ca.der').read_bytes())
        (variant / 'server-chain.pem').write_bytes((variant / 'leaf.pem').read_bytes() + (variant / 'ca.pem').read_bytes())
        for filename in ['seed.bin', 'wrong-root.der']:
            (variant / filename).write_bytes((directory / filename).read_bytes())
    return target

if __name__ == '__main__':
    assert len(sys.argv) == 3 and sys.argv[1] in ['fixtures', 'signature-fixtures']
    (fixtures if sys.argv[1] == 'fixtures' else signature_fixtures)(sys.argv[2])
