"""Independent loopback HTTP client execution and fault oracle (test only)."""
import http.client
import io
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import h11
EXE=sys.argv[2]
COUNT=0
BINARY=bytes(range(256))*3+b'\0\xff\r\n'

def check(out,status):
    assert out.returncode==status,(out.returncode,status,out.stdout,out.stderr)
    if status:assert not out.stdout,out.stdout
    else:assert not out.stderr,out.stderr

def request(conn,head_only=False):
    parser=h11.Connection(h11.SERVER);body=b'';head=None
    while True:
        event=parser.next_event()
        if event is h11.NEED_DATA:
            data=conn.recv(4096)
            if not data:raise EOFError('incomplete request')
            parser.receive_data(data);continue
        if isinstance(event,h11.Request):
            head=event
            assert event.http_version==b'1.1' and event.target.startswith((b'/',b'*'))
            headers=list(event.headers);assert [v for k,v in headers if k==b'host']==[b'virtual.example:8080'],headers
            assert [v for k,v in headers if k==b'connection']==[b'close'],headers
            assert len([v for k,v in headers if k==b'content-length'])==1
            if head_only:return head,body
        if isinstance(event,h11.Data):body+=event.data
        if isinstance(event,h11.EndOfMessage):return head,body

def fixed(body=BINARY,status=200,version=b'HTTP/1.1'):
    return version+b' '+str(status).encode()+b' Result\r\nContent-Length: '+str(len(body)).encode()+b'\r\nX-Raw: \x80\xff\r\n\r\n'+body

def chunked(body=BINARY):
    wire=b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n'
    at=0
    while at<len(body):
        count=min(17,len(body)-at);wire+=('%x;tag="a\\b"\r\n'%count).encode()+body[at:at+count]+b'\r\n';at+=count
    return wire+b'0;done=yes\r\nX-Meta: custom\r\n\r\n'

def send(conn,wire,fragment=0):
    if not fragment:conn.sendall(wire)
    else:
        for at in range(0,len(wire),fragment):conn.sendall(wire[at:at+fragment])

def case(handler,args=(),status=0,data=None,name='/path?q=x',family=socket.AF_INET,trace=None,fault=None,output=None):
    global COUNT
    server=socket.socket(family,socket.SOCK_STREAM);server.bind(('127.0.0.1',0) if family==socket.AF_INET else ('::1',0));server.listen();server.settimeout(.3)
    stop=threading.Event();errors=[];seen=[]
    def worker():
        conn=None
        try:
            # Traced stdin staging can precede connect by more than one accept
            # window. Keep accepting until the process ends; preflight errors
            # still stop promptly instead of stranding an unaccepted backlog.
            while conn is None and not stop.is_set():
                try:conn,_=server.accept()
                except TimeoutError:pass
            if conn is None:return
            conn.settimeout(.7);handler(conn,stop,seen)
        except (TimeoutError,ConnectionError,BrokenPipeError,EOFError):
            if status==0 and not stop.is_set():errors.append(sys.exc_info()[1])
        except BaseException as e:errors.append(e)
        finally:
            if conn:conn.close()
    thread=threading.Thread(target=worker);thread.start()
    address=('127.0.0.1:%d' if family==socket.AF_INET else '[::1]:%d')%server.getsockname()[1]
    command=[EXE,address,'virtual.example:8080',name,'--timeout','1500',*args]
    if sys.argv[1]=='native':command=[EXE,address]
    if trace:
        command=['strace','-qq','-o',trace,'-e','trace=mmap,munmap,socket,close,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write,open,openat,rt_sigaction',*[part for item in (fault if isinstance(fault,list) else [fault]) if item for part in ['-e',item]],*command]
    start=time.monotonic()
    if output is None:out=subprocess.run(command,input=data,capture_output=True,timeout=5)
    else:out=subprocess.run(command,input=data,stdout=output,stderr=subprocess.PIPE,timeout=5)
    elapsed=time.monotonic()-start;stop.set();thread.join(1.5);server.close();assert not thread.is_alive();assert not errors,(errors,out,elapsed);check(out,status);COUNT+=1
    return out,seen,elapsed

def ordinary(wire,body=None,fragment=0,close=False,method=None,request_body=None):
    def peer(conn,stop,seen):
        head,got=request(conn)
        if method is not None:assert head.method==method,(head.method,method)
        if request_body is not None:assert got==request_body,(len(got),len(request_body))
        seen.append((head,got));send(conn,wire,fragment)
        if not close:stop.wait(1)
    return peer

def oracle_body(wire,method='GET'):
    class Sock:
        def makefile(self,*args):return io.BytesIO(wire)
    response=http.client.HTTPResponse(Sock(),method=method);response.begin();return response.read()

def matrix():
    vectors=[(fixed(),BINARY,False),(chunked(),BINARY,False),(b'HTTP/1.1 200 OK\r\nX: y\r\n\r\n'+BINARY,BINARY,True),(b'HTTP/1.1 204 No Content\r\nX: y\r\n\r\n',b'',False),(fixed(BINARY,404),BINARY,False),(fixed(BINARY,200,b'HTTP/1.0'),BINARY,False)]
    for family in (socket.AF_INET,socket.AF_INET6):
        for wire,body,close in vectors:
            assert oracle_body(wire)==body
            for fragment in (0,1,7):
                out,_,_=case(ordinary(wire,fragment=fragment,close=close),family=family);assert out.stdout==body
    for method,status in (('HEAD',200),('GET',304),('GET',204)):
        wire=b'HTTP/1.1 '+str(status).encode()+b' Result\r\nX: y\r\n'
        if status!=204:wire+=b'Content-Length: 999\r\n'
        wire+=b'\r\n';out,_,_=case(ordinary(wire,method=method.encode()),['--method',method]);assert not out.stdout
    interim=b'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </x>\r\n\r\n'
    out,_,_=case(ordinary(interim+chunked(),fragment=1));assert out.stdout==BINARY
    out,_,_=case(ordinary(fixed()+b'UNSOLICITED SECOND RESPONSE'),['--raw']);assert out.stdout==fixed()
    out,seen,_=case(ordinary(fixed(),request_body=BINARY,method=b'POST'),['--method','POST','--body','-','--header','X-Custom:opaque','--header','X-Custom:duplicate'],data=BINARY);assert out.stdout==BINARY
    assert [v for k,v in seen[0][0].headers if k==b'x-custom']==[b'opaque',b'duplicate']
    case(ordinary(fixed(),method=b'OPTIONS'),['--method','OPTIONS'],name='*')
    works=[]
    for fragment in (0,1,7):
        out,_,_=case(ordinary(chunked(),fragment=fragment),['--report']);assert b'framing=2' in out.stdout and b'trailers=1' in out.stdout;works.append(re.search(rb'work=(\d+)',out.stdout)[1])
    assert len(set(works))==1,works
    large=bytes((i*29+7)&255 for i in range(1024*1024));out,_,elapsed=case(ordinary(fixed(large)));assert out.stdout==large
    print('large-response bytes=%d process-seconds=%.6f'%(len(large),elapsed))
    print('http-client-matrix cases=%d'%COUNT)

def early(conn,stop,seen):
    conn.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4096);head,_=request(conn,True)
    assert head.method==b'POST'
    conn.sendall(b'HTTP/1.1 413 Payload Too Large\r\nContent-Length: 4\r\n\r\n')
    received=0
    while True:
        part=conn.recv(4096)
        if not part:break
        received+=len(part)
    assert received<4*1024*1024,received
    seen.append(received);conn.sendall(b'stop');stop.wait(1)

def limits():
    for suffix in (b'',b'x'):
        wire=b'HTTP/1.1 200 OK\r\n\r\nabc'+suffix
        cap=len(wire)-len(suffix)
        out,_,_=case(ordinary(wire,close=True),['--max-response',str(cap)],status=0 if not suffix else 3)
        if not suffix:assert out.stdout==b'abc'
        else:assert ('received=%d'%(cap+1)).encode() in out.stderr,out.stderr
    for suffix in (b'',b'x'):
        wire=b'HTTP/1.1 200 OK\r\n\r\nabc'+suffix
        out,_,_=case(ordinary(wire,close=True),['--max-body','3'],status=0 if not suffix else 3)
        if not suffix:assert out.stdout==b'abc'
    wire=fixed(b'abc')
    out,_,_=case(ordinary(wire),['--max-response',str(len(wire))]);assert out.stdout==b'abc'
    case(ordinary(wire),['--max-response',str(len(wire)-1)],status=3)
    for extra in (['--max-body','2'],['--max-output','2'],['--max-head','10'],['--max-line','10'],['--max-io','1'],['--max-work','0'],['--max-headers','2'],['--timeout','0']):
        case(ordinary(wire),extra,status=3)
    interim=b'HTTP/1.1 103 Hints\r\n\r\n'
    case(ordinary(interim+fixed()),['--max-interims','0'],status=3)
    case(ordinary(interim*2+fixed()),['--max-interim-bytes',str(len(interim))],status=3)
    case(ordinary(interim+fixed()),['--max-interim-bytes',str(len(interim))])
    case(ordinary(chunked()),['--max-chunks','1'],status=3)
    case(ordinary(chunked()),['--max-trailers','0'],status=3)
    case(ordinary(chunked()),['--max-trailer-bytes','1'],status=3)
    # Peer won't send the final body until it sees our checked write half-close.
    out,seen,_=case(early,['--method','POST','--body','-','--report'],data=b'x'*(4*1024*1024));assert seen and b'stopped=1 shutdown=1' in out.stdout,out
    print('http-client-limits-early-final cases=%d'%COUNT)

def failures():
    wires=[b'',b'H',b'HTTP/1.1 200 OK\r\n',b'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\na',b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na',b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na',b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n',b'HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n',b'HTTP/1.1 200 OK\n\n',b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 1\r\n\r\n',b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: x\r\n\r\n',b'HTTP/1.1 100 Continue\r\n\r\n']
    for wire in wires:case(ordinary(wire,close=True),status=3)
    global COUNT
    bad=[['--method','CONNECT'],['--method','BAD METHOD'],['--header','Host:other'],['--header','Content-Length:0'],['--header','Transfer-Encoding:chunked'],['--header','Connection:keep-alive'],['--header','Expect:100-continue'],['--header','Upgrade:h2c'],['--header','Proxy-Authorization:x'],['--header','TE:trailers'],['--header','X:bad\r\nInjected:yes'],['--max-request','1']]
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/preflight.trace'
        for args in bad:
            out=subprocess.run(['strace','-qq','-o',trace,'-e','trace=mmap,munmap,socket,connect,close',EXE,'127.0.0.1:9','virtual.example:8080','/',*args],capture_output=True,timeout=2)
            check(out,3);resources(trace);assert 'socket(' not in open(trace).read() and 'connect(' not in open(trace).read();COUNT+=1
        for authority,target,args,data in [('bad\r\nInjected:yes','/',[],None),('virtual.example','/bad\r\nInjected:yes',[],None),('virtual.example','http://other.example/',[],None),('virtual.example','/',['--method','TRACE','--body','-'],b'x')]:
            out=subprocess.run(['strace','-qq','-o',trace,'-e','trace=mmap,munmap,socket,connect,close',EXE,'127.0.0.1:9',authority,target,*args],input=data,capture_output=True,timeout=2)
            check(out,3);resources(trace);assert 'socket(' not in open(trace).read() and 'connect(' not in open(trace).read();COUNT+=1
    for args in ([],['127.0.0.1:9','x'],['hostname:80','x','/'],['127.0.0.1:9','x','/','--unknown'],['127.0.0.1:9','x','/','--timeout','60001'],['127.0.0.1:9','x','/','--header',':x']):
        out=subprocess.run([EXE,*args],capture_output=True,timeout=2);check(out,2);COUNT+=1
    print('http-client-failures cases=%d'%COUNT)

def resources(trace):
    live={};fds=set();alloc=0;calls={}
    for line in open(trace):
        call=line.split('(',1)[0];calls[call]=calls.get(call,0)+1
        if line.startswith('mmap('):
            result=line.rsplit(' = ',1)[-1].split()[0]
            if result.startswith('0x'):assert result not in live;live[result]=int(line.split(',',2)[1]);alloc+=1
        elif line.startswith('munmap('):
            address=line.split('(',1)[1].split(',',1)[0];length=int(line.split(',',1)[1].split(')',1)[0]);assert line.rstrip().endswith(' = 0') and live.get(address)==length,(line,live);del live[address]
        elif line.startswith(('socket(','open(','openat(')):
            result=int(line.rsplit(' = ',1)[-1].split()[0])
            if result>=0:assert result not in fds;fds.add(result)
        elif line.startswith('close('):
            fd=int(line.split('(',1)[1].split(')',1)[0]);assert fd in fds,(line,fds);fds.remove(fd)
    assert not live and not fds,(live,fds,open(trace).read())
    return alloc,calls

def faults():
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/trace'
        interim=b'HTTP/1.1 103 Hints\r\n\r\n'
        for wire,args in ((fixed(),()),(interim+chunked(),('--report',))):
            case(ordinary(wire),args,trace=trace);alloc,calls=resources(trace);print('allocation-positions mode=%s count=%d'%(' '.join(args),alloc))
            for index in range(1,alloc+1):case(ordinary(wire),args,status=4,trace=trace,fault='inject=mmap:error=ENOMEM:when=%d'%index);resources(trace)
            for syscall in ('socket','connect','poll','getsockopt','getpeername','sendto','recvfrom','close'):
                if calls.get(syscall):case(ordinary(wire),args,status=3,trace=trace,fault='inject=%s:error=EIO:when=1'%syscall);resources(trace)
            for syscall in ('sendto','recvfrom','poll'):
                if calls.get(syscall):case(ordinary(wire),args,trace=trace,fault='inject=%s:error=EINTR:when=1'%syscall);resources(trace)
        # Every active leaf, including repeated interruptions, consumes quota.
        leaves=('socket','connect','poll','getsockopt','getpeername','sendto','recvfrom','shutdown')
        out,_,_=case(ordinary(fixed()),['--report'],trace=trace);_,calls=resources(trace)
        assert int(re.search(rb'io=(\d+)',out.stdout)[1])==sum(calls.get(k,0) for k in leaves),(out,calls)
        for syscall in ('poll','recvfrom'):
            out,_,_=case(ordinary(fixed()),['--max-io','15'],status=3,trace=trace,fault='inject=%s:error=EINTR:when=1+'%syscall);_,calls=resources(trace)
            assert b'io-limit' in out.stderr and b'io=15' in out.stderr and calls.get(syscall,0)>1,out
            assert sum(calls.get(k,0) for k in leaves)==15,calls
        out,_,_=case(ordinary(fixed()),['--timeout','100'],status=3,trace=trace,fault='inject=recvfrom:error=EINTR:when=1+');_,calls=resources(trace);assert b'timeout stage=receive' in out.stderr and calls.get('recvfrom',0)>1,(out,calls)
        malformed=b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx'
        out,_,_=case(ordinary(malformed),status=3,trace=trace,fault='inject=close:error=EIO:when=1');resources(trace);assert b'malformed' in out.stderr and b'cleanup-error' in out.stderr,out
        # A positive final receive is deliberately delayed beyond the deadline.
        for wire,close in ((fixed(),False),(b'HTTP/1.1 200 OK\r\n\r\nabc',True)):
            out,_,_=case(ordinary(wire,close=close),['--timeout','50'],status=3,trace=trace,fault=['inject=sendto:delay_exit=20ms:when=1','inject=recvfrom:delay_enter=150ms:when=2']);resources(trace);assert b'timeout stage=receive' in out.stderr,out
            received=[line for line in open(trace) if line.startswith('recvfrom(')];assert len(received)==2 and int(received[-1].rsplit(' = ',1)[1].split()[0])>0,received
        # Force header/data read before delaying the successful EOF probe.
        close=b'HTTP/1.1 200 OK\r\n\r\nabc'
        out,_,_=case(ordinary(close,close=True),['--timeout','80','--max-response',str(len(close))],status=3,trace=trace,fault=['inject=sendto:delay_exit=20ms:when=1','inject=recvfrom:delay_enter=150ms:when=3']);resources(trace);assert b'timeout' in out.stderr
        received=[line for line in open(trace) if line.startswith('recvfrom(')];assert len(received)==3 and received[-1].rsplit(' = ',1)[1].split()[0]=='0',received
        case(ordinary(close,close=True),['--max-response',str(len(close))],status=3,trace=trace,fault=['inject=sendto:delay_exit=20ms:when=1','inject=recvfrom:error=EIO:when=3']);resources(trace)
        case(ordinary(fixed()),['--timeout','100'],status=3,trace=trace,fault='inject=close:delay_exit=150ms:when=1');resources(trace)
        out,_,_=case(early,['--method','POST','--body','-'],data=b'x'*(4*1024*1024),status=3,trace=trace,fault='inject=shutdown:error=EIO:when=1');resources(trace);assert b'socket stage=shutdown' in out.stderr,out
        out,_,_=case(early,['--method','POST','--body','-','--timeout','1500'],data=b'x'*(4*1024*1024),status=3,trace=trace,fault='inject=shutdown:delay_exit=1700ms:when=1');resources(trace);assert b'timeout stage=shutdown' in out.stderr and b'shutdown=1' in out.stderr,out
        stopped=[line for line in open(trace) if line.startswith('shutdown(')];assert len(stopped)==1 and ' = 0' in stopped[0],stopped
        # Fixed scheduling control makes the final clock observation the same
        # publication leaf in both runs; failures occur after socket closure.
        case(ordinary(fixed()),trace=trace,fault='inject=sendto:delay_exit=20ms:when=1');_,calls=resources(trace)
        out,_,_=case(ordinary(fixed()),status=3,trace=trace,fault=['inject=sendto:delay_exit=20ms:when=1','inject=clock_gettime:error=EIO:when=%d'%calls['clock_gettime']]);resources(trace);assert b'clock stage=publish' in out.stderr,out
    print('http-client-faults cases=%d'%COUNT)

def io_faults():
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/trace';wire=fixed()
        case(ordinary(wire),status=5,trace=trace,fault='inject=write:error=EIO:when=1');resources(trace)
        case(ordinary(wire),trace=trace,fault='inject=write:error=EINTR:when=1');resources(trace)
        out,_,_=case(ordinary(wire),trace=trace,fault='inject=write:retval=7:when=1');resources(trace);assert out.stdout==BINARY[7:]
        with open('/dev/full','wb') as sink:case(ordinary(wire),status=5,trace=trace,output=sink)
        resources(trace)
        read_end,write_end=os.pipe();os.close(read_end)
        try:case(ordinary(wire),status=5,trace=trace,output=write_end)
        finally:os.close(write_end)
        resources(trace);assert 'EPIPE' in open(trace).read() and 'SIG_IGN' in open(trace).read()
        for syscall,error,status in (('read','EIO',5),('read','EINTR',0),('rt_sigaction','EPERM',5)):
            case(ordinary(wire,request_body=BINARY),['--method','POST','--body','-'],data=BINARY,status=status,trace=trace,fault='inject=%s:error=%s:when=1'%(syscall,error));alloc,calls=resources(trace)
            if syscall=='rt_sigaction':assert not alloc and not calls.get('socket')
        path=directory+'/body';open(path,'wb').write(BINARY)
        for syscall in ('open','read','close'):
            case(ordinary(wire),['--body',path],status=5,trace=trace,fault='inject=%s:error=EIO:when=1'%syscall);resources(trace)
        read_end,write_end=os.pipe();os.close(read_end)
        try:
            out=subprocess.run(['strace','-qq','-o',trace,'-e','trace=mmap,munmap,write,rt_sigaction',EXE,'127.0.0.1:9','x','/','--max-request','0'],stdout=subprocess.PIPE,stderr=write_end,timeout=2);assert out.returncode==5 and not out.stdout,out
        finally:os.close(write_end)
        resources(trace);assert 'EPIPE' in open(trace).read()
    print('http-client-io cases=%d'%(COUNT+1))

def native():
    def peer(conn,stop,seen):
        head,body=request(conn);assert head.method==b'POST' and head.target==b'/native?q=x' and body==b'\0\xff\r\n'
        send(conn,b'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: x\r\n\r\n'+chunked(body),1);stop.wait(1)
    case(peer);print('http-client-native cases=1')

if __name__=='__main__':{'native':native,'matrix':matrix,'limits':limits,'failures':failures,'faults':faults,'io':io_faults}[sys.argv[1]]()
