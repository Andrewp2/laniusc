"""Independent RFC8446 struct model; generate all native commands and expected bytes."""
import pathlib, struct, sys
MAX = (1 << 24) - 1
KINDS = {1, 2, 4, 5, 8, 11, 13, 15, 20, 24}
class WireError(Exception):
    def __init__(self, code): self.code = code

def need(condition, code):
    if not condition: raise WireError(code)

class Reader:
    def __init__(self, data): self.data, self.at = data, 0
    def take(self, count):
        need(count <= len(self.data) - self.at, 2)
        value = self.data[self.at:self.at+count]; self.at += count
        return value
    def number(self, width): return int.from_bytes(self.take(width), 'big')
    def vector(self, width, low=0, high=None):
        length = self.number(width)
        need(low <= length <= ((1 << (8*width))-1 if high is None else high), 3)
        return self.take(length)
    def end(self): need(self.at == len(self.data), 3)

def extension_list(data):
    need(len(data) <= 65535, 3); source = Reader(data); seen = {}
    while source.at < len(data):
        kind = source.number(2); payload = source.vector(2)
        need(kind not in seen, 6); seen[kind] = payload
    return seen

def certificate_list(data):
    need(len(data) <= MAX, 3); source = Reader(data)
    while source.at < len(data):
        source.vector(3, 1); extension_list(source.vector(2))

def hello_extensions(data, server=False):
    entries = extension_list(data); need(43 in entries, 7)
    source = Reader(entries[43])
    if server: need(len(entries[43]) == 2, 3); need(source.number(2) == 0x0304, 5)
    else:
        versions = source.vector(1, 2, 254); source.end()
        need(len(versions) % 2 == 0, 3)
        need(0x0304 in struct.unpack('>'+'H'*(len(versions)//2), versions), 5)

def parse_body(kind, data, hash_length):
    need(len(data) <= MAX, 3); source = Reader(data)
    if kind == 1:
        legacy = source.number(2); source.take(32); source.vector(1,0,32)
        suites = source.vector(2,2,65534); compression = source.vector(1,1,255)
        extensions = source.vector(2,8); source.end()
        need(legacy == 0x0303 and compression == b'\0', 5)
        need(len(suites) % 2 == 0, 3); hello_extensions(extensions)
    elif kind == 2:
        legacy = source.number(2); source.take(32); source.vector(1,0,32); source.take(2)
        compression = source.number(1); extensions = source.vector(2,6); source.end()
        need(legacy == 0x0303 and compression == 0, 5); hello_extensions(extensions, True)
    elif kind == 8:
        extensions = source.vector(2); source.end(); extension_list(extensions)
    elif kind == 13:
        source.vector(1); extensions = source.vector(2,2); source.end()
        extensions = extension_list(extensions); need(13 in extensions, 7)
        nested = Reader(extensions[13]); algorithms = nested.vector(2,2,65534); nested.end()
        need(len(algorithms) % 2 == 0, 3)
    elif kind == 11:
        source.vector(1); entries = source.vector(3); source.end(); certificate_list(entries)
    elif kind == 15:
        source.number(2); source.vector(2); source.end()
    elif kind == 20:
        need(hash_length in (32,48), 3); need(len(data) >= hash_length, 2); need(len(data) == hash_length, 3)
    elif kind == 24:
        need(len(data) >= 1, 2); need(len(data) == 1, 3); need(data[0] <= 1, 5)
    elif kind == 4:
        lifetime = source.number(4); source.number(4); source.vector(1); source.vector(2,1)
        extensions = source.vector(2,0,65534); source.end(); need(lifetime <= 604800, 5); extension_list(extensions)
    elif kind == 5: need(len(data) == 0, 3)
    else: raise WireError(4)

def frame(kind, body): return bytes([kind]) + len(body).to_bytes(3,'big') + body

def parse_frame(data, hash_length):
    source = Reader(data); header = source.take(4); kind = header[0]; need(kind in KINDS, 4)
    body = source.take(int.from_bytes(header[1:],'big')); source.end(); parse_body(kind,body,hash_length)

def frame_list(data):
    source = Reader(data)
    while source.at < len(data):
        header = source.take(4); need(header[0] in KINDS, 4); source.take(int.from_bytes(header[1:],'big'))

def vector(data,width): return len(data).to_bytes(width,'big')+data

def ext(kind,payload=b''): return struct.pack('>HH',kind,len(payload))+payload

def cert(data,extensions=b''): return vector(data,3)+vector(extensions,2)

def result(op,param,data):
    try:
        if op in (0,2):
            parse_frame(data,param)
            if op == 2: raise WireError(8)
            output = data
        elif op == 1: frame_list(data); output = data
        elif op == 3:
            need(param in (1,2,3), 3); source = Reader(data)
            while source.at < len(data): source.vector(param)
            output = data
        elif op == 4: extension_list(data); output = data
        elif op == 5: certificate_list(data); output = data
        elif op == 6:
            need(param in KINDS,4); need(len(data)<=MAX,3); output = frame(param,data)
        else: raise AssertionError(op)
        return struct.pack('<QQ',0,len(output))+output
    except WireError as error: return struct.pack('<QQ',error.code,0)

random = bytes(range(32)); retry = bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
versions = ext(43,b'\x02\x03\x04')
selected = ext(43,b'\x03\x04')
algorithms = ext(13,vector(b'\x08\x04\x08\x07',2))
valid = []
def good(name,kind,body,hash_length=32):
    wire = frame(kind,body); parse_frame(wire,hash_length); valid.append((name,wire,hash_length))
for size in (0,1,31):
    sid = bytes(range(32)) if size else b''
    good('client-'+str(size),1,b'\x03\x03'+random+vector(sid,1)+vector(b'\x13\x01\x13\x03',2)+b'\x01\0'+vector(versions+ext(65535,bytes(range(size))),2))
for is_retry in (False,True):
    for sid in (b'',bytes(range(32))):
        good('server-'+str(is_retry)+'-'+str(len(sid)),2,b'\x03\x03'+(retry if is_retry else random)+vector(sid,1)+b'\x13\x03\0'+vector(selected+ext(0xfefe,b'opaque'),2))
good('encrypted-empty',8,b'\0\0'); good('encrypted-opaque',8,vector(ext(64,b'\0\xff')+ext(65535),2))
for context in (b'',bytes(range(255))): good('request-'+str(len(context)),13,vector(context,1)+vector(algorithms+ext(65535,b'x'),2))
good('certificate-empty',11,b'\0\0\0\0')
entries = cert(b'\x30\x01',ext(65535,b'a'))+cert(b'\x30\x02\x03',ext(65535,b'b'))
good('certificate-chain',11,b'\0'+vector(entries,3))
good('certificate-context255',11,vector(bytes(range(255)),1)+vector(entries,3))
for size in (0,1,129): good('verify-'+str(size),15,b'\x08\x04'+vector(bytes(i%256 for i in range(size)),2))
for size in (32,48): good('finished-'+str(size),20,bytes(range(size)),size)
for flag in (0,1): good('key-update-'+str(flag),24,bytes([flag]))
for lifetime,nonce,ticket in ((0,b'',b'x'),(604800,bytes(range(255)),bytes(range(129)))):
    good('ticket-'+str(lifetime),4,struct.pack('>II',lifetime,0xffffffff)+vector(nonce,1)+vector(ticket,2)+vector(ext(42,b'\0\0\xff\xff')+ext(65535),2))
good('end-early',5,b'')
for line in pathlib.Path(__file__).with_name('rfc8448_vectors.txt').read_text().splitlines():
    if not line or line.startswith('#'): continue
    name,wire=line.split(); wire=bytes.fromhex(wire); parse_frame(wire,32); valid.append(('RFC8448-'+name,wire,32))

cases=[]
def add(name,op,param,data,layouts=(0,1,2,3)):
    for layout in layouts: cases.append((name,op,param,layout,data))
for name,wire,h in valid:
    add(name,0,h,wire); add(name+'-short-output',2,h,wire)
    cuts=sorted(cut for cut in {0,1,2,3,4,5,6,len(wire)//2,len(wire)-1} if cut<len(wire))
    for cut in cuts: add(name+'-truncate-'+str(cut),0,h,wire[:cut],(0,3))
    add(name+'-trailing',0,h,wire+b'!',(1,2))
    if len(wire)>4:
        add(name+'-header-short',0,h,wire[:1]+(len(wire)-5).to_bytes(3,'big')+wire[4:],(0,3))
        add(name+'-header-long',0,h,wire[:1]+(len(wire)-3).to_bytes(3,'big')+wire[4:],(0,3))
# Target specific nested grammar rather than only inconsistent outer framing.
malformed=[
    ('legacy-client',1,b'\x03\x04'+random+b'\0\0\x02\x13\x03\x01\0'+vector(versions+ext(65535),2)),
    ('compression-client',1,b'\x03\x03'+random+b'\0\0\x02\x13\x03\x01\x01'+vector(versions+ext(65535),2)),
    ('empty-suites',1,b'\x03\x03'+random+b'\0\0\0\x01\0'+vector(versions+ext(65535),2)),
    ('odd-suites',1,b'\x03\x03'+random+b'\0\0\x03\x13\x03\x13\x01\0'+vector(versions+ext(65535),2)),
    ('session33',1,b'\x03\x03'+random+vector(bytes(33),1)+b'\0\x02\x13\x03\x01\0'+vector(versions+ext(65535),2)),
    ('missing-client-version',1,b'\x03\x03'+random+b'\0\0\x02\x13\x03\x01\0'+vector(ext(65535,b'xxxx'),2)),
    ('odd-versions',1,b'\x03\x03'+random+b'\0\0\x02\x13\x03\x01\0'+vector(ext(43,b'\x03\x03\x04\x03')+ext(65535),2)),
    ('wrong-version',2,b'\x03\x03'+random+b'\0\x13\x03\0'+vector(ext(43,b'\x03\x03'),2)),
    ('compression-server',2,b'\x03\x03'+random+b'\0\x13\x03\x01'+vector(selected,2)),
    ('duplicate-ext',8,vector(ext(65535)+ext(65535),2)),
    ('truncated-ext',8,vector(b'\0\x2b\0\x04\x03',2)),
    ('request-no-algs',13,b'\0'+vector(ext(65535),2)),
    ('request-odd-algs',13,b'\0'+vector(ext(13,b'\0\x03\x08\x04\x08'),2)),
    ('empty-cert-entry',11,b'\0'+vector(cert(b''),3)),
    ('duplicate-cert-ext',11,b'\0'+vector(cert(b'\x30',ext(63)+ext(63)),3)),
    ('key-update2',24,b'\x02'),('key-update-extra',24,b'\0\0'),('end-early-nonempty',5,b'\0'),
    ('ticket-overweek',4,struct.pack('>II',604801,0)+b'\0\0\x01x\0\0'),
    ('ticket-empty',4,bytes(8)+b'\0\0\0\0\0'),
    ('finished-empty',20,b''),('finished-31',20,bytes(31)),('finished-33',20,bytes(33)),
]
for name,kind,body in malformed: add(name,0,32,frame(kind,body))
for h in (0,1,31,64): add('unsupported-hash-'+str(h),0,h,frame(20,bytes(32)))
for kind in (0,3,254,255): add('unknown-kind-'+str(kind),0,32,frame(kind,b''))
for data in (b'',frame(5,b'')+frame(24,b'\0'),frame(5,b'x'),valid[0][1]+valid[1][1],frame(5,b'')+b'\x01\0',frame(254,b'')):
    add('frame-list-'+str(len(data)),1,32,data)
for width in (1,2,3):
    for data in (b'',vector(b'',width)+vector(b'x',width)+vector(bytes(range(255)),width),bytes(width-1), (2).to_bytes(width,'big')+b'x'):
        add('vector-list-'+str(width)+'-'+str(len(data)),3,width,data)
    if width>1: add('vector-list-wide-'+str(width),3,width,vector(bytes(range(256))+b'x',width))
for data in (b'',ext(0)+ext(63,b'x')+ext(64)+ext(65535),ext(65535)+ext(65535),b'\0',b'\0\x01\0',ext(1,b'x')[:-1]): add('extension-list-'+data.hex(),4,32,data)
for data in (b'',entries,cert(b'x'),cert(b''),cert(b'x',ext(65535)+ext(65535)),entries[:-1]): add('certificate-list-'+str(len(data)),5,32,data)
for kind in sorted(KINDS|{0,3,254,255}):
    for data in (b'',b'opaque body'): add('raw-frame-'+str(kind)+'-'+str(len(data)),6,kind,data)

source=bytearray(); expected=bytearray(); records=[]
for name,op,param,layout,data in cases:
    assert len(data)<=4096
    source+=struct.pack('<4Q',op,param,layout,len(data))+data
    expected+=result(op,param,data)
    records.append(f'{name}\top={op},param={param},layout={layout},length={len(data)}\t{len(expected)}\n')
pathlib.Path(sys.argv[1]).write_bytes(source); pathlib.Path(sys.argv[2]).write_bytes(expected); pathlib.Path(sys.argv[3]).write_text(''.join(records))
print(len(cases))
