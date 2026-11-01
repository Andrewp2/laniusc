"""Fake DNS servers on loopback for stub-dig. Each server answers UDP and TCP
on one port and logs every query. Some names misbehave on 127.0.0.1 only:
SERVFAIL, REFUSED, silence, malformed records, wrong IDs and questions,
spoofed sources, truncation and broken TCP frames. The expected output of
every lookup is written out here independently of the Lanius code.
Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

HELP = (b"Usage: stub-dig [--resolv-conf PATH] [--hosts PATH | --no-hosts] [--port N] [--family any|ipv4|ipv6]"
        b" [--timeout-ms N] [--attempts N] [--deadline-ms N] NAME\n")
INVALID = b"stub-dig: invalid arguments; see --help errno=0\n"
S1, S2, S3 = "127.0.0.1", "127.0.0.2", "127.0.0.3"
A, AAAA, CNAME = 1, 28, 5
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def wire(name):
    return b"".join(bytes([len(label)]) + label.encode() for label in name.split(".") if label) + b"\0"


def record(owner, rtype, ttl, data):
    return wire(owner) + struct.pack(">HHIH", rtype, 1, ttl, len(data)) + data


def a(owner, ttl, text):
    return record(owner, A, ttl, socket.inet_pton(socket.AF_INET, text))


def aaaa(owner, ttl, text):
    return record(owner, AAAA, ttl, socket.inet_pton(socket.AF_INET6, text))


def cname(owner, ttl, target):
    return record(owner, CNAME, ttl, wire(target))


def parse_query(packet):
    ident, flags, qd, an, ns, ar = struct.unpack(">HHHHHH", packet[:12])
    labels, at = [], 12
    while packet[at]:
        labels.append(packet[at + 1:at + 1 + packet[at]].decode().lower())
        at += packet[at] + 1
    qtype, qclass = struct.unpack(">HH", packet[at + 1:at + 5])
    return ident, ".".join(labels), qtype, packet[12:at + 5], ar > 0


def response(ident, question, rcode=0, answers=(), tc=False):
    flags = 0x8180 | rcode | (0x0200 if tc else 0)
    return struct.pack(">HHHHHH", ident, flags, 1, len(answers), 0, 0) + question + b"".join(answers)


BIG = [f"198.51.100.{n}" for n in range(1, 41)]


def zone(name, qtype):
    """(rcode, answers) for a well-behaved server."""
    www4, www6 = a("www.example.test", 300, "192.0.2.1"), aaaa("www.example.test", 200, "2001:db8::1")
    www = {A: [www4], AAAA: [www6]}
    if name == "www.example.test":
        return 0, www[qtype]
    if name == "alias.example.test":
        return 0, [cname(name, 60, "www.example.test")] + www[qtype]
    if name == "chain.example.test":
        return 0, [cname(name, 30, "alias.example.test"), cname("alias.example.test", 60, "www.example.test")] + www[qtype]
    if name == "v4only.example.test":
        return 0, [a(name, 120, "192.0.2.4")] if qtype == A else []
    if name == "other.example.test":
        return 0, [a("unrelated.example.test", 120, "192.0.2.66")]
    if name == "big.example.test":
        return 0, [a(name, 100, ip) for ip in BIG] if qtype == A else []
    if name.startswith("flaky-") and name.endswith(".example.test"):
        return 0, [a(name, 50, "192.0.2.9")] if qtype == A else [aaaa(name, 50, "2001:db8::9")]
    return 3, []


class Servers:
    def __init__(self):
        self.log, self.lock, self.sockets = [], threading.Lock(), []
        self.v6 = socket.has_ipv6
        for _ in range(50):
            try:
                self.bind()
                break
            except OSError:
                for s in self.sockets:
                    s.close()
                self.sockets = []
        else:
            raise RuntimeError("no free port")
        for s in self.sockets:
            threading.Thread(target=self.serve_udp if s.type == socket.SOCK_DGRAM else self.serve_tcp, args=(s,), daemon=True).start()

    def bind(self):
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.bind((S1, 0))
        self.port = probe.getsockname()[1]
        self.sockets.append(probe)
        hosts = [(socket.AF_INET, S2)] + ([(socket.AF_INET6, "::1")] if self.v6 else [])
        for family, host in hosts:
            u = socket.socket(family, socket.SOCK_DGRAM)
            self.sockets.append(u)
            try:
                u.bind((host, self.port))
            except OSError:
                if family == socket.AF_INET6:
                    self.v6 = False
                    self.sockets.pop().close()
                    continue
                raise
        for family, host in [(socket.AF_INET, S1)] + hosts:
            if family == socket.AF_INET6 and not self.v6:
                continue
            t = socket.socket(family, socket.SOCK_STREAM)
            t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sockets.append(t)
            t.bind((host, self.port))
            t.listen(16)

    def note(self, server, transport, name, qtype, opt):
        with self.lock:
            self.log.append((server, transport, name, qtype, opt))

    def take_log(self):
        with self.lock:
            log, self.log = self.log, []
        return log

    def serve_udp(self, s):
        server = s.getsockname()[0]
        while True:
            packet, peer = s.recvfrom(4096)
            ident, name, qtype, question, opt = parse_query(packet)
            self.note(server, "udp", name, qtype, opt)
            for kind, data in self.udp(server, ident, name, qtype, question):
                if kind == "spoof":
                    other = socket.socket(s.family, socket.SOCK_DGRAM)
                    other.sendto(data, peer)
                    other.close()
                else:
                    s.sendto(data, peer)

    def udp(self, server, ident, name, qtype, question):
        rcode, answers = zone(name, qtype)
        good = response(ident, question, rcode, answers)
        if name == "dead.example.test" or (server == S1 and name.startswith("flaky-drop.")):
            return []
        if name == "big.example.test" and qtype == A:
            return [("send", response(ident, question, 0, [], tc=True))]
        if server == S1:
            if name.startswith("flaky-servfail."):
                return [("send", response(ident, question, 2))]
            if name.startswith("flaky-refused."):
                return [("send", response(ident, question, 5))]
            if name.startswith("flaky-garbage."):
                return [("send", struct.pack(">HHHHHH", ident, 0x8180, 1, 1, 0, 0) + question + wire(name) + b"\x00\x01\x00")]
            if name.startswith("flaky-wrongid."):
                own = [a(name, 50, "192.0.2.8")] if qtype == A else [aaaa(name, 50, "2001:db8::8")]
                other_question = wire("decoy.example.test") + question[-4:]
                return [("send", response(ident ^ 1, question, 0, own)), ("send", response(ident, other_question, 0, own)),
                        ("spoof", response(ident, question, 0, own)), ("send", response(ident, question, 0, own))]
            if name.startswith("flaky-tcp"):
                return [("send", response(ident, question, 0, [], tc=True))]
        return [("send", good)]

    def serve_tcp(self, s):
        server = s.getsockname()[0]
        while True:
            conn, _ = s.accept()
            threading.Thread(target=self.tcp_conn, args=(conn, server), daemon=True).start()

    def tcp_conn(self, conn, server):
        with conn:
            try:
                head = b""
                while len(head) < 2:
                    more = conn.recv(2 - len(head))
                    if not more:
                        return
                    head += more
                size = struct.unpack(">H", head)[0]
                packet = b""
                while len(packet) < size:
                    more = conn.recv(size - len(packet))
                    if not more:
                        return
                    packet += more
                ident, name, qtype, question, opt = parse_query(packet)
                self.note(server, "tcp", name, qtype, opt)
                rcode, answers = zone(name, qtype)
                body = response(ident, question, rcode, answers)
                if server == S1 and name.startswith("flaky-tcpeof."):
                    conn.sendall(struct.pack(">H", len(body)) + body[:10])
                    return
                if server == S1 and name.startswith("flaky-tcpid."):
                    body = response(ident ^ 0x55, question, rcode, answers)
                if server == S1 and name.startswith("flaky-tcpshort."):
                    conn.sendall(struct.pack(">H", 5) + body[:5])
                    return
                if name == "dead.example.test":
                    time.sleep(5)
                    return
                conn.sendall(struct.pack(">H", len(body)) + body)
            except OSError:
                pass


def run(exe, *args, timeout=30):
    out = subprocess.run([exe, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    return out


def exchange(candidate, qtype, server, port, transport, outcome, discarded=0):
    shown = f"[{server}]:{port}" if ":" in server else f"{server}:{port}"
    kind = "AAAA" if qtype == AAAA else "A"
    return f";; exchange\t{candidate}\t{kind}\t{shown}\t{transport}\t{outcome}\tdiscarded={discarded}"


def found(source, name, canonical, ttl, addresses):
    lines = [f";; status\tfound\tsource={source}", f";; name\t{name}", f";; canonical\t{canonical}"]
    for address in addresses:
        kind = "AAAA" if ":" in address else "A"
        lines.append(f"{canonical}.\t{ttl}\tIN\t{kind}\t{address}")
    return lines


def text(lines):
    return ("\n".join(lines) + "\n").encode()


class Bench:
    def __init__(self, exe, directory, servers):
        self.exe, self.directory, self.servers, self.count = exe, directory, servers, 0

    def conf(self, body):
        self.count += 1
        path = os.path.join(self.directory, f"resolv{self.count}.conf")
        with open(path, "w") as handle:
            handle.write(body)
        return path

    def dig(self, body, *args, hosts=None):
        extra = ["--no-hosts"] if hosts is None else ["--hosts", hosts]
        self.servers.take_log()
        began = time.monotonic()
        out = run(self.exe, "--resolv-conf", self.conf(body), "--port", str(self.servers.port), *extra, *args)
        return out, self.servers.take_log(), time.monotonic() - began


def cli(exe):
    out = run(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    for args in ([], ["a", "b"], ["--port", "0", "x"], ["--port", "65536", "x"], ["--family", "ipv5", "x"], ["--timeout-ms", "0", "x"],
                 ["--attempts", "9", "x"], ["--hosts", "h", "--no-hosts", "x"], ["--port", "53", "--port", "53", "x"], ["--bogus", "x"],
                 ["--help", "x"], ["--deadline-ms"], ["--deadline-ms", "600001", "x"]):
        out = run(exe, *args)
        case(out.returncode == 2 and out.stdout == b"" and out.stderr == INVALID, args, out)
    for name in ("a..b", "x" * 64 + ".test", "bad name", ".", ".lead", "a" * 254):
        out = run(exe, "--no-hosts", "--resolv-conf", "/dev/null", name)
        case(out.returncode == 2 and out.stdout == b"" and out.stderr == b"stub-dig: invalid name errno=0\n", name, out)
    out = run(exe, "--resolv-conf", "/nonexistent/resolv.conf", "x")
    case(out.returncode == 4 and out.stderr == b"stub-dig: cannot read resolv.conf errno=2\n", out)
    out = run(exe, "--resolv-conf", "/dev/null", "--hosts", "/nonexistent/hosts", "x")
    case(out.returncode == 4 and out.stderr == b"stub-dig: cannot read hosts errno=2\n", out)
    for args, address in ((["192.0.2.7"], "192.0.2.7"), (["--family", "ipv6", "2001:db8::5"], "2001:db8::5"), (["192.0.2.8."], "192.0.2.8")):
        out = run(exe, "--no-hosts", "--resolv-conf", "/dev/null", *args)
        case(out.returncode == 0 and out.stdout == text(found("numeric", address, address, 0, [address])), args, out)
    out = run(exe, "--no-hosts", "--resolv-conf", "/dev/null", "--family", "ipv4", "2001:db8::5")
    case(out.returncode == 1 and out.stdout == text([";; status\tnodata\tsource=numeric", ";; name\t2001:db8::5"]), out)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        hosts = os.path.join(directory, "hosts")
        with open(hosts, "w") as handle:
            handle.write("# 10.9.9.9 commented.test\n10.1.2.3\tHostOnly.test hostalias # trailing\nbogus hostonly.test\n"
                         "::10 hostonly.test\n10.1.2.3 hostonly.test\n10.4.4.4 second.test\n")
        conf = os.path.join(directory, "resolv.conf")
        with open(conf, "w") as handle:
            handle.write("nameserver 127.0.0.1\n")
        for args, name, canonical, addresses in (
                (["hostonly.test"], "hostonly.test", "HostOnly.test", ["10.1.2.3", "::10"]),
                (["HOSTALIAS."], "HOSTALIAS", "HostOnly.test", ["10.1.2.3"]),
                (["--family", "ipv6", "hostonly.test"], "hostonly.test", "hostonly.test", ["::10"]),
                (["--family", "ipv4", "second.test"], "second.test", "second.test", ["10.4.4.4"])):
            out = run(exe, "--resolv-conf", conf, "--port", "1", "--hosts", hosts, *args)
            case(out.returncode == 0 and out.stdout == text(found("hosts", name, canonical, 0, addresses)), args, out)


def dns(exe):
    servers = Servers()
    port = servers.port
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        bench = Bench(exe, directory, servers)
        two = "nameserver 127.0.0.1\nnameserver 127.0.0.2\n"
        quick = ["--timeout-ms", "200", "--attempts", "1"]

        def check(body, args, lines, code, log=None, limit=None):
            out, seen, took = bench.dig(body, *quick, *args)
            case(out.returncode == code and out.stderr == b"" and out.stdout == text(lines), args, out.stdout.decode(), lines)
            if log is not None:
                case(seen == log, args, seen, log)
            if limit is not None:
                case(took < limit, args, took)
            return seen

        www = found("dns", "www.example.test", "www.example.test", 200, ["192.0.2.1", "2001:db8::1"])
        ok = [exchange("www.example.test", A, S1, port, "udp", "answer 1"), exchange("www.example.test", AAAA, S1, port, "udp", "answer 1")]
        check(two, ["www.example.test"], ok + www, 0, [(S1, "udp", "www.example.test", A, False), (S1, "udp", "www.example.test", AAAA, False)])
        check(two, ["--family", "ipv4", "www.example.test."],
              [ok[0]] + found("dns", "www.example.test", "www.example.test", 300, ["192.0.2.1"]), 0)
        for name, ttl in (("alias.example.test", 60), ("chain.example.test", 30)):
            check(two, [name], [exchange(name, A, S1, port, "udp", "answer 1"), exchange(name, AAAA, S1, port, "udp", "answer 1")]
                  + found("dns", name, "www.example.test", ttl, ["192.0.2.1", "2001:db8::1"]), 0)
        check(two, ["v4only.example.test"], [exchange("v4only.example.test", A, S1, port, "udp", "answer 1"), exchange("v4only.example.test", AAAA, S1, port, "udp", "nodata")]
              + found("dns", "v4only.example.test", "v4only.example.test", 120, ["192.0.2.4"]), 0)
        search = two + "search corp.test example.test\n"
        check(search, ["--family", "ipv6", "v4only.example.test"],
              [exchange("v4only.example.test", AAAA, S1, port, "udp", "nodata"), exchange("v4only.example.test.corp.test", AAAA, S1, port, "udp", "nxdomain"),
               exchange("v4only.example.test.example.test", AAAA, S1, port, "udp", "nxdomain"), ";; status\tnodata\tsource=dns", ";; name\tv4only.example.test"], 1)
        # Answers owned by another name are not the question's records.
        check(two, ["--family", "ipv4", "other.example.test"], [exchange("other.example.test", A, S1, port, "udp", "nodata"),
              ";; status\tnodata\tsource=dns", ";; name\tother.example.test"], 1)
        # Search order: fewer dots than ndots tries the search list first.
        check(search, ["www"], [exchange("www.corp.test", A, S1, port, "udp", "nxdomain"), exchange("www.example.test", A, S1, port, "udp", "answer 1"),
              exchange("www.example.test", AAAA, S1, port, "udp", "answer 1")] + www, 0,
              [(S1, "udp", "www.corp.test", A, False), (S1, "udp", "www.example.test", A, False), (S1, "udp", "www.example.test", AAAA, False)])
        check(search + "options ndots:3\n", ["--family", "ipv4", "www.example.test"],
              [exchange("www.example.test.corp.test", A, S1, port, "udp", "nxdomain"), exchange("www.example.test.example.test", A, S1, port, "udp", "nxdomain"),
               exchange("www.example.test", A, S1, port, "udp", "answer 1")] + found("dns", "www.example.test", "www.example.test", 300, ["192.0.2.1"]), 0)
        check(search, ["www.corp.test."], [exchange("www.corp.test", A, S1, port, "udp", "nxdomain"), ";; status\tnxdomain\tsource=dns", ";; name\twww.corp.test"], 1)
        check(search, ["--family", "ipv4", "missing"], [exchange("missing.corp.test", A, S1, port, "udp", "nxdomain"), exchange("missing.example.test", A, S1, port, "udp", "nxdomain"),
              exchange("missing", A, S1, port, "udp", "nxdomain"), ";; status\tnxdomain\tsource=dns", ";; name\tmissing"], 1)
        # Truncated UDP falls back to TCP on the same server.
        check(two, ["big.example.test"], [exchange("big.example.test", A, S1, port, "tcp", "answer 40"), exchange("big.example.test", AAAA, S1, port, "udp", "nodata")]
              + found("dns", "big.example.test", "big.example.test", 100, BIG), 0,
              [(S1, "udp", "big.example.test", A, False), (S1, "tcp", "big.example.test", A, False), (S1, "udp", "big.example.test", AAAA, False)])
        # Failures on the first server move to the second, for each type.
        for label, outcome, transport in (("servfail", "rcode 2", "udp"), ("refused", "rcode 5", "udp"), ("drop", "timeout", "udp"), ("garbage", "malformed", "udp"),
                                          ("tcpeof", "eof", "tcp"), ("tcpid", "mismatch", "tcp"), ("tcpshort", "frame-length", "tcp")):
            name = f"flaky-{label}.example.test"
            lines = []
            for qtype in (A, AAAA):
                lines += [exchange(name, qtype, S1, port, transport, outcome), exchange(name, qtype, S2, port, "udp", "answer 1")]
            check(two, [name], lines + found("dns", name, name, 50, ["192.0.2.9", "2001:db8::9"]), 0, limit=3)
        # A wrong ID and a wrong question are discarded (two each); the spoofed
        # source never arrives, because the connected socket filters it.
        name = "flaky-wrongid.example.test"
        check(two, [name], [exchange(name, A, S1, port, "udp", "answer 1", 2), exchange(name, AAAA, S1, port, "udp", "answer 1", 2)]
              + found("dns", name, name, 50, ["192.0.2.8", "2001:db8::8"]), 0)
        # No server answers: every attempt is listed and the status is failed.
        lines = [exchange("dead.example.test", A, server, port, "udp", "timeout") for _ in range(2) for server in (S1, S2)]
        out, _, took = bench.dig(two, "--timeout-ms", "150", "--attempts", "2", "dead.example.test")
        case(out.returncode == 3 and out.stdout == text(lines + [";; status\tfailed\tsource=dns", ";; name\tdead.example.test"]) and 0.6 <= took < 3, out.stdout.decode(), took)
        # A total deadline bounds the whole lookup.
        out, _, took = bench.dig(two, "--timeout-ms", "1000", "--attempts", "8", "--deadline-ms", "300", "dead.example.test")
        case(out.returncode == 3 and b";; status\tfailed" in out.stdout and took < 2, out, took)
        # A refused port is an explicit I/O error before the next server.
        check("nameserver 127.0.0.3\nnameserver 127.0.0.1\n", ["--family", "ipv4", "www.example.test"],
              [exchange("www.example.test", A, S3, port, "udp", "io 111"), exchange("www.example.test", A, S1, port, "udp", "answer 1")]
              + found("dns", "www.example.test", "www.example.test", 300, ["192.0.2.1"]), 0)
        # Options: use-vc, edns0, rotate, no-aaaa; malformed lines are skipped.
        seen = check(two + "options use-vc\n", ["www.example.test"], [line.replace("\tudp\t", "\ttcp\t") for line in ok] + www, 0)
        case([entry[1] for entry in seen] == ["tcp", "tcp"], seen)
        check(two + "options edns0\n", ["www.example.test"], ok + www, 0, [(S1, "udp", "www.example.test", A, True), (S1, "udp", "www.example.test", AAAA, True)])
        check(two + "options rotate\n", ["www.example.test"], [ok[0], exchange("www.example.test", AAAA, S2, port, "udp", "answer 1")] + www, 0)
        check(two + "options no-aaaa\n", ["www.example.test"], [ok[0]] + found("dns", "www.example.test", "www.example.test", 300, ["192.0.2.1"]), 0)
        messy = ("; comment\n# comment\nnameserver bogus\nnameserver\nfrobnicate yes\noptions ndots:x timeout:abc wat\n"
                 "nameserver 127.0.0.2\nnameserver 127.0.0.1\nnameserver 127.0.0.3\nnameserver 127.0.0.4\nsearch corp.test\ndomain example.test\n")
        check(messy, ["--family", "ipv4", "flaky-servfail"], [exchange("flaky-servfail.example.test", A, S2, port, "udp", "answer 1")]
              + found("dns", "flaky-servfail.example.test", "flaky-servfail.example.test", 50, ["192.0.2.9"]), 0)
        # An IPv6 nameserver.
        if servers.v6:
            check("nameserver ::1\n", ["--family", "ipv6", "www.example.test"], [exchange("www.example.test", AAAA, "::1", port, "udp", "answer 1")]
                  + found("dns", "www.example.test", "www.example.test", 200, ["2001:db8::1"]), 0)
        else:
            case(True)
        # Hosts answer first; with --no-hosts the same name goes to DNS.
        hosts = os.path.join(directory, "hosts")
        with open(hosts, "w") as handle:
            handle.write("10.1.2.3 www.example.test\n")
        out, seen, _ = bench.dig(two, *quick, "www.example.test", hosts=hosts)
        case(out.returncode == 0 and out.stdout == text(found("hosts", "www.example.test", "www.example.test", 0, ["10.1.2.3"])) and seen == [], out, seen)


MODES = {"cli": cli, "dns": dns}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"stub-dig-{mode} cases={cases}")
