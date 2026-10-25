"""Independent typed-policy/entropy/SEC1/work admission checks, not a peer trust seam."""
import ctypes
import importlib.util
import pathlib
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('connection_wire_peer', HERE/'peer.py')
wire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wire)
Q = lambda *values: struct.pack('<'+'Q'*len(values), *values)
U16 = wire.U16
P_WORK, X_WORK, SCHEDULE = 67108864, 1048576, 131072
DEFAULT = 268435456
POLICIES = [(29,), (23,), (29, 23), (23, 29), (29, 29)]
P_PUBLIC = wire.P256.encode(wire.P256.G)


def ext(kind, data):
    return U16(kind)+U16(len(data))+data


def client_frame(policy, initial):
    groups = b''.join(U16(g) for g in policy)
    extensions = ext(43, b'\x02\x03\x04')+ext(10, U16(len(groups))+groups)
    extensions += ext(13, b'\0\x02\x08\x07')+ext(50, b'\0\x02\x08\x07')
    key = b''
    if initial:
        if initial == 23:
            public = P_PUBLIC
        else:
            public = ctypes.create_string_buffer(32)
            assert wire.material.SODIUM.crypto_scalarmult_curve25519_base(public, bytes(range(33, 65))) == 0
            public = public.raw
        key = U16(initial)+U16(len(public))+public
    extensions += ext(51, U16(len(key))+key)
    body = b'\x03\x03'+bytes(range(1, 33))+b'\0\0\x04\x13\x03\x13\x01\x01\0'+U16(len(extensions))+extensions
    return b'\x01'+len(body).to_bytes(3, 'big')+body


def server_packet(group, public):
    extensions = ext(43, b'\x03\x04')+ext(51, U16(group)+U16(len(public))+public)
    body = b'\x03\x03'+b'S'*32+b'\0\x13\x03\0'+U16(len(extensions))+extensions
    frame = b'\x02'+len(body).to_bytes(3, 'big')+body
    return b'\x16\x03\x03'+U16(len(frame))+frame


def public_cost(policy):
    return (X_WORK if 29 in policy else 0)+(P_WORK if 23 in policy else 0)


def setup_cost(policy, initial):
    n = len(client_frame(policy, initial))
    return public_cost(policy)+(4096+32*n)+(1024+8*n)


def exchange_cost(policy, initial, packet):
    # Documented semantic tariffs: wire ingress, incoming record, complete SH,
    # selected P-256 exchange and SHA256 schedule. No elapsed-time assertion.
    return setup_cost(policy, initial)+2*len(packet)+(1024+8*len(packet))+(4096+32*(len(packet)-5))+P_WORK+SCHEDULE


def run(executable):
    cases = []
    def add(policy, initial, length, scalar=0, metadata=0, work=DEFAULT, packet=b'', status=0, feed=0, exact_remaining=None):
        for layout in (0, 1):
            cases.append((Q(layout, policy, initial, length, scalar, metadata, work, len(packet))+packet,
                          (policy, initial, work, packet, status, feed, exact_remaining)))
    for policy, initial, length in [(0, 29, 64), (1, 23, 64), (2, 29, 96), (3, 23, 96)]:
        add(policy, initial, length)
    add(1, 23, 63, status=2)
    add(2, 29, 64, status=2)
    add(1, 23, 64, metadata=1, status=1)
    for scalar in (1, 2, 3):
        add(1, 23, 64, scalar=scalar, status=3)
        add(2, 29, 96, scalar=scalar, status=3)
    add(3, 23, 96, scalar=1, status=3)
    add(4, 29, 64, status=4)
    add(0, 23, 64, status=4)
    add(0, 29, 64, work=X_WORK-1, status=5)
    add(1, 23, 64, work=P_WORK-1, status=5)
    add(2, 29, 96, work=P_WORK+X_WORK-1, status=5)
    for public in [P_PUBLIC[:33], b'\x02'+P_PUBLIC[1:33], b'\0'+P_PUBLIC[1:]]:
        add(1, 23, 64, packet=server_packet(23, public), feed=112)
    add(1, 23, 64, packet=server_packet(29, bytes(range(32))), feed=112)
    add(1, 23, 64, packet=server_packet(23, b'\x04'+bytes(64)), feed=6)
    valid = server_packet(23, P_PUBLIC)
    needed = exchange_cost((23,), 23, valid)
    add(1, 23, 64, packet=valid, work=needed, exact_remaining=0)
    add(1, 23, 64, packet=valid, work=needed-1, feed=5)
    with tempfile.TemporaryDirectory(prefix='tls_group_admission_') as directory:
        trace = pathlib.Path(directory)/'memory.trace'
        result = subprocess.run(['strace','-qq','-o',str(trace),'-e','trace=mmap,munmap,mremap,brk','-e','signal=none',executable],
                                input=Q(len(cases))+b''.join(case[0] for case in cases),capture_output=True,timeout=40)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, len(result.stdout), result.stdout[-64:].hex(), result.stderr)
        assert trace.read_text() == '', 'engine admission allocated'
        r = wire.Reader(result.stdout)
        for number, (_, expected) in enumerate(cases):
            policy_id, initial, budget, packet, status, feed, remaining = expected
            policy = POLICIES[policy_id]
            hello = r.block()
            actual = [r.word() for _ in range(8)]
            assert actual[0] == status and actual[1] == feed, (number, actual, expected)
            assert actual[2] == len(packet) and actual[4] == int(feed != 0), (number, actual)
            if status:
                assert hello == b'' and actual[3] == 0
            else:
                frame = client_frame(policy, initial)
                assert hello == b'\x16\x03\x01'+U16(len(frame))+frame, (number, hello.hex())
                assert actual[3] <= budget
                if not packet:
                    assert actual[3] == budget-setup_cost(policy, initial), (number, actual, setup_cost(policy, initial))
                if remaining is not None:
                    assert actual[3] == remaining, (number, actual)
            if policy_id == 4:
                assert actual[5:] == [0, 0, 0]
            else:
                assert actual[5:] == ([96, 32, 64] if len(policy) == 2 else [64, 32 if policy == (29,) else 0, 32 if policy == (23,) else 0])
        assert r.at == len(r.data)
    print(f'tls connection group admissions: {len(cases)} accepted')


if __name__ == '__main__':
    run(sys.argv[1])
