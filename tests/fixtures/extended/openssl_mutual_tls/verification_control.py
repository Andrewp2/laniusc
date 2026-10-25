"""CPU-only native controls for the exact wrong-server-trust fixture.

The peer loads root.pem to verify client certificates. OpenSSL consequently
builds its outgoing server chain with that root too. This differs from a
leaf-only server that never loaded the root. No production code is used here.
"""
from pathlib import Path
import ssl
import sys
import tempfile
from certificates import generate, openssl


def check(directory):
    directory=Path(directory)
    server_context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.load_cert_chain(directory/'valid.pem',directory/'valid.key')
    server_context.verify_mode=ssl.CERT_REQUIRED
    server_context.load_verify_locations(directory/'root.pem')
    server_context.num_tickets=0
    server_context.minimum_version=server_context.maximum_version=ssl.TLSVersion.TLSv1_3
    client_context=ssl.create_default_context(cafile=directory/'untrusted.pem')
    client_context.minimum_version=client_context.maximum_version=ssl.TLSVersion.TLSv1_3
    client_context.load_cert_chain(directory/'client.pem',directory/'client.key')
    incoming_client,outgoing_client,incoming_server,outgoing_server=(ssl.MemoryBIO() for _ in range(4))
    client=client_context.wrap_bio(incoming_client,outgoing_client,server_side=False,server_hostname='localhost')
    server=server_context.wrap_bio(incoming_server,outgoing_server,server_side=True)
    failure=None
    for _ in range(64):
        for endpoint in (client,server):
            try: endpoint.do_handshake()
            except ssl.SSLWantReadError: pass
            except ssl.SSLCertVerificationError as error:
                assert endpoint is client
                failure=error
                break
        if outgoing_client.pending: incoming_server.write(outgoing_client.read())
        if outgoing_server.pending: incoming_client.write(outgoing_server.read())
        if failure: break
    assert failure and failure.verify_code==19, failure
    chain=client._sslobj.get_unverified_chain()
    assert len(chain)==2
    assert chain[-1].get_info()['subject']==((('commonName','Lanius TLS Test root'),),)
    # A second native interface distinguishes the supplied chain from the
    # earlier leaf-only expectation, without widening the accepted error set.
    leaf_only=openssl(directory,'verify','-CAfile','untrusted.pem','valid.pem',expected=2)
    with_root=openssl(directory,'verify','-CAfile','untrusted.pem','-untrusted','root.pem','valid.pem',expected=2)
    assert b'error 20 at' in leaf_only.stdout+leaf_only.stderr
    assert b'error 19 at' in with_root.stdout+with_root.stderr
    return failure.verify_code


if __name__=='__main__':
    if len(sys.argv)==2:
        check(sys.argv[1])
    else:
        with tempfile.TemporaryDirectory(prefix='mutual_tls_native_control_') as directory:
            generate(directory)
            check(directory)
    print('openssl-mutual-tls exact-peer native control: Python/OpenSSL code=19 chain=leaf+root; openssl-verify leaf-only=20 with-root=19')
