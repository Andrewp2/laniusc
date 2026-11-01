"""Independent compressed files, atomic publication and reached failure traces."""
from collections import Counter
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zlib

CAP=16*1024*1024
OUTPUT_CAP=64*1024*1024
HELP=(b'Usage: decompress_file --format raw|zlib|gzip [--] INPUT OUTPUT\n'
      b'Decode a regular no-follow input into a new file. Existing output is never replaced.\n'
      b'Short options: -f FORMAT, -h. --help validates supplied arguments and opens no files.\n'
      b'Duplicate options, unknown formats and extra operands are errors.\n'
      b"Paths use 1..4095 raw bytes; the output leaf uses 1..255 bytes and cannot be '.' or '..'.\n"
      b'An output path cannot end in /. The output parent must already be a directory.\n'
      b'Limits: 16 MiB compressed, 64 MiB decoded, 1024 gzip members, 32768 read attempts.\n'
      b'Fixed buffers: 4096 input bytes, 4096 output bytes, 32768 history bytes, 707 i32 entries.\n'
      b'Decoder calls are capped at 262144 and temporary-file write attempts at 131072.\n'
      b'Complete headers, checksums, trailers, EOF and input close precede publication.\n'
      b'Publication uses NoReplace in a cooperative local filesystem namespace.\n'
      b'Published or unconfirmed failures are reported without promising rollback.\n'
      b'Cleanup may keep a recovery file; its parent and name are reported as hexadecimal bytes.\n'
      b'Interrupted work spends attempts; blocking I/O has no wall-clock timeout.\n'
      b'Successful execution writes no stdout or stderr. Help writes stdout.\n')
CALLS='openat,close,fcntl,statx,read,write,fsync,renameat2,unlinkat,getrandom,mmap,munmap,mremap,brk,rt_sigaction'
DIAGNOSTIC=re.compile(rb'decompress_file: code=([0-8]) phase=([a-z-]+) visibility=(not-published|published|unconfirmed) file_synced=([01]) directory_synced=([01]) cleanup_failed=([01]) retained=([01]) recovery_parent_hex=([0-9a-f]+|-) recovery_name_hex=([0-9a-f]+|-)\n')

def pattern(n):
    block=bytes((i*73+19)%256 for i in range(256));return (block*((n+255)//256))[:n]

def compress(data,format='gzip',level=6,strategy=zlib.Z_DEFAULT_STRATEGY):
    bits={'raw':-15,'zlib':15,'gzip':31}[format];c=zlib.compressobj(level,zlib.DEFLATED,bits,8,strategy)
    wire=c.compress(data)+c.flush();assert zlib.decompress(wire,bits)==data;return wire

def arguments(text):
    out=[];start=0;depth=0;quoted=False;escaped=False
    for index,char in enumerate(text):
        if quoted:
            if escaped: escaped=False
            elif char=='\\':escaped=True
            elif char=='"':quoted=False
        elif char=='"':quoted=True
        elif char in '([{':depth+=1
        elif char in ')]}':depth-=1
        elif char==',' and depth==0:out.append(text[start:index].strip());start=index+1
    out.append(text[start:].strip());assert not quoted and depth==0
    return out

def unquote(value):
    assert value.startswith('"') and value.endswith('"'),value
    return bytes.fromhex(value[1:-1].replace('\\x',''))

def ledger(text,preflight=False,observe_reads=True):
    events=[];counts=Counter();maps={};fds={};retired=[];peak=0;temp=None;renamed=False
    input_eof=False;input_closed=False;file_synced=False;temporary_closed=False
    for line in text.splitlines():
        m=re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)',line)
        assert m and m[1] in CALLS.split(','),line
        name,argtext,result=m.groups();args=arguments(argtext);counts[name]+=1
        item=dict(name=name,args=args,argtext=argtext,result=result,ordinal=counts[name],line=line)
        if name=='mmap':
            size=int(args[1]);item['extent']=size
            if result.startswith('0x'):assert result not in maps;maps[result]=size;peak=max(peak,sum(maps.values()))
            else:assert result.startswith('-1 ENOMEM ') and 'INJECTED' in result
        elif name=='munmap':assert result=='0' and maps.pop(args[0],None)==int(args[1]),item
        elif name in ('mremap','brk'):raise AssertionError(item)
        elif name=='openat':
            assert not preflight;path=unquote(args[1]);item['path']=path
            assert 'O_TRUNC' not in args[2]
            if 'O_CREAT' in args[2]:
                assert 'O_EXCL' in args[2] and re.fullmatch(rb'\.tmp-[0-9a-f]{32}',path)
                role='temporary';temp=path
            elif 'O_DIRECTORY' in args[2]:
                role='parent';assert 'O_NOFOLLOW' in args[2] and 'O_NONBLOCK' in args[2]
            else:role='input';assert 'O_RDONLY' in args[2] and 'O_NOFOLLOW' in args[2] and 'O_NONBLOCK' in args[2]
            item['role']=role
            if result.split()[0].isdigit():
                fd=int(result.split()[0]);assert fd>2 and fd not in fds;fds[fd]=role;item['fd']=fd
        elif name=='fcntl':
            fd=int(args[0]);assert fd in fds;item['role']=fds[fd]
            if args[1]=='F_DUPFD_CLOEXEC' and result.split()[0].isdigit():
                new=int(result.split()[0]);assert new not in fds;fds[new]='anchor';item['fd']=new
        elif name=='close':
            fd=int(args[0]);assert fd in fds;item['role']=fds.pop(fd)
            if item['role']=='input':input_closed=result=='0' and (input_eof or not observe_reads)
            if item['role']=='temporary':temporary_closed=result=='0' and file_synced
            if result!='0':assert 'INJECTED' in result;retired.append((fd,item['role']))
        elif name in ('read','fsync','statx'):
            if name=='read':
                fd=int(args[0]);assert fds.get(fd)=='input';item['role']='input'
                assert 1<=int(args[2])<=4096
                if result.split()[0].isdigit():
                    amount=int(result.split()[0]);assert amount<=int(args[2]);input_eof=amount==0
            elif name=='fsync':
                fd=int(args[0]);assert fd in fds;item['role']=fds[fd]
                if item['role']=='temporary':
                    assert input_closed,('file sync before input EOF/close',item)
                    if result=='0':file_synced=True
                elif item['role']=='anchor':assert renamed,('directory sync before publication',item)
        elif name=='write':
            fd=int(args[0]);assert fd in (1,2) or fds.get(fd)=='temporary',item
            if fd>2:assert not renamed;item['role']='temporary'
            else:
                item['role']='stdout' if fd==1 else 'diagnostic'
                assert not maps and not fds,('report before retirement',item,maps,fds)
        elif name=='renameat2':
            assert args[0]==args[2] and fds.get(int(args[0]))=='anchor'
            assert unquote(args[1])==temp and unquote(args[3])==b'result' and args[4]=='RENAME_NOREPLACE'
            assert 'input' not in fds.values() and 'temporary' not in fds.values()
            assert input_closed and temporary_closed and file_synced,('publication before validation/close/sync',item)
            if result=='0':renamed=True
        elif name=='unlinkat':
            assert fds.get(int(args[0]))=='anchor' and unquote(args[1])==temp and args[2]=='0'
            assert not renamed,('unlink after publication',item)
        events.append(item)
    assert not maps and not fds,(maps,fds)
    if preflight:assert not any(x['name'] in ('openat','read','close','fcntl','renameat2','unlinkat') for x in events)
    assert counts['renameat2']<=1
    return dict(events=events,peak=peak,skipped_closes=retired,temp=temp)


def diagnostic(data):
    m=DIAGNOSTIC.fullmatch(data);assert m,data
    keys=('code','phase','visibility','file_synced','directory_synced','cleanup_failed','retained','parent','name')
    values=dict(zip(keys,(v.decode() for v in m.groups())))
    for key in ('code','file_synced','directory_synced','cleanup_failed','retained'):values[key]=int(values[key])
    return values

class Runner:
    observes=True
    def __init__(self,exe,group):
        self.exe=str(Path(exe).resolve());h=Path(self.exe).read_bytes()[:64]
        assert len(h)==64 and h[:6]==b'\x7fELF\x02\x01' and int.from_bytes(h[16:18],'little')==2 and int.from_bytes(h[18:20],'little')==62
        self.directory=Path(tempfile.mkdtemp(prefix=f'decompress-file-{group}-'));self.count=0
    def run(self,name,wire=b'',plain=b'',*,format='gzip',args=None,status=0,expected=None,existing=False,preflight=False,injections=(),quiet=False,large=False,trace_reads=False,closed_stdout=False,setup=None):
        d=self.directory/name;d.mkdir();(d/'out').mkdir();(d/'input.bin').write_bytes(wire)
        old=b'old-destination\0\xff';destination=d/'out/result'
        if existing:destination.write_bytes(old)
        if setup:setup(d)
        before=destination.lstat() if destination.exists() or destination.is_symlink() else None
        command=['strace','--kill-on-exit','-qq','-xx','-s','256','-e','signal=none','-e','trace='+','.join(x for x in CALLS.split(',') if not large or x not in ('read','write') or (trace_reads and x=='read')),'-o',str(d/'trace')]
        for call,ordinal,failure in injections:command+=['-e',f'inject={call}:error={failure}:when={ordinal}']
        command+=[self.exe,*(args if args is not None else ['--format',format,'input.bin','out/result'])]
        (d/'command').write_text(repr(command)+'\n')
        if closed_stdout:
            reader,writer=os.pipe();os.close(reader)
            try:result=subprocess.run(command,cwd=d,stdin=subprocess.DEVNULL,stdout=writer,stderr=subprocess.PIPE,timeout=65,check=False)
            finally:os.close(writer)
            result.stdout=b''
        else:result=subprocess.run(command,cwd=d,stdin=subprocess.DEVNULL,capture_output=True,timeout=65,check=False)
        (d/'stdout').write_bytes(result.stdout);(d/'stderr').write_bytes(result.stderr);(d/'status').write_text(str(result.returncode)+'\n')
        assert result.returncode==status,(name,result.returncode,status,result.stderr)
        help_case=args is not None and status==0 and any(x in ("--help","-h") for x in args)
        assert result.stdout==(HELP if help_case else b''),(name,result.stdout)
        report=None
        if status and not quiet:
            report=diagnostic(result.stderr);assert report['code']==status
            for key,value in (expected or {}).items():assert report[key]==value,(name,key,report,value)
            assert report['retained']==0
        else:assert not result.stderr,(name,result.stderr)
        traced=ledger((d/'trace').read_text(),preflight,not large or trace_reads)
        found=traced['events'];marked=[x for x in found if 'INJECTED' in x['result']];selected=[]
        for call,ordinal,failure in injections:
            positions=range(int(ordinal.split('..')[0]),int(ordinal.split('..')[1])+1) if isinstance(ordinal,str) else [ordinal]
            for position in positions:
                reached=[x for x in found if x['name']==call and x['ordinal']==position]
                assert len(reached)==1 and reached[0]['result'].startswith('-1 '+failure+' ');selected+=reached
        assert {x['line'] for x in marked}=={x['line'] for x in selected}
        assert len(traced['skipped_closes'])==sum(call=='close' for call,_,_ in injections)
        renamed=any(x['name']=='renameat2' and x['result']=='0' for x in found)
        if renamed:
            assert destination.is_file() and destination.read_bytes()==plain
            if report:assert report['visibility']=='published'
        elif before is not None:
            after=destination.lstat();assert (after.st_dev,after.st_ino)==(before.st_dev,before.st_ino)
            if existing:assert destination.read_bytes()==old
        else:assert not destination.exists() and not destination.is_symlink()
        if status==0 and not help_case:assert renamed
        if report and report['name']!='-':
            raw=bytes.fromhex(report['name']);assert bytes.fromhex(report['parent'])==b'out' and raw==traced['temp']
            retained=d/'out'/os.fsdecode(raw);assert retained.is_file();assert report['cleanup_failed']==1
            assert set(p.name for p in (d/'out').iterdir())=={os.fsdecode(raw)}|({'result'} if before else set())
        else:assert set(p.name for p in (d/'out').iterdir())==({'result'} if before or renamed else set())
        assert (d/'input.bin').read_bytes()==wire
        self.count+=1;return traced,report,d


def model(r):
    for format in ('raw','zlib','gzip'):
        for label,plain,level,strategy in [('empty',b'',6,0),('binary',bytes(range(256))*17,6,0),('stored',pattern(8193),0,0),('fixed',b'abcd\0\xff'*12001,6,zlib.Z_FIXED)]:
            r.run(format+'-'+label,compress(plain,format,level,strategy),plain,format=format)
    a,b=pattern(10001),b'member-two'*1001
    r.run('concatenated-gzip',compress(a)+compress(b),a+b)
    r.run('large-fixed-workspace',compress(pattern(4*1024*1024)),pattern(4*1024*1024),large=True)
    r.run('existing-protected',compress(b'new'),b'new',status=2,existing=True,expected={'phase':'commit','visibility':'not-published'})


def rejection(r):
    good=compress(pattern(8193));bad_crc=bytearray(good);bad_crc[-8]^=1;bad_size=bytearray(good);bad_size[-4]^=1
    cases=[('empty',b'','gzip'),('header',b'\x00'*10,'gzip'),('crc',bytes(bad_crc),'gzip'),('isize',bytes(bad_size),'gzip'),
           ('body-truncated',good[:len(good)//2],'gzip'),('trailer-truncated',good[:-1],'gzip'),('trailing-gzip',good+b'x','gzip'),
           ('reserved-raw',b'\x07','raw'),('trailing-raw',compress(b'abc','raw')+b'x','raw'),
           ('trailing-zlib',compress(b'abc','zlib')+b'x','zlib'),('zlib-header',b'\x00\x00','zlib')]
    for name,wire,format in cases:r.run(name,wire,format=format,status=2,existing=True,expected={'phase':'decode','visibility':'not-published'})
    r.run('missing-input',args=['-f','gzip','missing','out/result'],status=3,existing=True,expected={'phase':'input-open'})
    r.run('directory-input',args=['-f','gzip','out','out/result'],status=3,existing=True,expected={'phase':'input-metadata'})
    r.run('symlink-input',good,args=['-f','gzip','link','out/result'],status=3,existing=True,expected={'phase':'input-open'},setup=lambda d:os.symlink('input.bin',d/'link'))
    r.run('symlink-parent',good,args=['-f','gzip','input.bin','link/result'],status=3,expected={'phase':'parent-open'},setup=lambda d:os.symlink('out',d/'link'))


def cli(r):
    invalid=[[],['--format'],['--format','gzip'],['--format','gzip','input.bin'],['input.bin','out/result'],
             ['-f','unknown','input.bin','out/result'],['-f','GZIP','input.bin','out/result'],['-f','gzip','-f','gzip','input.bin','out/result'],
             ['--unknown'],['--help=yes'],['-hh'],['--help','-h'],['-f','gzip','input.bin','out/result','extra'],
             ['--help','-f','bad'],['--help','a','b','c'],['-f','gzip','','out/result'],['-f','gzip','input.bin',''],
             ['-f','gzip','x'*4096,'out/result'],['-f','gzip','input.bin','x'*4096],['-f','gzip','input.bin','out/'+'x'*256],
             ['-f','gzip','input.bin','out/.'],['-f','gzip','input.bin','out/..'],['-f','gzip','input.bin','out/'],
             ['--help','input.bin','out/.'],['x']*17,['--help','x'*8193]]
    for i,args in enumerate(invalid):r.run(f'invalid-{i}',args=args,status=2,preflight=True,expected={'phase':'arguments'})
    for i,args in enumerate((['--help'],['-h'],['--help','-f','gzip'],['--help','input.bin'],['--help','input.bin','out/result'],['-f','raw','input.bin','out/result','--help'])):
        r.run(f'help-{i}',args=args,preflight=True)
    plain=b'aliases\0\xff';wire=compress(plain)
    r.run('format-short',wire,plain,args=['-f','gzip','--','input.bin','out/result'])
    r.run('format-intermixed',wire,plain,args=['input.bin','--format=gzip','out/result'])
    r.run('closed-help',args=['--help'],status=5,preflight=True,closed_stdout=True,expected={'phase':'help'})
    r.run('diagnostic-failure-keeps-usage',args=['--bad'],status=2,preflight=True,quiet=True,injections=(('write',1,'EIO'),))
    r.run('signal-failure',args=['--help'],status=5,preflight=True,quiet=True,injections=(('rt_sigaction',1,'EIO'),))


def input_limits(r):
    # Raw stored blocks are byte aligned. Make exactly CAP encoded bytes with
    # independent payload lengths, then test the real EOF probe and one excess byte.
    remaining=CAP;wire=bytearray();plain=bytearray()
    while remaining:
        count=min(65535,remaining-5);assert count>=0
        block=pattern(count);remaining-=count+5;wire+=bytes([1 if remaining==0 else 0])+struct.pack('<HH',count,count^65535)+block;plain+=block
    assert len(wire)==CAP and zlib.decompress(wire,-15)==plain
    exact=r.run('exact-input-cap',bytes(wire),bytes(plain),format='raw',large=True,trace_reads=True)
    excess=r.run('excess-input-probe',bytes(wire)+b'x',format='raw',status=2,existing=True,large=True,trace_reads=True,expected={'visibility':'not-published'})
    if r.observes:
        for traced,expected_probe in ((exact[0],0),(excess[0],1)):
            reads=[x for x in traced['events'] if x['name']=='read']
            assert sum(int(x['result']) for x in reads[:-1])==CAP
            assert int(reads[-1]['args'][2])==1 and int(reads[-1]['result'])==expected_probe


def member_limits(r):
    r.run('gzip-member-cap',compress(b'')*1024,b'',large=True)
    r.run('gzip-member-excess',compress(b'')*1025,status=2,existing=True,large=True,expected={'phase':'decode'})


def output_limit(r):
    large=b'a'*(OUTPUT_CAP+1)
    r.run('output-cap-excess',compress(large),status=2,existing=True,large=True,expected={'phase':'decode','visibility':'not-published'})


def faults(r):
    plain=pattern(8193);wire=compress(plain)
    base,_,_=r.run('baseline',wire,plain);events=base['events'];maps=[x for x in events if x['name']=='mmap']
    assert len(maps)>=8
    for old in maps:
        actual,_,_=r.run(f'oom-{old["ordinal"]}',wire,status=4,injections=(('mmap',old['ordinal'],'ENOMEM'),))
        reached=[x for x in actual['events'] if x['name']=='mmap'];assert len(reached)==old['ordinal']
        assert [x['args'] for x in reached]==[x['args'] for x in maps[:old['ordinal']]]
    # Bind semantic owner roles instead of selecting guessed syscall ordinals.
    choose=lambda name,role:next(x for x in events if x['name']==name and x.get('role')==role)
    for role in ('input','parent','temporary'):
        old=choose('openat',role);status=3 if role!='temporary' else 5
        r.run('open-'+role,wire,status=status,injections=(('openat',old['ordinal'],'EACCES'),))
    old=choose('read','input');r.run('read-eio',wire,status=3,injections=(('read',old['ordinal'],'EIO'),),expected={'phase':'input-read'})
    r.run('read-eintr',wire,plain,injections=(('read',old['ordinal'],'EINTR'),))
    write=choose('write','temporary');r.run('write-eio',wire,status=5,injections=(('write',write['ordinal'],'EIO'),),expected={'phase':'write'})
    r.run('write-eintr',wire,plain,injections=(('write',write['ordinal'],'EINTR'),))
    for role,status,phase in [('parent',8,'parent-close'),('input',3,'input-close'),('temporary',5,'commit'),('anchor',8,'commit')]:
        old=choose('close',role);r.run('close-'+role,wire,plain,status=status,injections=(('close',old['ordinal'],'EIO'),),expected={'phase':phase,'cleanup_failed':1})
    fsync=choose('fsync','temporary');r.run('file-sync-eio',wire,status=5,injections=(('fsync',fsync['ordinal'],'EIO'),),expected={'visibility':'not-published'})
    sync=choose('fsync','anchor');r.run('directory-sync-retry',wire,plain,status=6,injections=(('fsync',sync['ordinal'],'EIO'),),expected={'visibility':'published','directory_synced':1})
    r.run('directory-sync-exhausted',wire,plain,status=6,injections=(('fsync',f'{sync["ordinal"]}..{sync["ordinal"]+1}','EIO'),),expected={'visibility':'published','directory_synced':0})
    rename=next(x for x in events if x['name']=='renameat2');r.run('rename-eio-unconfirmed',wire,status=7,injections=(('renameat2',rename['ordinal'],'EIO'),),expected={'visibility':'unconfirmed'})
    # A failure control establishes the cleanup unlink site. Its execution is counted.
    failed,_,_=r.run('write-failure-control',wire,status=5,injections=(('write',write['ordinal'],'EIO'),))
    unlink=next(x for x in failed['events'] if x['name']=='unlinkat')
    writes=[x for x in events if x['name']=='write' and x.get('role')=='temporary'];assert len(writes)>=2
    prefix=int(writes[0]['result']);assert 0<prefix<len(plain)
    kept,report,d=r.run('keep-recovery-prefix',wire,status=5,injections=(('write',writes[1]['ordinal'],'EIO'),('unlinkat',unlink['ordinal'],'EIO')),expected={'cleanup_failed':1,'visibility':'not-published'})
    confirmed=[x for x in kept['events'] if x['name']=='write' and x.get('role')=='temporary' and x['result'].isdigit()]
    assert len(confirmed)==1 and int(confirmed[0]['result'])==prefix
    path=d/'out'/os.fsdecode(bytes.fromhex(report['name']));assert path.read_bytes()==plain[:prefix]
    return len(maps)


def controls():
    assert len(HELP)>1000
    for format in ('raw','zlib','gzip'):assert zlib.decompress(compress(pattern(8193),format),{'raw':-15,'zlib':15,'gzip':31}[format])==pattern(8193)
    line=b'decompress_file: code=6 phase=commit visibility=published file_synced=1 directory_synced=1 cleanup_failed=0 retained=0 recovery_parent_hex=- recovery_name_hex=-\n'
    assert diagnostic(line)['code']==6
    assert arguments('3, "\\x61\\x2c\\x62", {x=1, y=2}, 0')==['3','"\\x61\\x2c\\x62"','{x=1, y=2}','0']
    assert unquote('"\\x61\\x2c\\x62"')==b'a,b'
    good='mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n'
    assert ledger(good)['peak']==16
    for bad in (good.replace('munmap(0x1000, 16) = 0\n',''),good.replace('16) = 0\n','15) = 0\n')):
        try:ledger(bad)
        except AssertionError:pass
        else:raise AssertionError('bad allocation ledger accepted')
    quote=lambda value:'"'+''.join(f'\\x{x:02x}' for x in value)+'"'
    name=quote(b'.tmp-'+b'0'*32)
    publish=(f'openat(AT_FDCWD, {quote(b"input.bin")}, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) = 3\n'
             f'openat(AT_FDCWD, {quote(b"out")}, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_NONBLOCK) = 4\n'
             'fcntl(4, F_DUPFD_CLOEXEC, 0) = 5\n'
             f'openat(5, {name}, O_WRONLY|O_CREAT|O_EXCL, 0600) = 6\n'
             'close(4) = 0\nread(3, "", 1) = 0\nclose(3) = 0\nfsync(6) = 0\nclose(6) = 0\n'
             f'renameat2(5, {name}, 5, {quote(b"result")}, RENAME_NOREPLACE) = 0\n'
             'fsync(5) = 0\nclose(5) = 0\n')
    ledger(publish)
    for bad in (publish.replace('read(3, "", 1) = 0\n',''),publish.replace('fsync(6) = 0\n','')):
        try:ledger(bad)
        except AssertionError:pass
        else:raise AssertionError('publication without EOF or file sync accepted')
    class CountOnly:
        observes=False
        def __init__(self):self.count=0
        def run(self,*args,**kwargs):self.count+=1
    for function,wanted in ((model,15),(rejection,15),(cli,37),(member_limits,2)):
        counter=CountOnly();function(counter);assert counter.count==wanted,(function.__name__,counter.count,wanted)
    print('decompress-file CPU controls passed; fixed_cases=72 fault_cases=18+A')

if __name__=='__main__':
    if sys.argv[1:]==['controls']:controls()
    else:
        group,exe=sys.argv[1:];r=Runner(exe,group);extra={'model':model,'rejection':rejection,'cli':cli,'input_limits':input_limits,'member_limits':member_limits,'output_limit':output_limit,'faults':faults}[group](r)
        print(f'decompress-file-{group} cases={r.count} reached_allocations={extra or 0} evidence={r.directory}')
