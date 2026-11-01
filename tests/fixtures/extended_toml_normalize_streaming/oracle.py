"""Focused TOML streaming consumer wires, ownership and reached host faults."""
from collections import Counter
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import tomllib

READ_CALLS=131072
COPY_CALLS=262144
TRACE='read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'
HELP=b'Usage: toml-normalize [--check] [--max-input-bytes N] [--max-output-bytes N] [--max-nodes N] [--max-depth N] [--max-string-bytes N] [--max-number-bytes N] [--max-work N]\n'
DIAGNOSTIC=re.compile(rb'toml-normalize: (invalid-arguments|invalid-utf8|resource-limit|io-failure|allocation-failure|toml-error) stage=(arguments|input|parse|encode|output)(?: kind=([a-z0-9 /-]+))?(?: byte=([0-9]+))?(?: written=([0-9]+))?\n')


def diagnostic(data):
    match=DIAGNOSTIC.fullmatch(data);assert match,data
    keys=('reason','stage','kind','byte','written')
    result=dict(zip(keys,(x.decode() if x else None for x in match.groups())))
    for key in ('byte','written'):
        if result[key] is not None:result[key]=int(result[key])
    return result


def output_error(reason,written):
    return f'toml-normalize: {reason} stage=output written={written}\n'.encode()


def unquote(value):
    assert value.startswith('"') and value.endswith('"'),value
    return bytes.fromhex(value[1:-1].replace('\\x',''))


def model_cases():
    return [
        ('empty',b'',b''),('comment',b'# comment\r\n',b''),
        ('insertion-order',b'b=2\na=1',b'"b"=2\n"a"=1\n'),
        ('nested-table',b'[server]\nport=8080\nhost="localhost"\n',b'"server"={"port"=8080,"host"="localhost"}\n'),
        ('array-table',b'[[w]]\nx=1\n[[w]]\nx=2\n',b'"w"=[{"x"=1},{"x"=2}]\n'),
        ('control-escapes',b'x="\\b\\t\\n\\r\\f\\u0000\\u007F"',b'"x"="\\u0008\\u0009\\u000a\\u000d\\u000c\\u0000\\u007f"\n'),
        ('unicode-key','"é😀"="中 e\u0301"'.encode(),'"é😀"="中 e\u0301"\n'.encode()),
        ('numeric-kinds',b'i=0x10\nf=1.2500\nz=-0.0\n',b'"i"=16\n"f"=1.25\n"z"=-0.0\n'),
        ('temporal-11',b't=12:34\nz=1979-05-27t07:32-00:00\n',b'"t"=12:34:00\n"z"=1979-05-27T07:32:00-00:00\n'),
        ('escapes-11',b's="\\e\\xE9"',b'"s"="\\u001b'+ 'é'.encode()+b'"\n'),
        ('utf8-copy-boundary',b's="'+b'a'*1018+'😀é'.encode()+b'"',b'"s"="'+b'a'*1018+'😀é'.encode()+b'"\n'),
        ('escape-copy-boundary',b's="'+b'a'*1018+b'\\tZ"',b'"s"="'+b'a'*1018+b'\\u0009Z"\n'),
    ]


def ledger(text,*,argv_count,argv_bytes,input_cap=16777216,preflight=False,help_mode=False):
    events=[];counts=Counter();live={};consumed=0;eof=False;started=False;input_owner=None
    input_retired=False;document=None;retiring=False;peak=0
    argv_allocations=int(argv_count>0)+int(argv_bytes>0)
    for line in text.splitlines():
        match=re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)',line)
        assert match and match[1] in TRACE.split(','),line
        name,args,answer=match.groups();counts[name]+=1
        event=dict(name=name,args=args,answer=answer,ordinal=counts[name],line=line)
        if name=='mmap':
            assert not input_retired and not started,('allocation after input retirement/encoding boundary',line)
            extent=int(args.split(',')[1]);event['extent']=extent
            phase='argv' if counts['mmap']<=argv_allocations else ('parse' if eof else 'input');event['phase']=phase
            if answer.startswith('0x'):
                address=answer.split()[0];assert address not in live
                # Generation distinguishes a reused virtual address from a retired owner.
                live[address]=(extent,counts['mmap'],phase);peak=max(peak,sum(x[0] for x in live.values()))
            else:assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name=='munmap':
            address,extent=args.split(',');address=address.strip();owned=live.pop(address,None)
            assert answer=='0' and owned is not None and owned[0]==int(extent),line
            if eof and input_owner==(address,owned):
                assert not input_retired;input_retired=True;document=live.copy()
                assert all(value[2]=='parse' for value in document.values())
            elif input_retired:retiring=True
        elif name in ('mremap','brk','openat','close'):
            raise AssertionError(('unexpected owned host service',line))
        elif name=='read':
            assert not preflight and not started and not eof and args.split(',')[0]=='0'
            assert not any(value[2]=='argv' for value in live.values()),('argv must retire before input',line)
            if input_cap:
                assert len(live)==1 and next(iter(live.values()))[2]=='input',('one collector owner',line,live)
                address=next(iter(live));input_owner=(address,live[address])
            else:assert not live
            requested=int(args.rsplit(',',1)[1]);event['requested']=requested
            remaining=input_cap-consumed;assert 0<requested<=(min(1024,remaining) if remaining else 1)
            if answer.isdigit():
                amount=int(answer);assert amount<=requested;consumed+=amount;eof=amount==0
        elif name=='write':
            fd=int(args.split(',')[0]);assert fd in (1,2);event['fd']=fd
            requested=int(args.rsplit(',',1)[1]);event['requested']=requested;assert 0<requested<=1024
            if fd==1 and not help_mode:
                assert not preflight and eof and input_retired and not retiring and document
                assert live==document,('document must remain unchanged throughout publication',line,live,document)
                started=True
            else:assert not live,('diagnostic/help before retirement',line,live)
            if answer.isdigit():assert int(answer)<=requested
        elif name=='rt_sigaction':assert not events and args.startswith('SIGPIPE,') and 'SIG_IGN' in args
        events.append(event)
    assert not live,('unreleased owners',live)
    assert counts['rt_sigaction']==1 and counts['read']<=READ_CALLS
    assert sum(x.get('fd')==1 for x in events)<=(64 if help_mode else COPY_CALLS-1)
    assert sum(x.get('fd')==2 for x in events)<=64
    if preflight:assert counts['read']==0
    return dict(events=events,consumed=consumed,eof=eof,input_retired=input_retired,document=document,peak=peak)


class Runner:
    observes=True
    def __init__(self,executable,group):
        self.executable=str(Path(executable).resolve());header=Path(self.executable).read_bytes()[:64]
        assert len(header)==64 and header[:6]==b'\x7fELF\x02\x01' and int.from_bytes(header[16:18],'little')==2 and int.from_bytes(header[18:20],'little')==62
        self.directory=Path(tempfile.mkdtemp(prefix=f'toml-normalize-streaming-{group}-'));self.count=0
    def run(self,name,data=b'',expected=b'',*,args=(),status=0,error=None,injections=(),input_cap=16777216,preflight=False,help_mode=False,closed_stdout=False,compact=False):
        args=[os.fsencode(x) for x in args];d=self.directory/name;d.mkdir();source=d/'input';source.write_bytes(data)
        command=['strace','--kill-on-exit','-qq','-xx','-s','64' if compact else '256','-e','signal=none','-e','trace='+TRACE,'-o',str(d/'trace')]
        for call,position,failure in injections:
            action=failure if failure.startswith('retval=') else 'error='+failure
            command+=['-e',f'inject={call}:{action}:when={position}']
        command+=[self.executable,*args];(d/'command').write_text(repr(command)+'\n')
        fd=os.open(source,os.O_RDONLY)
        try:
            if closed_stdout:
                reader,writer=os.pipe();os.close(reader)
                try: result=subprocess.run(command,stdin=fd,stdout=writer,stderr=subprocess.PIPE,timeout=60,check=False)
                finally:os.close(writer)
                result.stdout=b''
            else:result=subprocess.run(command,stdin=fd,capture_output=True,timeout=60,check=False)
        finally:os.close(fd)
        for path,value in [('stdout',result.stdout),('stderr',result.stderr)]: (d/path).write_bytes(value)
        (d/'status').write_text(str(result.returncode)+'\n')
        assert result.returncode==status and result.stdout==expected,(name,result.returncode,status,result.stdout[:128],expected[:128],result.stderr)
        if isinstance(error,dict):
            observed=diagnostic(result.stderr)
            for key,value in error.items():assert observed[key]==value,(name,observed,error)
        else:assert result.stderr==(error or b''),(name,result.stderr,error)
        traced=ledger((d/'trace').read_text(),argv_count=len(args),argv_bytes=sum(map(len,args)),input_cap=input_cap,preflight=preflight,help_mode=help_mode)
        events=traced['events'];indexed={(x['name'],x['ordinal']):x for x in events};selected=[]
        for call,position,failure in injections:
            if isinstance(position,str) and position.endswith('+'):positions=range(int(position[:-1]),1+sum(x['name']==call for x in events))
            elif isinstance(position,str):positions=range(int(position.split('..')[0]),int(position.split('..')[1])+1)
            else:positions=[position]
            for ordinal in positions:
                event=indexed.get((call,ordinal));assert event is not None,(name,call,ordinal,'not reached')
                prefix=failure.removeprefix('retval=') if failure.startswith('retval=') else '-1 '+failure+' '
                assert event['answer'].startswith(prefix) and 'INJECTED' in event['answer'];selected.append(event)
        assert {x['line'] for x in events if 'INJECTED' in x['answer']}=={x['line'] for x in selected}
        for descriptor,payload in [(1,result.stdout),(2,result.stderr)]:
            confirmed=sum(int(x['answer']) for x in events if x.get('fd')==descriptor and x['answer'].isdigit())
            assert confirmed==len(payload),(name,descriptor,confirmed,len(payload))
        if status==0 and not help_mode:
            assert traced['eof'] and traced['consumed']==len(data)
            assert traced['input_retired'] or input_cap==0
        assert source.read_bytes()==data
        self.count+=1;return traced


def model(r):
    for name,data,expected in model_cases():r.run(name,data,expected)
    source=b's="'+b'\t'*131072+b'"\n';expected=b'"s"="'+b'\\u0009'*131072+b'"\n'
    plain=r.run('expanded-normal',source,expected,compact=True)
    checked=r.run('expanded-check',source,args=['--check'],compact=True)
    if r.observes:
        extents=lambda trace:[x['extent'] for x in trace['events'] if x['name']=='mmap' and x['phase']!='argv']
        assert extents(plain)==extents(checked)
        assert sorted(x[0] for x in plain['document'].values())==sorted(x[0] for x in checked['document'].values())


def limits(r):
    source=b'#'+b'a'*(4096-5)+b'\nx=1';assert len(source)==4096
    exact=r.run('exact-input-probe',source,b'"x"=1\n',args=['--max-input-bytes=4096'],input_cap=4096)
    excess=r.run('excess-input-probe',source+b'\n',args=['--max-input-bytes=4096'],input_cap=4096,status=2,error=b'toml-normalize: resource-limit stage=input\n')
    r.run('exact-output',b'x=1',b'"x"=1\n',args=['--max-output-bytes=6'])
    rejected=r.run('output-preflight',b'x=1',args=['--max-output-bytes=5'],status=2,error=b'toml-normalize: toml-error stage=encode kind=output limit\n')
    r.run('check-bypasses-output-cap',b'x=1',args=['--check','--max-output-bytes=0'])
    r.run('zero-input-probe',args=['--max-input-bytes=0'],input_cap=0)
    r.run('last-option-wins',b'x=1',b'"x"=1\n',args=['--max-output-bytes=0','--max-output-bytes=6'])
    r.run('invalid-help-options-before-input',b'\xff',args=['--help','--bad'],status=2,error=b'toml-normalize: invalid-arguments stage=arguments\n',preflight=True)
    if r.observes:
        for trace,probe in ((exact,0),(excess,1)):
            reads=[x for x in trace['events'] if x['name']=='read']
            assert sum(int(x['answer']) for x in reads[:-1])==4096
            assert reads[-1]['requested']==1 and reads[-1]['answer']==str(probe)
        assert rejected['input_retired'] and not any(x.get('fd')==1 for x in rejected['events'])


def fault_wire():
    source=b's="'+b'a'*2100+b'"\n[t]\na=[1,true,"ok"]\n'
    expected=b'"s"="'+b'a'*2100+b'"\n"t"={"a"=[1,true,"ok"]}\n'
    return source,expected


def io(r):
    source,expected=fault_wire();args=['--max-nodes=64']
    baseline=r.run('fault-baseline',source,expected,args=args)
    allocations=[x for x in baseline['events'] if x['name']=='mmap']
    for allocation in allocations:
        ordinal=allocation['ordinal'];stage={'argv':'arguments','input':'input','parse':'parse'}[allocation['phase']]
        denied=r.run(f'oom-{ordinal}',source,args=args,status=4,
                     error={'reason':'allocation-failure','stage':stage},injections=[('mmap',ordinal,'ENOMEM')])
        if r.observes:
            seen=[x for x in denied['events'] if x['name']=='mmap']
            assert len(seen)==ordinal
            assert [x['args'] for x in seen]==[x['args'] for x in allocations[:ordinal]]
            assert seen[-1]['answer'].startswith('-1 ENOMEM ') and 'INJECTED' in seen[-1]['answer']
    r.run('read-interrupted',source,expected,args=args,injections=[('read',1,'EINTR')])
    r.run('read-after-prefix',source,args=args,status=3,error=b'toml-normalize: io-failure stage=input\n',injections=[('read',2,'EIO')])
    r.run('write-first-error',source,args=args,status=3,error=output_error('io-failure',0),injections=[('write',1,'EIO')])
    writes=[x for x in baseline['events'] if x.get('fd')==1]
    assert len(writes)>=2 and writes[0]['answer'].isdigit()
    confirmed=int(writes[0]['answer'])
    r.run('write-after-real-prefix',source,expected[:confirmed],args=args,status=3,
          error=output_error('io-failure',confirmed),injections=[('write',writes[1]['ordinal'],'EIO')])
    r.run('write-interrupted',source,expected,args=args,injections=[('write',1,'EINTR')])
    r.run('write-would-block',source,args=args,status=3,error=output_error('io-failure',0),injections=[('write',1,'EAGAIN')])
    r.run('write-zero',source,args=args,status=3,error=output_error('io-failure',0),injections=[('write',1,'retval=0')])
    r.run('signal-failure',source,status=3,preflight=True,injections=[('rt_sigaction',1,'EIO')])
    r.run('closed-output',source,args=args,status=3,error=output_error('io-failure',0),closed_stdout=True)
    r.run('help',b'\xff',HELP,args=['--help'],preflight=True,help_mode=True)
    r.run('closed-help',b'\xff',args=['--help'],status=3,error=b'toml-normalize: io-failure stage=arguments\n',preflight=True,help_mode=True,closed_stdout=True)
    r.run('diagnostic-failure',b'\xff',args=['--bad'],status=3,preflight=True,injections=[('write',1,'EIO')])
    r.run('owned-parse-failure',b'a="allocated"\nb=[',status=2,error={'reason':'toml-error','stage':'parse','kind':'unexpected end'})
    r.run('invalid-utf8-offset',b'a=1\n\xff',status=2,error=b'toml-normalize: invalid-utf8 stage=input byte=4\n')
    assert r.count==15+len(allocations),(r.count,len(allocations))
    return len(allocations)


def budgets(r):
    exhausted=r.run('input-call-limit',b'x=1',status=2,error=b'toml-normalize: resource-limit stage=input\n',
                    injections=[('read','1+','EINTR')],compact=True)
    source,expected=fault_wire()
    stalled=r.run('output-call-limit-after-prefix',source,expected[:1024],status=3,
                  injections=[('write','2+','EINTR')],compact=True)
    if r.observes:
        reads=[x for x in exhausted['events'] if x['name']=='read']
        assert len(reads)==READ_CALLS and exhausted['consumed']==0 and not exhausted['eof']
        writes=[x for x in stalled['events'] if x.get('fd')==1]
        # Exactly two local encoder reads: one before the confirmed first
        # scratch chunk, one before the permanently interrupted second chunk.
        assert len(writes)==COPY_CALLS-2 and writes[0]['answer']=='1024'
        reports=[x for x in stalled['events'] if x.get('fd')==2]
        wanted=output_error('resource-limit',1024)
        assert len(reports)==64
        for report in reports:
            assert report['requested']==len(wanted)
            assert unquote(report['args'].split(', ',1)[1].rsplit(', ',1)[0])==wanted
        # Continuous injection also interrupts every diagnostic attempt.
        # The observed selected output-limit message is never delivered;
        # failed diagnostics therefore override the primary status 2 with 3.


class ControlRunner:
    """Only exercises host corpus construction; never executes a native file."""
    observes=False
    def __init__(self):self.count=0
    def run(self,name,data=b'',expected=b'',**options):
        assert isinstance(data,bytes) and isinstance(expected,bytes)
        assert options.get('status',0) in (0,2,3,4)
        self.count+=1
        return {'events':[
            {'name':'write','fd':1,'ordinal':1,'answer':'1024'},
            {'name':'write','fd':1,'ordinal':2,'answer':'1024'}]}


def ledger_controls():
    signal='rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=0}, NULL, 8) = 0'
    def mmap(address,extent):return f'mmap(NULL, {extent}, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = {address}'
    def release(address,extent):return f'munmap({address}, {extent}) = 0'
    # The input deliberately reuses a retired argv address. A later parser
    # allocation also reuses a retired collector-growth address.
    setup=[signal,mmap('0x100000000',40),mmap('0x200000000',7),release('0x200000000',7),release('0x100000000',40),
           mmap('0x100000000',1024),'read(0, "\\x78\\x3d\\x31", 1024) = 3',
           mmap('0x300000000',2048),release('0x100000000',1024),'read(0, "", 1024) = 0',
           mmap('0x100000000',64),mmap('0x400000000',128),release('0x300000000',2048)]
    write='write(1, "\\x22\\x78\\x22\\x3d\\x31\\x0a", 6) = 6'
    cleanup=[release('0x100000000',64),release('0x400000000',128)]
    valid=setup+[write]+cleanup
    options=dict(argv_count=1,argv_bytes=7)
    good=ledger('\n'.join(valid),**options)
    assert good['document']=={'0x100000000':(64,5,'parse'),'0x400000000':(128,6,'parse')}
    bad=[]
    # Input remains live at publication.
    bad.append(setup[:-1]+[write,setup[-1]]+cleanup)
    # One of two document owners dies between source retirement and first write.
    bad.append(setup+[cleanup[0],write,cleanup[1]])
    bad.append(setup+[write,cleanup[0],write,cleanup[1]])
    bad.append(setup+[mmap('0x500000000',32),write,release('0x500000000',32)]+cleanup)
    bad.append(setup+[write,release('0x100000000',63),cleanup[1]])
    bad.append(setup+[write,cleanup[0]])
    # Captured argv byte backing cannot survive into input collection.
    bad.append(setup[:3]+setup[4:7]+[setup[3]]+setup[7:]+[write]+cleanup)
    for trace in bad:
        try:ledger('\n'.join(trace),**options)
        except AssertionError:pass
        else:raise AssertionError(('observer accepted corrupt lifetime',trace))
    return len(bad)


def controls():
    for name,source,wire in model_cases():
        assert isinstance(source,bytes) and isinstance(wire,bytes)
        if name not in ('temporal-11','escapes-11'):
            assert tomllib.loads(source.decode())==tomllib.loads(wire.decode()),name
    source,wire=fault_wire();assert tomllib.loads(source.decode())==tomllib.loads(wire.decode())
    assert len(HELP)==170
    for function,expected in ((model,14),(limits,8),(io,15),(budgets,2)):
        control=ControlRunner();function(control);assert control.count==expected
    rejected=ledger_controls()
    print(f'toml-normalize-streaming host-controls model=14 limits=8 io=15+A budgets=2 rejected_lifetime_corruptions={rejected}; no native evidence')


GROUPS={'model':model,'limits':limits,'io':io,'budgets':budgets}
if __name__=='__main__':
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls()
    else:
        assert len(sys.argv)==3 and sys.argv[1] in GROUPS
        runner=Runner(sys.argv[2],sys.argv[1]);allocations=GROUPS[sys.argv[1]](runner) or 0
        print(f'toml-normalize-streaming-{sys.argv[1]} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
