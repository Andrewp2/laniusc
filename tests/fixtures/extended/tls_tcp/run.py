"""Bounded loopback-only real OpenSSL peers; production TLS stays in Lanius.

Wire output is length-prefixed byte strings, never JSON. Fault injection belongs
to strace and never fabricates successful short-send data. Fragmentation uses
real TCP forwarding; its copies are test plumbing, not a TLS implementation.
"""
import pathlib
import socket
import struct
import subprocess
import sys
import threading
import time

def stream_pattern(length, multiplier, increment):
    return bytes((i * multiplier + increment) % 256 for i in range(length))

def listener(small=False):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if small: sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2048)
    sock.bind(('127.0.0.1', 0))
    sock.listen(1)
    sock.settimeout(8)
    return sock

def connect(port, small=False):
    end = time.monotonic() + 5
    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if small: sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2048)
        try:
            sock.connect(('127.0.0.1', port))
            return sock
        except ConnectionRefusedError:
            sock.close()
            if time.monotonic() >= end: raise
            time.sleep(0.005)

def proxy(left, right, fragment, threads):
    def forward(source, destination):
        source.settimeout(12)
        destination.settimeout(12)
        try:
            while True:
                data = source.recv(fragment or 65536)
                if not data: break
                destination.sendall(data)
        except (OSError, TimeoutError): pass
        finally:
            try: destination.shutdown(socket.SHUT_WR)
            except OSError: pass
    for a, b in [(left, right), (right, left)]:
        thread = threading.Thread(target=forward, args=(a, b), daemon=True)
        thread.start()
        threads.append(thread)

def run(binary, directory, role, suite, length, mode, fault, fragment, transport, expected, root_name, exporter, group, peer_groups, calls):
    directory = pathlib.Path(directory)
    cipher = ['TLS_CHACHA20_POLY1305_SHA256', 'TLS_AES_128_GCM_SHA256'][suite]
    assert group in range(4) and peer_groups in ['X25519', 'P-256', 'X25519:P-256']
    common = ['-tls1_3', '-groups', peer_groups, '-sigalgs', 'ed25519', '-ciphersuites', cipher]
    peer = None
    resources, threads = [], []
    small = length >= 65537
    peer_input = stream_pattern(length, 37 if role else 53, 11 if role else 193)
    if transport == 'udp':
        native = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        native.connect(('127.0.0.1', 9))
    elif transport == 'unconnected':
        native = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    elif transport in ['eof', 'partial_eof']:
        local = listener()
        native = connect(local.getsockname()[1])
        remote, _ = local.accept()
        local.close()
        if transport == 'partial_eof': remote.sendall(b'\x16\x03')
        remote.shutdown(socket.SHUT_WR)
        resources.append(remote)
    elif role == 0:
        reservation = listener(small)
        port = reservation.getsockname()[1]
        reservation.close()
        command = ['openssl', 's_server', '-accept', f'127.0.0.1:{port}', '-cert', str(directory / 'leaf.pem'), '-cert_chain', str(directory / 'ca.pem'), '-key', str(directory / 'key.pem'), '-quiet', '-naccept', '1', '-ign_eof'] + common
        if exporter:
            command.remove('-quiet')
            command += ['-keymatexport', 'lanius-tcp-test', '-keymatexportlen', '32']
        peer = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        remote = connect(port, small)
        if fragment:
            local = listener(small)
            native = connect(local.getsockname()[1], small)
            bridge, _ = local.accept()
            local.close()
            resources += [bridge, remote]
            proxy(bridge, remote, fragment, threads)
        else: native = remote
    else:
        local = listener(small)
        port = local.getsockname()[1]
        command = ['openssl', 's_client', '-connect', f'127.0.0.1:{port}', '-CAfile', str(directory / 'root.pem'), '-no-CApath', '-no-CAstore', '-verify_return_error', '-verify_hostname', 'path.example', '-quiet', '-no_ign_eof'] + common
        if exporter:
            command.remove('-quiet')
            command += ['-nocommands', '-keymatexport', 'lanius-tcp-test', '-keymatexportlen', '32']
        peer = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        front, _ = local.accept()
        local.close()
        if fragment:
            local = listener(small)
            bridge = connect(local.getsockname()[1], small)
            native, _ = local.accept()
            local.close()
            resources += [front, bridge]
            proxy(front, bridge, fragment, threads)
        else: native = front
    if small: native.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2048)
    native.setblocking(transport == 'blocking')
    trace = directory / f'trace-{role}-{suite}-{mode}-{time.monotonic_ns()}.txt'
    argv = [str(binary), str(role), str(suite), (directory / root_name).read_bytes().hex(), (directory / 'chain.der').read_bytes().hex(), (directory / 'seed.bin').read_bytes().hex(), str(length), str(mode), str(calls), '0' if mode == 4 else '12000', str(int(expected)), str(group)]
    command = ['strace', '-qq', '-o', str(trace), '-s', '64', '-e', 'trace=mmap,mremap,munmap,brk,close,sendto,recvfrom,getrandom,fcntl,getsockopt,getpeername,poll,clock_gettime,shutdown', '-e', 'signal=none']
    if fault != '-': command += ['-e', 'inject=' + fault]
    command += argv
    native_process = subprocess.Popen(command, stdin=native, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    native.close()
    written, peer_stdout, peer_stderr = [], [], []
    delivered = threading.Event()
    export_ready, native_finished, first_application = threading.Event(), threading.Event(), threading.Event()
    if length == 0: delivered.set()
    if peer is not None:
        def drain(stream, parts, application):
            total = 0
            while True:
                chunk = stream.read1(65536)
                if not chunk: break
                parts.append(chunk)
                total += len(chunk)
                if application and total: first_application.set()
                if application and total >= length: delivered.set()
                if application and b'Keying material:' in b''.join(parts): export_ready.set()
        for stream, parts, application in [(peer.stdout, peer_stdout, True), (peer.stderr, peer_stderr, False)]:
            reader = threading.Thread(target=drain, args=(stream, parts, application), daemon=True)
            reader.start()
            threads.append(reader)
        def write_peer():
            try:
                if mode == 8:
                    # Ensure an independent peer write occurs after observing
                    # the first application byte under the requested epoch.
                    # RFC8446 permits postponing a KU response until that write.
                    peer.stdin.write(peer_input[:1])
                    peer.stdin.flush()
                    assert first_application.wait(12), 'KeyUpdate phase made no application progress'
                    peer.stdin.write(peer_input[1:])
                else: peer.stdin.write(peer_input)
                peer.stdin.flush()
                written.append(True)
                # The independent client closes only after receiving its echo;
                # stdin EOF must not terminate it before bidirectional data.
                if role == 1:
                    if exporter: export_ready.wait(12)
                    else: delivered.wait(12)
                else: native_finished.wait(18)
            except (OSError, BrokenPipeError): pass
            finally:
                try: peer.stdin.close()
                except OSError: pass
        thread = threading.Thread(target=write_peer, daemon=True)
        thread.start()
        threads.append(thread)
    try:
        native_out, native_err = native_process.communicate(timeout=18)
        native_finished.set()
        delivered.set()
        if peer is not None:
            peer.wait(timeout=5)
            for thread in threads: thread.join(timeout=1)
            peer_out, peer_err = b''.join(peer_stdout), b''.join(peer_stderr)
            peer_status = peer.returncode
        else: peer_out, peer_err, peer_status = b'', b'', 0
    except BaseException:
        native_process.kill()
        native_process.wait(timeout=2)
        if peer is not None:
            peer.kill()
            peer.wait(timeout=2)
        raise
    finally:
        for sock in resources: sock.close()
    # Success includes fixture assertions, not merely the TLS peer's exit.
    assert native_process.returncode == 0, (native_process.returncode, native_out, native_err, peer_err, trace.read_text())
    fields = [struct.pack('<q', peer_status), native_out, native_err, peer_out, peer_err, trace.read_bytes()]
    sys.stdout.buffer.write(b''.join(struct.pack('<Q', len(value)) + value for value in fields))

if __name__ == '__main__':
    assert len(sys.argv) == 16
    run(sys.argv[1], sys.argv[2], *(int(value) for value in sys.argv[3:7]), sys.argv[7], int(sys.argv[8]), sys.argv[9], bool(int(sys.argv[10])), sys.argv[11], bool(int(sys.argv[12])), int(sys.argv[13]), sys.argv[14], int(sys.argv[15]))
