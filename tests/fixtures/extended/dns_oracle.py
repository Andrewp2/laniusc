"""Independent dnspython 2.7.0 wire/semantic oracle. Test-only isolated venv."""
import random
import struct
import subprocess
import sys
import time
import dns.edns
import dns.message
import dns.name
import dns.rdata
import dns.rrset


def wire_name(labels):
    return b"".join(bytes([len(label)]) + label for label in labels) + b"\0"


def header(qd=0, an=0, ns=0, ar=0, flags=0x8180):
    return struct.pack("!6H", 18291, flags, qd, an, ns, ar)


def rr(name, kind, data, cls=1, ttl=0xFEDCBA98):
    return name + struct.pack("!HHIH", kind, cls, ttl, len(data)) + data


def tuple_line(line):
    fields = {}
    for item in line.split():
        if "=" in item:
            key, value = item.split("=", 1)
            fields.setdefault(key, []).append(value)
    return fields


def expected_report(packet):
    parsed = dns.message.from_wire(packet, one_rr_per_rrset=True)
    identity, flags, qd, an, ns, ar = struct.unpack_from("!6H", packet)
    out = [tuple_line(f"id={identity} flags={flags} qd={qd} an={an} ns={ns} ar={ar} rcode={parsed.rcode()}")]
    position = 12
    for _ in range(qd):
        name, used = dns.name.from_wire(packet, position)
        position += used
        kind, cls = struct.unpack_from("!HH", packet, position)
        position += 4
        out.append(tuple_line(f"name={name.to_wire().hex()} type={kind} class={cls}"))
    for section, count in enumerate((an, ns, ar), 1):
        for _ in range(count):
            name, used = dns.name.from_wire(packet, position)
            position += used
            kind, cls, ttl, size = struct.unpack_from("!HHIH", packet, position)
            position += 10
            raw = packet[position:position + size]
            row = tuple_line(f"section={section} name={name.to_wire().hex()} type={kind} class={cls} ttl={ttl} data={raw.hex()}")
            if kind == 41:
                row.update(tuple_line(f"udp={cls} version={(ttl >> 16) & 255} ext_rcode={ttl >> 24} edns_flags={ttl & 65535}"))
                at = 0
                while at < size:
                    code, length = struct.unpack_from("!HH", raw, at)
                    at += 4
                    row.setdefault("option", []).append(f"{code}:{raw[at:at+length].hex()}")
                    at += length
            else:
                value = dns.rdata.from_wire(cls, kind, packet, position, size)
                if cls == 1 and kind in (1, 28):
                    row["A" if kind == 1 else "AAAA"] = [raw.hex()]
                if kind in (2, 5, 12):
                    row["domain"] = [value.target.to_wire().hex()]
                if kind == 15:
                    row["preference"] = [str(value.preference)]
                    row["exchange"] = [value.exchange.to_wire().hex()]
                if kind == 6:
                    row["primary"], row["mailbox"] = [value.mname.to_wire().hex()], [value.rname.to_wire().hex()]
                    for field in ("serial", "refresh", "retry", "expire", "minimum"):
                        row[field] = [str(getattr(value, field))]
                if kind == 16:
                    row["txt"] = [part.hex() for part in value.strings]
            out.append(row)
            position += size
    assert position == len(packet)
    return out


class Runner:
    def __init__(self, executable):
        self.executable = executable
        self.count = 0
        self.native = 0.0

    def call(self, args, packet, status=0):
        before = time.monotonic()
        result = subprocess.run([self.executable, *args], input=packet, capture_output=True, timeout=20)
        self.native += time.monotonic() - before
        self.count += 1
        assert result.returncode == status, (args, result.returncode, result.stderr, packet.hex())
        if status == 0:
            assert not result.stderr, result.stderr
        else:
            assert not result.stdout, (args, result.stdout[:100])
        return result

    def inspect(self, packet, args=()):
        result = self.call(["inspect", *args], packet)
        actual = [tuple_line(line) for line in result.stdout.decode("ascii").splitlines()]
        assert actual == expected_report(packet), (actual, expected_report(packet), packet.hex())
        return result.stdout

    def summary(self, label):
        print(f"{label} cases={self.count} native_ms={self.native*1000:.0f}")


def message(seed):
    rng = random.Random(seed)
    labels = [b"MiXeD" + bytes([seed]), b"example"]
    if seed % 4 == 0:
        labels = [b"\0\xff.\\Az", bytes(range(32, 64))]
    if seed == 1:
        labels = [b"x" * 63, b"y" * 63, b"z" * 63, b"Q" * 61]
    name = dns.name.Name(tuple(labels) + (b"",))
    target = dns.name.Name((b"ns\0\xff",) + tuple(labels[1:]) + (b"",))
    target_wire = target.to_wire()
    msg = dns.message.Message(seed * 1703 & 65535)
    msg.flags = 0x81B0
    msg.question = [dns.rrset.RRset(name, 1, 1), dns.rrset.RRset(target, 1, 28)]
    entries = [
        (1, bytes([192, 0, 2, seed])),
        (28, rng.randbytes(16)),
        (2, target_wire), (5, target_wire), (12, target_wire),
        (15, struct.pack("!H", 65535-seed) + target_wire),
        (6, target_wire + name.to_wire() + struct.pack("!5I", 0xFFFFFFFF, 0, 0x80000000, 1, 0xFFFFFFFF)),
        (16, b"\0\3\0\xffZ" + bytes([255]) + bytes(range(255))),
        (65000, b"\xc0\xff\x00" + rng.randbytes(13)),
    ]
    for index, (kind, raw) in enumerate(entries):
        value = dns.rdata.from_wire(1, kind, raw, 0, len(raw))
        row = dns.rrset.from_rdata(name if index % 2 else target, 0xFFFFFFFF, value)
        [msg.answer, msg.authority, msg.additional][index % 3].append(row)
    msg.use_edns(edns=seed % 2, ednsflags=0x8001, payload=[1, 512, 1232, 65535][seed % 4],
                 options=[dns.edns.GenericOption(65001, b"\x00\xff"), dns.edns.GenericOption(12, b"")])
    msg.set_rcode(16 + seed % 16)
    return msg.to_wire(max_size=65535)


def matrix(executable):
    run = Runner(executable)
    for seed in range(24):
        run.inspect(message(seed))
    # Pointer-to-root and pointer-to-previous-pointer are valid and remain fused.
    root = header(qd=3, flags=0) + b"\0\0\1\0\1" + b"\xc0\x0c\0\1\0\1" + b"\xc0\x11\0\1\0\1"
    run.inspect(root)
    # Every possible label byte is covered without interpreting UTF-8 or dots.
    for start in range(0, 256, 32):
        name = wire_name([bytes((i % 256) for i in range(start, start+32))])
        run.inspect(header(qd=1, flags=0x0130) + name + struct.pack("!HH", 255, 65535))
    run.summary("dnspython-matrix")


def query(executable):
    run = Runner(executable)
    for name in [".", "", "Example.COM", "one.two.", ".".join(["x"*63,"y"*63,"z"*63,"q"*61])]:
        packet = run.call(["query", "--id", "65535", "--type", "28", "--class", "255", name], b"").stdout
        parsed = dns.message.from_wire(packet)
        want = dns.name.from_text(name or ".")
        assert parsed.id == 65535 and parsed.flags == 256 and len(parsed.question) == 1
        assert parsed.question[0].name == want and parsed.question[0].rdtype == 28 and parsed.question[0].rdclass == 255
        run.inspect(packet)
    for seed in range(12):
        raw = wire_name([bytes([0,255,46,92,seed,65]), bytes(range(seed,seed+31))])
        packet = run.call(["query", "--wire-name", "--udp-size", "1232", "--dnssec", "--type", "65000"], raw).stdout
        parsed = dns.message.from_wire(packet)
        assert parsed.question[0].name.to_wire() == raw and parsed.question[0].rdtype == 65000
        assert parsed.edns == 0 and parsed.payload == 1232 and parsed.ednsflags == 0x8000
        run.inspect(packet)
    for args in [[], ["bad"], ["inspect", "x"], ["query"], ["query", "a", "b"], ["inspect", "--id", "1"],
                 ["query", "--wire-name", "x"], ["query", "--dnssec", "x"], ["query", ".."], ["query", ".a"],
                 ["query", "a..b"], ["query", "x"*64], ["query", ".".join(["x"*63]*4)], ["--unknown"]]:
        run.call(args, b"", 2)
    for option, maximum in [("--id",65535),("--type",65535),("--class",65535),("--udp-size",65535),
                            ("--max-input",65535),("--max-output",1048576),("--max-work",16777216),("--max-records",262140)]:
        for bad in ["-1", "+1", "", str(maximum+1), "1x", "2147483648"]:
            run.call(["query", option, bad, "x"], b"", 2)
    run.call(["query"] + ["--dnssec"] * 32, b"", 2)
    run.call(["query", "x"*8193], b"", 2)
    run.summary("query-and-arguments")


def invalid_cases():
    name = wire_name([b"abc", b"example"])
    question = name + b"\0\1\0\1"
    base = header(qd=1, an=1) + question
    cases = []
    for raw in [b"\xc0\x0c", b"\xc0\x0e", b"\xc0\x00", b"\xff\xff", b"\xc0", b"\x40", b"\x80", b"\4test\xc0\x0c"]:
        cases.append(header(qd=1) + raw + b"\0\1\0\1")
    # Referencing label payload, QTYPE zero byte, or unknown RDATA is forbidden.
    cases.append(base + rr(b"\xc0\x0d",1,b"\1\2\3\4"))
    cases.append(base + rr(struct.pack("!H",0xC000+12+len(name)),1,b"\1\2\3\4"))
    unknown_at = len(base) + 1 + 10
    cases.append(header(qd=1,an=2)+question+rr(b"\0",65000,b"\1x\0")+rr(struct.pack("!H",0xC000+unknown_at),1,b"\1\2\3\4"))
    for kind, raw in [(1,b"123"),(28,b"x"*15),(2,b"\0x"),(5,b"\xc0"),(12,b"\1x"),
                      (15,b"\0\1"),(6,b"\0\0"+b"x"*19),(16,b""),(16,b"\3ab")]:
        cases.append(base+rr(b"\xc0\x0c",kind,raw))
    # Declared RDATA cannot consume bytes from a following record.
    cases.append(header(qd=1,an=2)+question+rr(b"\xc0\x0c",5,b"\xc0")+rr(b"\0",1,b"\1\2\3\4"))
    opt = rr(b"\0",41,b"",1232,0)
    cases.extend([header(an=1)+opt, header(ar=1)+rr(name,41,b"",1232,0),
                  header(ar=2)+opt+opt, header(ar=1)+rr(b"\0",41,b"\0\1\0",1232,0),
                  header(ar=1)+rr(b"\0",41,b"\0\1\0\2x",1232,0)])
    cases.append(header(qd=1)+wire_name([b"a"*63]*4)+b"\0\1\0\1")
    cases.append(header(flags=0x0040))
    cases.append(header(flags=0x0800))
    cases.append(header()+b"trailing")
    return cases


def failures(executable):
    run = Runner(executable)
    good = message(3)
    # Truncation is diagnosed before any inspector output, including late RDATA.
    for size in list(range(min(96,len(good)))) + [len(good)-1,len(good)-2,len(good)-12]:
        result = run.call(["inspect"], good[:size], 2)
        assert result.stderr.startswith(b"dns-message: truncated byte="), (size,result.stderr)
    for packet in invalid_cases():
        before = time.monotonic()
        result = subprocess.run([executable,"inspect"],input=packet,capture_output=True,timeout=20)
        run.native += time.monotonic() - before
        run.count += 1
        assert result.returncode in (2,3) and not result.stdout, (result,packet.hex())
    report = run.inspect(good)
    for option, value in [("--max-input",len(good)-1),("--max-records",1),("--max-work",0),("--max-output",len(report)-1)]:
        run.call(["inspect",option,str(value)],good,3)
    assert run.inspect(good,["--max-input",str(len(good)),"--max-output",str(len(report))]) == report
    # Long valid pointer chains are bounded even though each expands to root.
    for count,status in [(129,0),(130,3)]:
        packet = bytearray(header(qd=count,flags=0))
        previous = 12
        packet.extend(b"\0\0\1\0\1")
        for _ in range(count-1):
            at=len(packet)
            packet.extend(struct.pack("!H",0xC000+previous)+b"\0\1\0\1")
            previous=at
        if status==0:
            run.inspect(bytes(packet))
        else:
            run.call(["inspect"],bytes(packet),status)
    run.summary("malformed-limits")


def edns_root(executable):
    run = Runner(executable)
    packet = header(qd=1, ar=1, flags=0) + b"\0\0\1\0\1" + rr(b"\xc0\x0c", 41, b"", 1232, 0)
    run.inspect(packet)
    run.summary("compressed-edns-root")


def scale(executable):
    run = Runner(executable)
    name = wire_name([b"scale",b"example"])
    packet = header(qd=1,an=1600)+name+b"\0\1\0\1"
    packet += b"".join(rr(b"\xc0\x0c",1,struct.pack("!I",i),ttl=i) for i in range(1600))
    run.inspect(packet,["--max-output","1048576"])
    run.summary(f"scale bytes={len(packet)} records=1600")


if __name__ == "__main__":
    assert dns.__version__ == "2.7.0", dns.__version__
    mode = sys.argv[1]
    if mode in {"matrix","query","failures","scale","edns_root"}:
        globals()[mode](sys.argv[2])
    elif mode == "packet":
        sys.stdout.buffer.write(message(3))
    else:
        raise ValueError(mode)
