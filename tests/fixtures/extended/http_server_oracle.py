"""Independent loopback HTTP clients; all service/protocol behavior is Lanius."""
import ast,collections,contextlib,email.utils,os,re,select,shutil,socket,subprocess,sys,tempfile,time
from pathlib import Path
import h11
MODE=EXE=None
COUNT=0
TRACE_SYSCALLS='socket,accept4,fcntl,close,mmap,munmap,recvfrom,sendto,poll,shutdown,clock_gettime,rt_sigaction,write'
REPORT_PARSER=None

@contextlib.contextmanager
def retained(label):
    directory=Path(tempfile.mkdtemp(prefix='http-server-app-'+label+'-'))
    try:yield directory
    except BaseException:
        print('HTTP application failure evidence retained: '+str(directory),file=sys.stderr,flush=True)
        raise
    else:shutil.rmtree(directory)

def reports(errors):
    global REPORT_PARSER
    if not errors:return []
    if REPORT_PARSER is None:
        # Reuse the concurrent application's strict report parser without
        # importing its executable oracle or executing any of its tests.
        path=Path(__file__).with_name('server_concurrency')/'oracle.py'
        tree=ast.parse(path.read_text(),filename=str(path))
        fields=next(ast.literal_eval(node.value) for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=='REPORT_FIELDS' for target in node.targets))
        definition=next(node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name=='parse_reports')
        namespace={'re':re,'REPORT_FIELDS':fields}
        exec(compile(ast.Module(body=[definition],type_ignores=[]),str(path),'exec'),namespace)
        REPORT_PARSER=namespace['parse_reports']
    rows=REPORT_PARSER(errors,False)
    assert [row['id'] for row in rows]==list(range(len(rows))),rows
    for row in rows:
        assert row['code'] in (0,3,4) and row['failed']==int(row['code']!=0),row
        assert all(row[name] in (0,1) for name in ('rejected','shutdown','eof','closed')),row
        assert row['sent']<=row['response'] and row['closed']==row['cleanup']==1,row
        assert row['cleanup-errors']<=1,row
        if row['code']==0:
            assert row['cleanup-errors']==0 and row['eof']==1,row
            if row['response']:assert row['sent']==row['response'] and row['shutdown']==1,row
    return rows

def observed(path):
    result=[];counts=collections.Counter()
    for line in Path(path).read_text().splitlines():
        if not line or line.startswith(('---','+++')):continue
        found=re.fullmatch(r'(?:\[([0-9a-fA-Fx]+)\]\s+)?([a-z0-9_]+)\((.*)\)\s+=\s+(.+)',line)
        assert found,('unparsed syscall',line)
        ip,name,args,value=found.groups();assert name in TRACE_SYSCALLS.split(','),line
        counts[name]+=1
        result.append(dict(ip=None if ip is None else int(ip,16),name=name,args=args,result=value,ordinal=counts[name],line=line))
    return result

def reached(path,syscall,ordinal,error=None,delayed=False):
    entries=observed(path)
    selected=[entry for entry in entries if entry['name']==syscall]
    assert 0<ordinal<=len(selected),(syscall,ordinal,entries)
    target=selected[ordinal-1];assert target['ip'] is not None,target
    if error is not None:
        marked=[entry for entry in entries if 'INJECTED' in entry['result']]
        assert marked==[target] and target['result'].split()[:2]==['-1',error],(target,marked)
    if delayed:assert 'DELAYED' in target['result'],target
    return target

def start(args=(),family=socket.AF_INET,trace=None,fault=None,stdout=None,artifacts=None):
    address='127.0.0.1:0' if family==socket.AF_INET else '[::1]:0'
    command=[EXE,address,'--timeout','1000','--report',*map(str,args)]
    if trace:command=['strace','--kill-on-exit','-qq','-i','-s','4096','-o',str(trace),'-e','signal=none','-e','trace='+TRACE_SYSCALLS,*[p for f in (fault if isinstance(fault,list) else [fault]) if f for p in ['-e',f]],*command]
    p=subprocess.Popen(command,stdout=subprocess.PIPE if stdout is None else stdout,stderr=subprocess.PIPE)
    p.application_command=command;p.application_startup=b''
    if artifacts is not None:(artifacts/'command.txt').write_text(repr(command)+'\n')
    endpoint=None
    if stdout is None:
        try:
            until=time.monotonic()+3
            while not p.application_startup.endswith(b'\n'):
                remaining=until-time.monotonic();assert remaining>0 and select.select([p.stdout],[],[],remaining)[0],'startup timeout'
                block=os.read(p.stdout.fileno(),96-len(p.application_startup))
                if not block:break
                p.application_startup+=block
                assert len(p.application_startup)<96 or p.application_startup.endswith(b'\n'),p.application_startup
            if p.application_startup:
                assert p.application_startup.endswith(b'\n'),p.application_startup
                value=p.application_startup.decode().strip()
                if value.startswith('['):host,port=value[1:].split(']:')
                else:host,port=value.rsplit(':',1)
                endpoint=(host,int(port))
        except BaseException:
            if p.poll() is None:p.kill()
            out,err=p.communicate(timeout=3)
            if artifacts is not None:
                (artifacts/'startup.stdout').write_bytes(p.application_startup+out);(artifacts/'native.stderr').write_bytes(err)
                (artifacts/'startup.diagnostic.txt').write_text(repr(dict(returncode=p.returncode,error=repr(sys.exc_info()[1])))+'\n')
            raise
    return p,endpoint

def parse(wire,method=b'GET',expected=200,body=b'',interims=0):
    parser=h11.Connection(h11.CLIENT)
    parser.send(h11.Request(method=method,target=b'/',headers=[(b'host',b'x')]))
    parser.send(h11.EndOfMessage())
    parser.receive_data(wire);parser.receive_data(b'');status=None;content=bytearray();info=0;ended=False
    while True:
        event=parser.next_event()
        if event is h11.NEED_DATA:raise AssertionError(('incomplete',wire))
        if isinstance(event,h11.InformationalResponse):info+=1;assert event.status_code==100
        elif isinstance(event,h11.Response):
            assert status is None;status=event.status_code
            headers=list(event.headers)
            assert [v for n,v in headers if n==b'connection']==[b'close'],headers
            dates=[v for n,v in headers if n==b'date'];assert len(dates)==1 and len(dates[0])==29,headers
            dt=email.utils.parsedate_to_datetime(dates[0].decode());assert email.utils.format_datetime(dt,usegmt=True).encode()==dates[0]
        elif isinstance(event,h11.Data):content.extend(event.data)
        elif isinstance(event,h11.EndOfMessage):ended=True
        elif isinstance(event,h11.ConnectionClosed):break
        elif event is h11.PAUSED:break
    assert status==expected and bytes(content)==body and info==interims and ended,(status,expected,len(content),len(body),info,wire[:300])

def exchange(wire,args=(),family=socket.AF_INET,fragment=0,expect=False,early=False,status=200,body=b'',process_status=0,trace=None,fault=None,method=b'GET'):
    global COUNT
    with retained('exchange') as directory:
        p=conn=None;received=b'';out=err=b'';finished=False;peer_error=None;intervention='none'
        (directory/'request.bin').write_bytes(wire)
        try:
            p,endpoint=start(args,family,trace,fault,artifacts=directory)
            if endpoint:
                try:
                    conn=socket.create_connection(endpoint,2);conn.settimeout(3)
                    if expect:
                        head,content=wire.split(b'\r\n\r\n',1);conn.sendall(head+b'\r\n\r\n')
                        until=time.monotonic()+3
                        while b'\r\n\r\n' not in received:
                            remaining=until-time.monotonic();assert remaining>0,'Continue deadline'
                            conn.settimeout(remaining);part=conn.recv(1024);assert part,('EOF before Continue',received);received+=part
                        assert received==b'HTTP/1.1 100 Continue\r\n\r\n',received
                        conn.settimeout(3);conn.sendall(content)
                    elif fragment:
                        for at in range(0,len(wire),fragment):conn.sendall(wire[at:at+fragment])
                    else:conn.sendall(wire)
                    if not early:conn.shutdown(socket.SHUT_WR)
                    while True:
                        chunk=conn.recv(65536)
                        if not chunk:break
                        received+=chunk
                    if early:conn.shutdown(socket.SHUT_WR)
                except OSError as error:
                    peer_error=repr(error)
                    # Only an explicitly expected failed process may close/reset
                    # a peer before a complete HTTP response. Its exact exit,
                    # accepted outcome and resource/injection checks still apply.
                    if process_status==0 or status is not None:raise
            out,err=p.communicate(timeout=4);finished=True
            assert p.returncode==process_status,(p.returncode,process_status,out,err,received[:300])
            assert not out,out
            rows=reports(err)
            if process_status==0:assert endpoint is not None and len(rows)==1 and rows[0]['code']==0,(endpoint,rows)
            else:assert len(rows)<=1,rows
            if status is not None:parse(received,method,status,body,1 if expect else 0)
            elif rows and rows[0]['code']==4 and rows[0]['rejected'] and rows[0]['response'] and rows[0]['sent']==rows[0]['response'] and rows[0]['shutdown'] and rows[0]['eof']:
                parse(received,method,500,b'')
            COUNT+=1
            return received,err
        finally:
            if conn:conn.close()
            if p is not None and not finished:
                if p.poll() is None:intervention='killed live process after failed oracle check';p.kill()
                out,err=p.communicate(timeout=3)
            if p is not None:
                (directory/'native.stdout').write_bytes(p.application_startup+out)
                (directory/'native.stderr').write_bytes(err)
            (directory/'response.bin').write_bytes(received)
            (directory/'diagnostic.txt').write_text(repr(dict(error=repr(sys.exc_info()[1]),returncode=None if p is None else p.returncode,peer_error=peer_error,intervention=intervention,trace=None if trace is None else str(trace)))+'\n')
            if trace is not None:
                # Keep these beside the trace until the whole fault group has
                # also checked ownership, reached injection and baseline prefix.
                for name in ('request.bin','native.stdout','native.stderr','response.bin','diagnostic.txt','command.txt','startup.stdout','startup.diagnostic.txt'):
                    source=directory/name
                    if source.exists():Path(str(trace)+'.'+name).write_bytes(source.read_bytes())

def request(method=b'GET',target=b'/health',body=b'',extra=b'',version=b'1.1',chunked=False):
    head=method+b' '+target+b' HTTP/'+version+b'\r\nHost: local.example\r\n'+extra
    if chunked:
        encoded=b''
        for at in range(0,len(body),17):
            chunk=body[at:at+17];encoded+=hex(len(chunk))[2:].encode()+b';tag="q\\x"\r\n'+chunk+b'\r\n'
        return head+b'Transfer-Encoding: chunked\r\n\r\n'+encoded+b'0\r\nX-Result: yes\r\n\r\n'
    return head+b'Content-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body

def resources(path):
    live={};fds=set();calls=collections.Counter();allocations=0;events='\n'.join(re.sub(r'^\[[0-9a-fA-Fx]+\]\s+','',line) for line in open(path).read().splitlines() if line and not line.startswith(('---','+++')))+'\n'
    if events=='\n':events=''
    for line in events.splitlines():
        name=line.split('(',1)[0];calls[name]+=1
        result=line.rsplit(' = ',1)[-1].split()[0]
        if name=='mmap' and result.startswith('0x'):
            length=int(line.split(',')[1]);assert result not in live,events;live[result]=length;allocations+=1
        elif name=='munmap':
            address,length=line[7:].split(')',1)[0].split(',');assert result=='0' and live.pop(address,None)==int(length),events
        elif name in ('socket','accept4') and re.fullmatch(r'\d+',result):
            fd=int(result);assert fd not in fds,events;fds.add(fd)
        elif name=='close':
            fd=int(line[6:].split(')')[0]);assert fd in fds,events;fds.remove(fd)
            # Fault injection skips the kernel close. This ledger checks one
            # ownership-release attempt; physical release occurs at process exit.
            assert result=='0' or '(INJECTED)' in line,events
    assert not live and not fds,(live,fds,events)
    return allocations,calls,events

def matrix():
    binary=bytes(range(256))*3+b'\0\xff\r\n'
    vectors=[(request(),b'GET',200,b'ok\n'),(request(b'HEAD'),b'HEAD',200,b''),(request(b'POST',b'/echo',binary),b'POST',200,binary),(request(b'POST',b'/echo',binary,chunked=True),b'POST',200,binary),(request(b'OPTIONS',b'*'),b'OPTIONS',204,b''),(request(target=b'/absent'),b'GET',404,b''),(request(b'POST',b'/health'),b'POST',405,b''),(request(b'CONNECT',b'x:443'),b'CONNECT',501,b''),(request(target=b'http://other.example/health?q=x',extra=b'X: \x80\xff\r\n'),b'GET',200,b'ok\n'),(request(target=b'//health'),b'GET',404,b''),(request(target=b'https://other.example/health'),b'GET',421,b''),(request(version=b'1.0',extra=b'Expect: 100-continue\r\n'),b'GET',200,b'ok\n')]
    for family in (socket.AF_INET,socket.AF_INET6):
        for wire,method,status,body in vectors:exchange(wire,family=family,method=method,status=status,body=body,fragment=7)
    for fragment in (1,13):exchange(request(b'POST',b'/echo',binary,chunked=True),fragment=fragment,method=b'POST',body=binary)
    exchange(request(b'POST',b'/echo',binary,extra=b'Expect: 100-continue\r\n'),expect=True,method=b'POST',body=binary)
    exchange(b'POST /health HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: 9999\r\n\r\n',early=True,status=405,method=b'POST')
    exchange(request(extra=b'Upgrade: websocket\r\nConnection: Upgrade\r\n'),body=b'ok\n')
    exchange(request()+request(target=b'/absent'),body=b'ok\n')
    print('http-server-matrix cases=%d'%COUNT)

def limits():
    vectors=[(b'POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n',400,()),(b'GET /health HTTP/1.1\r\nHost: x\r\nHost: x\r\n\r\n',400,()),(b'GET /health HTTP/1.1\nHost: x\n\n',400,()),(request(b'POST',b'/echo',extra=b'Expect: unknown\r\n'),417,()),(request(b'POST',b'/echo',extra=b'Expect: 100-continue\r\nExpect: 100-continue\r\n'),417,()),(request(b'POST',b'/echo',b'ab'),413,('--max-body','1')),(request(),431,('--max-head','10')),(b'POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nab',400,()),(b'POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n1;\r\na\r\n0\r\n\r\n',400,()),(b'POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: X-Secret\r\n\r\n0\r\nX-Secret: x\r\n\r\n',400,())]
    for wire,status,args in vectors:exchange(wire,args,status=status)
    for args in (('--max-response','1'),('--max-work','0'),('--max-io','2'),('--timeout','0')):exchange(request(),args,status=None,process_status=3)
    exchange(b'',status=None)
    binary=bytes(range(256))*4096;exchange(request(b'POST',b'/echo',binary),('--timeout','3000'),method=b'POST',body=binary)
    print('http-server-limits-scale cases=%d'%COUNT)

def drain_boundary(cap,amount,expected):
    global COUNT
    p,endpoint=start(('--drain',cap));conn=socket.create_connection(endpoint,2);conn.settimeout(3);wire=b''
    try:
        conn.sendall(b'POST /health HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\nExpect: 100-continue\r\n\r\n')
        while True:
            part=conn.recv(4096)
            if not part:break
            wire+=part
        parse(wire,b'POST',405)
        conn.sendall(bytes(range(amount)));conn.shutdown(socket.SHUT_WR)
        out,err=p.communicate(timeout=3);assert p.returncode==expected and not out,(p.returncode,err)
        rows=reports(err);assert len(rows)==1 and rows[0]['drain']==amount and rows[0]['code']==expected,rows
        COUNT+=1
    finally:
        conn.close()
        if p.poll() is None:p.kill();p.communicate()

def line_limit_cases():
    wire=b'GET /'+b'a'*80+b' HTTP/1.1\r\nHost: x\r\n\r\n'
    for fragment in (0,1):exchange(wire,('--max-line','64'),fragment=fragment,status=414)
    exchange(request(extra=b'X-Large: '+b'a'*80+b'\r\n'),('--max-line','64'),status=431)
    exchange(wire,('--max-line','64','--max-head','32'),status=431)
    for fragment in (0,1):
        exchange(b'G'*80+b' / HTTP/1.1\r\nHost: x\r\n\r\n',('--max-line','64'),fragment=fragment,status=400)
        exchange(b'GET / HTTP/'+b'1'*80+b'\r\nHost: x\r\n\r\n',('--max-line','64'),fragment=fragment,status=400)

def line_limits():
    line_limit_cases();print('http-server-line-limits cases=%d'%COUNT)

def boundaries():
    global COUNT
    line_limit_cases()
    # No100 before an immediately known excessive fixed body.
    exchange(b'POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nExpect: 100-continue\r\n\r\n',('--max-body','1'),early=True,status=413,method=b'POST')
    for cap,amount,status in ((0,0,0),(17,17,0),(17,18,3)):drain_boundary(cap,amount,status)
    with retained('late-boundaries') as d:
        trace=os.path.join(d,'trace')
        for syscall,when,pattern in (('recvfrom',2,r'recvfrom\([^\n]* = 0[^\n]*DELAYED'),('sendto',1,r'sendto\([^\n]* = [1-9]\d*[^\n]*DELAYED'),('shutdown',1,r'shutdown\([^\n]* = 0[^\n]*DELAYED')):
            wire,err=exchange(request(),('--timeout','50'),status=None,process_status=3,trace=trace,fault='inject=%s:delay_exit=150ms:when=%d'%(syscall,when))
            _,_,events=resources(trace);assert re.search(pattern,events),events
            reached(trace,syscall,when,delayed=True)
            rows=reports(err);assert len(rows)==1 and rows[0]['code']==3,rows
            if syscall=='recvfrom':assert rows[0]['eof']==1,rows
            if syscall=='shutdown':assert rows[0]['shutdown']==1,rows
            # A successful send is recorded before its subsequent clock error.
            if syscall!='recvfrom' or b'HTTP/' in wire:
                match=re.search(rb'sent=(\d+) response=(\d+)',err);assert match and int(match[1])>0,err
    # Two requests use two accepted owners, never a persistent HTTP connection.
    p,endpoint=start(('--requests',2))
    try:
        for _ in range(2):
            conn=socket.create_connection(endpoint,2);conn.settimeout(3);conn.sendall(request());conn.shutdown(socket.SHUT_WR);wire=b''
            while True:
                part=conn.recv(4096)
                if not part:break
                wire+=part
            conn.close();parse(wire,b'GET',200,b'ok\n');COUNT+=1
        out,err=p.communicate(timeout=3);rows=reports(err);assert p.returncode==0 and not out and len(rows)==2 and all(row['code']==0 for row in rows),(p.returncode,err)
    finally:
        if p.poll() is None:p.kill();p.communicate()
    for args in ([],['localhost:80'],['127.0.0.1:0','--requests','0'],['127.0.0.1:0','--timeout','60001'],['127.0.0.1:0','--max-io','0'],['127.0.0.1:0','--drain','67108865'],['127.0.0.1:0','--max-work','-1'],['127.0.0.1:0','--unknown','1']):
        result=subprocess.run([EXE,*args],capture_output=True,timeout=2);assert result.returncode==2 and not result.stdout and not result.stderr,(args,result);COUNT+=1
    print('http-server-boundaries cases=%d'%COUNT)

def native():
    global COUNT
    with tempfile.TemporaryDirectory() as d:
        trace=os.path.join(d,'trace')
        post_close=0
        for mode in ('normal','send','post-close'):
            fault=None
            if mode=='send':fault='inject=sendto:error=EIO:when=3'
            if mode=='post-close':fault='inject=clock_gettime:error=EIO:when=%d'%post_close
            command=['strace','-qq','-o',trace,'-e','trace='+TRACE_SYSCALLS]
            if fault:command+=['-e',fault]
            result=subprocess.run([*command,EXE,*(['post-close'] if mode=='post-close' else [])],capture_output=True,timeout=4);assert result.returncode==0 and not result.stdout and not result.stderr,result
            _,_,events=resources(trace)
            if mode=='send':assert re.search(r'sendto\([^\n]* = -1 EIO[^\n]*INJECTED',events),events
            if mode=='post-close':assert re.search(r'close\([^\n]* = 0\nclock_gettime\([^\n]* = -1 EIO[^\n]*INJECTED',events),events
            if mode=='normal':post_close=events.split('close(',1)[0].count('clock_gettime(')+1
            # The exact fixture queues its request in two sends before accepting.
            before=events.split('accept4(',1)[0];assert before.count('sendto(')==2,events
            COUNT+=1
    print('http-server-native cases=%d'%COUNT)

def quota_case(trace):
    _,err=exchange(request(),('--max-io','12'),status=None,process_status=3,trace=trace,fault='inject=recvfrom:error=EINTR:when=1+')
    quota_trace(trace,err)

def quota_trace(trace,err):
    resources(trace)
    entries=observed(trace);accepted=[entry for entry in entries if entry['name']=='accept4' and entry['result'].split()[0].isdigit()]
    assert len(accepted)==1,entries
    fd=int(accepted[0]['result'].split()[0]);owner=[entry for entry in entries if entry['args'].startswith(str(fd)+', ')]
    attempts=[entry for entry in owner if entry['name'] in ('recvfrom','sendto','shutdown') or (entry['name']=='fcntl' and entry['args']==str(fd)+', F_GETFL')]
    reads=[entry for entry in entries if entry['name']=='recvfrom']
    assert len(attempts)==12 and len(reads)==11 and all(entry['result'].split()[:2]==['-1','EINTR'] and 'INJECTED' in entry['result'] for entry in reads),(attempts,reads)
    rows=reports(err);assert len(rows)==1 and rows[0]['io']==12 and rows[0]['received']==rows[0]['sent']==0 and rows[0]['code']==3,rows
    # The listener flag/accept and physical shared polls are service operations,
    # outside this per-owner quota. All-EINTR receive leaves immediate interest,
    # so this case charges no owner wait participation in place of a leaf call.
    assert not any(entry['name']=='poll' and re.search(r'fd='+str(fd)+r'\b',entry['args']) for entry in entries),entries

def quota():
    with retained('quota') as d:quota_case(os.path.join(d,'trace'))
    print('http-server-exact-quota cases=%d'%COUNT)

def faults():
    global COUNT
    with retained('faults') as d:
        trace=d/'baseline.trace';wire=request(b'POST',b'/echo',bytes(range(256))*24)
        exchange(wire,method=b'POST',body=bytes(range(256))*24,trace=trace);alloc,calls,_=resources(trace)
        baseline=[entry for entry in observed(trace) if entry['name']=='mmap'];assert len(baseline)==alloc and all(entry['ip'] is not None and entry['result'].startswith('0x') for entry in baseline),baseline
        for n in range(1,alloc+1):
            trace=d/('allocation-%d.trace'%n)
            exchange(wire,method=b'POST',status=None,process_status=4,trace=trace,fault='inject=mmap:error=ENOMEM:when=%d'%n);resources(trace)
            reached(trace,'mmap',n,'ENOMEM');seen=[entry for entry in observed(trace) if entry['name']=='mmap']
            assert len(seen)>=n,seen
            for index in range(n):
                assert seen[index]['ip']==baseline[index]['ip'] and seen[index]['args']==baseline[index]['args'],('allocation prefix drift',n,index,baseline[index],seen[index])
                if index+1<n:assert seen[index]['result'].startswith('0x'),seen[index]
        for syscall in ('accept4','fcntl','recvfrom','sendto','shutdown','clock_gettime'):
            assert calls[syscall]>0,(syscall,calls)
            trace=d/('fatal-'+syscall+'.trace');exchange(request(),status=None,process_status=3,trace=trace,fault='inject=%s:error=EIO:when=1'%syscall);resources(trace);reached(trace,syscall,1,'EIO')
        for syscall in ('accept4','recvfrom','sendto','shutdown'):
            trace=d/('retry-'+syscall+'.trace');exchange(request(),body=b'ok\n',trace=trace,fault='inject=%s:error=EINTR:when=1'%syscall);resources(trace);reached(trace,syscall,1,'EINTR')
        for n in (1,2):
            trace=d/('close-%d.trace'%n);exchange(request(),status=None,process_status=3,trace=trace,fault='inject=close:error=EIO:when=%d'%n);resources(trace);reached(trace,'close',n,'EIO')
        trace=d/'late-receive.trace'
        exchange(request(),('--timeout','50'),status=None,process_status=3,trace=trace,fault='inject=recvfrom:delay_exit=150ms:when=1');_,_,events=resources(trace);assert re.search(r'recvfrom\([^\n]* = [1-9]\d*[^\n]*DELAYED',events),events
        reached(trace,'recvfrom',1,delayed=True)
        quota_case(d/'quota.trace')
        # Closed stdout and /dev/full fail startup before accept, freeing args/listener.
        for which in ('pipe','full'):
            trace=d/('stdout-'+which+'.trace')
            if which=='pipe':r,w=os.pipe();os.close(r);output=os.fdopen(w,'wb')
            else:output=open('/dev/full','wb')
            try:
                p,_=start(trace=trace,stdout=output,artifacts=d);out,err=p.communicate(timeout=3)
                Path(str(trace)+'.native.stdout').write_bytes(out or b'');Path(str(trace)+'.native.stderr').write_bytes(err)
                assert p.returncode==5,(p.returncode,err)
            finally:output.close()
            resources(trace);COUNT+=1
        trace=d/'signal.trace';p,_=start(trace=trace,fault='inject=rt_sigaction:error=EINTR:when=1');out,err=p.communicate(timeout=3);assert p.returncode==5 and not out and not err;none,c,_=resources(trace);assert none==0 and not c['socket'];reached(trace,'rt_sigaction',1,'EINTR');COUNT+=1
    print('http-server-faults cases=%d source-allocation-positions=%d'%(COUNT,alloc))

def controls():
    count=0
    line=b'received=60 sent=100 response=100 interim=0 drain=0 tail=0 io=6 cleanup=1 cleanup-errors=0 work=444 scan=120 id=0 rejected=0 shutdown=1 eof=1 closed=1 code=0 failed=0\n'
    assert reports(line)[0]['id']==0;count+=1
    for malformed in (line.replace(b' id=0',b''),line.replace(b' eof=1',b' eof=2'),line.replace(b' failed=0',b' failed=1'),line.replace(b' id=0',b' id=1'),line.replace(b' id=0',b' id=0 id=0'),line.replace(b' sent=100',b' sent=101'),line.rstrip(b'\n')):
        try:reports(malformed)
        except AssertionError:count+=1
        else:raise AssertionError(('report mutation accepted',malformed))
    parse(b'HTTP/1.1 200 OK\r\nDate: Thu, 01 Jan 1970 00:00:00 GMT\r\nConnection: close\r\nContent-Length: 2\r\n\r\n\0\xff',b'POST',200,b'\0\xff');count+=1
    assert b'Transfer-Encoding: chunked' in request(b'POST',b'/echo',b'\0\xff',chunked=True);count+=1
    with tempfile.TemporaryDirectory(prefix='http_app_cpu_controls_') as directory:
        path=Path(directory)/'trace'
        def event(text):return '[0000000000401000] '+text+'\n'
        prefix=event('socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 3')+event('fcntl(3, F_GETFL) = 0x802')+event('accept4(3, NULL, NULL, SOCK_NONBLOCK) = 4')+event('fcntl(4, F_GETFL) = 0x802')
        reads=''.join(event('recvfrom(4, 0x41000000, 1024, 0, NULL, NULL) = -1 EINTR (Interrupted system call) (INJECTED)') for _ in range(11))
        suffix=event('close(4) = 0')+event('close(3) = 0')
        trace=prefix+reads+suffix
        failed=line.replace(b'received=60',b'received=0').replace(b'sent=100',b'sent=0').replace(b'response=100',b'response=0').replace(b'io=6',b'io=12').replace(b'shutdown=1',b'shutdown=0').replace(b'eof=1',b'eof=0').replace(b'code=0 failed=0',b'code=3 failed=1')
        path.write_text(trace);quota_trace(path,failed);count+=1
        mutations=[(trace.replace(event('fcntl(4, F_GETFL) = 0x802'),''),failed),
                   (trace,failed.replace(b'io=12',b'io=14')),
                   (trace.replace('recvfrom(4,','recvfrom(3,'),failed)]
        for changed,diagnostic in mutations:
            path.write_text(changed)
            try:quota_trace(path,diagnostic)
            except AssertionError:count+=1
            else:raise AssertionError('quota mutation accepted')
        path.write_text(event('mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory) (INJECTED)'))
        assert reached(path,'mmap',1,'ENOMEM')['ip']==0x401000;count+=1
        try:reached(path,'mmap',1,'EIO')
        except AssertionError:count+=1
        else:raise AssertionError('wrong injection errno accepted')
    print('http-server-app CPU-controls=%d native-cases=0'%count)

if __name__=='__main__':
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls()
    else:
        assert len(sys.argv)==3,'usage: http_server_oracle.py MODE EXE, or controls'
        MODE,EXE=sys.argv[1:]
        {'matrix':matrix,'limits':limits,'boundaries':boundaries,'native':native,'faults':faults,'quota':quota,'line-limits':line_limits}[MODE]()
