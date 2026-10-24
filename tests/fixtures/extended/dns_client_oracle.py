"""Independent loopback DNS transport oracle; test-only dnspython 2.7.0."""
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import dns.message
import dns.name
import dns.rrset
import dns.rdatatype
assert dns.__version__ == "2.7.0", dns.__version__
EXE = sys.argv[2]
COUNT = 0

def check(out, status):
    assert out.returncode == status, (out.returncode, status, out.stdout, out.stderr)
    if status: assert not out.stdout, out.stdout
    else: assert not out.stderr, out.stderr

def response(query, *, tc=False, rcode=0, size=0):
    parsed = dns.message.from_wire(query)
    assert len(parsed.question) == 1 and parsed.opcode() == 0
    result = dns.message.make_response(parsed)
    result.set_rcode(rcode)
    if tc: result.flags |= 512
    if not tc and not rcode:
        if size:
            result.answer.append(dns.rrset.from_text(parsed.question[0].name, 17, 'IN', 'TYPE65000', '\\# %d %s' % (size, bytes((i * 29 + 7) & 255 for i in range(size)).hex())))
        else: result.answer.append(dns.rrset.from_text(parsed.question[0].name, 17, 'IN', 'A', '192.0.2.17'))
    return result.to_wire(max_size=65535)

def exact(conn, count):
    result = b''
    while len(result) < count:
        part = conn.recv(count-len(result))
        if not part: raise EOFError((count,len(result)))
        result += part
    return result

def tcp_query(server):
    conn, _ = server.accept(); conn.settimeout(1.5)
    query = exact(conn, int.from_bytes(exact(conn,2),'big'))
    dns.message.from_wire(query)
    return conn,query

def frame(conn, wire, fragment=False):
    wire = len(wire).to_bytes(2,'big') + wire
    if fragment:
        for byte in wire: conn.sendall(bytes([byte]))
    else: conn.sendall(wire)

def case(handler, args=(), status=0, data=None, family=socket.AF_INET, trace=None, fault=None, name='example.com', output=None):
    global COUNT
    host = '127.0.0.1' if family == socket.AF_INET else '::1'
    for _ in range(8):
        tcp = socket.socket(family,socket.SOCK_STREAM);tcp.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);tcp.bind((host,0))
        port=tcp.getsockname()[1];udp=socket.socket(family,socket.SOCK_DGRAM)
        try:udp.bind((host,port));break
        except OSError:udp.close();tcp.close()
    else:raise AssertionError('cannot reserve a loopback UDP/TCP port pair')
    tcp.listen();tcp.settimeout(.25);udp.settimeout(.25)
    stop = threading.Event(); errors=[]; expected=[]
    def worker():
        try: handler(udp,tcp,stop,expected)
        except (TimeoutError,ConnectionResetError,BrokenPipeError,EOFError):
            if status == 0 and not stop.is_set(): errors.append(sys.exc_info()[1])
        except BaseException as error: errors.append(error)
    thread = threading.Thread(target=worker);thread.start()
    endpoint = ('127.0.0.1:%d' if family == socket.AF_INET else '[::1]:%d') % port
    command=[EXE,endpoint,name,'--timeout','1500',*args]
    if sys.argv[1] == 'native': command=[EXE,endpoint]
    if trace:
        command=['strace','-qq','-o',trace,'-e','trace=mmap,munmap,socket,close,connect,sendto,recvfrom,poll,getrandom,clock_gettime,read,write,rt_sigaction',*[part for item in (fault if isinstance(fault,list) else [fault]) if item for part in ['-e',item]],*command]
    started=time.monotonic()
    if output is None: out=subprocess.run(command,input=data,capture_output=True,timeout=4)
    else: out=subprocess.run(command,input=data,stdout=output,stderr=subprocess.PIPE,timeout=4)
    elapsed=time.monotonic()-started
    stop.set();thread.join(2);udp.close();tcp.close();assert not thread.is_alive();assert not errors,errors
    check(out,status)
    if expected and status == 0 and "--raw" in args and not (fault and 'inject=write:retval=' in str(fault)):
        assert out.stdout == expected[0], (len(out.stdout),len(expected[0]),out.stdout[:200],expected[0][:200])
        dns.message.from_wire(out.stdout)
    COUNT += 1
    return out,elapsed

def udp_ok(udp,tcp,stop,expected):
    query,peer=udp.recvfrom(65535);parsed=dns.message.from_wire(query)
    assert parsed.payload == 1232
    wire=response(query);expected.append(wire);udp.sendto(wire,peer)

def tcp_ok(udp,tcp,stop,expected):
    conn,query=tcp_query(tcp);wire=response(query);expected.append(wire);frame(conn,wire,True)
    # A complete framed DNS response is sufficient: do not wait for EOF.
    stop.wait(1);conn.close()

def fallback(udp,tcp,stop,expected,local=False,partial=False):
    query,peer=udp.recvfrom(65535)
    if local: first=response(query,size=2000)
    elif partial: first=response(query,tc=True)[:-1]  # cut OPT, keep full question
    else: first=response(query,tc=True)
    udp.sendto(first,peer);conn,second=tcp_query(tcp);assert second==query
    wire=response(second);expected.append(wire);frame(conn,wire,True);stop.wait(1);conn.close()

def matrix():
    for family in (socket.AF_INET,socket.AF_INET6):
        case(udp_ok,['--raw'],family=family)
        case(tcp_ok,['--raw','--mode','tcp'],family=family)
        for local,partial in ((False,False),(True,False),(False,True)):
            case(lambda *v: fallback(*v,local=local,partial=partial),['--raw'],family=family)
    def binary(udp,tcp,stop,expected):
        q,peer=udp.recvfrom(65535);p=dns.message.from_wire(q);assert p.question[0].name.labels==(b'A\0\xff.',b'COM',b'')
        r=dns.message.make_response(p);r.question[0].name=dns.name.Name((b'a\0\xff.',b'com',b''));wire=r.to_wire();expected.append(wire);udp.sendto(wire,peer)
    case(binary,['--raw','--wire-name'],data=b'\x04A\0\xff.\x03COM\0',name='-')
    for rcode in (1,2,3,5,16):
        def negative(udp,tcp,stop,expected):
            q,peer=udp.recvfrom(65535);wire=response(q,rcode=rcode);expected.append(wire);udp.sendto(wire,peer)
        case(negative,['--raw'])
    def classic(udp,tcp,stop,expected):
        q,peer=udp.recvfrom(65535);assert dns.message.from_wire(q).edns == -1;wire=response(q);expected.append(wire);udp.sendto(wire,peer)
    case(classic,['--raw','--udp-size','0'])
    def large(udp,tcp,stop,expected):
        conn,q=tcp_query(tcp);wire=response(q,size=60000);expected.append(wire);frame(conn,wire);stop.wait(1);conn.close()
    case(large,['--raw','--mode','tcp'])
    out,_=case(udp_ok)
    assert out.stdout.startswith(b'transport=udp attempts=1 packets=1 discarded=0\n') and b'A=c0000211' in out.stdout
    print('transport-matrix cases=%d' % COUNT)

def junk():
    mutations=[lambda v: bytes([v[0]^1])+v[1:],lambda v:v[:2]+b'\x01\x00'+v[4:],lambda v:v[:2]+b'\x89\x00'+v[4:],lambda v:v[:4]+b'\0\0'+v[6:],lambda v:v[:13]+bytes([v[13]^1])+v[14:],lambda v:v[:25]+b'\0\x1c'+v[27:],lambda v:v[:27]+b'\0\x03'+v[29:],lambda v:v[:12]+b'\xc0\x0c'+v[14:]]
    for mutation in mutations:
        def peer(udp,tcp,stop,expected):
            q,p=udp.recvfrom(65535);wire=response(q);bad=mutation(wire)
            # Include TC on every wrong envelope: none may initiate TCP.
            bad=bad[:2]+(int.from_bytes(bad[2:4],'big')|512).to_bytes(2,'big')+bad[4:]
            udp.sendto(bad,p);udp.sendto(wire,p);expected.append(wire)
        case(peer,['--raw','--id','1234'])
    def short_tc(udp,tcp,stop,expected):
        q,p=udp.recvfrom(65535);wire=response(q);tc=response(q,tc=True)
        for end in (0,2,12,13,20,27,28):udp.sendto(tc[:end],p)
        udp.sendto(wire,p);expected.append(wire)
    case(short_tc,['--raw'])
    def wrong_source(udp,tcp,stop,expected):
        q,p=udp.recvfrom(65535);wire=response(q);rogue=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);rogue.sendto(response(q,tc=True),p);rogue.close();udp.sendto(wire,p);expected.append(wire)
    case(wrong_source,['--raw'])
    def retry(udp,tcp,stop,expected):
        first,p=udp.recvfrom(65535);second,p2=udp.recvfrom(65535);assert dns.message.from_wire(first).question==dns.message.from_wire(second).question
        wire=response(second);udp.sendto(wire,p2);expected.append(wire)
    case(retry,['--raw','--retry','30'])
    def trickle(udp,tcp,stop,expected):
        q,p=udp.recvfrom(65535);bad=response(q);bad=bytes([bad[0]^1])+bad[1:]
        for _ in range(30):
            if stop.wait(.007):return
            udp.sendto(bad,p)
    _,elapsed=case(trickle,['--raw','--retry','35','--attempts','1','--timeout','1000'],status=3)
    assert elapsed < .2,elapsed
    def flood(udp,tcp,stop,expected):
        q,p=udp.recvfrom(65535);bad=response(q);bad=bytes([bad[0]^1])+bad[1:]
        for _ in range(8):udp.sendto(bad,p)
    out,_=case(flood,['--raw','--max-packets','2'],status=3);assert b'packet-limit' in out.stderr
    print('correlation-retries cases=%d' % COUNT)

def failures():
    for mutation in (lambda w:w+b'junk',lambda w:w[:6]+b'\0\x02'+w[8:],lambda w:w[:2]+(int.from_bytes(w[2:4],'big')|64).to_bytes(2,'big')+w[4:]):
        def malformed(udp,tcp,stop,expected):
            q,p=udp.recvfrom(65535);udp.sendto(mutation(response(q)),p)
        out,_=case(malformed,['--raw'],status=3);assert b'dns' in out.stderr
    for payload in (b'',b'\0',b'\0\0',b'\0\x0b',b'\xff\xff',b'\0\x14xxx'):
        def bad_frame(udp,tcp,stop,expected):
            conn,q=tcp_query(tcp);conn.sendall(payload);conn.close()
        args=['--raw','--mode','tcp']
        if payload==b'\xff\xff':args+=['--max-bytes','1232']
        case(bad_frame,args,status=3)
    for modifier in ('id','question','tc','trailing','tc-trailing'):
        def bad_tcp(udp,tcp,stop,expected):
            conn,q=tcp_query(tcp);wire=response(q)
            if modifier=='id':wire=bytes([wire[0]^1])+wire[1:]
            if modifier=='question':wire=wire[:13]+bytes([wire[13]^1])+wire[14:]
            if modifier=='tc':wire=response(q,tc=True)
            if modifier=='trailing':wire+=b'x'
            if modifier=='tc-trailing':wire=response(q,tc=True)+b'x'
            frame(conn,wire);conn.close()
        case(bad_tcp,['--raw','--mode','tcp'],status=3)
    case(lambda *v:fallback(*v),['--raw','--mode','udp'],status=3)
    case(lambda *v:fallback(*v,local=True),['--raw','--max-bytes','1232'],status=3)
    case(udp_ok,['--raw','--max-received','1'],status=3)
    case(udp_ok,['--raw','--max-output','1'],status=3)
    # No nameserver interaction occurs on invalid options/name, expired clock,
    # explicit work exhaustion, or entropy failure.
    invalid=[['--attempts','0'],['--attempts','9'],['--retry','0'],['--udp-size','511'],['--udp-size','65508'],['--udp-size','65535'],['--max-bytes','511'],['--max-bytes','65536'],['--type','65536'],['--type','252'],['--type','251'],['--class','65536'],['--id','65536'],['--max-packets','0'],['--max-work','0'],['--timeout','0'],['--udp-size','0','--dnssec']]
    global COUNT
    for args in invalid:
        out=subprocess.run([EXE,'127.0.0.1:9','example.com',*args],capture_output=True,timeout=2);check(out,3);COUNT+=1
    for args in ([],['127.0.0.1:9'],['name:53','.'],['127.0.0.1:9','a..b'],['127.0.0.1:9','a','--unknown'],['127.0.0.1:9','a','--timeout','60001'],['127.0.0.1:9','a','--type','-1']):
        out=subprocess.run([EXE,*args],capture_output=True,timeout=2);check(out,2);COUNT+=1
    print('transport-failures cases=%d' % COUNT)

def resources(trace):
    live={};fds=set();alloc=0;calls={}
    for line in open(trace):
        call=line.split('(',1)[0];calls[call]=calls.get(call,0)+1
        if line.startswith('mmap('):
            result=line.rsplit(' = ',1)[-1].split()[0]
            if result.startswith('0x'):
                length=int(line.split(',',2)[1]);assert result not in live;live[result]=length;alloc+=1
        elif line.startswith('munmap('):
            assert line.rstrip().endswith(' = 0'),line
            address=line.split('(',1)[1].split(',',1)[0];length=int(line.split(',',1)[1].split(')',1)[0]);assert address in live and live[address]==length,(line,live);del live[address]
        elif line.startswith('socket('):
            result=int(line.rsplit(' = ',1)[-1].split()[0])
            if result>=0:assert result not in fds;fds.add(result)
        elif line.startswith('close('):
            fd=int(line.split('(',1)[1].split(')',1)[0]);assert fd in fds,line;fds.remove(fd)
    assert not live and not fds,(live,fds,open(trace).read())
    return alloc,calls

def faults():
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/trace'
        for handler,args in ((udp_ok,['--raw']),(tcp_ok,['--raw','--mode','tcp']),(lambda *v:fallback(*v),['--raw'])):
            case(handler,args,trace=trace);alloc,calls=resources(trace)
            print("allocation-positions mode=%s count=%d" % (" ".join(args),alloc))
            # Every allocation reached by each successful transport path.
            for index in range(1,alloc+1):
                case(handler,args,status=4,trace=trace,fault='inject=mmap:error=ENOMEM:when=%d'%index);resources(trace)
            for syscall in ('socket','connect','sendto','recvfrom','poll','close','clock_gettime','getrandom'):
                if not calls.get(syscall):continue
                at=1
                case(handler,args,status=3,trace=trace,fault='inject=%s:error=EIO:when=%d'%(syscall,at));resources(trace)
            # EINTR and short native sends/reads are normal progress states.
            for syscall in ('recvfrom','sendto','poll'):
                if not calls.get(syscall):continue
                case(handler,args,trace=trace,fault='inject=%s:error=EINTR:when=1'%syscall);resources(trace)
        # Delaying the first receive until the immediate peer has replied
        # ensures this is a late successful datagram, rather than just EAGAIN.
        case(udp_ok,['--raw','--timeout','50'],status=3,trace=trace,fault='inject=recvfrom:delay_enter=200ms:when=1');resources(trace)
        assert re.search(r'recvfrom\([^\n]+ = [1-9][0-9]*',open(trace).read()),open(trace).read()
        def coalesced(udp,tcp,stop,expected):
            conn,q=tcp_query(tcp);frame(conn,response(q));stop.wait(1);conn.close()
        # Let the peer put the complete frame in the socket while send returns.
        # Prefix read is then call1; delay the successful final body read2.
        case(coalesced,['--raw','--mode','tcp','--timeout','100'],status=3,trace=trace,fault=['inject=sendto:delay_exit=30ms:when=1','inject=recvfrom:delay_enter=200ms:when=2']);resources(trace)
        lines=[line for line in open(trace) if line.startswith('recvfrom(')]
        assert len(lines)==2 and re.search(r' = [1-9][0-9]*',lines[1]),lines
        def malformed(udp,tcp,stop,expected):
            q,p=udp.recvfrom(65535);udp.sendto(response(q)+b'x',p)
        out,_=case(malformed,['--raw'],status=3,trace=trace,fault='inject=close:error=EIO:when=1');resources(trace)
        assert b'dns' in out.stderr and b'cleanup-error' in out.stderr,out
    print('transport-faults cases=%d' % COUNT)

def io_faults():
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/trace'
        case(udp_ok,['--raw'],status=5,trace=trace,fault='inject=write:error=EIO:when=1');resources(trace)
        case(udp_ok,['--raw'],trace=trace,fault='inject=write:error=EINTR:when=1');resources(trace)
        out,_=case(udp_ok,['--raw'],trace=trace,fault='inject=write:retval=7:when=1');resources(trace)
        assert out.stdout.startswith(b'\x01\x00\x00\x00\x01'),out.stdout
        with open('/dev/full','wb') as sink:case(udp_ok,['--raw'],status=5,trace=trace,output=sink)
        resources(trace)
        read_end,write_end=os.pipe();os.close(read_end)
        try:case(udp_ok,['--raw'],status=5,trace=trace,output=write_end)
        finally:os.close(write_end)
        resources(trace);events=open(trace).read();assert 'EPIPE' in events and 'SIG_IGN' in events,events
        case(udp_ok,['--raw','--wire-name'],name='-',data=b'\0',status=5,trace=trace,fault='inject=read:error=EIO:when=1');resources(trace)
        case(udp_ok,['--raw','--wire-name'],name='-',data=b'\0',trace=trace,fault='inject=read:error=EINTR:when=1');resources(trace)
        case(udp_ok,['--raw'],status=5,trace=trace,fault='inject=rt_sigaction:error=EPERM:when=1');alloc,calls=resources(trace);assert not alloc and not calls.get('socket')
        read_end,write_end=os.pipe();os.close(read_end)
        try:
            out=subprocess.run(['strace','-qq','-o',trace,'-e','trace=mmap,munmap,write,rt_sigaction',EXE,'127.0.0.1:9','.','--attempts','0'],stdout=subprocess.PIPE,stderr=write_end,timeout=2)
            assert out.returncode==5 and not out.stdout,out
        finally:os.close(write_end)
        resources(trace);assert 'EPIPE' in open(trace).read()
    print('cli-io-faults cases=%d' % (COUNT+1))

def precedence():
    with tempfile.TemporaryDirectory() as directory:
        trace=directory+'/trace'
        with open(trace,'w') as out:out.write('mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\nmunmap(0x1000, 32) = 0\n')
        rejected=False
        try:resources(trace)
        except AssertionError:rejected=True
        assert rejected,'short unmap passed the resource ledger'
        with open(trace,'w') as out:out.write('mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\nmunmap(0x1000, 64) = 0\n')
        assert resources(trace)[0]==1
        for local in (False,True):
            out,_=case(lambda *v:fallback(*v,local=local),['--raw','--mode','udp'],status=3,trace=trace,fault='inject=close:error=EIO:when=1')
            resources(trace);assert b'truncated stage=receive' in out.stderr and b'cleanup-error' in out.stderr,out
        def dropped(udp,tcp,stop,expected):
            udp.recvfrom(65535);udp.recvfrom(65535);stop.wait(.2)
        out,_=case(dropped,['--raw','--attempts','2','--retry','15'],status=3,trace=trace)
        resources(trace);assert b'timeout stage=receive attempts=2' in out.stderr,out
        out,_=case(dropped,['--raw','--attempts','2','--retry','15'],status=3,trace=trace,fault='inject=close:error=EIO:when=2')
        resources(trace);assert b'timeout stage=receive attempts=2' in out.stderr and b'cleanup-error' in out.stderr,out
        out,_=case(dropped,['--raw','--attempts','2','--retry','15'],status=3,trace=trace,fault='inject=close:error=EIO:when=1')
        resources(trace);assert b'socket stage=close attempts=1' in out.stderr and b'cleanup-error' not in out.stderr,out
    print('error-precedence cases=%d ledger-checks=2' % COUNT)

def native():
    def peer(udp,tcp,stop,expected):
        q,p=udp.recvfrom(65535);parsed=dns.message.from_wire(q)
        assert parsed.id==42 and parsed.question[0].name.labels==(b'A\0\xff',b'')
        udp.sendto(response(q),p)
    case(peer)
    print('native-contract cases=1')

if __name__=='__main__':
    {'precedence':precedence,'io':io_faults,'native':native,'matrix':matrix,'junk':junk,'failures':failures,'faults':faults}[sys.argv[1]]()
