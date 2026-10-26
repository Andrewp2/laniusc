"""Independent CSV/HTTP/ZIP application oracle; production remains Lanius."""
import csv
import importlib.util
import io
import os
from pathlib import Path
import re
import resource
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

sys.dont_write_bytecode = True
from peers import Server, chunked, fixed

spec = importlib.util.spec_from_file_location("http_batch_resource_ledger",Path(__file__).parent.parent/"http_batch"/"resources.py")
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)
MODE, EXE = sys.argv[1:]
CASES = 0
DETAIL = ""
HEADER = ["archive-name","numeric-endpoint","http-authority","origin-target"]
AUTHORITY = "virtual.fixture:8080"
BINARY = bytes(range(256))*17+b"\0\xff\r\n"
TRACE = "mmap,munmap,socket,close,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write,rt_sigaction"


def manifest(rows, *, ending="\r\n", header=HEADER):
    output = io.StringIO(newline="")
    writer = csv.writer(output,lineterminator=ending)
    writer.writerow(header)
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def zip_contents(data, rows, bodies, statuses=None):
    statuses = statuses or [200]*len(rows)
    comment = b"row,status,bytes\n"+b"".join(f"{i},{status},{len(body)}\n".encode() for i,(status,body) in enumerate(zip(statuses,bodies)))
    assert data.startswith(b"PK\x03\x04") and data.endswith(comment)
    ending = len(data)-22-len(comment)
    assert struct.unpack_from("<I",data,ending)[0] == 0x06054b50
    assert struct.unpack_from("<H",data,ending+20)[0] == len(comment)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = archive.infolist()
        assert len(entries) == len(rows) and archive.comment == comment
        assert list(csv.reader(io.StringIO(archive.comment.decode(),newline=""))) == [["row","status","bytes"],*[[str(i),str(status),str(len(body))] for i,(status,body) in enumerate(zip(statuses,bodies))]]
        for item,row,body in zip(entries,rows,bodies):
            assert item.filename == row[0] and item.orig_filename == row[0], (item,row)
            assert item.compress_type == zipfile.ZIP_STORED and item.flag_bits == 2048
            assert item.file_size == item.compress_size == len(body)
            assert item.date_time == (1980,1,1,0,0,0)
            assert archive.read(item) == body  # ZipInfo preserves duplicate-name identity.


def injection_event(observed, fault, descriptor=None):
    requested = re.fullmatch(r"inject=([a-z0-9_]+):(?:error=([A-Z][A-Z0-9_]*)|retval=(-?\d+)):when=(\d+)",fault)
    assert requested, fault
    name,error,returned,ordinal = requested.groups()
    marked = [(kind,event) for kind,events in observed["attempts"].items() for event in events
              if event["injected"] or "INJECTED" in event["result"]]
    assert len(marked) == 1, (fault,marked)
    actual_name,event = marked[0]
    assert actual_name == name and event["ordinal"] == int(ordinal), (fault,marked)
    assert event["injected"] and event["result"].count("(INJECTED)") == 1, (fault,event)
    result = re.match(r"^(-?\d+)(?:\s+([A-Z][A-Z0-9_]*))?(?:\s|$)",event["result"])
    assert result, (fault,event)
    value,native_error = result.groups()
    if error is not None:
        assert value == "-1" and native_error == error, (fault,event)
    else:
        assert int(value) == int(returned) and native_error is None, (fault,event)
    if descriptor is not None:
        assert event["args"].startswith(f"{descriptor},"), (fault,event)
    return event


def injection_controls():
    # CPU controls use the shared real trace parser and actual marker matcher;
    # no application is executed and these are not native process cases.
    def parsed(trace):
        return ledger.analyze(trace)
    read = 'read(0, "", 1) = -1 EINTR (Interrupted system call) (INJECTED)\n'
    zero = 'write(1, "", 1) = 0 (INJECTED)\n'
    third = 'write(2, "", 0) = 0\n'*2+'write(2, "", 1) = -1 EIO (Input/output error) (INJECTED)\n'
    oom = '[0000000000401000] mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = -1 ENOMEM (Cannot allocate memory) (INJECTED)\n'
    valid = [(read,"inject=read:error=EINTR:when=1",0),
             (zero,"inject=write:retval=0:when=1",1),
             (third,"inject=write:error=EIO:when=3",2),
             (oom,"inject=mmap:error=ENOMEM:when=1",None)]
    for trace,fault,descriptor in valid:
        injection_event(parsed(trace),fault,descriptor)
    invalid = [(read,"inject=read:error=EIO:when=1",0),
               (read,"inject=read:retval=0:when=1",0),
               (zero,"inject=write:retval=1:when=1",1),
               (zero,"inject=write:error=EIO:when=1",1),
               (read,"inject=read:error=EINTR:when=2",0),
               (read,"inject=write:error=EINTR:when=1",0),
               (read,"inject=read:error=EINTR:when=1",1),
               (read.replace(" (INJECTED)",""),"inject=read:error=EINTR:when=1",0),
               (read+read,"inject=read:error=EINTR:when=1",0),
               (read+zero,"inject=read:error=EINTR:when=1",0),
               (read.replace("-1 EINTR (Interrupted system call)","1"),"inject=read:error=EINTR:when=1",0)]
    for trace,fault,descriptor in invalid:
        try:
            injection_event(parsed(trace),fault,descriptor)
        except AssertionError:
            continue
        raise AssertionError(("injection matcher accepted mutation",fault,trace))
    return len(valid)+len(invalid)


def invoke(directory, data, args=(), status=0, *, traced=False, fault=None,
           stdout=subprocess.PIPE, preexec_fn=None, diagnostic=True, no_sockets=False, fault_fd=None):
    global CASES
    CASES += 1
    trace = directory/f"process-{CASES}.trace"
    command = [EXE,*map(str,args)]
    if traced or fault:
        command = ["strace","--kill-on-exit","-qq","-i","-o",str(trace),"-e",f"trace={TRACE}",*(["-e",fault] if fault else []),*command]
    start = time.monotonic()
    output = subprocess.run(command,input=data,stdout=stdout,stderr=subprocess.PIPE,
                            preexec_fn=preexec_fn,timeout=12)
    elapsed = time.monotonic()-start
    assert output.returncode == status, (args,status,output)
    if status == 0:
        assert not output.stderr, output
    elif diagnostic:
        assert output.stderr.startswith(b"fetch-many: ") and output.stderr.endswith(b"\n") and b"\0" not in output.stderr, output
    observed = None
    if traced or fault:
        events = trace.read_text()
        observed = ledger.analyze(events)
        if fault:
            injection_event(observed,fault,fault_fd)
        if no_sockets:
            assert not observed["calls"].get("socket",0), (output,events)
    return output,observed,elapsed,trace


def exchange(directory, names, bodies, *, statuses=None, wires=None, args=(), status=0,
             barrier=0, ipv6=False, fragment=0, traced=False, check_requests=True):
    statuses = statuses or [200]*len(names)
    wires = wires or [fixed(body,code) for body,code in zip(bodies,statuses)]
    responses = {f"/job/{i}?x={i}".encode():wire for i,wire in enumerate(wires)}
    with Server(responses,barrier=barrier,ipv6=ipv6,fragment=fragment,allow_abort=status!=0) as server:
        rows = [[name,server.address,AUTHORITY,f"/job/{i}?x={i}"] for i,name in enumerate(names)]
        data = manifest(rows)
        assert list(csv.reader(io.StringIO(data.decode(),newline=""),strict=True)) == [HEADER,*rows]
        output,observed,elapsed,trace = invoke(directory,data,args,status,traced=traced)
        if status == 0:
            zip_contents(output.stdout,rows,bodies,statuses)
            if barrier:
                assert server.release.is_set() and len(server.records) >= barrier
            if check_requests:
                assert sorted(head.target for head in server.records) == sorted(responses)
                assert all([value for key,value in head.headers if key == b"host"] == [AUTHORITY.encode()] for head in server.records)
        else:
            assert output.stdout == b"", output
    return output,observed,elapsed,trace


def matrix(directory):
    first = exchange(directory,["one.bin"],[BINARY])[0].stdout
    assert exchange(directory,["one.bin"],[BINARY])[0].stdout == first
    exchange(directory,["duplicate","duplicate","","../dot/./name","世界/é,\"line\r\n.bin","empty/"],
             [b"first",b"second",b"empty name",b"dot",BINARY,b""],args=("--concurrency=4",),barrier=4,traced=True)
    for concurrency in (1,2,4,16):
        count = concurrency+1
        _,observed,_,_ = exchange(directory,[f"ordered/{i}.bin" for i in range(count)],
                                  [bytes([i])*31 for i in range(count)],
                                  args=(f"--concurrency={concurrency}","--max-total-work=1073741824"),
                                  barrier=concurrency,traced=True)
        assert observed["max_sockets"] == concurrency, observed
    # Force job1's transport to complete and close before job0's response.
    # A completion-ordered archive cannot pass merely by scheduling luck.
    earlier_closed = threading.Event()
    order = []
    first_body,second_body = b"CSV first held"*3,b"CSV second completed"*2
    def first_response(connection,server):
        assert server.wait(earlier_closed)
        order.append("first-response")
        connection.sendall(fixed(first_body,201))
    def second_response(connection,server):
        connection.sendall(fixed(second_body,202))
        connection.shutdown(socket.SHUT_WR)
        assert connection.recv(1) == b""
        order.append("second-closed")
        earlier_closed.set()
    with Server({b"/first":first_response,b"/second":second_response},barrier=2) as server:
        rows = [["csv-first",server.address,AUTHORITY,"/first"],["csv-second",server.address,AUTHORITY,"/second"]]
        result,observed,_,_ = invoke(directory,manifest(rows),("--concurrency=2",),traced=True)
        zip_contents(result.stdout,rows,[first_body,second_body],[201,202])
        assert order == ["second-closed","first-response"] and observed["max_sockets"] == 2, (order,observed)
    exchange(directory,["ipv6.bin"],[BINARY],ipv6=True)
    exchange(directory,["fragmented.bin"],[BINARY],fragment=7)
    exchange(directory,["chunked","close-delimited","informational","empty"],[BINARY,BINARY,BINARY,b""],
             wires=[chunked(BINARY),b"HTTP/1.0 200 OK\r\n\r\n"+BINARY,
                    # RFC 9110 section 8.6 forbids Content-Length even at zero
                    # on 204; its message ends with the head (RFC 9112 6.3).
                    b"HTTP/1.1 103 Early Hints\r\nLink: </a>\r\n\r\n"+fixed(BINARY),
                    b"HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"],
             statuses=[200,200,200,204],barrier=4,traced=True)
    for code in (201,206):
        fields = f"Content-Range: bytes 0-{len(BINARY)-1}/{len(BINARY)}\r\n".encode() if code == 206 else b""
        exchange(directory,[f"status-{code}"],[BINARY],statuses=[code],wires=[fixed(BINARY,code,fields)])
    exchange(directory,["redirect","missing","server-error"],[b"redirect",b"missing",BINARY],
             statuses=[301,404,503],wires=[fixed(b"redirect",301,b"Location: /must-not-follow\r\n"),fixed(b"missing",404),fixed(BINARY,503)],
             args=("--allow-http-errors",),barrier=3,traced=True)
    with Server({b"/x":fixed(BINARY)}) as server:
        rows = [["last-line",server.address,AUTHORITY,"/x"]]
        for ending in ("\n","\r\n"):
            data = manifest(rows,ending=ending).rstrip(b"\r\n")
            result,_,_,_ = invoke(directory,data)
            zip_contents(result.stdout,rows,[BINARY])


def failures(directory):
    bad_rows = [("/absolute","127.0.0.1:1",AUTHORITY,"/x",2),
                ("C:drive","127.0.0.1:1",AUTHORITY,"/x",2),
                ("back\\slash","127.0.0.1:1",AUTHORITY,"/x",2),
                ("name","localhost:80",AUTHORITY,"/x",2),
                ("name","127.0.0.1",AUTHORITY,"/x",2),
                ("name","127.0.0.1:1","bad\r\nInjected: yes","/x",2),
                ("name","127.0.0.1:1",AUTHORITY,"not-origin",2)]
    for name,endpoint,authority,target,code in bad_rows:
        with Server({b"/valid":fixed(b"early")},allow_abort=True) as server:
            rows = [["valid",server.address,AUTHORITY,"/valid"],[name,endpoint,authority,target]]
            output,_,_,_ = invoke(directory,manifest(rows),status=code,traced=True,no_sockets=True)
            assert output.stdout == b"" and not server.records
    malformed = [b"",manifest([]),b"wrong,header,has,fields\r\n",manifest([["one","a","b"]]),
                 manifest([["one","a","b","c","extra"]]),manifest([["one","a","b","c"],["two"]]),
                 b",".join(value.encode() for value in HEADER)+b"\r\n\"unterminated",
                 manifest([["nul\0name","127.0.0.1:1",AUTHORITY,"/x"]]),
                 manifest([["tab\tname","127.0.0.1:1",AUTHORITY,"/x"]]),
                 b",".join(value.encode() for value in HEADER)+b"\r\n\xff,a,b,c\r\n"]
    for data in malformed:
        output,_,_,_ = invoke(directory,data,status=2,traced=True,no_sockets=True)
        assert output.stdout == b""
    for code in (301,404,503):
        output,_,_,_ = exchange(directory,["early","rejected"],[b"early",BINARY],statuses=[200,code],status=2,barrier=2,traced=True)
        assert f"row=1 status={code}".encode() in output.stderr, output
    exchange(directory,["bad-directory/"],[b"not empty"],status=2,traced=True)
    invalid_wires = [b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nshort",
                     b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nab",
                     b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n",
                     b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 0\r\n\r\n",
                     b"HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n",
                     b"HTTP/1.1 100 Continue\r\n\r\n"*5+fixed(b""),b"HTTP/1.1 200 OK\r\n",
                     fixed(b"",204)]  # Exact former invalid positive: forbidden CL: 0.
    for wire in invalid_wires:
        exchange(directory,["good","bad"],[b"good",b""],wires=[fixed(b"good"),wire],status=3,barrier=2,traced=True)
    reserved = socket.socket()
    reserved.bind(("127.0.0.1",0))  # Reserved and not listening: deterministic refusal.
    try:
        output,_,_,_ = invoke(directory,manifest([["refused",f"127.0.0.1:{reserved.getsockname()[1]}",AUTHORITY,"/x"]]),status=3,traced=True)
        assert output.stdout == b""
    finally:
        reserved.close()
    def silence(connection,server):
        server.stop.wait(3)
    with Server({b"/stall":silence},allow_abort=True) as server:
        data = manifest([["stall",server.address,AUTHORITY,"/stall"]])
        output,_,_,_ = invoke(directory,data,("--timeout-ms=100",),3,traced=True)
        assert output.stdout == b"" and len(server.records) == 1


def limits(directory):
    invalid = [("--concurrency=0",),("--concurrency=17",),("--timeout-ms=60001",),("--max-input=262145",),
               ("--max-body=8388609",),("--max-total-body=33554433",),("--max-wire=16777217",),
               ("--max-total-wire=67108865",),("--max-output=41943041",),("--max-io=0",),("--max-io=1000001",),
               ("--max-work=268435457",),("--max-total-work=1073741825",),("--max-operations=10000001",),
               ("--max-input=-1",),("--max-input=+1",),("--max-input=184467440737095516160",),
               ("--max-input",),("--unknown",),("operand",),("--help","--allow-http-errors"),
               ("--concurrency=1","--concurrency=2"),("--allow-http-errors","--allow-http-errors")]
    for args in invalid:
        output,_,_,_ = invoke(directory,b"",args,2,traced=True,no_sockets=True)
        assert output.stdout == b""
    help_output,_,_,_ = invoke(directory,b"",("--help",),traced=True,no_sockets=True)
    assert help_output.stdout.startswith(b"Usage: fetch-many") and b"--max-total-work" in help_output.stdout and b"--max-operations" in help_output.stdout
    with Server({b"/x":fixed(b"abc")}) as server:
        rows = [["n",server.address,AUTHORITY,"/x"]]
        data = manifest(rows)
        output,_,_,_ = invoke(directory,data,(f"--max-input={len(data)}",))
        zip_contents(output.stdout,rows,[b"abc"])
    for maximum in (0,len(data)-1):
        result,_,_,_ = invoke(directory,data,(f"--max-input={maximum}",),2,traced=True,no_sockets=True)
        assert result.stdout == b""
    for name,endpoint,authority,target in (("n"*1025,"127.0.0.1:1",AUTHORITY,"/x"),
                                           ("n","1"*65,AUTHORITY,"/x"),("n","127.0.0.1:1","h"*1025,"/x"),
                                           ("n","127.0.0.1:1",AUTHORITY,"/"+"a"*4096)):
        result,_,_,_ = invoke(directory,manifest([[name,endpoint,authority,target]]),status=2,traced=True,no_sockets=True)
        assert result.stdout == b""
    too_many = manifest([[str(i),"127.0.0.1:1",AUTHORITY,"/x"] for i in range(65)])
    result,_,_,_ = invoke(directory,too_many,status=2,traced=True,no_sockets=True)
    assert result.stdout == b""
    body = b"abcde"
    wire = fixed(body)
    for flag,exact in (("max-body",len(body)),("max-total-body",len(body)),("max-wire",len(wire)),("max-total-wire",len(wire))):
        exchange(directory,["n"],[body],args=(f"--{flag}={exact}",))
        exchange(directory,["n"],[body],args=(f"--{flag}={exact-1}",),status=3,traced=True)
    baseline = exchange(directory,["n"],[body])[0].stdout
    exchange(directory,["n"],[body],args=(f"--max-output={len(baseline)}",))
    for maximum in (0,len(baseline)-1):
        exchange(directory,["n"],[body],args=(f"--max-output={maximum}",),status=2,traced=True)
    for flag in ("max-body","max-total-body"):
        exchange(directory,["empty"],[b""],args=(f"--{flag}=0",))
    for flag,value in (("max-io",1),("max-operations",0),("max-work",0),("max-total-work",0),("timeout-ms",0)):
        exchange(directory,["n"],[body],args=(f"--{flag}={value}",),status=3,traced=True)
    for flag,maximum in (("max-total-body",6),("max-total-wire",2*len(fixed(b"abc")))):
        exchange(directory,["a","b"],[b"abc",b"abc"],args=(f"--{flag}={maximum}",),barrier=2)
        exchange(directory,["a","b"],[b"abc",b"abc"],args=(f"--{flag}={maximum-1}",),status=3,barrier=2,traced=True)
    exchange(directory,["long"+"n"*1020],[b""],args=("--max-input=262144",))
    # These adapter caps differ from http_client defaults, so test the actual
    # application's wiring rather than assuming raw library coverage transfers.
    for custom,status in ((62,0),(63,3)):
        fields = b"".join(f"X-{i}: a\r\n".encode() for i in range(custom))
        exchange(directory,["headers"],[b""],wires=[fixed(b"",fields=fields)],status=status,traced=True)
    for count,status in ((4096,0),(4097,3)):
        wire = (b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                +b"1\r\na\r\n"*count+b"0\r\n\r\n")
        exchange(directory,["chunks"],[b"a"*count],wires=[wire],status=status,traced=True)
    for count,status in ((32,0),(33,3)):
        wire = (b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n"
                +b"".join(f"X-T{i}: a\r\n".encode() for i in range(count))+b"\r\n")
        exchange(directory,["trailers"],[b""],wires=[wire],status=status,traced=True)
    exchange(directory,["interims"],[b""],wires=[b"HTTP/1.1 100 Continue\r\n\r\n"*4+fixed(b"")])
    fields = b"X-A: "+b"a"*6000+b"\r\nX-B: "+b"b"*6000+b"\r\nX-C: "
    pad = 16384-len(fixed(b"",fields=fields+b"\r\n"))
    for extra,status in ((0,0),(1,3)):
        wire = fixed(b"",fields=fields+b"c"*(pad+extra)+b"\r\n")
        assert len(wire) == 16384+extra
        exchange(directory,["head"],[b""],wires=[wire],status=status,traced=True)
    exchange(directory,["line"],[b""],wires=[fixed(b"",fields=b"X-Line: "+b"a"*9000+b"\r\n")],status=3,traced=True)


def io_faults(directory):
    responses = {b"/x":fixed(BINARY)}
    with Server(responses,allow_abort=True) as server:
        rows = [["body.bin",server.address,AUTHORITY,"/x"]]
        data = manifest(rows)
        baseline,_,_,_ = invoke(directory,data)
        zip_contents(baseline.stdout,rows,[BINARY])
        for fault,status in (("inject=read:error=EINTR:when=1",0),("inject=read:error=EIO:when=1",5),
                             ("inject=read:error=EAGAIN:when=1",5),("inject=write:error=EINTR:when=1",0),
                             ("inject=write:error=EIO:when=1",5),("inject=write:error=EAGAIN:when=1",5),
                             ("inject=write:retval=0:when=1",5)):
            output,_,_,_ = invoke(directory,data,status=status,fault=fault,fault_fd=0 if "inject=read:" in fault else 1)
            assert output.stdout == (baseline.stdout if status == 0 else b""), output
        with open("/dev/full","wb") as destination:
            invoke(directory,data,status=5,stdout=destination)
        read_end,write_end = os.pipe()
        os.close(read_end)
        try:
            invoke(directory,data,status=5,stdout=write_end)
        finally:
            os.close(write_end)
        def restricted():
            resource.setrlimit(resource.RLIMIT_FSIZE,(19,19))
            signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
        path = directory/"short.zip"
        with path.open("wb") as destination:
            output,_,_,_ = invoke(directory,data,status=5,stdout=destination,preexec_fn=restricted)
        assert path.read_bytes() == baseline.stdout[:19] and b"written=19" in output.stderr, output
        for name,error in (("socket","EMFILE"),("connect","EIO"),("sendto","EIO"),("recvfrom","EIO")):
            output,_,_,_ = invoke(directory,data,status=3,fault=f"inject={name}:error={error}:when=1")
            assert output.stdout == b""
        output,_,_,_ = invoke(directory,b"",status=5,fault="inject=write:error=EIO:when=1",fault_fd=2,diagnostic=False)
        assert not output.stdout and not output.stderr
        output,_,_,_ = invoke(directory,b"",status=5,fault="inject=rt_sigaction:error=EIO:when=1",diagnostic=False)
        assert not output.stdout and not output.stderr
        # Kill neither peer nor product: wait until the actual injected poll
        # is logged, then release its response to prove successful EINTR retry.
    for error,status in (("EIO",3),("EINTR",0)):
        release = threading.Event()
        with Server(responses,gate=release,allow_abort=status!=0) as server:
            data = manifest([["body.bin",server.address,AUTHORITY,"/x"]])
            expected_trace = directory/f"process-{CASES+1}.trace"
            stop = threading.Event()
            def after_marker():
                end = time.monotonic()+5
                while not stop.is_set() and time.monotonic() < end:
                    if expected_trace.exists() and "INJECTED" in expected_trace.read_text():
                        release.set()
                        return
                    stop.wait(.005)
            watcher = threading.Thread(target=after_marker)
            watcher.start()
            try:
                output,_,_,_ = invoke(directory,data,status=status,fault=f"inject=poll:error={error}:when=1")
                if status == 0:
                    assert release.is_set()
                assert output.stdout == (baseline.stdout if status == 0 else b"")
            finally:
                stop.set()
                watcher.join(1)
                assert not watcher.is_alive()


def peak_bytes(trace):
    live = {}
    total = peak = 0
    for line in trace.read_text().splitlines():
        match = re.search(r"\b(mmap|munmap)\((.*)\)\s+=\s+(\S+)",line)
        if not match:
            continue
        name,args,result = match.groups()
        if name == "mmap" and result.startswith("0x"):
            length = int(args.split(",",2)[1])
            live[int(result,16)] = length
            total += length
            peak = max(peak,total)
        elif name == "munmap":
            address = int(args.split(",",1)[0],16)
            total -= live.pop(address)
    assert not live and total == 0
    return peak


def resources(directory):
    global DETAIL
    bodies = [b"a"*32,b"b"*32]
    responses = {b"/job/0?x=0":fixed(bodies[0]),b"/job/1?x=1":fixed(bodies[1])}
    args = ("--concurrency=2",)
    def attempt(fault=None,status=0):
        with Server(responses,allow_abort=status!=0) as server:
            rows = [[f"item{i}.bin",server.address,AUTHORITY,f"/job/{i}?x={i}"] for i in range(2)]
            output,observed,elapsed,trace = invoke(directory,manifest(rows),args,status,traced=True,fault=fault)
            if status == 0:
                zip_contents(output.stdout,rows,bodies)
            else:
                assert output.stdout == b""
            return output,observed,elapsed,trace
    baseline,observed,_,_ = attempt()
    allocations = observed["allocations"]
    assert allocations and 1 <= observed["max_sockets"] <= 2
    for allocation in allocations:
        ordinal = allocation["ordinal"]
        _,failed,_,_ = attempt(f"inject=mmap:error=ENOMEM:when={ordinal}",4)
        selected = [event for event in failed["attempts"].get("mmap",[]) if event["injected"]]
        assert len(selected) == 1
        actual = selected[0]
        assert actual["ordinal"] == ordinal and actual["ip"] == allocation["ip"]
        assert int(actual["args"].split(",",2)[1]) == allocation["length"], (allocation,actual)
    # One bounded observation, including startup/CSV/network/ZIP/output. No
    # throughput comparison, timing correctness assertion or memory-quota claim.
    names = [f"scale/{i:03}.bin" for i in range(64)]
    payloads = [bytes([i])*1024 for i in range(64)]
    output,scale,elapsed,trace = exchange(directory,names,payloads,barrier=4,traced=True)
    assert scale["max_sockets"] == 4
    peak = peak_bytes(trace)
    DETAIL = (f" oom-points={len(allocations)} scale-jobs=64 scale-body-bytes=65536"
              f" scale-zip-bytes={len(output.stdout)} scale-max-sockets={scale['max_sockets']}"
              f" scale-allocations={len(scale['allocations'])} scale-peak-requested={peak} scale-seconds={elapsed:.3f}")


controls = injection_controls()
with tempfile.TemporaryDirectory(prefix="lanius_fetch_many_") as temporary:
    if MODE != "injection-controls":
        {"matrix":matrix,"failures":failures,"limits":limits,"io":io_faults,"resources":resources}[MODE](Path(temporary))
print(f"fetch-many-{MODE} cases={CASES}{DETAIL} injection-controls={controls}")
