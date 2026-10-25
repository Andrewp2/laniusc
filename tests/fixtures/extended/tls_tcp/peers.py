"""Independent OpenSSL peer setup shared by TLS adapter/application tests.

Only test code imports the signed DER fixture builder. All private seeds here
are public deterministic test data; production obtains ephemeral entropy from
the OS and never imports this module. No subprocess supplies production TLS.
"""
import base64
import importlib.util
import pathlib
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

if __name__ == '__main__':
    assert len(sys.argv) == 3 and sys.argv[1] == 'fixtures'
    fixtures(sys.argv[2])
