"""Real unreadable output pipes, checked cleanup, and preallocation setup errors."""
import os,pathlib,re,subprocess,sys,tempfile

exe=sys.argv[1]
valid=b'family,first,second,count\nnormal,0,1,3\nbeta,2,3,4\n'
late_invalid=b'family,first,second,count\nnormal,0,1,3\nbeta,0,3,4\n'

def traced(data,args=(),closed_stdout=False,closed_stderr=False,fault=None):
    owned=[]
    def closed_pipe():
        read,write=os.pipe()
        os.close(read)
        owned.append(write)
        return write
    stdout=closed_pipe() if closed_stdout else subprocess.PIPE
    stderr=closed_pipe() if closed_stderr else subprocess.PIPE
    try:
        with tempfile.NamedTemporaryFile() as trace:
            command=['strace','-qq','-o',trace.name,'-e','trace=rt_sigaction,mmap,munmap,openat,read,write']
            if fault:command+=['-e',fault]
            # restore_signals resets Python's inherited SIGPIPE ignore before
            # exec. The CLI must install its own policy to survive these pipes.
            result=subprocess.run(command+[exe,*args],input=data,stdout=stdout,stderr=stderr,restore_signals=True,timeout=5)
            log=pathlib.Path(trace.name).read_text()
    finally:
        for descriptor in owned:os.close(descriptor)
    live={};allocations=0
    for line in log.splitlines():
        match=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if match:
            assert match[2] not in live,line
            live[match[2]]=int(match[1]);allocations+=1
        match=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if match:assert live.pop(match[1],None)==int(match[2]),line
    assert not live,(live,log)
    assert result.returncode==5,(result.returncode,result.stdout,result.stderr,log)
    return result,allocations,log

def ignored(log):
    assert re.search(r'rt_sigaction\(SIGPIPE, \{sa_handler=SIG_IGN,.*\) += 0',log),log

# Actual EPIPE from the kernel, not an injected write return. All input,
# parsed-table, staged-output and argument mappings must be released.
result,allocations,log=traced(valid,closed_stdout=True)
assert allocations>=5 and result.stderr and b'error=5 stage=4' in result.stderr
assert re.search(r'write\(1,.*= -1 EPIPE',log),log
ignored(log)

# The original validation error becomes the existing I/O status if writing
# its diagnostic also hits a real closed stderr pipe, after owned cleanup.
result,allocations,log=traced(late_invalid,closed_stderr=True)
assert allocations>=5 and not result.stdout
assert re.search(r'write\(2,.*= -1 EPIPE',log),log
ignored(log)

result,allocations,log=traced(valid,closed_stdout=True,closed_stderr=True)
assert allocations>=5
assert re.search(r'write\(1,.*= -1 EPIPE',log) and re.search(r'write\(2,.*= -1 EPIPE',log),log
ignored(log)

# A failed process policy setup exits before even invalid arguments are
# inspected. It attempts no diagnostic under an unknown SIGPIPE disposition.
for cause in ['EPERM','EINTR']:
    result,allocations,log=traced(valid,['--unknown'],fault=f'inject=rt_sigaction:error={cause}:when=1')
    assert allocations==0 and not result.stdout and not result.stderr
    assert log.count('rt_sigaction(')==1 and 'INJECTED' in log
    assert not re.search(r'^(?:mmap|munmap|openat|read|write)\(',log,re.M),log

print('real closed stdout/stderr and combined pipes: status5, complete mapping cleanup; signal setup EPERM/EINTR: no args, allocation or output')
