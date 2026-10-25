# Test-only independent peer. Creates real OpenSSL chains, then uses libsodium
# detached signatures and hashlib/hmac for the complete authentication flight.
import calendar
import copy
import ctypes
import datetime
import hashlib
import hmac
import pathlib
import struct
import subprocess
import sys
import tempfile

Q = lambda *n: struct.pack('<' + 'Q' * len(n), *(x & ((1 << 64)-1) for x in n))
U16 = lambda n: n.to_bytes(2, 'big')
U24 = lambda n: n.to_bytes(3, 'big')
FRAME = lambda kind, body: bytes([kind]) + U24(len(body)) + body
EXT = lambda kind, body: U16(kind) + U16(len(body)) + body
HASH = (hashlib.sha256, hashlib.sha384)
H = lambda b, algorithm=0: HASH[algorithm](b).digest()
MAC = lambda k, b, algorithm=0: hmac.new(k, b, HASH[algorithm]).digest()
HASH_LENGTH = (32, 48)
SODIUM = ctypes.CDLL('libsodium.so.23')
assert SODIUM.sodium_init() >= 0
P, U = ctypes.c_void_p, ctypes.c_ulonglong
SODIUM.crypto_sign_seed_keypair.argtypes = [P, P, P]
SODIUM.crypto_sign_detached.argtypes = [P, ctypes.POINTER(U), P, U, P]
SODIUM.crypto_sign_verify_detached.argtypes = [P, P, U, P]
SODIUM.crypto_scalarmult_curve25519_base.argtypes = [P, P]
SODIUM.crypto_scalarmult_curve25519.argtypes = [P, P, P]
LEAF_SEED = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')

def keypair(seed):
    public, private = ctypes.create_string_buffer(32), ctypes.create_string_buffer(64)
    assert SODIUM.crypto_sign_seed_keypair(public, private, seed) == 0
    return public.raw, private.raw

PUBLIC, PRIVATE = keypair(LEAF_SEED)
assert PUBLIC.hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
def sign(message):
    output, n = ctypes.create_string_buffer(64), U()
    assert SODIUM.crypto_sign_detached(output, ctypes.byref(n), message, len(message), PRIVATE) == 0 and n.value == 64
    return output.raw

def verify(public, message, signature):
    return SODIUM.crypto_sign_verify_detached(signature, message, len(message), public) == 0

def expand(secret, label, context, length=None, algorithm=0):
    size = HASH_LENGTH[algorithm]
    if length is None: length = size
    label = b'tls13 ' + label
    info = U16(length) + bytes([len(label)]) + label + bytes([len(context)]) + context
    previous, output = b'', b''
    for i in range(1, (length+size-1)//size+1):
        previous = MAC(secret, previous + info + bytes([i]), algorithm)
        output += previous
    return output[:length]

def der(data, at=0):
    start = at
    tag, length = data[at:at+2]
    at += 2
    if length & 128:
        count = length & 127
        assert 0 < count <= 4 and data[at] != 0
        length = int.from_bytes(data[at:at+count], 'big')
        at += count
        assert length >= 128
    assert at+length <= len(data)
    return tag, data[at:at+length], data[start:at+length], at+length

def members(data):
    out, at = [], 0
    while at < len(data):
        tag, value, encoded, at = der(data, at)
        out.append((tag, value, encoded))
    assert at == len(data)
    return out

def cert_parts(cert):
    tag, body, encoded, end = der(cert)
    assert tag == 48 and end == len(cert)
    outer = members(body)
    assert len(outer) == 3
    tbs = members(outer[0][1])
    assert tbs[0][0] == 160 and members(tbs[0][1])[0][1] == b'\x02'
    assert members(outer[1][1])[0][1] == bytes.fromhex('2b6570')
    spki = members(tbs[6][1])
    assert spki[1][0] == 3 and spki[1][1][0] == 0 and len(spki[1][1]) == 33
    assert outer[2][0] == 3 and outer[2][1][0] == 0 and len(outer[2][1]) == 65
    def instant(value):
        tag, text, _ = value
        text = text.decode('ascii')
        if tag == 23:
            year = int(text[:2]); year += 1900 if year >= 50 else 2000
            assert len(text) == 13 and text[-1] == 'Z'
            return calendar.timegm((year, int(text[2:4]), int(text[4:6]), int(text[6:8]), int(text[8:10]), int(text[10:12])))
        assert tag == 24
        return calendar.timegm(datetime.datetime.strptime(text, '%Y%m%d%H%M%SZ').timetuple())
    validity = members(tbs[4][1])
    return dict(tbs=outer[0][2], signature=outer[2][1][1:], public=spki[1][1][1:], issuer=tbs[3][2], subject=tbs[5][2], first=instant(validity[0]), last=instant(validity[1]), spki=tbs[6][2])

def command(args):
    result = subprocess.run(['openssl'] + list(map(str, args)), capture_output=True, timeout=5)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout

class Chain:
    def __init__(self, folder, count, large=False):
        self.folder = folder
        folder.mkdir()
        config = folder/'config.ini'
        san = ['server.example'] + ([f'n{i:03d}.' + 'a'*40 + '.example' for i in range(180)] if large else [])
        common = 'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n'
        config.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=TLS auth test\n[root]\nbasicConstraints=critical,CA:TRUE,pathlen:8\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n[ca]\nbasicConstraints=critical,CA:TRUE,pathlen:8\nkeyUsage=critical,keyCertSign,cRLSign\n' + common + ('subjectAltName=' + ','.join('DNS:'+s for s in san) + '\n' if large else '') + '[leaf]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n' + common + 'subjectAltName=' + ','.join('DNS:'+s for s in san) + '\n')
        def private(i, seed):
            path = folder/f'{i}.key'
            raw = folder/f'{i}.key.der'
            raw.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + seed)
            command(['pkey', '-inform', 'DER', '-in', raw, '-out', path])
            return path
        rootkey = private('root', H(b'tls authentication root seed'))
        rootpem = folder/'root.pem'
        command(['req','-new','-x509','-key',rootkey,'-config',config,'-extensions','root','-subj','/CN=TLS auth root','-days','2','-set_serial','100','-out',rootpem])
        self.root = command(['x509','-in',rootpem,'-outform','DER'])
        issuer, issuerkey = rootpem, rootkey
        ordered = []
        for i in range(count-1):
            key = private(i, H(f'tls authentication intermediate {i}'.encode()))
            csr, pem = folder/f'{i}.csr', folder/f'{i}.pem'
            command(['req','-new','-key',key,'-config',config,'-subj',f'/CN=TLS auth intermediate {i}','-out',csr])
            command(['x509','-req','-in',csr,'-CA',issuer,'-CAkey',issuerkey,'-set_serial',str(200+i),'-days','2','-extfile',config,'-extensions','ca','-out',pem])
            ordered.append(command(['x509','-in',pem,'-outform','DER']))
            issuer, issuerkey = pem, key
        leafkey = private('leaf', LEAF_SEED)
        csr, leafpem = folder/'leaf.csr', folder/'leaf.pem'
        command(['req','-new','-key',leafkey,'-config',config,'-subj','/CN=server.example','-out',csr])
        command(['x509','-req','-in',csr,'-CA',issuer,'-CAkey',issuerkey,'-set_serial','400','-days','2','-extfile',config,'-extensions','leaf','-out',leafpem])
        self.chain = [command(['x509','-in',leafpem,'-outform','DER'])] + ordered[::-1]
        all_parts = [cert_parts(c) for c in self.chain + [self.root]]
        assert all_parts[0]['public'] == PUBLIC
        self.now = max(c['first'] for c in all_parts) + 1
        assert self.now <= min(c['last'] for c in all_parts)
        for child, parent in zip(all_parts, all_parts[1:]):
            assert child['issuer'] == parent['subject'] and verify(parent['public'],child['tbs'],child['signature'])
        self.checked_paths = {}
        assert self.openssl(self.chain,self.root,b'server.example',self.now)

    def openssl(self, chain, anchor, reference, now):
        token = (tuple(chain),anchor,reference,now)
        if token not in self.checked_paths:
            paths=[]
            for i, cert in enumerate(chain+[anchor]):
                raw=self.folder/f'verify-{i}.der'; pem=self.folder/f'verify-{i}.pem'
                raw.write_bytes(cert)
                result=subprocess.run(['openssl','x509','-inform','DER','-in',str(raw),'-out',str(pem)],capture_output=True,timeout=5)
                if result.returncode != 0:
                    self.checked_paths[token]=False
                    return False
                paths.append(pem)
            untrusted=self.folder/'untrusted.pem'; untrusted.write_bytes(b''.join(p.read_bytes() for p in paths[1:-1]))
            args=['openssl','verify','-CAfile',str(paths[-1]),'-attime',str(now),'-verify_hostname',reference.decode('ascii')]
            if len(chain)>1: args+=['-untrusted',str(untrusted)]
            result=subprocess.run(args+[str(paths[0])],capture_output=True,timeout=5)
            self.checked_paths[token]=result.returncode==0
        return self.checked_paths[token]

def hello(hrr=False, algorithm=0):
    suite = U16(4867 if algorithm == 0 else 4866)
    client_private=bytes(range(32)); server_private=bytes(range(32,64))
    client_public, server_public, shared = (ctypes.create_string_buffer(32) for _ in range(3))
    assert SODIUM.crypto_scalarmult_curve25519_base(client_public,client_private)==0
    assert SODIUM.crypto_scalarmult_curve25519_base(server_public,server_private)==0
    assert SODIUM.crypto_scalarmult_curve25519(shared,client_private,server_public)==0
    versions=EXT(43,b'\x02\x03\x04'); schemes=EXT(13,b'\x00\x02\x08\x07'); groups=EXT(10,b'\x00\x02\x00\x1d')
    shares=EXT(51,U16(36)+b'\x00\x1d\x00\x20'+client_public.raw)
    def ch(extension):
        return FRAME(1,b'\x03\x03'+bytes(range(32))+b'\x00\x00\x02'+suite+b'\x01\x00'+U16(len(extension))+extension)
    full=ch(versions+schemes+groups+shares)
    sh_ext=EXT(43,b'\x03\x04')+EXT(51,b'\x00\x1d\x00\x20'+server_public.raw)
    sh=FRAME(2,b'\x03\x03'+bytes(range(32,64))+b'\x00'+suite+b'\x00'+U16(len(sh_ext))+sh_ext)
    first=full; retry=b''; second=b''; prefix=first+sh
    if hrr:
        first=ch(versions+schemes+groups+EXT(51,b'\x00\x00'))
        retry_ext=EXT(43,b'\x03\x04')+EXT(51,b'\x00\x1d')
        magic=bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
        retry=FRAME(2,b'\x03\x03'+magic+b'\x00'+suite+b'\x00'+U16(len(retry_ext))+retry_ext)
        second=full
        prefix=FRAME(254,H(first,algorithm))+retry+second+sh
    size=HASH_LENGTH[algorithm]
    early=MAC(bytes(size),bytes(size),algorithm); derived=expand(early,b'derived',H(b'',algorithm),algorithm=algorithm)
    handshake=MAC(derived,shared.raw,algorithm); secret=expand(handshake,b's hs traffic',H(prefix,algorithm),algorithm=algorithm)
    return first,sh,retry,second,prefix,secret

def flight(chain, prefix, secret, context=b'', entry_ext=b'', algorithm=0):
    ee=FRAME(8,b'\x00\x00')
    entries=b''.join(U24(len(cert))+cert+U16(len(entry_ext))+entry_ext for cert in chain)
    certificate=FRAME(11,bytes([len(context)])+context+U24(len(entries))+entries)
    signed=b' '*64+b'TLS 1.3, server CertificateVerify\x00'+H(prefix+ee+certificate,algorithm)
    assert len(signed)==98+HASH_LENGTH[algorithm]
    signature=sign(signed); assert verify(PUBLIC,signed,signature)
    cv=FRAME(15,b'\x08\x07\x00\x40'+signature)
    finished=FRAME(20,MAC(expand(secret,b'finished',b'',algorithm=algorithm),H(prefix+ee+certificate+cv,algorithm),algorithm))
    return [ee,certificate,cv,finished]

class Case:
    def __init__(self, material, **changes):
        self.algorithm=changes.pop('algorithm',0)
        self.material=material; self.layout=0; self.maximum=98304; self.max_input=1048576; self.work=67108864; self.signatures=64
        self.reference=b'server.example'; self.now=material.now; self.anchor=material.root; self.variant=0; self.mode=0; self.mutate=0
        self.ch,self.sh,self.hrr,self.ch2,self.prefix,self.secret=hello(False,self.algorithm)
        self.path_error=0; self.path_spent=len(material.chain); self.actions=[]
        self.__dict__.update(changes)
    def feed(self, frame, fault=0, scratch=0, op=0): self.actions.append((op,fault,scratch,bytes(frame))); return self
    def action(self, op): return self.feed(b'',op=op)
    def frames(self): return flight(self.material.chain,self.prefix,self.secret,algorithm=self.algorithm)
    def wire(self):
        h=[self.layout,self.now,self.variant,self.maximum,self.max_input,self.work,self.signatures,len(self.actions),len(self.anchor),len(self.ch),len(self.sh),len(self.secret),len(self.reference),len(self.hrr),len(self.ch2),self.mode,self.mutate,self.algorithm]
        out=Q(*h)+self.anchor+self.ch+self.sh+self.secret+self.reference+self.hrr+self.ch2
        for op,fault,scratch,frame in self.actions: out+=Q(op,fault,scratch,len(frame))+frame
        return out

def constructor(c):
    if c.variant in (7,8,9,10): return 1
    if c.variant==1: return 5
    if c.variant==2: return 6
    if c.variant==6: return 3
    if c.maximum<4 or c.maximum>16777219: return 2
    if c.variant in (3,4,5): return 7
    if c.mode in (1,2,3): return 4
    return 0

class State:
    def __init__(self,c): self.step=0; self.error=0; self.prefix=c.prefix

def observe(c,s,status,signatures,work):
    auth=s.error==0 and s.step==4
    words=[status,5 if s.error else s.step,int(bool(s.error)),int(auth),int(auth),int(auth),signatures,work]
    words+=struct.unpack('<4Q',PUBLIC if auth else bytes(32))
    words+=struct.unpack('<6Q',H(s.prefix,c.algorithm).ljust(48,b'\0') if auth else bytes(48))
    words += [6 if auth and not s.prefix.startswith(b'\xfe') else 8 if auth else 0, s.error]
    return list(words)

def oracle(c):
    active=State(c); branch=copy.deepcopy(active); signatures=c.signatures; observations=[]
    for op,fault,scratch,frame in c.actions:
        s=branch if op==2 else active; status=0; rule=1; debit=0
        if op==1: branch=copy.deepcopy(active)
        if op in (0,2):
            if fault: status=1
            elif s.error: status=s.error
            elif s.step==1 and scratch in (1,2,3): status=1
            elif s.step==4: status=12
            elif len(frame)>min(c.maximum,c.max_input): status=8
            else:
                debit=4096+256*len(frame); rule=2
                # Work stops are intentionally isolated before any path debit.
                prior_known=c.work-sum(x[2] for x in observations if x[1]==2)
                if prior_known<debit: status=9; rule=1; debit=0
                elif len(frame)<4: status=202
                elif frame[0] not in (1,2,4,5,8,11,13,15,20,24): status=204
                elif int.from_bytes(frame[1:4],'big')>len(frame)-4: status=202
                elif int.from_bytes(frame[1:4],'big')!=len(frame)-4: status=203
                elif frame[0]!=(8,11,15,20)[s.step]: status=12
                elif s.step==0:
                    if frame != FRAME(8,b'\x00\x00'): status=206
                elif s.step==1:
                    body=frame[4:]; context_length=body[0]
                    if context_length: status=13
                    elif body[1:4]==b'\0\0\0': status=14
                    elif getattr(c,'too_many',False): status=15
                    elif getattr(c,'entry_extensions',False): status=16
                    elif scratch==4: status=11
                    else:
                        rule=3
                        spent=min(signatures,c.path_spent); signatures-=spent
                        if spent<c.path_spent: status=112
                        else: status=c.path_error
                elif s.step==2:
                    if frame[4:6]!=b'\x08\x07' or frame[6:8]!=b'\x00\x40' or len(frame[8:])!=64: status=7
                    elif signatures==0: status=10
                    else:
                        signatures-=1
                        signed=b' '*64+b'TLS 1.3, server CertificateVerify\0'+H(s.prefix,c.algorithm)
                        if not verify(PUBLIC,signed,frame[8:]): status=17
                elif s.step==3:
                    if len(frame[4:])<HASH_LENGTH[c.algorithm]: status=202
                    elif len(frame[4:])!=HASH_LENGTH[c.algorithm]: status=203
                    elif frame[4:]!=MAC(expand(c.secret,b'finished',b'',algorithm=c.algorithm),H(s.prefix,c.algorithm),c.algorithm): status=18
                if not status: s.prefix+=frame; s.step+=1
            if status not in (0,1,11): s.error=s.error or status
        # Work model never mirrors X.509 parsing. Rule3 requires its unknown
        # nonnegative extra debit; rule2 checks the exact portable bridge tariff.
        observations.append((observe(c,s,status,signatures,0),rule,debit,frame))
    return observations

def cases(material, mode, long=None, algorithm=0):
    result=[]
    def add(c):
        for layout in (0,1): d=copy.copy(c); d.layout=layout; result.append(d)
    if mode=='positive':
        c=Case(material,algorithm=algorithm,mutate=1)
        for frame in c.frames(): c.feed(frame)
        c.action(4).action(3); add(c)
        c=Case(material,algorithm=algorithm,mode=4); c.ch,c.sh,c.hrr,c.ch2,c.prefix,c.secret=hello(True,algorithm)
        for frame in c.frames(): c.feed(frame)
        add(c)
        c=Case(material,algorithm=algorithm); f=c.frames()
        c.feed(f[0]).action(1).feed(f[1],op=2).feed(f[1]).feed(f[2],op=2).feed(f[2]).feed(f[3],op=2).feed(f[3]).action(4)
        add(c)
        assert long is not None and len(flight(long.chain,c.prefix,c.secret,algorithm=algorithm)[1])>65536
        c=Case(long,algorithm=algorithm,work=16777216)
        for frame in c.frames(): c.feed(frame)
        add(c)
        c=Case(long,algorithm=algorithm,work=67108864)
        for frame in c.frames(): c.feed(frame)
        add(c)
    else:
        for variant in range(1,11): add(Case(material,algorithm=algorithm,variant=variant))
        for maximum in (3,16777220): add(Case(material,algorithm=algorithm,maximum=maximum))
        for mode in (1,2,3): add(Case(material,algorithm=algorithm,mode=mode))
        for fault in (1,2,3):
            c=Case(material,algorithm=algorithm); f=c.frames()
            for frame in f: c.feed(frame,fault=fault).feed(frame)
            add(c)
        for scratch in (1,2,3,4):
            c=Case(material,algorithm=algorithm); f=c.frames()
            c.feed(f[0]).feed(f[1],scratch=scratch).feed(f[1]).feed(f[2]).feed(f[3]); add(c)
        for kind in ('order','replay','unknown','truncated','length','ee_duplicate','context','empty','extensions','count','raw','cert_signature','anchor','identity','time','cv','cv_context','cv_scheme','cv_length','finished','finished_length','cv_budget','path_budget','work','frame_limit','certificate_work','after_complete','copy_failure'):
            c=Case(material,algorithm=algorithm); f=c.frames()
            if kind=='order': c.feed(f[1]).feed(f[0])
            elif kind=='replay': c.feed(f[0]).feed(f[0]).feed(f[1])
            elif kind=='unknown': c.feed(FRAME(255,b'')).feed(f[0])
            elif kind=='truncated': c.feed(b'\x08\x00').feed(f[0])
            elif kind=='length': c.feed(f[0]+b'x').feed(f[0])
            elif kind=='ee_duplicate':
                ext=EXT(0,b'')*2; c.feed(FRAME(8,U16(len(ext))+ext)).feed(f[0])
            elif kind=='context': c.feed(f[0]).feed(flight(material.chain,c.prefix,c.secret,context=b'x',algorithm=algorithm)[1])
            elif kind=='empty': c.feed(f[0]).feed(FRAME(11,b'\0\0\0\0'))
            elif kind=='extensions': c.entry_extensions=True; c.feed(f[0]).feed(flight(material.chain,c.prefix,c.secret,entry_ext=EXT(18,b''),algorithm=algorithm)[1])
            elif kind=='count': c.too_many=True; c.feed(f[0]).feed(flight([material.chain[0]]*9,c.prefix,c.secret,algorithm=algorithm)[1])
            elif kind=='raw': c.path_error=109; c.path_spent=0; c.feed(f[0]).feed(flight([cert_parts(material.chain[0])['spki']],c.prefix,c.secret,algorithm=algorithm)[1])
            elif kind=='cert_signature':
                bad=material.chain[0][:-1]+bytes([material.chain[0][-1]^1]); assert not material.openssl([bad]+material.chain[1:],c.anchor,c.reference,c.now)
                c.path_error=117; c.path_spent=1; c.feed(f[0]).feed(flight([bad]+material.chain[1:],c.prefix,c.secret,algorithm=algorithm)[1])
            elif kind in ('anchor','identity','time'):
                if kind=='anchor': c.anchor=material.chain[0]; c.path_error=116; c.path_spent=len(material.chain)-1
                if kind=='identity': c.reference=b'other.example'; c.path_error=126; c.path_spent=len(material.chain)-1
                if kind=='time': c.now=0; c.path_error=118; c.path_spent=0
                assert not material.openssl(material.chain,c.anchor,c.reference,c.now)
                c.feed(f[0]).feed(f[1]).feed(f[2]).feed(f[3])
            elif kind in ('cv','cv_context','cv_scheme','cv_length'):
                altered=bytearray(f[2])
                if kind=='cv': altered[-1]^=1
                if kind=='cv_context': altered[8:]=sign(b' '*64+b'TLS 1.3, client CertificateVerify\0'+H(c.prefix+f[0]+f[1],algorithm))
                if kind=='cv_scheme': altered[4:6]=b'\x04\x03'
                if kind=='cv_length': altered=bytearray(FRAME(15,b'\x08\x07\x00\x3f'+bytes(altered[8:-1])))
                c.feed(f[0]).feed(f[1]).feed(altered).feed(f[2],fault=1).feed(f[2]).feed(f[3])
            elif kind in ('finished','finished_length'):
                bad=f[3][:-1]+bytes([f[3][-1]^1]) if kind=='finished' else FRAME(20,f[3][4:-1])
                c.feed(f[0]).feed(f[1]).feed(f[2]).feed(bad).feed(f[3])
            elif kind in ('cv_budget','path_budget'):
                c.signatures=2 if kind=='cv_budget' else 1
                for frame in f: c.feed(frame)
            elif kind=='work': c.work=0; c.feed(f[0]).feed(f[0])
            elif kind=='frame_limit': c.maximum=5; c.feed(f[0])
            elif kind=='certificate_work': c.work=sum(4096+256*len(x) for x in f[:2])-1; c.feed(f[0]).feed(f[1]).feed(f[1])
            elif kind=='after_complete':
                for frame in f: c.feed(frame)
                c.feed(f[0]).feed(f[3])
            elif kind=='copy_failure':
                c.feed(f[0]).feed(f[1]).action(1); bad=f[2][:-1]+bytes([f[2][-1]^1])
                c.feed(bad,op=2).feed(f[2]).feed(f[3]).action(4).feed(f[3],op=2)
            add(c)
    return result

def emit(cases):
    out=Q(len(cases))
    for c in cases:
        wire=c.wire(); expected=constructor(c); observations=[] if expected else oracle(c)
        out+=Q(len(wire))+wire+Q(expected,c.layout,c.work,len(observations),len(c.anchor))+c.anchor
        for words,rule,debit,frame in observations: out+=Q(rule,debit,len(frame))+Q(*words)+frame
    sys.stdout.buffer.write(out)

if __name__=='__main__':
    mode=sys.argv[1]
    with tempfile.TemporaryDirectory(prefix='laniusc_tls_authentication_') as temp:
        base=pathlib.Path(temp); material=Chain(base/'short',2)
        if mode=='ordinary':
            c=Case(material); frames=c.frames(); source=Q(2)
            for layout in (0,1):
                source+=Q(layout,c.now,len(c.anchor),len(c.ch),len(c.sh),*(len(x) for x in frames))
                source+=c.anchor+c.ch+c.sh+c.secret+b''.join(frames)
            expected=(PUBLIC+H(c.prefix+b''.join(frames)))*2
            sys.stdout.buffer.write(Q(len(source))+source+Q(len(expected))+expected)
        else:
            long=Chain(base/'long',8,True) if mode=='positive' else None
            emit(cases(material,mode,long))
