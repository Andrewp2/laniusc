"""Native application checks; libc resolves, Python compares endpoint values."""
import ipaddress
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

sys.dont_write_bytecode = True
MODE, EXE, OBSERVER, NATIVE = sys.argv[1:]
CASES = 0
DETAIL = ""


def endpoints(output):
    assert not output or output.endswith(b"\n"), output
    values = []
    for line in output.decode("ascii").splitlines():
        if line.startswith("["):
            host, port = line[1:].split("]:")
            address, separator, scope = host.partition("%")
            ip = ipaddress.IPv6Address(address)
            scoped = int(scope) if separator else 0
            canonical = "::ffff:" + str(ip.ipv4_mapped) if ip.ipv4_mapped else str(ip)
            if scoped:
                canonical += "%" + str(scoped)
            assert line == f"[{canonical}]:{int(port)}", line
        else:
            address, port = line.split(":")
            ip = ipaddress.IPv4Address(address)
            scoped = 0
            assert line == f"{ip}:{int(port)}", line
        assert 0 <= int(port) <= 65535 and 0 <= scoped <= 0xffffffff
        values.append((ip.version, int(port), scoped, ip.packed))
    return values


def reference(host, service, family, transport, numeric=False, passive=False):
    port = service.isascii() and service.isdecimal()
    flags = (4 if numeric else 0) | (1024 if port else 0) | (1 if passive else 0)
    result = subprocess.run([NATIVE, "-" if passive else host, str(int(service)) if port else service,
                             str(family), str(transport), str(flags)], capture_output=True, timeout=8)
    assert result.returncode == 0 and not result.stderr, result
    text = result.stdout.decode().strip()
    if text.startswith("N"):
        return tuple(map(int, text[1:].split(":")))
    assert text.startswith("O") and text.endswith("/"), text
    records = []
    for row in text[1:-1].split("/"):
        version, port, scope, raw = row.split(":")
        records.append((int(version), int(port), int(scope), bytes.fromhex(raw)))
    return records


def run(directory, args, expected=0, mode=None, count=0, command=(), stdout=subprocess.PIPE,
        preexec_fn=None, expected_prefix=None, diagnostic=True):
    global CASES
    CASES += 1
    environment = os.environ.copy()
    for key in ("LD_PRELOAD", "LANIUS_RESOLVE_MODE", "LANIUS_RESOLVE_COUNT", "LANIUS_RESOLVE_TRACE"):
        environment.pop(key, None)
    trace = directory / f"native-{CASES}.trace"
    if mode is not None:
        environment.update(LD_PRELOAD=OBSERVER, LANIUS_RESOLVE_MODE=str(mode),
                           LANIUS_RESOLVE_COUNT=str(count), LANIUS_RESOLVE_TRACE=str(trace))
    result = subprocess.run([*map(str, command), EXE, *args], capture_output=False,
                            stdin=subprocess.DEVNULL, stdout=stdout, stderr=subprocess.PIPE,
                            env=environment, preexec_fn=preexec_fn, timeout=8)
    assert result.returncode == expected, (args, mode, result)
    if expected == 0:
        assert not result.stderr, (args, result)
    elif diagnostic:
        assert result.stderr.startswith(b"resolve-host: ") and result.stderr.endswith(b"\n"), (args, result)
    if expected_prefix is not None:
        assert result.stdout == expected_prefix, (args, result, expected_prefix)
    events = trace.read_text().splitlines() if trace.exists() else []
    gets = [row for row in events if row.startswith("G ")]
    assert len(gets) <= 1 and events.count("F") <= 1, events
    if "F" in events:
        assert len(gets) == 1 and events[-1] == "F", events
    return result, events


def hints(events, flags, family, kind, host, service, mode):
    expected = [flags, family, kind, 6 if kind == 1 else 17,
                int(host is None), int(service is None), len(host or ""), len(service or ""), mode]
    actual = [row for row in events if row.startswith("G ")]
    assert len(actual) == 1 and list(map(int, actual[0].split()[1:])) == expected, (actual, expected)


def synthetic(count, port=8080, family=0):
    result = []
    for i in range(count):
        version = 4 if family == 2 else 6 if family == 10 else 6 if i % 2 else 4
        if version == 4:
            raw, scope = ipaddress.IPv4Address("198.51.100.227").packed, 0
        else:
            raw = ipaddress.IPv6Address("::ffff:192.0.2.123" if i % 4 == 3 else "2001:db8:1234:ffff:0:abcd:dead:beef").packed
            scope = 0xffffffff if i % 4 == 3 else 0x89abcdef
        result.append((version, port, scope, raw))
    return result


def native_case(directory, host, service, family=0, kind=1, numeric=False, passive=False, extra=()):
    args = ["--family", {0:"any", 2:"ipv4", 10:"ipv6"}[family], "--transport", "tcp" if kind == 1 else "udp"]
    if numeric:
        args += ["--numeric-host"]
    if passive:
        args += ["--passive", service]
    else:
        args += [host, service]
    args += list(extra)
    expected = reference(host, service, family, kind, numeric, passive)
    failed = isinstance(expected, tuple)
    output, events = run(directory, args, 3 if failed else 0, mode=0)
    port = service.isascii() and service.isdecimal()
    flags = (4 if numeric else 0) | (1024 if port else 0) | (1 if passive else 0)
    hints(events, flags, family, kind, None if passive else host, str(int(service)) if port else service, 0)
    if failed:
        assert output.stdout == b"" and f"code={expected[0]}, system={expected[1]}".encode() in output.stderr, output
        assert events.count("F") == 0, events
    else:
        assert endpoints(output.stdout) == expected and events.count("F") == 1, (output, expected, events)


def local_service_prerequisite(name, kind):
    # db and files are local providers. A successful files record must return
    # before a later sss/other provider; do not assume services starts at files.
    lines = Path("/etc/nsswitch.conf").read_text().splitlines()
    policy = next(line.split("#",1)[0].split(":",1)[1].split() for line in lines
                  if line.split("#",1)[0].strip().startswith("services:"))
    before = policy[:policy.index("files")]
    assert before in ([], ["db"]), policy
    after = policy[policy.index("files")+1:]
    assert not after or not after[0].startswith("["), policy
    protocol = "tcp" if kind == 1 else "udp"
    records = []
    for line in Path("/etc/services").read_text().splitlines():
        fields = line.split("#",1)[0].split()
        if len(fields) >= 2 and name in (fields[0], *fields[2:]):
            port, selected = fields[1].split("/")
            if selected == protocol:
                records.append(int(port))
    expected = {"http":80, "domain":53}[name]
    assert expected in records, (name, protocol, records)


def matrix(directory):
    for service, kind in (("http",1), ("domain",1), ("domain",2)):
        local_service_prerequisite(service, kind)
    for kind in (1, 2):
        for host, family in (("127.0.0.1", 2), ("::1", 10), ("fe80::1%7", 10), ("::ffff:192.0.2.1", 10)):
            for port in ("0", "65535"):
                native_case(directory, host, port, family, kind, numeric=True, extra=("--numeric-service",))
        for family in (0, 2, 10):
            native_case(directory, "localhost", "8080", family, kind)
            native_case(directory, None, "0", family, kind, passive=True)
        native_case(directory, "127.0.0.1", "00080", 2, kind)
        native_case(directory, "127.0.0.1", "domain", 2, kind)
    native_case(directory, "localhost", "http", 0, 1)
    native_case(directory, "127.0.0.1", "80", 2, 1, extra=("--family=ipv4", "--transport=tcp"))
    output, events = run(directory, ["--family=ipv6", "--transport=udp", "127.0.0.1", "80", "--family=ipv4", "--transport=tcp"], mode=0)
    assert endpoints(output.stdout) == reference("127.0.0.1", "80", 2, 1) and events.count("F") == 1
    hints(events, 1024, 2, 1, "127.0.0.1", "80", 0)
    for family in (0, 2, 10):
        for kind in (1, 2):
            output, events = run(directory, ["fixture", "8080", "--family", {0:"any",2:"ipv4",10:"ipv6"}[family], "--transport", "tcp" if kind == 1 else "udp"], mode=1)
            assert endpoints(output.stdout) == synthetic(4, family=family), output
            hints(events, 1024, family, kind, "fixture", "8080", 1)
            assert events.count("F") == 1
    output, events = run(directory, ["fixture", "named"], mode=1)
    assert endpoints(output.stdout) == synthetic(4, 43210) and events.count("F") == 1
    hints(events, 0, 0, 1, "fixture", "named", 1)
    output, events = run(directory, ["--passive", "named", "--transport=udp"], mode=1)
    assert endpoints(output.stdout) == synthetic(4, 43210) and events.count("F") == 1
    hints(events, 1, 0, 2, None, "named", 1)
    output, _ = run(directory, ["--help"])
    assert output.stdout.startswith(b"Usage: resolve-host ") and output.stdout.endswith(b"\n")


def limits(directory):
    invalid = [[], ["localhost"], ["a", "1", "extra"], ["--passive"], ["--passive", "host", "80"],
               ["--passive", "80", "--numeric-host"], ["--family"], ["--family=bad", "a", "1"],
               ["--transport=sctp", "a", "1"], ["--numeric-host=yes", "a", "1"], ["--bad", "a", "1"],
               ["--numeric-service", "a", "http"], ["a", "65536"], ["a", "184467440737095516160"],
               ["a", "+80"], ["a", "-1"], ["", "80"], ["*", "80"], ["*", "80", "--numeric-host"],
               ["a", "*"], ["a", ""], ["a b", "80"], ["a\t", "80"], [b"\xff", "80"], ["a", b"\x80"],
               ["a"*4097, "80"], ["a", "s"*65], ["--max-results=0", "a", "80"],
               ["--max-results=1025", "a", "80"], ["--max-output=1048577", "a", "80"],
               ["--max-write-calls=2147483648", "a", "80"], ["--max-output=-1", "a", "80"],
               ["--max-output=+1", "a", "80"], ["--max-output=", "a", "80"], ["x"*8193, "80"],
               ["--numeric-service"]*33]
    for args in invalid:
        result, events = run(directory, args, 2, mode=1, expected_prefix=b"")
        assert not events, (args, events, result)
    for args, host, service in ((["h"*4096, "80"], "h"*4096, "80"), (["h", "s"*64], "h", "s"*64),
                                (["--", "-host", "80"], "-host", "80")):
        result, events = run(directory, args, mode=1)
        hints(events, 1024 if service == "80" else 0, 0, 1, host, service, 1)
        assert len(endpoints(result.stdout)) == 4 and events.count("F") == 1
    baseline, _ = run(directory, ["fixture", "8080"], mode=1)
    size = len(baseline.stdout)
    run(directory, ["fixture", "8080", f"--max-output={size}"], mode=1, expected_prefix=baseline.stdout)
    for maximum in (0, size-1):
        _, events = run(directory, ["fixture", "8080", f"--max-output={maximum}"], 2, mode=1, expected_prefix=b"")
        assert events.count("F") == 1
    for maximum, status in ((3, 2), (4, 0)):
        result, events = run(directory, ["fixture", "8080", f"--max-results={maximum}"], status, mode=1)
        assert result.stdout == (baseline.stdout if status == 0 else b"") and events.count("F") == 1
    for count, maximum, status in ((64,64,0), (65,64,2), (1024,1024,0), (1025,1024,2)):
        result, events = run(directory, ["fixture", "8080", f"--max-results={maximum}", "--max-output=1048576"], status, mode=16, count=count)
        assert events.count("F") == 1
        assert endpoints(result.stdout) == (synthetic(count) if status == 0 else [])
    for mode in (2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14):
        result, events = run(directory, ["fixture", "8080"], 3, mode=mode, expected_prefix=b"")
        assert events.count("F") == int(mode >= 8), events
        if mode == 3:
            assert b"code=-11, system=13" in result.stderr, result
        if mode in (4, 5, 6, 7):
            assert b"system=0" in result.stderr, result
    _, events = run(directory, ["fixture", "8080", "--max-results=4"], 2, mode=17, count=4, expected_prefix=b"")
    assert events.count("F") == 1
    native_case(directory, "not-a-number", "80", 0, 1, numeric=True)
    native_case(directory, "127.0.0.1", "definitely-no-such-local-service-lanius", 2, 1)


def io(directory):
    args = ["127.0.0.1", "8080", "--numeric-host", "--family=ipv4"]
    baseline, _ = run(directory, args)
    assert baseline.stdout == b"127.0.0.1:8080\n"
    for budget, status, prefix in ((0,5,b""), (1,5,baseline.stdout), (2,0,baseline.stdout)):
        result, _ = run(directory, [*args, f"--max-write-calls={budget}"], status, expected_prefix=prefix)
        if status:
            assert f"written={len(prefix)}, calls={budget}".encode() in result.stderr
    for fault, status, calls in (("inject=write:error=EINTR:when=1",0,3),
                                  ("inject=write:error=EINTR:when=1+",5,4),
                                  ("inject=write:error=EIO:when=1",5,1),
                                  ("inject=write:error=EAGAIN:when=1",5,1),
                                  ("inject=write:retval=0:when=1",5,1)):
        trace = directory / "output.trace"
        result, _ = run(directory, [*args,"--max-write-calls=4"], status,
                        command=("strace","-qq","-o",trace,"-e","trace=write","-e",fault),
                        expected_prefix=baseline.stdout if status == 0 else b"", diagnostic="when=1+" not in fault)
        assert "INJECTED" in trace.read_text()
        if status:
            # Permanently interrupted stderr may itself consume its own eight
            # attempts, so no diagnostic bytes are guaranteed in this case.
            if "when=1+" not in fault:
                assert f"written=0, calls={calls}".encode() in result.stderr
    with open("/dev/full", "wb") as full:
        run(directory, args, 5, stdout=full)
    read_end, write_end = os.pipe()
    os.close(read_end)
    try:
        run(directory, args, 5, stdout=write_end)
    finally:
        os.close(write_end)
    # A real short regular-file write, not a fabricated successful syscall
    # result: the file-size limit accepts seven bytes, then returns EFBIG.
    def restricted_file():
        resource.setrlimit(resource.RLIMIT_FSIZE, (7,7))
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    path = directory / "short-output"
    with path.open("wb") as destination:
        result, _ = run(directory, args, 5, stdout=destination, preexec_fn=restricted_file)
    assert path.read_bytes() == baseline.stdout[:7]
    assert b"written=7, calls=2" in result.stderr, result


def executable_ranges():
    data = Path(EXE).read_bytes()
    assert data[:6] == b"\x7fELF\x02\x01"
    offset = struct.unpack_from("<Q",data,32)[0]
    stride, count = struct.unpack_from("<HH",data,54)
    assert stride == 56
    ranges = []
    for index in range(count):
        kind, flags, _, address, _, _, length, _ = struct.unpack_from("<IIQQQQQQ",data,offset+index*stride)
        if kind == 1 and flags & 1:
            ranges.append((address,address+length))
    assert ranges
    return ranges


def local_mappings(events):
    live = {}
    requests = []
    all_mmaps = []
    ordinal = 0
    ranges = executable_ranges()
    for line in events.splitlines():
        match = re.match(r"\[([0-9a-f]+)\] (.*)",line)
        assert match, line
        instruction, line = int(match[1],16), match[2]
        if line.startswith("mmap("):
            ordinal += 1
            all_mmaps.append((instruction,line))
            if "MAP_32BIT" not in line:
                continue
            assert any(begin <= instruction < end for begin,end in ranges), (instruction,line)
            length = int(line.split(",",2)[1].strip())
            address = line.rsplit(" = ",1)[-1].split()[0]
            requests.append((ordinal,instruction,length,address))
            if address.startswith("0x"):
                assert address not in live, line
                live[address] = length
        elif line.startswith("munmap("):
            address, length = line[7:].split(")",1)[0].split(",")
            generated = any(begin <= instruction < end for begin,end in ranges)
            if address in live:
                assert generated, (instruction,line)
                assert line.endswith(" = 0") and int(length) == live.pop(address), line
            elif generated and int(address,16) < 0x80000000:
                # Source allocations use MAP_32BIT. A second or unowned low
                # release must fail rather than disappear from the ledger.
                # Loader/libc instructions and high CRT bootstrap mappings
                # are outside this source-owner ledger.
                raise AssertionError(("unowned source release",instruction,line))
    assert not live, live
    # Vec::relocate's typed allocation and direct byte/frame allocations can
    # have separate emitted allocator sites. Site identity is per role, not a
    # public allocator contract. Every observed site's requests retain flags.
    sites = {row[1] for row in requests}
    assert all("MAP_32BIT" in line for ip,line in all_mmaps if ip in sites), all_mmaps
    return requests


def ledger_controls():
    # CPU mutation controls exercise the actual classifier without running an
    # application or fabricating accepted product I/O. Keep the valid high CRT
    # cleanup distinct from invalid generated low-address cleanup.
    source = executable_ranges()[0][0]+1
    foreign = 0x7fff00000000
    def event(ip, body):
        return f"[{ip:016x}] {body}\n"
    allocation = event(source,"mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x40001000")
    release = event(source,"munmap(0x40001000, 8) = 0")
    valid = allocation+release
    assert len(local_mappings(valid)) == 1
    bootstrap = event(source,"mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000")
    bootstrap += event(source,"munmap(0x7fff10000000, 4096) = 0")
    native = event(foreign,"mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000")
    native += event(foreign,"munmap(0x7fff20000000, 4096) = 0")
    assert local_mappings(bootstrap+native) == []
    mutations = [valid+release,
                 event(source,"munmap(0x40002000, 8) = 0"),
                 allocation+event(source,"munmap(0x40001000, 7) = 0"),
                 allocation+event(source,"munmap(0x40001000, 8) = -1 EINVAL (Invalid argument)"),
                 allocation,
                 allocation+event(foreign,"munmap(0x40001000, 8) = 0")]
    for mutation in mutations:
        try:
            local_mappings(mutation)
        except AssertionError:
            continue
        raise AssertionError(("ledger accepted invalid mutation",mutation))
    return 2+len(mutations)


def resources(directory):
    global DETAIL
    controls = ledger_controls()
    args = ["fixture", "8080", "--max-results=64"]
    trace = directory / "alloc.trace"
    command = ("strace","-qq","-i","-o",trace,"-e","trace=mmap,munmap")
    # A count-one control keeps argv/setup unchanged. Exactly seven live
    # allocation sites are reached: argument entries/storage, host/service
    # staging, native frame, exact address Vec, exact output Buffer reserve.
    small, events = run(directory, args, mode=16, count=1, command=command)
    assert endpoints(small.stdout) == synthetic(1) and events.count("F") == 1
    small_requests = local_mappings(trace.read_text())
    baseline, events = run(directory, args, mode=16, count=64, command=command)
    assert endpoints(baseline.stdout) == synthetic(64) and events.count("F") == 1
    requests = local_mappings(trace.read_text())
    roles = ("argument entries", "argument bytes", "host staging", "port staging", "hints/result frame", "address Vec", "output Buffer")
    assert len(requests) == len(small_requests) == len(roles), (requests,small_requests)
    assert [row[1] for row in requests] == [row[1] for row in small_requests], (requests,small_requests)
    sizes, small_sizes = [row[2] for row in requests], [row[2] for row in small_requests]
    # View<u8> is five native words (slice plus start/length). Both exact
    # result Vec requests must scale with count, while only output size varies.
    assert sizes[:5] == small_sizes[:5] == [len(args)*40, sum(map(len,args)), len("fixture")+1, len("8080")+1, 56], (sizes,small_sizes)
    assert small_sizes[5] > 0 and small_sizes[5] % 8 == 0 and sizes[5] == 64*small_sizes[5], (sizes,small_sizes)
    assert sizes[6] == len(baseline.stdout) and small_sizes[6] == len(small.stdout), (sizes,small_sizes)
    for index, (ordinal,instruction,length,_) in enumerate(requests):
        result, events = run(directory, args, 4, mode=16, count=64,
                             command=(*command,"-e",f"inject=mmap:error=ENOMEM:when={ordinal}"), expected_prefix=b"")
        assert "INJECTED" in trace.read_text()
        observed = local_mappings(trace.read_text())
        assert [row[:3] for row in observed] == [row[:3] for row in requests[:index+1]], (roles[index],observed)
        failed = [row for row in observed if not row[3].startswith("0x")]
        assert failed == [(ordinal,instruction,length,"-1")], (roles[index],observed)
        # Only address-Vec/output staging failures happen after native lookup.
        called = int(index >= 5)
        assert sum(row.startswith("G ") for row in events) == events.count("F") == called, (roles[index],events)
    for args, mode, count, status in ((["fixture","8080","--max-results=3"],1,0,2),
                                     (["fixture","8080","--max-output=0"],1,0,2),
                                     (["fixture","8080","--max-write-calls=0"],1,0,5),
                                     (["fixture","8080"],3,0,3), (["*","80"],1,0,2)):
        _, events = run(directory,args,status,mode=mode,count=count,command=command,expected_prefix=b"")
        local_mappings(trace.read_text())
        got = any(row.startswith("G ") for row in events)
        assert events.count("F") == int(got and mode != 3), events
    DETAIL = f" ledger-controls={controls} roles=" + ";".join(f"{role}:{size}" for role,size in zip(roles,sizes))


with tempfile.TemporaryDirectory(prefix="lanius_resolve_host_") as temporary:
    if MODE == "ledger-controls":
        DETAIL = f" ledger-controls={ledger_controls()}"
    else:
        {"matrix":matrix,"limits":limits,"io":io,"resources":resources}[MODE](Path(temporary))
print(f"resolve-host-{MODE} cases={CASES}{DETAIL}")
