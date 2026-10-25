"""Independent loopback HTTP clients; all service/protocol behavior is Lanius."""
import collections,email.utils,os,re,select,socket,subprocess,sys,tempfile,time
import h11
MODE,EXE=sys.argv[1:3]
COUNT=0
TRACE_SYSCALLS='socket,accept4,fcntl,close,mmap,munmap,recvfrom,sendto,poll,shutdown,clock_gettime,rt_sigaction,write'

def start(args=(),family=socket.AF_INET,trace=None,fault=None,stdout=None):
    address='127.0.0.1:0' if family==socket.AF_INET else '[::1]:0'
    command=[EXE,address,'--timeout','1000','--report',*map(str,args)]
    if trace:command=['strace','-qq','-o',trace,'-e','trace='+TRACE_SYSCALLS,*[p for f in (fault if isinstance(fault,list) else [fault]) if f for p in ['-e',f]],*command]
    p=subprocess.Popen(command,stdout=subprocess.PIPE if stdout is None else stdout,stderr=subprocess.PIPE)
    endpoint=None
    if stdout is None:
        assert select.select([p.stdout],[],[],3)[0],'startup timeout'
        line=p.stdout.readline()
        if line:
            value=line.decode().strip()
            if value.startswith('['):host,port=value[1:].split(']:')
            else:host,port=value.rsplit(':',1)
            endpoint=(host,int(port))
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
    p,endpoint=start(args,family,trace,fault);conn=None;received=b''
    try:
        if endpoint:
            try:
                conn=socket.create_connection(endpoint,2);conn.settimeout(3)
                if expect:
                    head,content=wire.split(b'\r\n\r\n',1);conn.sendall(head+b'\r\n\r\n')
                    while b'\r\n\r\n' not in received:received+=conn.recv(1024)
                    assert received==b'HTTP/1.1 100 Continue\r\n\r\n',received
                    conn.sendall(content)
                elif fragment:
                    for at in range(0,len(wire),fragment):conn.sendall(wire[at:at+fragment])
                else:conn.sendall(wire)
                if not early:conn.shutdown(socket.SHUT_WR)
                while True:
                    chunk=conn.recv(65536)
                    if not chunk:break
                    received+=chunk
                if early:conn.shutdown(socket.SHUT_WR)
            except (OSError,TimeoutError):
                if process_status==0:raise
        out,err=p.communicate(timeout=4)
        assert p.returncode==process_status,(p.returncode,process_status,out,err,received[:300])
        assert not out,out
        if process_status==0:assert err.endswith(b'failed=0\n'),err
        if status is not None:parse(received,method,status,body,1 if expect else 0)
        COUNT+=1
        return received,err
    finally:
        if conn:conn.close()
        if p.poll() is None:p.kill();p.communicate()

def request(method=b'GET',target=b'/health',body=b'',extra=b'',version=b'1.1',chunked=False):
    head=method+b' '+target+b' HTTP/'+version+b'\r\nHost: local.example\r\n'+extra
    if chunked:
        encoded=b''
        for at in range(0,len(body),17):
            chunk=body[at:at+17];encoded+=hex(len(chunk))[2:].encode()+b';tag="q\\x"\r\n'+chunk+b'\r\n'
        return head+b'Transfer-Encoding: chunked\r\n\r\n'+encoded+b'0\r\nX-Result: yes\r\n\r\n'
    return head+b'Content-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body

def resources(path):
    live={};fds=set();calls=collections.Counter();allocations=0;events=open(path).read()
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
        assert b'drain='+str(amount).encode()+b' ' in err,err
        assert err.endswith(b'failed='+str(int(expected!=0)).encode()+b'\n'),err
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
    with tempfile.TemporaryDirectory() as d:
        trace=os.path.join(d,'trace')
        for syscall,when,pattern in (('recvfrom',2,r'recvfrom\([^\n]* = 0[^\n]*DELAYED'),('sendto',1,r'sendto\([^\n]* = [1-9]\d*[^\n]*DELAYED'),('shutdown',1,r'shutdown\([^\n]* = 0[^\n]*DELAYED')):
            wire,err=exchange(request(),('--timeout','50'),status=None,process_status=3,trace=trace,fault='inject=%s:delay_exit=150ms:when=%d'%(syscall,when))
            _,_,events=resources(trace);assert re.search(pattern,events),events
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
        out,err=p.communicate(timeout=3);assert p.returncode==0 and not out and err.count(b'failed=0\n')==2,(p.returncode,err)
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
    _,err=exchange(request(),('--max-io','12'),status=None,process_status=3,trace=trace,fault='inject=recvfrom:error=EINTR:when=1+');_,c,events=resources(trace);assert c['recvfrom']>1
    actual=sum(c[name] for name in ('fcntl','accept4','recvfrom','sendto','poll','shutdown'));assert actual==12 and b' io=12 ' in err,(actual,err,events)

def quota():
    with tempfile.TemporaryDirectory() as d:quota_case(os.path.join(d,'trace'))
    print('http-server-exact-quota cases=%d'%COUNT)

def faults():
    global COUNT
    with tempfile.TemporaryDirectory() as d:
        trace=os.path.join(d,'trace');wire=request(b'POST',b'/echo',bytes(range(256))*24)
        exchange(wire,method=b'POST',body=bytes(range(256))*24,trace=trace);alloc,calls,_=resources(trace)
        for n in range(1,alloc+1):exchange(wire,method=b'POST',status=None,process_status=4,trace=trace,fault='inject=mmap:error=ENOMEM:when=%d'%n);resources(trace)
        for syscall in ('accept4','fcntl','recvfrom','sendto','shutdown','clock_gettime'):
            if calls[syscall]:exchange(request(),status=None,process_status=3,trace=trace,fault='inject=%s:error=EIO:when=1'%syscall);resources(trace)
        for syscall in ('accept4','recvfrom','sendto','shutdown'):
            exchange(request(),body=b'ok\n',trace=trace,fault='inject=%s:error=EINTR:when=1'%syscall);resources(trace)
        for n in (1,2):exchange(request(),status=None,process_status=3,trace=trace,fault='inject=close:error=EIO:when=%d'%n);resources(trace)
        exchange(request(),('--timeout','50'),status=None,process_status=3,trace=trace,fault='inject=recvfrom:delay_exit=150ms:when=1');_,_,events=resources(trace);assert re.search(r'recvfrom\([^\n]* = [1-9]\d*[^\n]*DELAYED',events),events
        quota_case(trace)
        # Closed stdout and /dev/full fail startup before accept, freeing args/listener.
        for which in ('pipe','full'):
            if which=='pipe':r,w=os.pipe();os.close(r);output=os.fdopen(w,'wb')
            else:output=open('/dev/full','wb')
            try:p,_=start(trace=trace,stdout=output);out,err=p.communicate(timeout=3);assert p.returncode==5,(p.returncode,err)
            finally:output.close()
            resources(trace);COUNT+=1
        p,_=start(trace=trace,fault='inject=rt_sigaction:error=EINTR:when=1');out,err=p.communicate(timeout=3);assert p.returncode==5 and not out and not err;alloc,c,_=resources(trace);assert alloc==0 and not c['socket'];COUNT+=1
    print('http-server-faults cases=%d'%COUNT)

{'matrix':matrix,'limits':limits,'boundaries':boundaries,'native':native,'faults':faults,'quota':quota,'line-limits':line_limits}[MODE]()
