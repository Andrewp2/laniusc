"""Test-only mTLS credentials: native OpenSSL generates and verifies every key/cert."""
import importlib.util
from pathlib import Path
import sys
sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1] / 'openssl_tls' / 'certificates.py'
SPEC = importlib.util.spec_from_file_location('mutual_tls_base_certificates', BASE)
BASE_CERTIFICATES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE_CERTIFICATES)
openssl = BASE_CERTIFICATES.openssl
PASSPHRASE = 'mutual TLS fixture secret'


def generate(directory):
    directory = Path(directory).resolve()
    BASE_CERTIFICATES.generate(directory)
    BASE_CERTIFICATES.authority_config(directory, 'untrusted')
    for authority in ('root', 'intermediate', 'untrusted'):
        with (directory / f'{authority}.cnf').open('a') as out:
            out.write('''
[client]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=URI:urn:fixture:transport-client
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[client_no_eku]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
''')
    for name, authority, extension in (
        ('client', 'root', 'client'), ('client-alt', 'root', 'client'),
        ('client-chain', 'intermediate', 'client'), ('client-expired', 'root', 'client'),
        ('client-wrong-purpose', 'root', 'server'), ('client-untrusted', 'untrusted', 'client'),
        ('client-no-eku', 'root', 'client_no_eku'),
    ):
        BASE_CERTIFICATES.request(directory, name, name)
        BASE_CERTIFICATES.issue(directory, name, authority, extension, expired=name=='client-expired')
    (directory/'client-chain-full.pem').write_bytes((directory/'client-chain.pem').read_bytes() + (directory/'intermediate.pem').read_bytes())
    openssl(directory,'pkey','-in','client.key','-aes-256-cbc','-passout',f'pass:{PASSPHRASE}','-out','client-encrypted.key')
    openssl(directory,'pkey','-in','client-encrypted.key','-passin',f'pass:{PASSPHRASE}','-check','-noout')
    (directory/'malformed.pem').write_bytes(b'this is not a PEM object\n')
    for name in ('client','client-alt','client-no-eku'):
        openssl(directory,'verify','-CAfile','root.pem','-purpose','sslclient',f'{name}.pem')
    openssl(directory,'verify','-CAfile','root.pem','-purpose','sslclient','-untrusted','intermediate.pem','client-chain.pem')
    for name, reason in [('client-expired',b'certificate has expired'),('client-wrong-purpose',b'unsuitable certificate purpose'),('client-untrusted',b'unable to get local issuer certificate')]:
        result=openssl(directory,'verify','-CAfile','root.pem','-purpose','sslclient',f'{name}.pem',expected=2)
        assert reason in result.stdout+result.stderr,(name,result)


if __name__=='__main__':
    generate(sys.argv[1])
    print('openssl-mutual-tls native credential generator: client chains/purpose/expiry and encrypted key verified')
