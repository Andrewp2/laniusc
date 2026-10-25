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


def client_frame(policy, initial, suites):
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
    ciphers=b''.join(U16(s) for s in suites)
    body = b'\x03\x03'+bytes(range(1, 33))+b'\0'+U16(len(ciphers))+ciphers+b'\x01\0'+U16(len(extensions))+extensions
    return b'\x01'+len(body).to_bytes(3, 'big')+body


def server_packet(group, public, suite=4867):
    extensions = ext(43, b'\x03\x04')+ext(51, U16(group)+U16(len(public))+public)
    body = b'\x03\x03'+b'S'*32+b'\0'+U16(suite)+b'\0'+U16(len(extensions))+extensions
    frame = b'\x02'+len(body).to_bytes(3, 'big')+body
    return b'\x16\x03\x03'+U16(len(frame))+frame


def public_cost(policy):
    return (X_WORK if 29 in policy else 0)+(P_WORK if 23 in policy else 0)


def setup_cost(policy, initial, suites=(4867,4865)):
    n = len(client_frame(policy, initial, suites))
    return public_cost(policy)+(4096+32*n)+(1024+8*n)


def exchange_cost(policy, initial, packet, suites=(4867,4865), sha384=False):
    # Documented semantic tariffs: wire ingress, incoming record, complete SH,
    # selected P-256 exchange and SHA256 schedule. No elapsed-time assertion.
    ecdh = X_WORK+SCHEDULE if initial==29 else P_WORK+SCHEDULE
    cost = setup_cost(policy,initial,suites)+2*len(packet)+(1024+8*len(packet))+(4096+32*(len(packet)-5))+ecdh
    if sha384:
        stream=lambda n:16384*((n+127)//128+1)+16384+32*(n+256)
        snapshot=2*16384+12288+32*(128+48)
        e=wire.sha384_expansion_cost;h=wire.sha384_hmac_cost;hashed=wire.sha384_hash_cost
        schedule=2*h(48)+h(32)+2*hashed(0)+2*e(7,48,48)+2*e(12,48,48)
        owner=e(3,0,32)+e(2,0,12)+196608
        cost+=12288+stream(len(client_frame(policy,initial,suites)))+stream(len(packet)-5)+schedule+snapshot+2*owner
    return cost


def run(executable):
    cases = []
    def add(policy, initial, length, scalar=0, metadata=0, work=DEFAULT, packet=b'', status=0, feed=0, exact_remaining=None, suite_policy=0):
        for layout in (0, 1):
            cases.append((Q(layout, policy, initial, length, scalar, metadata, work, len(packet),suite_policy)+packet,
                          (policy, initial, work, packet, status, feed, exact_remaining,suite_policy)))
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
    for suite_policy in (3,4,5):add(0,29,64,suite_policy=suite_policy,status=4)
    for group_policy,initial,length in [(0,29,64),(1,23,64),(2,29,96)]:
        pub=P_PUBLIC if initial==23 else wire.public_key((29,),29)
        packet=server_packet(initial,pub,4866)
        add(group_policy,initial,length,suite_policy=2,packet=packet)
    for group_policy,initial in [(0,29),(1,23)]:
        pub=P_PUBLIC if initial==23 else wire.public_key((29,),29)
        packet=server_packet(initial,pub,4866)
        needed=exchange_cost(POLICIES[group_policy],initial,packet,suites=(4866,),sha384=True)
        add(group_policy,initial,64,suite_policy=1,packet=packet,work=needed,exact_remaining=0)
        add(group_policy,initial,64,suite_policy=1,packet=packet,work=needed-1,feed=5)
    # Real unbound client -> validated HRR -> CH2 -> changed final suite / repeat
    # HRR. These exercise Engine's late-binding lock through public wire calls.
    def retry_packet(suite):
        extensions=ext(43,b'\x03\x04')+ext(51,U16(29))
        body=b'\x03\x03'+wire.HRR+b'\0'+U16(suite)+b'\0'+U16(len(extensions))+extensions
        frame=b'\x02'+len(body).to_bytes(3,'big')+body
        return b'\x16\x03\x03'+U16(len(frame))+frame
    for selected,changed in [(4866,4865),(4865,4867)]:
        packets=retry_packet(selected)+server_packet(29,wire.public_key((29,),29),changed)
        add(0,0,64,suite_policy=2,packet=packets,feed=113)
    add(0,0,64,suite_policy=2,packet=retry_packet(4866)*2,feed=113)
    add(0,29,64,suite_policy=1,packet=server_packet(29,wire.public_key((29,),29),4865),feed=112)
    with tempfile.TemporaryDirectory(prefix='tls_group_admission_') as directory:
        trace = pathlib.Path(directory)/'memory.trace'
        result = subprocess.run(['strace','-qq','-o',str(trace),'-e','trace=mmap,munmap,mremap,brk','-e','signal=none',executable],
                                input=Q(len(cases))+b''.join(case[0] for case in cases),capture_output=True,timeout=40)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, len(result.stdout), result.stdout[-64:].hex(), result.stderr)
        assert trace.read_text() == '', 'engine admission allocated'
        r = wire.Reader(result.stdout)
        for number, (_, expected) in enumerate(cases):
            policy_id, initial, budget, packet, status, feed, remaining, suite_policy = expected
            suites=(4866,) if suite_policy==1 else (4867,4865,4866) if suite_policy==2 else (4867,4865)
            policy = POLICIES[policy_id]
            hello = r.block()
            actual = [r.word() for _ in range(8)]
            assert actual[0] == status and actual[1] == feed, (number, actual, expected)
            assert actual[2] == len(packet) and actual[4] == int(feed != 0), (number, actual)
            if status:
                assert hello == b'' and actual[3] == 0
            else:
                frame = client_frame(policy, initial, suites)
                assert hello == b'\x16\x03\x01'+U16(len(frame))+frame, (number, hello.hex())
                assert actual[3] <= budget
                if not packet:
                    assert actual[3] == budget-setup_cost(policy, initial, suites), (number, actual, setup_cost(policy, initial, suites))
                if remaining is not None:
                    assert actual[3] == remaining, (number, actual)
            if policy_id == 4:
                assert actual[5:] == [0, 0, 0]
            else:
                assert actual[5:] == ([96, 32, 64] if len(policy) == 2 else [64, 32 if policy == (29,) else 0, 32 if policy == (23,) else 0])
            transcript = r.block()
            if packet and status==feed==0:
                algorithm='sha384' if suite_policy in (1,2) else 'sha256'
                assert transcript == getattr(wire.hashlib,algorithm)(frame+packet[5:]).digest(), (number,transcript.hex())
            else:
                assert transcript == b'', (number,transcript.hex())
        assert r.at == len(r.data)
    print(f'tls connection group admissions: {len(cases)} accepted')


if __name__ == '__main__':
    run(sys.argv[1])
