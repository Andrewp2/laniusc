"""Real count CSV, independent predictions/statistics and native fault paths."""
import csv,io,math,os,pathlib,re,subprocess,sys,tempfile
import mpmath as mp
mp.mp.dps=110
exe=sys.argv[1]
HEADER=b'family,trials,parameter,samples,threshold\n'
def run(data,args=()):return subprocess.run([exe,*args],input=data,capture_output=True,timeout=10)
def rows(result):
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    values=list(csv.DictReader(io.StringIO(result.stdout.decode())))
    assert all(None not in row and all(v is not None for v in row.values()) for row in values),values[:2]
    return values

data=HEADER+b'bernoulli,0,.25,3000,0\nbinomial,100,.3,3000,35\ngeometric,0,.2,3000,5\npoisson,0,10,3000,12\n'
result=run(data,['--seed','123']);values=rows(result)
assert run(data,['--seed','123']).stdout==result.stdout
assert run(data,['--seed','124']).stdout!=result.stdout
fields='kind job index value samples mean variance threshold exceedances pmf log_pmf survival log_survival draws work'.split()
assert list(values[0])==fields and len(values)==12004
last_draws=last_work=0
for job,(mean,variance,threshold) in enumerate([(.25,.1875,0),(30.,21.,35),(4.,20.,5),(10.,10.,12)],1):
    records=[x for x in values if int(x['job'])==job];samples=records[:-1];summary=records[-1]
    assert len(samples)==3000 and summary['kind']=='summary' and summary['samples']=='3000'
    assert summary['index']==summary['value']==''
    counts=[]
    for index,row in enumerate(samples):
        assert row['kind']=='sample' and int(row['index'])==index
        assert re.fullmatch(r'0|[1-9][0-9]*',row['value']),row
        counts.append(int(row['value']));assert all(row[k]=='' for k in fields[4:])
    actual=math.fsum(counts)/len(counts);observed=math.fsum((x-actual)**2 for x in counts)/len(counts)
    assert abs(float(summary['mean'])-actual)<=2e-12*max(1.,abs(actual))
    assert abs(float(summary['variance'])-observed)<=2e-12*max(1.,observed)
    assert abs(actual-mean)<=9*math.sqrt(variance/len(counts))
    assert abs(observed-variance)<=.4*variance
    exceedances=sum(x>threshold for x in counts)
    assert int(summary['threshold'])==threshold and int(summary['exceedances'])==exceedances
    if job==1:mass=mp.mpf('.75');survival=mp.mpf('.25')
    elif job==2:
        p=mp.mpf(float(.3));mass=mp.binomial(100,35)*p**35*(1-p)**65
        survival=mp.fsum(mp.binomial(100,k)*p**k*(1-p)**(100-k) for k in range(36,101))
    elif job==3:p=mp.mpf(float(.2));mass=p*(1-p)**5;survival=(1-p)**6
    else:mass=mp.exp(-10)*mp.mpf(10)**12/mp.factorial(12);survival=mp.gammainc(13,0,10,regularized=True)
    for field,want in [('pmf',mass),('log_pmf',mp.log(mass)),('survival',survival),('log_survival',mp.log(survival))]:
        observed=float(summary[field]);want=float(want)
        assert math.isfinite(observed) and abs(observed-want)<=2e-11*max(abs(want),1e-300),(job,field,observed,want)
    p=float(survival)
    assert abs(exceedances-len(counts)*p)<=9*math.sqrt(len(counts)*p*(1-p))+8
    assert int(summary['draws'])>last_draws and int(summary['work'])>last_work
    last_draws=int(summary['draws']);last_work=int(summary['work'])

# The first Bernoulli count identifies both seed parsing and stream origin.
mask=2**64-1;state=[];seed=17
for _ in range(4):
    seed=(seed+0x9e3779b97f4a7c15)&mask;z=seed;z=((z^(z>>30))*0xbf58476d1ce4e5b9)&mask;z=((z^(z>>27))*0x94d049bb133111eb)&mask;state.append(z^(z>>31))
z=(state[0]+state[3])&mask;word=((((z<<23)|(z>>41))&mask)+state[0])&mask
first=rows(run(HEADER+b'"bernoulli",0,.5,1,0\r\n',['-s17']))
assert int(first[0]['value'])==int(word<2**63) and first[-1]['draws']=='1'

full=rows(run(HEADER+b'binomial,4294967295,1,2,4294967295\n',['--seed',str(2**64-1),'--max-draws','0']))
assert [x['value'] for x in full[:-1]]==['4294967295']*2
assert full[-1]['mean']=='4294967295.0' or float(full[-1]['mean'])==4294967295.
assert float(full[-1]['variance'])==0 and full[-1]['draws']=='0'
assert float(full[-1]['pmf'])==1 and float(full[-1]['survival'])==0 and float(full[-1]['log_survival'])==-math.inf
for threshold,expected in [(-2**63,1.),(2**63-1,0.)]:
    endpoint=rows(run(HEADER+f'bernoulli,0,.5,2,{threshold}\n'.encode()))[-1]
    assert float(endpoint['survival'])==expected and int(endpoint['exceedances'])==2*int(expected)

invalid=[b'',b'bernoulli,0,.5,2,0\n',HEADER+b'bernoulli,0,.5,1\n',HEADER+b'wat,0,.5,1,0\n',HEADER+b'bernoulli,1,.5,1,0\n',HEADER+b'binomial,-1,.5,1,0\n',HEADER+b'binomial,4294967296,.5,1,0\n',HEADER+b'geometric,0,0,1,0\n',HEADER+b'poisson,0,1000000001,1,0\n',HEADER+b'bernoulli,0,nan,1,0\n',HEADER+b'bernoulli,0,inf,1,0\n',HEADER+b'binomial,10,.5,0,0\n',HEADER+b'binomial,10,.5,x,0\n',HEADER+b'binomial,10,.5,18446744073709551616,0\n',HEADER+b'binomial,10,.5,1,9223372036854775808\n',HEADER+b'geometric,0,.5,1,9007199254740992\n',HEADER+b'poisson,0,1,1,9007199254740991\n',HEADER+b'geometric,0,5e-324,1,0\n',HEADER+b'bernoulli,0,.5,"2\n',HEADER+b'bernoulli,0,.5,1,0\xff\n']
for bad in invalid:
    result=run(bad);assert result.returncode==2 and not result.stdout and result.stderr,(bad,result.returncode,result.stdout,result.stderr)
small=HEADER+b'bernoulli,0,.5,3,0\npoisson,0,100,4,100\n'
for args in [['--max-input-bytes','1'],['--max-jobs','0'],['--max-samples','1'],['--max-output-bytes','1'],['--max-work','1'],['--max-draws','0'],['--max-samples','4'],['--max-draws','3'],['--max-work','1500000']]:
    result=run(small,args);assert result.returncode==3 and not result.stdout and result.stderr,(args,result.returncode,result.stdout,result.stderr)
oversized=HEADER+b'poisson,0,'+b'1'*129+b',1,0\n'
result=run(oversized);assert result.returncode==3 and not result.stdout
late_invalid=HEADER+b'bernoulli,0,.5,3,0\ngeometric,0,0,1,0\n'
result=run(late_invalid);assert result.returncode==2 and not result.stdout
for args in [['operand'],['--seed','1','--seed','2'],['--seed','-1'],['--max-jobs','4097'],['--max-samples','1000001'],['--max-output-bytes','67108865'],['--help','--seed','1']]:
    result=run(small,args);assert result.returncode==2 and not result.stdout and result.stderr,(args,result.returncode,result.stderr)
result=run(b'',['--help']);assert result.returncode==0 and result.stdout.startswith(b'Usage: sample-counts ') and not result.stderr

def traced(data,args=(),fault=None,closed_stdout=False,closed_stderr=False,output=None):
    owned=[]
    def closed_pipe():
        read,write=os.pipe();os.close(read);owned.append(write);return write
    stdout=closed_pipe() if closed_stdout else output if output is not None else subprocess.PIPE
    stderr=closed_pipe() if closed_stderr else subprocess.PIPE
    try:
        with tempfile.NamedTemporaryFile() as trace:
            command=['strace','-qq','-o',trace.name,'-e','trace=rt_sigaction,mmap,munmap,openat,read,write']
            if fault:command+=['-e',fault]
            result=subprocess.run(command+[exe,*args],input=data,stdout=stdout,stderr=stderr,restore_signals=True,timeout=8)
            log=pathlib.Path(trace.name).read_text()
    finally:
        for descriptor in owned:os.close(descriptor)
    live={};count=0
    for line in log.splitlines():
        match=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if match:assert match[2] not in live;live[match[2]]=int(match[1]);count+=1
        match=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if match:assert live.pop(match[1],None)==int(match[2]),line
    assert not live,(live,fault,log)
    return result,count,log
baseline,count,log=traced(small,['--seed','9']);assert baseline.returncode==0 and count>=5
assert re.search(r'rt_sigaction\(SIGPIPE, \{sa_handler=SIG_IGN,.*\) += 0',log),log
for when in range(1,count+1):
    result,_,log=traced(small,['--seed','9'],f'inject=mmap:error=ENOMEM:when={when}+')
    assert result.returncode==4 and not result.stdout and result.stderr,(when,result.returncode,result.stdout,result.stderr)
    assert 'INJECTED' in log
for call in ['read','write']:
    result,_,_=traced(small,['--seed','9'],f'inject={call}:error=EINTR:when=1');assert result.returncode==0 and result.stdout==baseline.stdout
    result,_,_=traced(small,['--seed','9'],f'inject={call}:error=EIO:when=1');assert result.returncode==5 and not result.stdout and result.stderr
result,_,_=traced(small,['--seed','9'],'inject=write:retval=1:when=1');assert result.returncode==0 and result.stdout==baseline.stdout[1:]
for args,bad in [(['--max-output-bytes','1'],small),([],late_invalid),([],invalid[17])]:
    result,_,_=traced(bad,args);assert result.returncode in [2,3] and not result.stdout
for data,closed_stdout,closed_stderr in [(small,True,False),(late_invalid,False,True),(small,True,True)]:
    result,mappings,log=traced(data,closed_stdout=closed_stdout,closed_stderr=closed_stderr)
    assert result.returncode==5 and mappings>=5,(result.returncode,result.stderr,log)
    if closed_stdout:assert re.search(r'write\(1,.*= -1 EPIPE',log)
    if closed_stderr:assert re.search(r'write\(2,.*= -1 EPIPE',log)
    if not closed_stdout:assert not result.stdout
for cause in ['EPERM','EINTR']:
    result,mappings,log=traced(small,['--unknown'],f'inject=rt_sigaction:error={cause}:when=1')
    assert result.returncode==5 and mappings==0 and not result.stdout and not result.stderr
    assert log.count('rt_sigaction(')==1 and 'INJECTED' in log
    assert not re.search(r'^(?:mmap|munmap|openat|read|write)\(',log,re.M),log
with open('/dev/full','wb') as full:
    result,_,_=traced(small,output=full);assert result.returncode==5 and result.stderr
print('verified12000actual count samples, predictions/logs/moments/exceedances, full-u32 trials/seed, staging,',count,'allocation denials, I/O faults, real closed pipes and preallocation signal setup failure')
