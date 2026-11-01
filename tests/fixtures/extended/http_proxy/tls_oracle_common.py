"""Shared pieces of the TLS oracles: a throwaway self-signed certificate
(made by the openssl command) and Python ssl client wrappers."""
import os, ssl, subprocess


def certificate(directory):
    cert, key = os.path.join(directory, "cert.pem"), os.path.join(directory, "key.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
                    "-keyout", key, "-out", cert, "-days", "2", "-subj", "/CN=localhost",
                    "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)
    return cert, key


def wrapper(cert, protocols):
    """A socket wrapper offering protocols by ALPN (None: no ALPN)."""
    context = ssl.create_default_context(cafile=cert)
    if protocols:
        context.set_alpn_protocols(protocols)
    # A missing close_notify must show as an error, not a clean EOF.
    return lambda s: context.wrap_socket(s, server_hostname="localhost", suppress_ragged_eofs=False)
