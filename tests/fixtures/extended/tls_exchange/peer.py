"""Test-only real CLI orchestration with independent OpenSSL-backed TLS peers."""
import os
import pathlib
import select
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time

# Shared test-only authenticated-record transformer; no production backend.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tls_tcp'))
import signature_proxy


def read_spec(path):
    data = memoryview(pathlib.Path(path).read_bytes())
    assert len(data) <= 65536
    at = 0
    def word():
        nonlocal at
        assert at + 4 <= len(data)
        value = struct.unpack_from('<I', data, at)[0]
        at += 4
        return value
    def field():
        nonlocal at
        size = word()
        assert size <= 8192 and size <= len(data) - at
        value = bytes(data[at:at + size])
        at += size
        return os.fsdecode(value)
    def values():
        count = word()
        assert count <= 16
        return [field() for _ in range(count)]
    assert word() == 1
    spec = dict(zip(('fixtures', 'input', 'trace', 'executable', 'role', 'peer'),
                    (field() for _ in range(6))))
    spec['arguments'] = values()
    spec['inject'] = values()
    spec['seconds'] = word()
    spec['closed_stdout'] = word()
    assert 1 <= spec['seconds'] <= 30 and spec['closed_stdout'] in (0, 1)
    assert at == len(data)
    return spec


def write_receipt(receipt, status, output, errors):
    target = sys.stdout.buffer
    target.write(struct.pack('<iBBB', status, receipt['clean_close'],
                             0 if receipt['reused'] is None else 1 + receipt['reused'],
                             receipt['error'] is not None))
    fields = [receipt['openssl'].encode(), (receipt['version'] or '').encode(),
              (receipt['cipher'] or '').encode(), (receipt['error'] or '').encode(),
              output or b'', errors, receipt['received'], receipt['sent']]
    for field in fields:
        assert len(field) <= 1049600
        target.write(struct.pack('<I', len(field)) + field)


def context(directory, server, mode):
    signature = mode.split('-') if mode.startswith('signature-') else None
    if signature:
        assert len(signature) in [4, 5] and signature[1] in ['rsa', 'p256', 'mixed']
        directory = directory / 'signature' / signature[1]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER if server else ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.maximum_version = ssl.TLSVersion.TLSv1_3
    p256 = signature[3] == 'p256' if signature else mode in ['p256', 'aes256-p256']
    ctx.set_ecdh_curve('prime256v1' if p256 else 'X25519')
    expected = ({'chacha': {'TLS_CHACHA20_POLY1305_SHA256'}, 'aes128': {'TLS_AES_128_GCM_SHA256'}, 'aes256': {'TLS_AES_256_GCM_SHA384'}}[signature[2]] if signature else
                {'TLS_AES_256_GCM_SHA384'} if mode.startswith('aes256-') else {'TLS_CHACHA20_POLY1305_SHA256', 'TLS_AES_128_GCM_SHA256'})
    active = {value['name'] for value in ctx.get_ciphers() if value['protocol'] == 'TLSv1.3'}
    assert active == expected, f'OpenSSL peer suite policy not applied: {active} != {expected}'
    if server:
        ctx.num_tickets = 0
        ctx.load_cert_chain(directory / 'server-chain.pem', directory / 'key.pem')
        # This peer and the application server deliberately accept anonymous
        # clients. Server authentication remains mandatory in each client.
        ctx.verify_mode = ssl.CERT_NONE
    else:
        ctx.load_verify_locations(cafile=directory / 'root.pem')
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.check_hostname = True
    return ctx


def wait(connection, writing, expires):
    remaining = expires - time.monotonic()
    if remaining <= 0:
        raise TimeoutError('bounded peer I/O expired')
    select.select([connection], [connection] if writing else [], [], min(0.1, remaining))


def echo(connection, receipt, expires):
    connection.setblocking(False)
    pending = b''
    while True:
        if pending:
            try:
                count = connection.send(pending)
                assert count > 0
                receipt['sent'] += pending[:count]
                pending = pending[count:]
            except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
                wait(connection, True, expires)
            continue
        try:
            data = connection.recv(16384)
            if not data:
                break
            receipt['received'] += data
            assert len(receipt['received']) <= 1048577
            pending = data
        except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
            wait(connection, False, expires)
    connection.settimeout(max(0.01, expires - time.monotonic()))
    connection.unwrap().close()
    receipt['clean_close'] = True


def client_exchange(connection, payload, receipt, expires):
    connection.setblocking(False)
    sent = 0
    while sent < len(payload) or len(receipt['received']) < len(payload):
        progress = False
        if sent < len(payload):
            try:
                count = connection.send(payload[sent:sent + 16384])
                assert count > 0
                receipt['sent'] += payload[sent:sent + count]
                sent += count
                progress = True
            except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
                pass
        try:
            data = connection.recv(16384)
            if not data:
                raise EOFError('echo closed before all authenticated response bytes')
            receipt['received'] += data
            assert len(receipt['received']) <= 1048577
            progress = True
        except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
            pass
        if not progress:
            wait(connection, sent < len(payload), expires)
    connection.settimeout(max(0.01, expires - time.monotonic()))
    connection.unwrap().close()
    receipt['clean_close'] = True


def main():
    spec = read_spec(sys.argv[1])
    directory = pathlib.Path(spec['fixtures'])
    payload = pathlib.Path(spec['input']).read_bytes()
    server = spec['role'] == 'serve'
    receipt = dict(received=b'', sent=b'', error=None, clean_close=False,
                   version=None, cipher=None, reused=None, openssl=ssl.OPENSSL_VERSION)
    stop = threading.Event()
    mutations, proxy_threads, proxy_sockets = [], [], []
    listener = None
    if not server:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(0.1)
        port = listener.getsockname()[1]
    else:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as choice:
            choice.bind(('127.0.0.1', 0))
            port = choice.getsockname()[1]
    endpoint = f'127.0.0.1:{port}'
    arguments = [str(value).replace('@ENDPOINT@', endpoint) for value in spec['arguments']]

    def peer():
        raw = None
        connection = None
        try:
            expires = time.monotonic() + 8
            if not server:
                while not stop.is_set():
                    try:
                        raw, _ = listener.accept()
                        break
                    except socket.timeout:
                        if time.monotonic() >= expires:
                            raise TimeoutError('no application client accepted')
                if raw is None:
                    return
                raw.settimeout(5)
                if spec.get('peer') == 'raw':
                    raw.sendall(b'not a TLS record')
                    raw.close()
                    return
                ctx = context(directory, True, spec['peer'])
                parts = spec['peer'].split('-')
                if parts[0] == 'signature' and len(parts) == 5:
                    assert parts[4] in ['proof', 'finished']
                    keylog = directory / ('signature-keylog-' + str(time.monotonic_ns()) + '.txt')
                    ctx.keylog_filename = str(keylog)
                    bridge, endpoint = socket.socketpair()
                    proxy_sockets.extend([raw, bridge])
                    mutations.append(signature_proxy.start(raw, bridge, keylog,
                        {'chacha': 0, 'aes128': 1, 'aes256': 2}[parts[2]],
                        15 if parts[4] == 'proof' else 20, proxy_threads))
                    raw = endpoint
                connection = ctx.wrap_socket(raw, server_side=True)
            else:
                while not stop.is_set():
                    try:
                        raw = socket.create_connection(('127.0.0.1', port), timeout=0.1)
                        break
                    except (ConnectionRefusedError, TimeoutError):
                        if time.monotonic() >= expires:
                            raise TimeoutError('application server never listened')
                        stop.wait(0.01)
                if raw is None:
                    return
                raw.settimeout(5)
                connection = context(directory, False, spec['peer']).wrap_socket(raw, server_hostname='path.example')
            receipt['version'] = connection.version()
            receipt['cipher'] = connection.cipher()[0]
            receipt['reused'] = connection.session_reused
            if spec.get('peer') == 'truncate':
                connection.sendall(b'authenticated-before-truncation')
                receipt['sent'] = b'authenticated-before-truncation'
                # Drain the client's data and close_notify before omitting our
                # own alert. Closing with unread TCP data would instead risk a
                # reset and test a transport error rather than TLS truncation.
                while True:
                    data = connection.recv(16384)
                    if not data:
                        break
                    receipt['received'] += data
                socket.socket(fileno=connection.detach()).close()
            elif server:
                client_exchange(connection, payload, receipt, expires)
            else:
                echo(connection, receipt, expires)
        except Exception as error:
            receipt['error'] = f'{type(error).__name__}: {error}'
        finally:
            if connection is not None:
                connection.close()
            if raw is not None:
                raw.close()

    seconds = spec.get('seconds', 9)
    command = ['timeout', '--kill-after=1s', str(seconds) + 's', 'strace', '-qq', '-o', spec['trace'],
               '-e', 'trace=rt_sigaction,openat,close,read,write,mmap,munmap,mremap,brk,socket,connect,bind,listen,accept4,poll,fcntl,getsockopt,getpeername,sendto,recvfrom,shutdown,getrandom,clock_gettime',
               '-e', 'signal=none']
    for rule in spec.get('inject', []):
        command += ['-e', 'inject=' + rule]
    command += [spec['executable'], *arguments]
    with open(spec['input'], 'rb') as source:
        stdout = subprocess.PIPE
        if spec.get('closed_stdout'):
            closed_reader, stdout = os.pipe()
            os.close(closed_reader)
        process = subprocess.Popen(command, stdin=source if not server else subprocess.DEVNULL,
                                   stdout=stdout, stderr=subprocess.PIPE)
        if spec.get('closed_stdout'):
            os.close(stdout)
        worker = threading.Thread(target=peer, daemon=True)
        worker.start()
        try:
            output, errors = process.communicate(timeout=seconds + 3)
        finally:
            stop.set()
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=2)
            worker.join(timeout=6)
            assert not worker.is_alive(), 'peer cleanup timed out'
            if listener is not None:
                listener.close()
            for sock in proxy_sockets:
                sock.close()
            for thread in proxy_threads:
                thread.join(timeout=1)
            for mutation in mutations:
                assert not mutation.errors and mutation.mutations == 1, (mutation.errors, mutation.mutations)
                assert mutation.proof_scheme == (2052 if spec['peer'].split('-')[1] == 'rsa' else 1027)
    write_receipt(receipt, process.returncode, output, errors)


if __name__ == '__main__':
    main()
