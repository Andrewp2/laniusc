"""Independent decoding of compressed files and reached AtomicFile failure traces."""
from collections import Counter
import os
from pathlib import Path
import re
import random
import subprocess
import sys
import tempfile
import zlib

CAP=64*1024*1024
OUTPUT_CAP=65*1024*1024
HELP=b"Usage: compress_file --format raw|zlib|gzip [--] INPUT OUTPUT\nEncode a regular no-follow input into a new file. Existing output is never replaced.\nShort options: -f FORMAT, -h. --help validates supplied arguments and opens no files.\nDuplicate options, unknown formats and extra operands are errors.\nPaths use 1..4095 raw bytes; the output leaf uses 1..255 bytes and cannot be '.' or '..'.\nAn output path cannot end in /. The output parent must already be a directory.\nLimits: 64 MiB input, 65 MiB compressed output, 131072 read attempts.\nFixed buffers: 4096 input bytes, 4096 output bytes, 32768 block bytes,\n32773 pending bytes and 32768 i32 scratch entries.\nEncoder calls are capped at 262144 and temporary-file write attempts at 131072.\nEncoding completion, actual EOF and input close precede publication.\nPublication uses NoReplace in a cooperative local filesystem namespace.\nPublished or unconfirmed failures are reported without promising rollback.\nCleanup may keep a recovery file; its parent and name are reported as hexadecimal bytes.\nInterrupted work spends attempts; blocking I/O has no wall-clock timeout.\nSuccessful execution writes no stdout or stderr. Help writes stdout.\n"
CALLS='openat,close,fcntl,statx,read,write,fsync,renameat2,unlinkat,getrandom,mmap,munmap,mremap,brk,rt_sigaction'
DIAGNOSTIC=re.compile(rb'compress_file: code=([0-8]) phase=([a-z-]+) visibility=(not-published|published|unconfirmed) file_synced=([01]) directory_synced=([01]) cleanup_failed=([01]) retained=([01]) recovery_parent_hex=([0-9a-f]+|-) recovery_name_hex=([0-9a-f]+|-)\n')

def pattern(n):
    block=bytes((i*73+19)%256 for i in range(256));return (block*((n+255)//256))[:n]

def noise(n):
    return random.Random(0xDEF1A7E).randbytes(n)


def decoded(wire,format):
    bits={'raw':-15,'zlib':15,'gzip':31}[format]
    d=zlib.decompressobj(bits);value=d.decompress(wire)+d.flush()
    assert d.eof and not d.unused_data and not d.unconsumed_tail
    if format=='gzip':assert wire[:10]==bytes.fromhex('1f8b08000000000000ff')
    if format=='zlib':assert wire[:2]==b'\x78\x01'
    assert len(wire)<=OUTPUT_CAP
    return value


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

def ledger(text,preflight=False,fixed_workspace=False):
    events=[];counts=Counter();maps={};fds={};retired=[];peak=0;temp=None;renamed=False
    input_eof=False;input_closed=False;file_synced=False;temporary_closed=False
    workspace={};opened=False;streaming=False;input_retired=False
    for line in text.splitlines():
        m=re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)',line)
        assert m and m[1] in CALLS.split(','),line
        name,argtext,result=m.groups();args=arguments(argtext);counts[name]+=1
        item=dict(name=name,args=args,argtext=argtext,result=result,ordinal=counts[name],line=line)
        if name=='mmap':
            size=int(args[1]);item['extent']=size
            assert not streaming,('allocation after streaming began',item)
            if result.startswith('0x'):assert result not in maps;maps[result]=size;peak=max(peak,sum(maps.values()))
            else:assert result.startswith('-1 ENOMEM ') and 'INJECTED' in result
        elif name=='munmap':
            assert not streaming or input_retired,('release during streaming',item)
            assert result=='0' and maps.pop(args[0],None)==int(args[1]),item
            if args[0] in workspace:assert not fds,('workspace retired before file cleanup',item)
        elif name in ('mremap','brk'):raise AssertionError(item)
        elif name=='openat':
            assert not preflight;path=unquote(args[1]);item['path']=path
            if not opened and fixed_workspace:
                allocated=[x for x in events if x['name']=='mmap' and x['result'].startswith('0x')]
                last=allocated[-5:];assert [x['extent'] for x in last]==[4096,4096,32768,32773,131072]
                workspace={x['result']:x['extent'] for x in last};assert all(maps.get(a)==n for a,n in workspace.items())
            opened=True
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
            if item['role']=='input':input_retired=True;input_closed=result=='0' and input_eof
            if item['role']=='temporary':temporary_closed=result=='0' and file_synced
            if result!='0':assert 'INJECTED' in result;retired.append((fd,item['role']))
        elif name in ('read','fsync','statx'):
            if name=='read':
                fd=int(args[0]);assert fds.get(fd)=='input';item['role']='input'
                assert 1<=int(args[2])<=1024
                streaming=True
                assert all(maps.get(a)==n for a,n in workspace.items())
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
            if fd>2:
                assert not renamed;item['role']='temporary';assert 1<=int(args[2])<=1024
                assert all(maps.get(a)==n for a,n in workspace.items())
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
    return dict(events=events,peak=peak,skipped_closes=retired,temp=temp,workspace=workspace)


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
        self.directory=Path(tempfile.mkdtemp(prefix=f'compress-file-{group}-'));self.count=0
    def run(self,name,plain=b'',*,format='gzip',args=None,status=0,expected=None,existing=False,preflight=False,injections=(),quiet=False,compact=False,closed_stdout=False,setup=None):
        d=self.directory/name;d.mkdir();(d/'out').mkdir();(d/'input.bin').write_bytes(plain)
        old=b'old-destination\0\xff';destination=d/'out/result'
        if existing:destination.write_bytes(old)
        if setup:setup(d)
        before=destination.lstat() if destination.exists() or destination.is_symlink() else None
        old_content=destination.read_bytes() if before else None
        old_link=os.readlink(destination) if destination.is_symlink() else None
        command=['strace','--kill-on-exit','-qq','-xx','-s','64' if compact else '256','-e','signal=none','-e','trace='+CALLS,'-o',str(d/'trace')]
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
        traced=ledger((d/'trace').read_text(),preflight,True)
        found=traced['events'];by_call={(x['name'],x['ordinal']):x for x in found};marked=[x for x in found if 'INJECTED' in x['result']];selected=[]
        for call,ordinal,failure in injections:
            if isinstance(ordinal,str) and ordinal.endswith('+'):
                positions=range(int(ordinal[:-1]),1+sum(x['name']==call for x in found))
            else:positions=range(int(ordinal.split('..')[0]),int(ordinal.split('..')[1])+1) if isinstance(ordinal,str) else [ordinal]
            for position in positions:
                reached=by_call.get((call,position));assert reached and reached['result'].startswith('-1 '+failure+' ');selected.append(reached)
        assert {x['line'] for x in marked}=={x['line'] for x in selected}
        assert len(traced['skipped_closes'])==sum(call=='close' for call,_,_ in injections)
        renamed=any(x['name']=='renameat2' and x['result']=='0' for x in found)
        if renamed:
            assert destination.is_file() and decoded(destination.read_bytes(),format)==plain
            if report:assert report['visibility']=='published'
        elif before is not None:
            after=destination.lstat();assert (after.st_dev,after.st_ino)==(before.st_dev,before.st_ino)
            assert destination.read_bytes()==old_content
            if old_link is not None:assert os.readlink(destination)==old_link
        else:assert not destination.exists() and not destination.is_symlink()
        if status==0 and not help_case:assert renamed
        if report and report['name']!='-':
            raw=bytes.fromhex(report['name']);assert bytes.fromhex(report['parent'])==b'out' and raw==traced['temp']
            retained=d/'out'/os.fsdecode(raw);assert retained.is_file();assert report['cleanup_failed']==1
            assert set(p.name for p in (d/'out').iterdir())=={os.fsdecode(raw)}|({'result'} if before else set())
        else:assert set(p.name for p in (d/'out').iterdir())==({'result'} if before or renamed else set())
        assert (d/'input.bin').read_bytes()==plain
        self.count+=1;return traced,report,d


def model(r):
    observed={}
    for format in ('raw','zlib','gzip'):
        for label,plain in [('empty',b''),('binary',bytes(range(256))*17),('below-block',noise(32767)),('exact-block',noise(32768)),('above-block',noise(32769))]:
            result=r.run(format+'-'+label,plain,format=format)
            if r.observes and format=='gzip':observed[label]=result
    repeat=r.run('gzip-repeat',noise(32769))
    large=r.run('large-fixed-workspace',pattern(8*1024*1024),compact=True)
    if r.observes:
        original=observed['above-block']
        assert (repeat[2]/'out/result').read_bytes()==(original[2]/'out/result').read_bytes()
        baseline=observed['empty'][0]
        for traced in (original[0],repeat[0],large[0]):
            assert traced['peak']==baseline['peak']
            assert [x['extent'] for x in traced['events'] if x['name']=='mmap']==[x['extent'] for x in baseline['events'] if x['name']=='mmap']


def input_kinds(r):
    plain=b'original bytes\0\xff'
    r.run('missing-input',args=['-f','gzip','missing','out/result'],status=3,existing=True,expected={'phase':'input-open'})
    r.run('directory-input',args=['-f','gzip','out','out/result'],status=3,existing=True,expected={'phase':'input-metadata'})
    r.run('symlink-input',plain,args=['-f','gzip','link','out/result'],status=3,existing=True,expected={'phase':'input-open'},setup=lambda d:os.symlink('input.bin',d/'link'))
    r.run('fifo-input',plain,args=['-f','gzip','pipe','out/result'],status=3,existing=True,expected={'phase':'input-metadata'},setup=lambda d:os.mkfifo(d/'pipe'))
    r.run('symlink-parent',plain,args=['-f','gzip','input.bin','link/result'],status=3,expected={'phase':'parent-open'},setup=lambda d:os.symlink('out',d/'link'))
    r.run('existing-protected',plain,status=2,existing=True,expected={'phase':'commit','visibility':'not-published','file_synced':1})
    r.run('same-path-protected',plain,args=['-f','gzip','out/result','out/result'],status=2,existing=True,expected={'phase':'commit','visibility':'not-published'})
    r.run('same-inode-protected',plain,status=2,expected={'phase':'commit','visibility':'not-published'},setup=lambda d:os.link(d/'input.bin',d/'out/result'))
    r.run('symlink-destination-protected',plain,status=2,expected={'phase':'commit','visibility':'not-published'},setup=lambda d:os.symlink('../input.bin',d/'out/result'))


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
    plain=b'aliases\0\xff'
    r.run('format-short',plain,args=['-f','gzip','--','input.bin','out/result'])
    r.run('format-intermixed',plain,args=['input.bin','--format=gzip','out/result'])
    r.run('raw-path-bytes',plain,args=[b'-f',b'gzip',b'in-\xff',b'out/result'],setup=lambda d:(d/os.fsdecode(b'in-\xff')).write_bytes(plain))
    r.run('dash-path-after-double-dash',plain,args=['-f','gzip','--','-input','out/result'],setup=lambda d:(d/'-input').write_bytes(plain))
    r.run('closed-help',args=['--help'],status=5,preflight=True,closed_stdout=True,expected={'phase':'help'})
    r.run('diagnostic-failure-keeps-usage',args=['--bad'],status=2,preflight=True,quiet=True,injections=(('write',1,'EIO'),))
    r.run('signal-failure',args=['--help'],status=5,preflight=True,quiet=True,injections=(('rt_sigaction',1,'EIO'),))


def input_limits(r):
    plain=pattern(CAP)
    exact=r.run('exact-input-cap',plain,format='raw',compact=True)
    excess=r.run('excess-input-probe',plain+b'x',format='raw',status=2,existing=True,compact=True,expected={'phase':'input-read','visibility':'not-published'})
    if r.observes:
        for traced,expected_probe in ((exact[0],0),(excess[0],1)):
            reads=[x for x in traced['events'] if x['name']=='read']
            assert len(reads)==65537
            assert sum(int(x['result']) for x in reads[:-1])==CAP
            assert int(reads[-1]['args'][2])==1 and int(reads[-1]['result'])==expected_probe
        assert exact[0]['peak']==excess[0]['peak']


def faults(r):
    plain=noise(65537)
    base,_,base_dir=r.run('baseline',plain)
    wire=(base_dir/'out/result').read_bytes();events=base['events'];maps=[x for x in events if x['name']=='mmap']
    assert len(maps)>=9
    for old in maps:
        actual,_,_=r.run(f'oom-{old["ordinal"]}',plain,status=4,existing=True,injections=(('mmap',old['ordinal'],'ENOMEM'),))
        reached=[x for x in actual['events'] if x['name']=='mmap'];assert len(reached)==old['ordinal']
        assert [x['args'] for x in reached]==[x['args'] for x in maps[:old['ordinal']]]
    choose=lambda name,role:next(x for x in events if x['name']==name and x.get('role')==role)
    for role in ('input','parent','temporary'):
        old=choose('openat',role);status=3 if role!='temporary' else 5
        r.run('open-'+role,plain,status=status,existing=True,injections=(('openat',old['ordinal'],'EACCES'),))
    metadata=next(x for x in events if x['name']=='statx')
    r.run('metadata-eio',plain,status=3,existing=True,injections=(('statx',metadata['ordinal'],'EIO'),),expected={'phase':'input-metadata'})
    duplicate=next(x for x in events if x['name']=='fcntl' and x['args'][1]=='F_DUPFD_CLOEXEC')
    r.run('directory-duplicate-eio',plain,status=5,existing=True,injections=(('fcntl',duplicate['ordinal'],'EIO'),),expected={'phase':'temporary-create'})
    entropy=next(x for x in events if x['name']=='getrandom')
    r.run('entropy-eio',plain,status=5,existing=True,injections=(('getrandom',entropy['ordinal'],'EIO'),),expected={'phase':'temporary-create'})
    old=choose('read','input')
    r.run('read-eio',plain,status=3,existing=True,injections=(('read',old['ordinal'],'EIO'),),expected={'phase':'input-read'})
    r.run('read-eintr',plain,injections=(('read',old['ordinal'],'EINTR'),))
    write=choose('write','temporary')
    r.run('write-eio',plain,status=5,existing=True,injections=(('write',write['ordinal'],'EIO'),),expected={'phase':'write'})
    r.run('write-eintr',plain,injections=(('write',write['ordinal'],'EINTR'),))
    for role,status,phase in [('parent',8,'parent-close'),('input',3,'input-close'),('temporary',5,'commit'),('anchor',8,'commit')]:
        old=choose('close',role)
        r.run('close-'+role,plain,status=status,existing=role!='anchor',injections=(('close',old['ordinal'],'EIO'),),expected={'phase':phase,'cleanup_failed':1})
    fsync=choose('fsync','temporary')
    r.run('file-sync-eio',plain,status=5,existing=True,injections=(('fsync',fsync['ordinal'],'EIO'),),expected={'visibility':'not-published'})
    sync=choose('fsync','anchor')
    r.run('directory-sync-retry',plain,status=6,injections=(('fsync',sync['ordinal'],'EIO'),),expected={'visibility':'published','directory_synced':1})
    r.run('directory-sync-exhausted',plain,status=6,injections=(('fsync',f'{sync["ordinal"]}..{sync["ordinal"]+1}','EIO'),),expected={'visibility':'published','directory_synced':0})
    rename=next(x for x in events if x['name']=='renameat2')
    r.run('rename-eio-unconfirmed',plain,status=7,existing=True,injections=(('renameat2',rename['ordinal'],'EIO'),),expected={'visibility':'unconfirmed'})
    # This real failed-write process locates cleanup unlink; it is counted once.
    failed,_,_=r.run('write-failure-control',plain,status=5,existing=True,injections=(('write',write['ordinal'],'EIO'),))
    unlink=next(x for x in failed['events'] if x['name']=='unlinkat')
    writes=[x for x in events if x['name']=='write' and x.get('role')=='temporary'];assert len(writes)>=2
    prefix=int(writes[0]['result']);assert 0<prefix<len(wire)
    kept,report,d=r.run('keep-recovery-prefix',plain,status=5,existing=True,injections=(('write',writes[1]['ordinal'],'EIO'),('unlinkat',unlink['ordinal'],'EIO')),expected={'cleanup_failed':1,'visibility':'not-published'})
    confirmed=[x for x in kept['events'] if x['name']=='write' and x.get('role')=='temporary' and x['result'].isdigit()]
    assert len(confirmed)==1 and int(confirmed[0]['result'])==prefix
    assert (d/'out'/os.fsdecode(bytes.fromhex(report['name']))).read_bytes()==wire[:prefix]
    budget,_,_=r.run('read-attempt-budget',plain,status=2,existing=True,compact=True,injections=(('read','1+','EINTR'),),expected={'phase':'input-read'})
    assert sum(x['name']=='read' for x in budget['events'])==131072
    budget,_,_=r.run('write-attempt-budget',plain,status=2,existing=True,quiet=True,injections=(('write','1+','EINTR'),))
    writes=[x for x in budget['events'] if x['name']=='write'];payload=[x for x in writes if x.get('role')=='temporary'];reports=[x for x in writes if x.get('role')=='diagnostic']
    assert len(payload)==131072 and len(reports)==64
    for event in reports:
        request=unquote(event['args'][1]);value=diagnostic(request)
        assert value['code']==2 and value['phase']=='write' and value['visibility']=='not-published'
        assert int(event['args'][2])==len(request)
    return len(maps)


def controls():
    assert len(HELP)==1188
    # Python zlib only verifies the oracle's independent decoder and known bytes.
    for format,bits in [('raw',-15),('zlib',15),('gzip',31)]:
        plain=pattern(8193);c=zlib.compressobj(1,zlib.DEFLATED,bits);wire=c.compress(plain)+c.flush()
        # zlib's gzip OS byte is host-specific; normalize only this host control.
        if format=='gzip':wire=wire[:8]+b'\x00\xff'+wire[10:]
        assert decoded(wire,format)==plain
        for invalid in (wire[:-1],wire+b'x'):
            try:decoded(invalid,format)
            except (AssertionError,zlib.error):pass
            else:raise AssertionError('truncated/trailing compressed bytes accepted')
    line=b'compress_file: code=6 phase=commit visibility=published file_synced=1 directory_synced=1 cleanup_failed=0 retained=0 recovery_parent_hex=- recovery_name_hex=-\n'
    assert diagnostic(line)['code']==6
    assert arguments('3, "\\x61\\x2c\\x62", {x=1, y=2}, 0')==['3','"\\x61\\x2c\\x62"','{x=1, y=2}','0']
    assert unquote('"\\x61\\x2c\\x62"')==b'a,b'
    good='mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n'
    assert ledger(good)['peak']==16
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
    workspace=''.join(f'mmap(NULL, {size}, X, Y, -1, 0) = 0x{index*0x100000:x}\n' for index,size in enumerate((4096,4096,32768,32773,131072),1))
    retirement=''.join(f'munmap(0x{index*0x100000:x}, {size}) = 0\n' for index,size in enumerate((4096,4096,32768,32773,131072),1))
    ledger(workspace+publish+retirement,fixed_workspace=True)
    write='write(6, '+quote(b'a')+', 1) = 1\n'
    publication_with_write=publish.replace('close(3) = 0\n',write+'close(3) = 0\n')
    ledger(workspace+publication_with_write+retirement,fixed_workspace=True)
    bad_cases=[good.replace('munmap(0x1000, 16) = 0\n',''),good.replace('16) = 0\n','15) = 0\n'),
               publish.replace('read(3, "", 1) = 0\n',''),publish.replace('fsync(6) = 0\n',''),
               (workspace+publish+retirement).replace('read(3, "", 1) = 0\n','read(3, "", 1) = 0\nmmap(NULL, 16, X, Y, -1, 0) = 0x9000\nmunmap(0x9000, 16) = 0\n'),
               workspace+publication_with_write.replace(write,'munmap(0x100000, 4096) = 0\n'+write)+retirement.replace('munmap(0x100000, 4096) = 0\n',''),
               publish.replace('close(3) = 0\n','')]
    for bad in bad_cases:
        try:ledger(bad,fixed_workspace=bad.startswith(workspace))
        except AssertionError:pass
        else:raise AssertionError('bad owner/publication ledger accepted')
    class CountOnly:
        observes=False
        def __init__(self):self.count=0
        def run(self,*args,**kwargs):self.count+=1
    for function,wanted in ((model,17),(input_kinds,9),(cli,39),(input_limits,2)):
        counter=CountOnly();function(counter);assert counter.count==wanted,(function.__name__,counter.count,wanted)
    print('compress-file CPU controls passed; fixed_cases=67 fault_cases=23+A')

if __name__=='__main__':
    if sys.argv[1:]==['controls']:controls()
    else:
        group,exe=sys.argv[1:];r=Runner(exe,group)
        extra={'model':model,'input_kinds':input_kinds,'cli':cli,'input_limits':input_limits,'faults':faults}[group](r)
        print(f'compress-file-{group} cases={r.count} reached_allocations={extra or 0} evidence={r.directory}')
