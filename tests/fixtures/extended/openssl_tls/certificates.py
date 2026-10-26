"""Create test-only certificates using the installed OpenSSL CLI.

No private keys or certificates are checked into the repository. All key
generation, signing and signature verification run in OpenSSL. Expiration is
fixed in the past; valid certificates are issued relative to the test run.
"""

import os
from pathlib import Path
import subprocess
import sys


def openssl(directory, *arguments, expected=0):
    result = subprocess.run(
        ["openssl", *map(str, arguments)],
        cwd=directory,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == expected, (
        arguments,
        result.returncode,
        result.stdout,
        result.stderr,
    )
    return result


def key(directory, name):
    openssl(
        directory,
        "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
        "-out", f"{name}.key",
    )


def request(directory, name, common_name):
    key(directory, name)
    openssl(
        directory,
        "req", "-new", "-sha256", "-key", f"{name}.key",
        "-subj", f"/CN={common_name}", "-out", f"{name}.csr",
    )


def issue(directory, name, authority, extensions, expired=False):
    arguments = [
        "ca", "-batch", "-notext", "-config", f"{authority}.cnf",
        "-extensions", extensions, "-in", f"{name}.csr", "-out", f"{name}.pem",
    ]
    if expired:
        arguments += ["-startdate", "20000101000000Z", "-enddate", "20010101000000Z"]
    openssl(directory, *arguments)


def authority_config(directory, name):
    (directory / f"{name}.database").write_text("")
    (directory / f"{name}.serial").write_text("1000\n")
    (directory / f"{name}.cnf").write_text(f"""
[ca]
default_ca=local
[local]
database={name}.database
serial={name}.serial
new_certs_dir=.
certificate={name}.pem
private_key={name}.key
default_md=sha256
default_days=2
unique_subject=no
policy=subject
[subject]
commonName=supplied
[intermediate]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:fixture.test,IP:127.0.0.1,IP:::1
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[wrong_purpose]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[without_san]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
""")


def generate(directory):
    os.umask(0o077)
    directory = Path(directory).resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name in ("root", "untrusted"):
        key(directory, name)
        openssl(
            directory,
            "req", "-new", "-x509", "-sha256", "-days", "2",
            "-key", f"{name}.key", "-subj", f"/CN=Lanius TLS Test {name}",
            "-addext", "basicConstraints=critical,CA:TRUE,pathlen:1",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            "-out", f"{name}.pem",
        )
    authority_config(directory, "root")
    request(directory, "intermediate", "Lanius TLS Test Intermediate")
    issue(directory, "intermediate", "root", "intermediate")
    authority_config(directory, "intermediate")
    for name, authority, extension in (
        ("valid", "root", "server"),
        ("expired", "root", "server"),
        ("chain", "intermediate", "server"),
        ("wrong-purpose", "root", "wrong_purpose"),
    ):
        request(directory, name, "subject-is-not-the-reference-identity")
        issue(directory, name, authority, extension, expired=name == "expired")
    request(directory, "cn-only", "localhost")
    issue(directory, "cn-only", "root", "without_san")
    (directory / "chain-full.pem").write_bytes(
        (directory / "chain.pem").read_bytes() + (directory / "intermediate.pem").read_bytes()
    )
    validate(directory)


def validate(directory):
    for identity in (("-verify_hostname", "localhost"), ("-verify_ip", "127.0.0.1")):
        openssl(directory, "verify", "-CAfile", "root.pem", "-purpose", "sslserver", *identity, "valid.pem")
    openssl(directory, "verify", "-CAfile", "root.pem", "-purpose", "sslserver",
            "-untrusted", "intermediate.pem", "-verify_hostname", "localhost", "chain.pem")
    openssl(directory, "verify", "-CAfile", "root.pem", "-purpose", "sslserver", "cn-only.pem")
    for arguments, reason in (
        (["-CAfile", "root.pem", "-verify_hostname", "wrong.invalid", "valid.pem"], b"hostname mismatch"),
        (["-CAfile", "root.pem", "-verify_ip", "127.0.0.2", "valid.pem"], b"IP address mismatch"),
        (["-CAfile", "untrusted.pem", "valid.pem"], b"unable to get local issuer certificate"),
        (["-CAfile", "root.pem", "expired.pem"], b"certificate has expired"),
        (["-CAfile", "root.pem", "chain.pem"], b"unable to get local issuer certificate"),
        (["-CAfile", "root.pem", "-purpose", "sslserver", "wrong-purpose.pem"], b"unsuitable certificate purpose"),
    ):
        result = openssl(directory, "verify", *arguments, expected=2)
        assert reason in result.stdout + result.stderr, (arguments, result)


if __name__ == "__main__":
    generate(sys.argv[1])
    print("openssl-tls certificates: 4 verified chains/identities, 6 rejected trust/identity/validity/purpose cases")
