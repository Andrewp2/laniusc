"""Independent TZif vectors plus Python zoneinfo; never production code."""
import datetime as dt
import io
import os
import pathlib
import random
import struct
import subprocess
import sys
import zoneinfo

UTC=dt.timezone.utc
EPOCH=dt.datetime(1970,1,1,tzinfo=UTC)
LIMITS=(4000000,200000,256,65536,4096,258,33554432)
ERR={name:i+1 for i,name in enumerate('InvalidView InputLimit TransitionLimit TypeLimit DesignationLimit FooterLimit CandidateLimit WorkLimit AllocationFailed Truncated Magic Version Counts TransitionOrder TypeIndex Offset Indicator Designation Footer InvalidRule MissingRule InconsistentFooter UnsupportedLeapScale Unspecified InvalidLocal LeapSecond YearRange Overflow Gap Ambiguous Destroyed UnsupportedRule'.split())}

def header(version,transitions,types,chars,leaps=0,std=0,ut=0):
    return b'TZif'+(b'\0' if version==1 else str(version).encode())+b'\0'*15+struct.pack('>6I',ut,std,leaps,transitions,types,chars)

def block(width,transitions,indices,types,chars,leaps=(),std=b'',ut=b''):
    return (b''.join(int(x).to_bytes(width,'big',signed=True) for x in transitions)+bytes(indices)+
            b''.join(struct.pack('>iBB',*x) for x in types)+chars+
            b''.join(int(t).to_bytes(width,'big',signed=True)+struct.pack('>i',c) for t,c in leaps)+std+ut)

def tzif(version=3,transitions=(),indices=(),types=((0,0,0),),chars=b'UTC\0',tail=b'UTC0',leaps=(),std=b'',ut=b''):
    h=header(version,len(transitions),len(types),len(chars),len(leaps),len(std),len(ut))
    body=block(4 if version==1 else 8,transitions,indices,types,chars,leaps,std,ut)
    if version==1:return h+body
    legacy=header(version,0,1,1)+block(4,(),(),((0,0,0),),b'\0')
    return legacy+h+body+b'\n'+tail+b'\n'

def layout(data):
    def one(at,width):
        ut,std,leap,nt,ty,nc=struct.unpack_from('>6I',data,at+20)
        end=at+44+nt*(width+1)+ty*6+nc+leap*(width+4)+std+ut
        return end,nt,ty,nc
    version=1 if data[4]==0 else int(chr(data[4]))
    end,nt,ty,nc=one(0,4);start=0;width=4;tail=b''
    if version>1:start=end;width=8;end,nt,ty,nc=one(start,8);tail=data[end+1:-1]
    transitions=[int.from_bytes(data[start+44+i*width:start+44+(i+1)*width],'big',signed=True) for i in range(nt)]
    return version,nt,ty,tail,transitions,start,end

def seconds(value):
    delta=value.astimezone(UTC)-EPOCH
    return delta.days*86400+delta.seconds

def at(second,nanos=123456789,op=0):return (op,second,nanos,0,0,0,0,0,0)
def local(value,op=1,nanos=987654321):return (op,0,nanos,value.year,value.month,value.day,value.hour,value.minute,value.second)
def row(second,nanos,z):
    value=(EPOCH+dt.timedelta(seconds=second)).astimezone(z)
    return (second,nanos,value.year,value.month,value.day,value.hour,value.minute,value.second,int(value.utcoffset().total_seconds()),int(value.dst()!=dt.timedelta(0)),value.tzname().encode())
def local_rows(value,nanos,z):
    found={}
    for fold in [0,1]:
        aware=value.replace(tzinfo=z,fold=fold);stamp=seconds(aware)
        back=(EPOCH+dt.timedelta(seconds=stamp)).astimezone(z)
        if back.replace(tzinfo=None)==value:found[stamp]=row(stamp,nanos,z)
    return [found[x] for x in sorted(found)]

def unknown_window(data,naive):
    version,nt,ty,tail,times,start,end=layout(data)
    width=4 if version==1 else 8
    indices=data[start+44+nt*width:start+44+nt*(width+1)]
    types_at=start+44+nt*(width+1);chars_at=types_at+ty*6
    names=[]
    for i in range(ty):
        pos=chars_at+data[types_at+i*6+5]
        names.append(data[pos:data.index(b'\0',pos)])
    low,high=naive-2147483647,naive+2147483647
    if not times:return not tail and names[0]==b'-00'
    if low<times[0] and names[0]==b'-00':return True
    if not tail and high>=times[-1]:return True
    for i in range(len(times)-1):
        if times[i]<=high and times[i+1]>low and names[indices[i]]==b'-00':return True
    return False

def reference_queries(data,queries):
    reference=data
    if layout(data)[3]==b'AAA0BBB,365/167,364/166':
        events=[]
        for year in range(1896,9994):
            january=dt.datetime(year,1,1,tzinfo=UTC)
            events.extend([(seconds(january+dt.timedelta(days=365,hours=167)),1),
                           (seconds(january+dt.timedelta(days=364,hours=165)),0)])
        events.sort()
        reference=tzif(transitions=[t for t,k in events],indices=[k for t,k in events],
                       types=[(0,0,0),(3600,1,4)],chars=b'AAA\0BBB\0',tail=b'')
    if layout(data)[3]==b'AAA0BBB,0/0,365/1':
        # Pinned tzcode's annual full-year guard emits these events only in
        # leap years. Century gaps exercise looking past nearby empty years.
        events=[]
        for year in range(1800,9995):
            if year%4==0 and (year%100!=0 or year%400==0):
                january=dt.datetime(year,1,1,tzinfo=UTC)
                events.extend([(seconds(january),1),(seconds(january+dt.timedelta(days=365)),0)])
        reference=tzif(transitions=[t for t,k in events],indices=[k for t,k in events],
                       types=[(0,0,0),(3600,1,4)],chars=b'AAA\0BBB\0',tail=b'')
    z=zoneinfo.ZoneInfo.from_file(io.BytesIO(reference))
    wanted=[]
    for op,stamp,nanos,*fields in queries:
        if op==0:
            r=row(stamp,nanos,z);wanted.append((ERR['Unspecified'],[]) if r[-1]==b'-00' else (0,[r]));continue
        value=dt.datetime(*fields)
        if unknown_window(data,seconds(value.replace(tzinfo=UTC))):wanted.append((ERR['Unspecified'],[]));continue
        rows=local_rows(value,nanos,z)
        if op==1:wanted.append((0,rows))
        elif not rows:wanted.append((ERR['Gap'],[]))
        elif op==4 and len(rows)>1:wanted.append((ERR['Ambiguous'],[]))
        else:wanted.append((0,[rows[-1] if op==3 else rows[0]]))
    return wanted

cases=[]
def add(data,queries=(),wanted=None,error=0,limits=LIMITS,label=''):
    if not error and wanted is None:wanted=reference_queries(data,queries)
    cases.append((data,list(queries),wanted,error,limits,label))

rng=random.Random(0x96362026)
names=['UTC','America/New_York','America/Chicago','Europe/Berlin','Europe/Dublin','Asia/Kathmandu','Asia/Kolkata','Africa/Monrovia','Australia/Lord_Howe','Pacific/Apia','Pacific/Chatham','Antarctica/Troll']
for name in names:
    source=next(pathlib.Path(root,name) for root in zoneinfo.TZPATH if pathlib.Path(root,name).is_file())
    data=source.read_bytes();meta=layout(data);queries=[]
    for year in [1800,1850,1900,1916,1945,1970,2000,2024,2038,2050,2100,2500,9990]:
        for month in [1,4,7,10]:queries.append(at(seconds(dt.datetime(year,month,15,12,tzinfo=UTC))))
    for stamp in meta[4][-50:]:
        for delta in [-1,0,1]:queries.append(at(stamp+delta))
    if meta[4]:queries.extend([at(meta[4][0]-1),at(meta[4][0])])
    for _ in range(25):
        value=dt.datetime(rng.randrange(1850,2600),rng.randrange(1,13),rng.randrange(1,28),rng.randrange(24),rng.randrange(60),rng.randrange(60))
        queries.append(local(value))
    # Ordinary IANA gaps/folds, including non-hour DST and the Apia date skip.
    for value in [dt.datetime(2024,3,10,2,30),dt.datetime(2024,11,3,1,30),dt.datetime(2024,10,27,2,30),dt.datetime(2024,4,7,1,45),dt.datetime(2011,12,30,12)]:
        for op in [1,2,3,4]:queries.append(local(value,op))
    add(data,queries,label=name)

# Explicit footer grammar, negative DST, southern hemisphere, leap days,
# transition hours outside their day, all-year rules and year boundaries.
for version,tail in [(2,b'UTC0'),(2,b'<+0545>-5:45'),(2,b'EST5EDT,M3.2.0,M11.1.0'),
                     (3,b'IST-1GMT0,M10.5.0,M3.5.0/1'),(3,b'AEST-10AEDT-11,M10.1.0,M4.1.0/3'),
                     (3,b'<-03>3<-02>,M3.5.0/-2,M10.5.0/-1'),
                     (3,b'AAA0BBB,59/167,300/-167'),(3,b'AAA0BBB,J60/1,J300/2'),
                     (3,b'AAA0BBB,365/167,364/166'),(3,b'AAA0BBB,0/0,365/1'),(4,b'AAA0BBB,0/-167,J365/167')]:
    data=tzif(version=version,tail=tail);queries=[]
    for year in [1899,1900,1999,2000,2023,2024,2025,2038,2100,2103,2400,9990]:
        for month,day in [(1,1),(1,7),(2,28),(3,1),(3,30),(4,1),(10,1),(10,31),(12,25),(12,31)]:
            value=dt.datetime(year,month,day,12,tzinfo=UTC);queries.append(at(seconds(value)));queries.append(local(value.replace(tzinfo=None)))
    add(data,queries,label=('tail',version,tail))
for version,tail,offset,name in [(2,b'XXX3EDT4,0/0,J365/23',-14400,b'EDT'),(3,b'EST5EDT,0/0,J365/25',-14400,b'EDT')]:
    data=tzif(version=version,tail=tail);queries=[];wanted=[]
    for year in [1999,2000,2001,2024,2100]:
        for month,day,hour in [(1,1,0),(1,1,4),(7,1,12),(12,31,23)]:
            stamp=seconds(dt.datetime(year,month,day,hour,tzinfo=UTC));queries.append(at(stamp));civil=EPOCH+dt.timedelta(seconds=stamp+offset)
            wanted.append((0,[(stamp,123456789,civil.year,civil.month,civil.day,civil.hour,civil.minute,civil.second,offset,1,name)]))
    add(data,queries,wanted,label=('all-year',tail))

# The standard designation is ignored for perpetual DST, even if it is -00.
data=tzif(tail=b'<-00>3EDT4,0/0,J365/23')
queries=[at(1704067200),local(dt.datetime(2024,1,1)),local(dt.datetime(2024,1,1),4)]
wanted=[(0,[(1704067200,123456789,2023,12,31,20,0,0,-14400,1,b'EDT')])]
wanted += [(0,[(1704081600,987654321,2024,1,1,0,0,0,-14400,1,b'EDT')])]*2
for stamp in [-(1<<63),(1<<63)-1]:
    queries.append(at(stamp,0,5));wanted.append((0,[(stamp,0,0,0,0,0,0,0,-14400,1,b'EDT')]))
add(data,queries,wanted,label='perpetual DST ignores standard placeholder')
add(tzif(tail=b'<-00>0'),[at(0),local(dt.datetime(2024,1,1))],[(ERR['Unspecified'],[])]*2,label='fixed footer placeholder')
data=tzif(tail=b'UTC0<-00>,M3.2.0,M11.1.0')
queries=[at(1704067200),at(1719792000),local(dt.datetime(2024,1,1))]
wanted=[(0,[(1704067200,123456789,2024,1,1,0,0,0,0,0,b'UTC')]),(ERR['Unspecified'],[]),(ERR['Unspecified'],[])]
add(data,queries,wanted,label='active footer placeholder coverage')


# Four real candidates for one local value; Python's fold bit is deliberately
# not used as an oracle for this arbitrary conforming TZif transition sequence.
multi=tzif(transitions=[100,200,300],indices=[1,2,3],types=[(300,0,0),(200,0,4),(100,0,8),(0,0,12)],chars=b'AAA\0BBB\0CCC\0UTC\0')
value=dt.datetime(1970,1,1,0,5,50);queries=[local(value,op) for op in [1,2,3,4]]
rows=[(u,987654321,1970,1,1,0,5,50,off,0,name) for u,off,name in [(50,300,b'AAA'),(150,200,b'BBB'),(250,100,b'CCC'),(350,0,b'UTC')]]
add(multi,queries,[(0,rows),(0,rows[:1]),(0,rows[-1:]),(ERR['Ambiguous'],[])],label='four-way fold')
lim=list(LIMITS);lim[5]=3;add(multi,queries[:1],[(ERR['CandidateLimit'],[])],limits=tuple(lim),label='candidate bound')

# Pre-first defaults, second-precision and unusually large valid offsets.
for offset in [-2147483647,-89999,-1521,1172,93599,2147483647]:
    data=tzif(version=1,types=[(offset,0,0)],tail=b'');queries=[at(0),at(-(1<<63),0,5),at((1<<63)-1,0,5)]
    shifted=EPOCH+dt.timedelta(seconds=offset)
    wanted=[(0,[(0,123456789,shifted.year,shifted.month,shifted.day,shifted.hour,shifted.minute,shifted.second,offset,0,b'UTC')])]
    wanted += [(0,[(stamp,0,0,0,0,0,0,0,offset,0,b'UTC')]) for stamp in [-(1<<63),(1<<63)-1]]
    add(data,queries,wanted,label=('fixed-offset',offset))
old=tzif(version=1,transitions=[100],indices=[1],types=[(100,0,0),(200,1,4)],chars=b'OLD\0NEW\0')
add(old,[at(99),at(100),at(101)],[(0,[(99,123456789,1970,1,1,0,3,19,100,0,b'OLD')]),(ERR['Unspecified'],[]),(ERR['Unspecified'],[])],label='v1 coverage')
unknown=tzif(transitions=[0],indices=[1],types=[(0,0,0),(0,0,4)],chars=b'-00\0UTC\0')
add(unknown,[at(-1),at(0),local(dt.datetime(2024,1,1))],[(ERR['Unspecified'],[]),(0,[(0,123456789,1970,1,1,0,0,0,0,0,b'UTC')]),(ERR['Unspecified'],[])],label='truncation coverage')

# Malformed layouts and semantic guards, with exact classifications where
# the vector targets one guard. Arbitrary truncations only require failure.
good=tzif();meta=layout(good);modern=meta[5]
for n in range(len(good)):add(good[:n],error=-1,label=('prefix',n))
def changed(offset,payload,error,label):
    data=bytearray(good);data[offset:offset+len(payload)]=payload;add(bytes(data),error=ERR[error],label=label)
changed(0,b'NOPE','Magic','magic');changed(4,b'5','Version','version');changed(modern+4,b'2','Version','second-version')
legacy_ignored=bytearray(good);legacy_ignored[44:51]=b'\x80\0\0\0\2\xff\xfe'
add(bytes(legacy_ignored),[at(0)],label='modern reader skips legacy record semantics')
reserved=bytearray(good);reserved[5:20]=b'x'*15;reserved[modern+5:modern+20]=b'y'*15
add(bytes(reserved),[at(0)],label='reserved header bytes ignored')

for field in [20,24]:changed(modern+field,struct.pack('>I',2),'Counts','indicator count')
changed(modern+36,b'\0'*4,'Counts','zero type count');changed(modern+40,b'\0'*4,'Counts','zero char count')
for field in [20,24,28,32,36,40]:changed(modern+field,struct.pack('>I',0xffffffff),'Truncated','oversize count')
add(tzif(transitions=[100,99],indices=[0,0]),error=ERR['TransitionOrder'],label='transition order')
add(tzif(transitions=[100],indices=[1]),error=ERR['TypeIndex'],label='type index')
add(tzif(types=[(-(1<<31),0,0)]),error=ERR['Offset'],label='forbidden offset')
add(tzif(types=[(0,2,0)]),error=ERR['Indicator'],label='isdst')
add(tzif(types=[(0,0,255)]),error=ERR['Designation'],label='designation index')
add(tzif(chars=b'ABC'),error=ERR['Designation'],label='unterminated designation')
add(tzif(std=b'\2'),error=ERR['Indicator'],label='standard indicator')
add(tzif(ut=b'\1'),error=ERR['Indicator'],label='UT requires standard')
add(tzif(std=b'\1',ut=b'\2'),error=ERR['Indicator'],label='UT indicator')
for version in [1,2,3,4]:
    add(tzif(version=version,leaps=[(78796800,1)]),error=ERR['UnsupportedLeapScale'],label=('leap scale',version))
add(tzif(version=4,leaps=[(78796800,5),(94694400,5)]),error=ERR['UnsupportedLeapScale'],label='v4 leap expiration/truncation')
for tail in [b'UT0',b'<UTC0',b'UTC25',b'UTC0DST25,M1.1.0,M2.1.0',b'UTC0DST,M0.1.0,M2.1.0',b'UTC0DST,M1.0.0,M2.1.0',b'UTC0DST,M1.1.7,M2.1.0',b'UTC0DST,J0,J300',b'UTC0DST,366,0',b'UTC0DST,1/168,2',b'UTC0DST,1/-168,2',b'UTC0DST,1/2u,2',b'UTC0\0',b'UTC0\n']:
    add(tzif(tail=tail),error=-1,label=('invalid tail',tail))
add(tzif(tail=b'UTC0DST'),error=ERR['MissingRule'],label='missing rules')
for tail in [b'AAA0BBB,365/167,0/-167',b'AAA0BBB,365/0,0/1']:
    add(tzif(tail=tail),error=ERR['UnsupportedRule'],label=('overlapping/tied annual pairs',tail))
for tail in [b'UTC0DST,1/-1,2',b'UTC0DST,1/25,2']:
    add(tzif(version=2,tail=tail),error=ERR['InvalidRule'],label='v2 transition time restriction')
add(tzif(transitions=[0],indices=[0],tail=b'XYZ1'),error=ERR['InconsistentFooter'],label='footer consistency')
for suffix in [b'',b'\n',b'\0',b'UTC0']:
    add(good[:-len(b'\nUTC0\n')]+suffix,error=-1,label='footer framing')
for index,value,error in [(0,len(good)-1,'InputLimit'),(1,0,'TransitionLimit'),(2,0,'InvalidView'),(3,3,'DesignationLimit'),(4,3,'FooterLimit'),(6,0,'WorkLimit')]:
    data=good if index!=1 else tzif(transitions=[0],indices=[0])
    lim=list(LIMITS);lim[index]=value;add(data,error=ERR[error],limits=tuple(lim),label=('limit',index,value))
lim=list(LIMITS);lim[2]=1;add(tzif(types=[(0,0,0),(1,0,0)]),error=ERR['TypeLimit'],limits=tuple(lim),label='type bound')
add(good,[at(0,1000000000),local(dt.datetime(2024,1,1))],[(ERR['InvalidLocal'],[]),(0,[(seconds(dt.datetime(2024,1,1,tzinfo=UTC)),987654321,2024,1,1,0,0,0,0,0,b'UTC')])],label='nanoseconds')
add(good,[(1,0,0,2024,2,30,1,1,1),(1,0,0,2024,1,1,0,0,60)],[(ERR['InvalidLocal'],[]),(ERR['LeapSecond'],[])],label='invalid civil')

# Query work is bounded independently of parse work. Repeated long borrowed
# names make the complete candidate scan exceed a budget that parses safely.
long=tzif(version=1,types=[(0,0,0)]*100,chars=b'A'*1023+b'\0',tail=b'')
lim=list(LIMITS);lim[6]=125000
add(long,[local(dt.datetime(2024,1,1))],[(ERR['WorkLimit'],[])],limits=tuple(lim),label='query work exhaustion')
all_year=tzif(tail=b'XXX3EDT4,0/0,J365/23')
lim=list(LIMITS);lim[6]=256
add(all_year,error=ERR['WorkLimit'],limits=tuple(lim),label='annual cycle work exhaustion')
for offset in [-1,0,1]:
    data=tzif(version=1,types=[(offset,0,0)],tail=b'')
    queries=[at(-(1<<63)),at((1<<63)-1)]
    wanted=[(ERR['Overflow'] if offset<0 else ERR['YearRange'],[]),(ERR['Overflow'] if offset>0 else ERR['YearRange'],[])]
    add(data,queries,wanted,label=('civil i64 bounds',offset))
add(tzif(),[at(-(1<<63)),at((1<<63)-1)],[(ERR['YearRange'],[])]*2,label='fixed footer civil bounds')
add(tzif(tail=b'AAA0BBB,M3.2.0,M11.1.0'),[at(-(1<<63),op=5),at((1<<63)-1,op=5)],[(ERR['YearRange'],[])]*2,label='DST footer year bounds')
for name,index in [(b'AAASUFFIX\0',3),(b'\0',0),(b'A,\xff\0',0)]:
    data=tzif(version=1,types=[(1172,1,index)],chars=name,tail=b'')
    designation=name[index:-1]
    add(data,[at(0)],[(0,[(0,123456789,1970,1,1,0,19,32,1172,1,designation)])],label=('raw designation/default DST',name,index))

# 30000 historical transitions and repeated bulk queries exercise binary search
# and the complete candidate scan without an I/O or timing oracle.
transitions=list(range(-1500000000,-1500000000+30000*1000,1000));types=[(0,0,0),(1,0,4)];indices=[i%2 for i in range(len(transitions))]
# Last type is offset1, matching the fixed +1-second footer.
data=tzif(transitions=transitions,indices=indices,types=types,chars=b'AAA\0BBB\0',tail=b'BBB-0:00:01')
queries=[at(transitions[i]+delta,0) for i in range(0,len(transitions),41) for delta in [-1,0,1]]
wanted=[]
for _,stamp,nanos,*_ in queries:
    import bisect
    i=bisect.bisect_right(transitions,stamp)-1;off=0 if i<0 else indices[i];v=EPOCH+dt.timedelta(seconds=stamp+off)
    wanted.append((0,[(stamp,0,v.year,v.month,v.day,v.hour,v.minute,v.second,off,0,b'BBB' if off else b'AAA')]))
add(data,queries,wanted,label='30000 transitions')

def run(executable):
    packet=bytearray()
    for data,queries,wanted,error,limits,label in cases:
        packet+=struct.pack('<7iQi',len(data),*limits[:6],limits[6],len(queries))+data
        for q in queries:packet+=struct.pack('<iqI6i',*q)
    r=subprocess.run([executable],input=packet,capture_output=True,timeout=35)
    assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr,len(r.stdout))
    at=0
    def take(n):
        nonlocal at
        b=r.stdout[at:at+n];assert len(b)==n,(at,n,len(r.stdout));at+=n;return b
    def integer():return struct.unpack('<i',take(4))[0]
    def rows():
        n=integer();out=[]
        for _ in range(n):
            values=struct.unpack('<qI9i',take(48));out.append((*values[:-1],take(values[-1])))
        return out
    for idx,(data,queries,wanted,error,limits,label) in enumerate(cases):
        status=integer();context=('seed=0x96362026',idx,label)
        if error:
            assert status>0 and (error<0 or status==error),(context,status,error);continue
        assert status==0,(context,status)
        version,nt,ty,footer_n=struct.unpack('<4i',take(16));footer=take(footer_n);expected_meta=layout(data)
        assert (version,nt,ty,footer)==expected_meta[:4],(context,version,nt,ty,footer,expected_meta[:4])
        for qi,(q,(expected_error,expected_rows)) in enumerate(zip(queries,wanted)):
            status=integer();assert status==expected_error,(context,qi,q,status,expected_error)
            if status==0:
                actual=rows();assert actual==expected_rows,(context,qi,q,actual,expected_rows)
    assert at==len(r.stdout),(at,len(r.stdout))
    print('verified',len(cases),'TZif cases and',sum(len(c[1]) for c in cases),'queries; Python zoneinfo, four-way folds, RFC tails and 30000 transitions')

if __name__=='__main__':run(sys.argv[1])
