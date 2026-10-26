"""Runtime-only server credentials; all key generation/crypto is OpenSSL."""

import importlib.util
from pathlib import Path
import sys


sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1] / "openssl_tls" / "certificates.py"
SPEC = importlib.util.spec_from_file_location("tls_server_base_certificates", BASE)
BASE_CERTIFICATES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE_CERTIFICATES)
PASSPHRASE = "server fixture secret"


def generate(directory):
    directory = Path(directory).resolve()
    BASE_CERTIFICATES.generate(directory)
    BASE_CERTIFICATES.openssl(
        directory, "pkey", "-in", "valid.key", "-aes-256-cbc",
        "-passout", f"pass:{PASSPHRASE}", "-out", "encrypted.key",
    )
    BASE_CERTIFICATES.openssl(
        directory, "pkey", "-in", "encrypted.key", "-passin", f"pass:{PASSPHRASE}",
        "-check", "-noout",
    )
    (directory / "malformed.pem").write_bytes(b"this is not a PEM object\n")


if __name__ == "__main__":
    generate(sys.argv[1])
    print("openssl-tls-server runtime credentials: verified chains and explicit encrypted key")
