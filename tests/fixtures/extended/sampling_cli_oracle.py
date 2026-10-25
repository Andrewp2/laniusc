"""Actual CSV/CLI sampling consumer, independent statistics and syscall faults."""
import csv,io,math,os,pathlib,re,struct,subprocess,sys,tempfile
exe=sys.argv[1]
HEADER=b'family,first,second,count\n'
def run(data,args=()):return subprocess.run([exe,*args],input=data,capture_output=True,timeout=15)
def rows(r):
    assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
    values=list(csv.DictReader(io.StringIO(r.stdout.decode())))
    assert all(None not in row and all(v is not None for v in row.values()) for row in values),values[:2]
    return values
data=HEADER+b'normal,-2,3,4000\nexponential,2,0,4000\ngamma,2,3,4000\nbeta,2,5,4000\n'
r=run(data,['--seed','123']);values=rows(r)
assert run(data,['--seed','123']).stdout==r.stdout
assert run(data,['--seed','124']).stdout!=r.stdout
assert list(values[0])=='kind job index value count mean variance draws work'.split()
assert len(values)==16004
draws=work=0
for job,(mean,variance) in enumerate([(-2.,9.),(.5,.25),(6.,18.),(2/7,10/(49*8))],1):
    records=[x for x in values if int(x['job'])==job]
    samples=records[:-1];summary=records[-1]
    assert len(samples)==4000 and summary['kind']=='summary' and summary['count']=='4000'
    xs=[]
    for index,row in enumerate(samples):
        assert row['kind']=='sample' and int(row['index'])==index
        x=float(row['value']);assert math.isfinite(x);xs.append(x)
        assert all(row[k]=='' for k in ['count','mean','variance','draws','work'])
    observed=math.fsum(xs)/len(xs);v=math.fsum((x-observed)**2 for x in xs)/len(xs)
    assert abs(float(summary['mean'])-observed)<=2e-12*max(1.,abs(observed))
    assert abs(float(summary['variance'])-v)<=2e-12*max(1.,v)
    assert abs(observed-mean)<=9*math.sqrt(variance/len(xs))
    assert abs(v-variance)<=.2*variance
    assert int(summary['draws'])>draws and int(summary['work'])>work
    draws=int(summary['draws']);work=int(summary['work'])
# An independent first xoshiro256++ draw plus exponential inverse makes the
# command's seed and stream origin observable without duplicating gamma code.
mask=(1<<64)-1;s=[];seed=17
for _ in range(4):
    seed=(seed+0x9e3779b97f4a7c15)&mask;z=seed;z=((z^(z>>30))*0xbf58476d1ce4e5b9)&mask;z=((z^(z>>27))*0x94d049bb133111eb)&mask;s.append(z^(z>>31))
z=(s[0]+s[3])&mask;word=((((z<<23)|(z>>41))&mask)+s[0])&mask
want=-math.log1p(-(word>>11)*2**-53)/3
first=rows(run(HEADER+b'"exponential",3,0,1\r\n',['--seed','17']))
assert abs(float(first[0]['value'])-want)<=4*math.ulp(want)
bad=[b'',b'normal,0,1,2\n',HEADER+b'normal,0,1\n',HEADER+b'wat,0,1,1\n',HEADER+b'normal,0,0,1\n',HEADER+b'gamma,-1,1,1\n',HEADER+b'normal,nan,1,1\n',HEADER+b'normal,0,inf,1\n',HEADER+b'exponential,1,1,1\n',HEADER+b'beta,1,1,0\n',HEADER+b'beta,1,1,x\n',HEADER+b'beta,1,1,18446744073709551616\n',HEADER+b'normal,0,1,"2\n',HEADER+b'normal,0,1,1\xff\n',HEADER+b'normal,0,1e300,2\n']
for data_bad in bad:
    failure=run(data_bad);assert failure.returncode==2 and not failure.stdout and failure.stderr,(data_bad,failure.returncode,failure.stdout,failure.stderr)
small=HEADER+b'normal,0,1,3\nbeta,2,3,4\n'
for args in [['--max-input-bytes','1'],['--max-jobs','0'],['--max-samples','1'],['--max-output-bytes','1'],['--max-work','1'],['--max-draws','0']]:
    failure=run(small,args);assert failure.returncode==3 and not failure.stdout and failure.stderr,(args,failure.returncode,failure.stderr)
# Failure after an earlier job has already filled the staged output must
# still publish no CSV. These are distinct from rejecting the first job.
late_invalid=HEADER+b'normal,0,1,3\nbeta,0,3,4\n'
failure=run(late_invalid);assert failure.returncode==2 and not failure.stdout and failure.stderr
for args in [['--max-samples','4'],['--max-draws','7'],['--max-work','3000000']]:
    failure=run(small,args);assert failure.returncode==3 and not failure.stdout and failure.stderr,(args,failure.returncode,failure.stdout,failure.stderr)
for args in [['operand'],['--seed','1','--seed','2'],['--max-jobs','4097'],['--max-samples','1000001'],['--max-output-bytes','67108865'],['--seed','-1'],['--help','--seed','1']]:
    failure=run(small,args);assert failure.returncode==2 and not failure.stdout and failure.stderr,(args,failure.returncode,failure.stderr)
help=run(b'',['--help']);assert help.returncode==0 and help.stdout.startswith(b'Usage: sample-distribution ') and not help.stderr
def traced(data,args=(),fault=None,output=None):
    with tempfile.NamedTemporaryFile() as trace:
        command=['strace','-qq','-o',trace.name,'-e','trace=mmap,munmap,read,write']
        if fault:command+=['-e',fault]
        result=subprocess.run(command+[exe,*args],input=data,stdout=output or subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
        log=pathlib.Path(trace.name).read_text()
    live={};count=0
    for line in log.splitlines():
        m=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if m:assert m[2] not in live;live[m[2]]=int(m[1]);count+=1
        m=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if m:assert live.pop(m[1],None)==int(m[2]),line
    assert not live,(live,fault,log)
    return result,count,log
baseline,count,_=traced(small,['--seed','9']);assert baseline.returncode==0 and count>=5,(baseline.returncode,count,baseline.stderr)
for when in range(1,count+1):
    failure,_,log=traced(small,['--seed','9'],'inject=mmap:error=ENOMEM:when='+str(when)+'+')
    assert failure.returncode==4 and not failure.stdout and failure.stderr,(when,failure.returncode,failure.stdout,failure.stderr)
    assert 'INJECTED' in log
for call in ['read','write']:
    result,_,_=traced(small,['--seed','9'],f'inject={call}:error=EINTR:when=1');assert result.returncode==0 and result.stdout==baseline.stdout
    result,_,_=traced(small,['--seed','9'],f'inject={call}:error=EIO:when=1');assert result.returncode==5 and not result.stdout and result.stderr
result,_,_=traced(small,['--seed','9'],'inject=write:retval=1:when=1');assert result.returncode==0 and result.stdout==baseline.stdout[1:]
for args,data_bad in [(['--max-output-bytes','1'],small),([],bad[-1]),([],bad[4])]:
    result,_,_=traced(data_bad,args);assert result.returncode in [2,3] and not result.stdout
with open('/dev/full','wb') as full:
    result,_,_=traced(small,output=full);assert result.returncode==5 and result.stderr
print('verified16000actualCSV samples, seeded stream origin, statistics, staging,',count,'allocation denials and I/O cleanup')
