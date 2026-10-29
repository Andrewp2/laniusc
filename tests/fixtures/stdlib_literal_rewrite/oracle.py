"""Independent Unicode replacement model and bounded application owner ledger."""
from collections import Counter
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

INPUT_CAP=262144
OUTPUT_CAP=1048576
READ_CALLS=4096
COPY_CALLS=4096
TRACE='read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'
HELP=b'Usage: literal_rewrite [--count N] [--] NEEDLE REPLACEMENT\nReplace literal, nonoverlapping matches in UTF-8 stdin; write UTF-8 stdout.\nAn empty needle inserts at Unicode scalar boundaries, including both ends.\nInserted text is not searched; bytes and line endings otherwise stay unchanged.\nNo normalization, case folding or automatic newline is performed.\n--count N replaces only the first N matches; omitted count replaces all.\nN is 1..20 ASCII digits in u64 range, including zero; leading zeros are allowed.\n--count=N is accepted; duplicate counts are rejected; options may be intermixed.\nUse -- before operands beginning with a dash. Sole -h or --help shows help.\nLimits: 262144 input bytes, 256 needle bytes, 4096 replacement bytes,\n1048576 output bytes; 4096 input calls and 4096 Copier provider calls.\nArguments: at most 8 tokens and 8192 bytes; help/diagnostics: 64 write attempts.\nValidate through EOF and stage the complete result before stdout.\nOutput failure may leave a prefix; diagnostics report confirmed written bytes.\nExit: 0 success, 2 invalid input or limit, 3 I/O failure, 4 allocation failure.\n'
ERRORS={
    'arguments':b'literal_rewrite: invalid arguments\n',
    'argument-utf8':b'literal_rewrite: argument is not valid UTF-8\n',
    'utf8':b'literal_rewrite: input is not valid UTF-8\n',
    'input-bytes':b'literal_rewrite: input exceeds 262144 bytes\n',
    'output-bytes':b'literal_rewrite: output exceeds 1048576 bytes\n',
    'read-calls':b'literal_rewrite: input read-call limit\n',
    'input-io':b'literal_rewrite: input I/O failure\n',
    'allocation':b'literal_rewrite: allocation failed\n',
    'copy-calls':b'literal_rewrite: output call limit; written=',
    'output-io':b'literal_rewrite: output I/O failure; written=',
    'help-io':b'literal_rewrite: help I/O failure; written=0\n',
}


def reference(data,needle,replacement,count=None):
    source=data.decode('utf-8');old=needle.decode('utf-8');new=replacement.decode('utf-8')
    # Clamp Python's signed count to the number of possible matches. Lanius
    # accepts all u64 values; no string can need more than scalars + one.
    selected=len(source)+1 if count is None else min(count,len(source)+1)
    return source.replace(old,new,selected).encode('utf-8')


def model_cases():
    cases=[
        ('empty',b'',b'',b'',None),('empty-insert',b'',b'',b'x',None),
        ('no-match',b'original\0\r\n',b'missing',b'new',None),
        ('nonoverlap',b'aaaaa',b'aa',b'X',None),('overlap-prefix',b'ababa',b'aba',b'X',None),
        ('inserted-not-searched',b'aaa',b'a',b'aa',None),('delete-all',b'aaaa',b'aa',b'',None),
        ('unchanged',b'ababa',b'ab',b'ab',None),
        ('literal-metacharacters',b'a.*$1\\a.*$1',b'.*$1',b'\\1$0.*',None),
        ('nul-and-lines',b'\0a\r\na\n\r\0a',b'a',b'XY',None),
        ('unicode-needle','é中😀é'.encode(),'é'.encode(),'Ω'.encode(),None),
        ('no-normalization','é e\u0301 é'.encode(),'é'.encode(),b'X',None),
        ('empty-unicode','Aé😀'.encode(),b'',b':',None),
        ('count-zero',b'aaaa',b'a',b'growth',0),('count-one',b'aaaaa',b'aa',b'X',1),
        ('count-exact',b'ab-ab-ab',b'ab',b'Q',3),('count-u64-max',b'aaaaa',b'aa',b'X',18446744073709551615),
        ('empty-count-zero','é😀'.encode(),b'',b'x',0),
        ('empty-count-one','é😀'.encode(),b'',b'x',1),
        ('empty-count-two','é😀'.encode(),b'',b'x',2),
        ('empty-count-end','é😀'.encode(),b'',b'x',3),
        ('empty-count-past-end','é😀'.encode(),b'',b'x',4),
        ('pattern-across-read',b'z'*1023+b'ABC'+b'z'*1024,b'ABC',b'Q',None),
        ('scalar-across-read',b'z'*1023+'😀é'.encode(),'😀'.encode(),'中'.encode(),None),
        ('replacement-across-copy',b'a'*1023+b'X',b'X','😀'.encode(),None),
        ('needle-byte-cap',b'a'*256+b'x'+b'a'*256,b'a'*256,b'Z',None),
    ]
    cases.extend((f'copy-edge-{size}',b'a'*size,b'Z',b'Q',None) for size in (1023,1024,1025))
    return cases


def ledger(text,*,argv_count,argv_bytes,preflight=False,help_mode=False,output_length=None):
    events=[];counts=Counter();live={};argv={};input_address=None;input_extent=None;output_address=None
    consumed=0;eof=False;input_retired=False;started=False;peak=0
    argv_allocations=int(argv_count>0)+int(argv_bytes>0)
    for line in text.splitlines():
        matched=re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)',line)
        assert matched and matched[1] in TRACE.split(','),line
        name,args,answer=matched.groups();counts[name]+=1
        event=dict(name=name,args=args,answer=answer,ordinal=counts[name],line=line)
        if name=='mmap':
            assert not started and not input_retired,('allocation after staged retirement/publication',line)
            extent=int(args.split(',')[1]);event['extent']=extent
            phase='argv' if counts['mmap']<=argv_allocations else ('output' if eof else 'input');event['phase']=phase
            if phase=='output':
                assert len(argv)==argv_allocations and all(live.get(a)==n for a,n in argv.items()),('argument backing retired before replacement allocation',line)
                assert input_address is not None and live.get(input_address)==input_extent,('input backing retired before replacement allocation',line)
            if answer.startswith('0x'):
                address=answer.split()[0];assert address not in live;live[address]=extent;peak=max(peak,sum(live.values()))
                if phase=='argv':argv[address]=extent
                elif phase=='output':
                    assert output_address is None and output_length==extent,('fresh exact output owner',event,output_length)
                    output_address=address
            else:assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name=='munmap':
            address,extent=args.split(',');address=address.strip()
            assert answer=='0' and live.pop(address,None)==int(extent),line
            if eof and address==input_address:
                assert not input_retired;input_retired=True
        elif name in ('mremap','brk','openat','close'):
            raise AssertionError(('unexpected allocation or owned file service',line))
        elif name=='read':
            assert not preflight and not started and not eof and args.split(',')[0]=='0'
            assert len(argv)==argv_allocations and all(live.get(a)==n for a,n in argv.items()),('argument retirement before replacement',line)
            current={a:n for a,n in live.items() if a not in argv};assert len(current)==1,('one input owner at each read',line,live)
            input_address=next(iter(current));input_extent=current[input_address]
            requested=int(args.rsplit(',',1)[1]);event['requested']=requested
            remaining=INPUT_CAP-consumed
            assert 0<requested<=(min(1024,remaining) if remaining else 1),(line,consumed)
            if answer.isdigit():
                amount=int(answer);assert amount<=requested;consumed+=amount;eof=amount==0
        elif name=='write':
            fd=int(args.split(',')[0]);assert fd in (1,2);event['fd']=fd
            requested=int(args.rsplit(',',1)[1]);event['requested']=requested;assert 0<requested<=1024
            if fd==1 and not help_mode:
                assert not preflight and eof and input_retired and output_address is not None
                assert live=={output_address:output_length},('publication requires only staged output',line,live)
                started=True
            else:assert not live,('report/help before owner retirement',line,live)
            if answer.isdigit():assert int(answer)<=requested
        elif name=='rt_sigaction':assert not events and args.startswith('SIGPIPE,') and 'SIG_IGN' in args
        events.append(event)
    assert not live,('unreleased owners',live)
    assert counts['rt_sigaction']==1 and counts['read']<=READ_CALLS
    stdout=[x for x in events if x.get('fd')==1];diagnostic=[x for x in events if x.get('fd')==2]
    assert len(stdout)<=(64 if help_mode else COPY_CALLS-1) and len(diagnostic)<=64
    if preflight:assert counts['read']==0
    return dict(events=events,consumed=consumed,eof=eof,input_retired=input_retired,output_address=output_address,peak=peak)


class Runner:
    observes=True
    def __init__(self,executable,group):
        self.executable=str(Path(executable).resolve());header=Path(self.executable).read_bytes()[:64]
        assert len(header)==64 and header[:6]==b'\x7fELF\x02\x01' and int.from_bytes(header[16:18],'little')==2 and int.from_bytes(header[18:20],'little')==62
        self.directory=Path(tempfile.mkdtemp(prefix=f'literal-rewrite-{group}-'));self.count=0
    def run(self,name,data=b'',needle=b'a',replacement=b'x',count=None,*,args=None,status=0,output=None,error=None,injections=(),preflight=False,help_mode=False,closed_stdout=False,closed_stderr=False):
        args=args if args is not None else ([needle,replacement] if count is None else [b'--count',str(count).encode(),needle,replacement])
        raw_args=[os.fsencode(x) for x in args]
        d=self.directory/name;d.mkdir();source=d/'input';source.write_bytes(data)
        command=['strace','--kill-on-exit','-qq','-xx','-s','256','-e','signal=none','-e','trace='+TRACE,'-o',str(d/'trace')]
        for call,position,failure in injections:
            action=failure if failure.startswith('retval=') else 'error='+failure
            command+=['-e',f'inject={call}:{action}:when={position}']
        command+=[self.executable,*raw_args];(d/'command').write_text(repr(command)+'\n')
        descriptor=os.open(source,os.O_RDONLY)
        try:
            if closed_stdout or closed_stderr:
                reader,writer=os.pipe();os.close(reader)
                try:
                    result=subprocess.run(command,stdin=descriptor,stdout=writer if closed_stdout else subprocess.PIPE,stderr=writer if closed_stderr else subprocess.PIPE,timeout=60,check=False)
                finally:os.close(writer)
                if closed_stdout:result.stdout=b''
                if closed_stderr:result.stderr=b''
            else:result=subprocess.run(command,stdin=descriptor,capture_output=True,timeout=60,check=False)
        finally:os.close(descriptor)
        for filename,value in [('stdout',result.stdout),('stderr',result.stderr)]: (d/filename).write_bytes(value)
        (d/'status').write_text(str(result.returncode)+'\n')
        wanted=HELP if help_mode and status==0 else (reference(data,needle,replacement,count) if output is None and status==0 else output or b'')
        assert result.returncode==status and result.stdout==wanted,(name,result.returncode,status,result.stdout[:128],wanted[:128],result.stderr)
        expected_error=ERRORS[error] if isinstance(error,str) else error or b''
        assert result.stderr==expected_error,(name,result.stderr,expected_error)
        final_length=None
        if not preflight:
            try: final_length=len(reference(data,needle,replacement,count))
            except UnicodeDecodeError:pass
        traced=ledger((d/'trace').read_text(),argv_count=len(raw_args),argv_bytes=sum(map(len,raw_args)),preflight=preflight,help_mode=help_mode,output_length=final_length)
        events=traced['events'];indexed={(x['name'],x['ordinal']):x for x in events};selected=[]
        for call,position,failure in injections:
            positions=range(int(position.split('..')[0]),int(position.split('..')[1])+1) if isinstance(position,str) else [position]
            for ordinal in positions:
                event=indexed.get((call,ordinal));assert event is not None,(name,call,ordinal,'not reached')
                prefix=failure.removeprefix('retval=') if failure.startswith('retval=') else '-1 '+failure+' '
                assert event['answer'].startswith(prefix) and 'INJECTED' in event['answer'],event;selected.append(event)
        assert {x['line'] for x in events if 'INJECTED' in x['answer']}=={x['line'] for x in selected}
        for fd,value in ((1,result.stdout),(2,result.stderr)):
            confirmed=sum(int(x['answer']) for x in events if x.get('fd')==fd and x['answer'].isdigit())
            assert confirmed==len(value),(name,fd,confirmed,len(value))
        if status==0 and not help_mode:
            assert traced['eof'] and traced['consumed']==len(data) and traced['input_retired']
            assert (traced['output_address'] is None)==(len(wanted)==0)
        assert source.read_bytes()==data
        self.count+=1;return traced


def model(r):
    for name,data,needle,replacement,count in model_cases():r.run(name,data,needle,replacement,count)


def admission(r):
    invalid=[[],[b'a'],[b'a',b'b',b'c'],[b'--unknown'],[b'-n',b'1',b'a',b'b'],
             [b'--count',b'a',b'b'],[b'--count=',b'a',b'b'],[b'--count',b'-1',b'a',b'b'],
             [b'--count',b'+1',b'a',b'b'],[b'--count',b' 1',b'a',b'b'],
             [b'--count',b'18446744073709551616',b'a',b'b'],[b'--count',b'0'*21,b'a',b'b'],
             [b'--count',b'1',b'--count=2',b'a',b'b'],[b'--help',b'a',b'b'],[b'-h',b'a'],
             [b'a'*257,b'b'],[b'a',b'b'*4097],[b'\xff',b'b'],[b'a',b'\xed\xa0\x80'],
             [b'x']*9,[b'x'*8193]]
    for index,args in enumerate(invalid):r.run(f'invalid-{index}',args=args,status=2,error='argument-utf8' if index in (17,18) else 'arguments',preflight=True)
    r.run('help-long',args=[b'--help'],preflight=True,help_mode=True)
    r.run('help-short',args=[b'-h'],preflight=True,help_mode=True)
    r.run('count-intermixed',b'aaa',b'a',b'X',1,args=[b'a',b'--count=01',b'X'])
    r.run('dash-literals',b'--help -x --help',b'--help',b'-x',args=[b'--',b'--help',b'-x'])
    for name,data,count in [('malformed',b'ok\xff',None),('truncated',b'ok\xf0\x9f',None),('surrogate',b'\xed\xa0\x80',None),('past-unicode',b'\xf4\x90\x80\x80',None),('count-zero-still-validates',b'\xff',0)]:
        traced=r.run(name,data,count=count,status=2,error='utf8')
        if r.observes:assert traced['eof'] and traced['consumed']==len(data)


def limits(r):
    exact=r.run('input-cap',b'a'*INPUT_CAP,b'Z',b'Q')
    excess=r.run('input-excess-probe',b'a'*(INPUT_CAP+1),b'Z',b'Q',status=2,error='input-bytes')
    data=b'b'+b'a'*209715
    assert len(data)<INPUT_CAP and len(reference(data,b'a',b'aaaaa'))==OUTPUT_CAP
    r.run('output-cap',data,b'a',b'aaaaa')
    rejected=r.run('output-excess-preflight',data+b'a',b'a',b'aaaaa',status=2,error='output-bytes')
    r.run('replacement-byte-cap',b'aaa',b'a',b'z'*4096)
    r.run('empty-needle-count-restricts-growth',b'a'*INPUT_CAP,b'',b'X'*4096,1)
    r.run('shrinking-full-input',b'a'*INPUT_CAP,b'a',b'')
    if r.observes:
        for traced,probe in ((exact,0),(excess,1)):
            reads=[x for x in traced['events'] if x['name']=='read']
            assert sum(int(x['answer']) for x in reads[:-1])==INPUT_CAP
            assert reads[-1]['requested']==1 and reads[-1]['answer']==str(probe)
        assert rejected['eof'] and rejected['input_retired'] and rejected['output_address'] is None
        assert not any(x.get('fd')==1 for x in rejected['events'])


def output_error(kind,written):
    return ERRORS[kind]+str(written).encode()+b'\n'


def io(r):
    data=b'a'*INPUT_CAP
    base=r.run('allocation-baseline',data)
    mappings=[x for x in base['events'] if x['name']=='mmap']
    if r.observes:
        assert [x['phase'] for x in mappings[:2]]==['argv','argv']
        assert [x['extent'] for x in mappings if x['phase']=='input']==[1024<<n for n in range(9)]
        assert [(x['phase'],x['extent']) for x in mappings[-1:]]==[('output',INPUT_CAP)]
    for old in mappings:
        actual=r.run(f'oom-{old["ordinal"]}',data,status=4,error='allocation',injections=(('mmap',old['ordinal'],'ENOMEM'),))
        reached=[x for x in actual['events'] if x['name']=='mmap']
        assert [x['args'] for x in reached]==[x['args'] for x in mappings[:old['ordinal']]]
    reads=[x for x in base['events'] if x['name']=='read'];writes=[x for x in base['events'] if x.get('fd')==1]
    assert len(reads)>1 and len(writes)>1
    r.run('read-after-prefix-eio',data,status=3,error='input-io',injections=(('read',reads[1]['ordinal'],'EIO'),))
    r.run('read-eintr',data,injections=(('read',reads[0]['ordinal'],'EINTR'),))
    r.run('write-first-eio',data,status=3,error=output_error('output-io',0),injections=(('write',writes[0]['ordinal'],'EIO'),))
    prefix=int(writes[0]['answer']);assert 0<prefix<INPUT_CAP
    r.run('write-after-prefix-eio',data,status=3,output=b'x'*prefix,error=output_error('output-io',prefix),injections=(('write',writes[1]['ordinal'],'EIO'),))
    r.run('write-eintr',data,injections=(('write',writes[0]['ordinal'],'EINTR'),))
    r.run('write-would-block',data,status=3,error=output_error('output-io',0),injections=(('write',writes[0]['ordinal'],'EAGAIN'),))
    r.run('write-zero',data,status=3,error=output_error('output-io',0),injections=(('write',writes[0]['ordinal'],'retval=0'),))
    r.run('signal-eio',status=3,preflight=True,injections=(('rt_sigaction',1,'EIO'),))
    r.run('closed-stdout',b'aaa',status=3,error=output_error('output-io',0),closed_stdout=True)
    r.run('empty-output-closed-stdout',b'aaa',b'a',b'',closed_stdout=True)
    r.run('closed-help',args=[b'--help'],status=3,error='help-io',preflight=True,help_mode=True,closed_stdout=True)
    r.run('diagnostic-failure-keeps-usage',args=[b'--unknown'],status=2,preflight=True,injections=(('write',1,'EIO'),))
    exhausted=r.run('read-attempt-limit',b'abc',status=2,error='read-calls',injections=(('read',f'1..{READ_CALLS}','EINTR'),))
    first=r.run('copy-attempt-limit',b'a'*2049,status=2,error=output_error('copy-calls',0),injections=(('write',f'1..{COPY_CALLS-1}','EINTR'),))
    later=r.run('copy-limit-after-prefix',b'a'*2049,status=2,output=b'x'*prefix,error=output_error('copy-calls',prefix),injections=(('write',f'2..{COPY_CALLS-2}','EINTR'),))
    if r.observes:
        assert sum(x['name']=='read' for x in exhausted['events'])==READ_CALLS
        assert sum(x.get('fd')==1 for x in first['events'])==COPY_CALLS-1
        assert sum(x.get('fd')==1 for x in later['events'])==COPY_CALLS-2
        assert sum(x.get('fd')==2 for x in first['events'])==1
        assert sum(x.get('fd')==2 for x in later['events'])==1
    return len(mappings)


class ControlRunner:
    """Host-only corpus construction, never native application evidence."""
    observes=False
    def __init__(self):self.count=0
    def run(self,name,data=b'',needle=b'a',replacement=b'x',count=None,*,status=0,help_mode=False,output=None,**kwargs):
        self.count+=1
        if status==0 and not help_mode:
            wanted=reference(data,needle,replacement,count)
            assert len(wanted)<=OUTPUT_CAP
            if output is not None:assert wanted==output
        if name=='allocation-baseline':
            return dict(events=[dict(name='mmap',ordinal=1,args='baseline'),dict(name='read',ordinal=1),dict(name='read',ordinal=2),dict(name='write',fd=1,ordinal=1,answer='1024'),dict(name='write',fd=1,ordinal=2)])
        if name.startswith('oom-'):return dict(events=[dict(name='mmap',ordinal=1,args='baseline')])
        return dict(events=[])


def controls():
    assert len(HELP)==1114 and len(model_cases())==29
    assert reference(b'aaaaa',b'aa',b'X')==b'XXa'
    assert reference('é😀'.encode(),b'',b':')==':é:😀:'.encode()
    assert reference('é😀'.encode(),b'',b':',2)==':é:😀'.encode()
    assert reference('é e\u0301'.encode(),'é'.encode(),b'X')=='X e\u0301'.encode()
    assert reference(b'aaa',b'a',b'aa',18446744073709551615)==b'aaaaaa'
    def mapping(address,extent):return f'mmap(NULL, {extent}, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = {address}'
    trace=[
        'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0',
        mapping('0x100000000',80),mapping('0x200000000',2),mapping('0x300000000',1024),
        'read(0, "a", 1024) = 1','read(0, "", 1024) = 0',mapping('0x400000000',1),
        'munmap(0x300000000, 1024) = 0','munmap(0x100000000, 80) = 0','munmap(0x200000000, 2) = 0',
        'write(1, "x", 1) = 1','munmap(0x400000000, 1) = 0',
    ]
    check=lambda lines:ledger('\n'.join(lines),argv_count=2,argv_bytes=2,output_length=1)
    assert check(trace)['input_retired']
    broken=[trace[:-1],trace[:7]+trace[8:],trace[:8]+trace[9:],
            trace[:10]+[trace[11],trace[10]],
            trace[:6]+[mapping('0x500000000',1)]+trace[6:],
            trace[:5]+trace[6:],trace[:-1]+['munmap(0x400000000, 2) = 0'],
            trace[:4]+[trace[8]]+trace[4:8]+trace[9:],
            trace[:6]+[trace[9]]+trace[6:9]+trace[10:],
            trace[:6]+[trace[7]]+trace[6:7]+trace[8:]]
    for bad in broken:
        try:check(bad)
        except AssertionError:pass
        else:raise AssertionError('corrupt ownership/publication trace accepted')
    groups=[]
    for name,run in GROUPS.items():
        control=ControlRunner();allocations=run(control) or 0
        groups.append(f'{name}={control.count}' if name!='io' else f'io={control.count-allocations}+A')
    print('literal-rewrite-controls '+' '.join(groups)+' (host-only; no native evidence)')


GROUPS=dict(model=model,admission=admission,limits=limits,io=io)
if __name__=='__main__':
    if sys.argv[1:]==['controls']:controls()
    else:
        group,exe=sys.argv[1:];runner=Runner(exe,group);allocations=GROUPS[group](runner) or 0
        if group=='io':assert runner.count==16+allocations
        print(f'literal-rewrite-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
