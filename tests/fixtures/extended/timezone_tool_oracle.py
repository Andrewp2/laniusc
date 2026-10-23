"""Real timezone-tool consumer, independent zoneinfo output and syscall faults."""
import csv
import datetime as dt
import io
import os
import pathlib
import re
import runpy
import struct
import subprocess
import sys
import tempfile
import zoneinfo

exe=sys.argv[1]
model=runpy.run_path('tests/fixtures/extended/timezone_oracle.py')
tzif=model['tzif'];epoch=model['EPOCH'];seconds=model['seconds'];multi=model['multi']
def run(args,data):return subprocess.run([exe]+args,input=data,capture_output=True,timeout=15)
def rows(result):
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    return list(csv.DictReader(io.StringIO(result.stdout.decode())))
def expected(stamp,nanos,z,index=0,count=1):
    v=(epoch+dt.timedelta(seconds=stamp)).astimezone(z)
    return dict(zip('candidate count unix_seconds nanos year month day hour minute second offset_seconds is_dst designation'.split(),map(str,[index,count,stamp,nanos,v.year,v.month,v.day,v.hour,v.minute,v.second,int(v.utcoffset().total_seconds()),int(v.dst()!=dt.timedelta(0)),v.tzname()])))
for name in ['UTC','America/New_York','Europe/Dublin','Asia/Kathmandu','Africa/Monrovia','Australia/Lord_Howe','Pacific/Apia']:
    data=next(pathlib.Path(root,name) for root in zoneinfo.TZPATH if pathlib.Path(root,name).is_file()).read_bytes()
    z=zoneinfo.ZoneInfo.from_file(io.BytesIO(data))
    for date in [dt.datetime(1850,1,1,tzinfo=dt.timezone.utc),dt.datetime(2024,7,1,tzinfo=dt.timezone.utc),dt.datetime(2500,12,31,tzinfo=dt.timezone.utc)]:
        stamp=seconds(date);actual=rows(run(['--nanos','123456789','at','--',str(stamp)],data))
        assert actual==[expected(stamp,123456789,z)],(name,date,actual)
    r=run(['info'],data);assert r.returncode==0 and not r.stderr
    lines=r.stdout.decode().splitlines();meta=model['layout'](data)
    assert lines[0]=='version,transitions,types,footer' and lines[2]=='type,offset_seconds,is_dst,designation'
    assert list(map(int,lines[1].split(',')[:3]))==list(meta[:3]) and len(lines)==3+meta[2]
ny=pathlib.Path('/usr/share/zoneinfo/America/New_York').read_bytes();z=zoneinfo.ZoneInfo.from_file(io.BytesIO(ny))
for value in [dt.datetime(2024,11,3,1,30),dt.datetime(2024,1,1,1,30)]:
    stamp_rows=model['local_rows'](value,123456789,z);arg=value.isoformat()+'.123456789'
    r=run(['local',arg],ny);want=[expected(t[0],123456789,z,i,len(stamp_rows)) for i,t in enumerate(stamp_rows)]
    assert rows(r)==want,(r.stdout,want)
    for policy,index in [('earliest',0),('latest',len(stamp_rows)-1)]:
        assert rows(run(['--resolve',policy,'local',arg],ny))==[want[index]]
r=run(['local','2024-11-03T01:30:00','--resolve','reject'],ny);assert r.returncode==2 and not r.stdout and b'local-fold' in r.stderr
for policy in ['all','reject','earliest','latest']:
    r=run(['local','2024-03-10T02:30:00','--resolve',policy],ny);assert r.returncode==2 and not r.stdout and b'local-gap' in r.stderr
fold_args=['local','1970-01-01T00:05:50.987654321']
r=run(fold_args,multi);fold_rows=rows(r);assert len(fold_rows)==4
assert [int(x['unix_seconds']) for x in fold_rows]==[50,150,250,350]
assert [int(x['candidate']) for x in fold_rows]==[0,1,2,3] and all(x['count']=='4' for x in fold_rows)
for policy,index in [('earliest',0),('latest',3)]:assert rows(run(fold_args+['--resolve',policy],multi))==[fold_rows[index]]
# Designations are byte views; the CLI makes arbitrary legacy octets safe CSV.
unsafe=tzif(version=1,types=[(1172,0,0),(0,0,4),(0,0,5)],chars=b'A,\xff\0\0UTC\0',tail=b'')
r=run(['at','0'],unsafe);assert rows(r)[0]['designation']==r'A\x2c\xff'
r=run(['info'],unsafe);assert r.returncode==0 and b'1,0,0,\n2,0,0,UTC\n' in r.stdout,(r.stdout,r.stderr)
valid=tzif()
invalid_args=[[],['bad'],['info','x'],['at'],['local'],['at','x'],['at','9223372036854775808'],['at','0','x'],['at','0','--nanos','1000000000'],['info','--nanos','1'],['info','--resolve','all'],['at','0','--nanos','1','--nanos','2'],['local','2024-01-01T00:00:00Z'],['local','2024-01-01T00:00:00+01:00'],['local','2024-02-30T00:00:00'],['local','2024-01-01T00:00:60'],['local','2024-01-01T00:00:00.1234567890'],['local','2024-01-01T00:00:00','--resolve','shift'],['--help','info'],['info','--max-work','1000000001'],['info','--max-input-bytes','67108865'],['info','--max-output-bytes','16777217'],['info','--max-transitions','1000001'],['info','--max-candidates','65537'],['info','--max-candidates','-1']]
for args in invalid_args:
    r=run(args,valid);assert r.returncode==2 and not r.stdout and r.stderr,(args,r.returncode,r.stdout,r.stderr)
for args,data in [(['info'],b''),(['info'],b'not a zone'),(['info'],valid[:-1]),(['info'],valid+b'x')]:
    r=run(args,data);assert r.returncode==2 and not r.stdout and r.stderr,(args,r.returncode,r.stderr)
for args,data in [(['info','--max-input-bytes','1'],valid),(['info','--max-transitions','0'],multi),(['info','--max-work','0'],valid),(['info','--max-output-bytes','1'],valid),(fold_args+['--max-candidates','3'],multi)]:
    r=run(args,data);assert r.returncode==3 and not r.stdout and b'resource-limit' in r.stderr,(args,r.returncode,r.stdout,r.stderr)
leaps=tzif(version=4,leaps=[(78796800,1)])
r=run(['info'],leaps);assert r.returncode==2 and not r.stdout and b'unsupported-leap-time-scale' in r.stderr
r=run(['local','2024-01-01T00:00:00'],tzif(tail=b'<-00>3EDT4,0/0,J365/23'));assert rows(r)[0]['unix_seconds']=='1704081600'
r=run(['info'],tzif(tail=b'AAA0BBB,365/167,0/-167'));assert r.returncode==2 and not r.stdout and b'unsupported-transition-rule' in r.stderr
truncated=tzif(version=1,transitions=[0],indices=[0],tail=b'')
r=run(['at','1'],truncated);assert r.returncode==2 and not r.stdout and b'unspecified-zone-coverage' in r.stderr
r=run(['--help'],b'');assert r.returncode==0 and r.stdout.startswith(b'Usage: timezone-tool ') and not r.stderr
# Every native anonymous mapping must be released on success and every late
# fault, measured from syscalls rather than assumptions about allocator calls.
def traced(args,data,inject=None,output=None):
    with tempfile.NamedTemporaryFile() as trace:
        command=['strace','-qq','-o',trace.name,'-e','trace=mmap,munmap,read,write']
        if inject:command+=['-e',inject]
        command += [exe]+args
        r=subprocess.run(command,input=data,stdout=output or subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
        log=pathlib.Path(trace.name).read_text()
    live={};allocs=0
    for line in log.splitlines():
        m=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if m:allocs+=1;assert m[2] not in live;live[m[2]]=int(m[1])
        m=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if m:assert live.pop(m[1],None)==int(m[2]),line
    assert not live,('leaked mappings',live,inject,log)
    return r,allocs,log
r,count,_=traced(fold_args,multi);baseline=r.stdout;assert r.returncode==0 and count>=5,(r.returncode,count,r.stderr)
for nth in range(1,count+1):
    r,_,log=traced(fold_args,multi,'inject=mmap:error=ENOMEM:when='+str(nth))
    assert r.returncode==4 and not r.stdout and r.stderr,(nth,r.returncode,r.stdout,r.stderr,log)
for args,data in [(fold_args+['--max-candidates','3'],multi),(['local','2024-03-10T02:30:00'],ny),(['info','--max-output-bytes','1'],valid),(['info'],leaps)]:
    r,_,_=traced(args,data);assert r.returncode in [2,3] and not r.stdout
for call in ['read','write']:
    r,_,_=traced(fold_args,multi,'inject='+call+':error=EINTR:when=1')
    assert r.returncode==0 and r.stdout==baseline,(call,r.returncode,r.stderr)
    r,_,_=traced(fold_args,multi,'inject='+call+':error=EIO:when=1')
    assert r.returncode==5 and not r.stdout and r.stderr,(call,r.returncode,r.stderr)
r,_,_=traced(fold_args,multi,'inject=write:retval=1:when=1')
assert r.returncode==0 and r.stdout==baseline[1:],(r.returncode,len(r.stdout),len(baseline),r.stderr)
with open('/dev/full','wb') as full:
    r,_,_=traced(fold_args,multi,output=full);assert r.returncode==5 and r.stderr
print('verified timezone-tool historical/future CSV, four-way folds, gaps, limits,',count,'allocation faults, I/O faults and mapping cleanup')
