"""Authored URL mapping/error catalog, not a second URL parser.

The native process handles the public API. This peer supplies literal expected
authority, identity, target and diagnostic projections. ipaddress only packs
the independently supplied expected IP identity; it never parses an input URL.
"""
from dataclasses import dataclass
import ipaddress
from pathlib import Path
import struct
import subprocess
import sys

MASK = (1 << 64) - 1
MAGIC = 0x55524C


def W(*values):
    return struct.pack("<" + "Q" * len(values), *(value & MASK for value in values))


def B(value):
    return W(len(value)) + value


@dataclass(frozen=True)
class Case:
    name: str
    raw: bytes
    answer: bytes
    url_cap: int = 16384
    target_cap: int = 8192
    malformed: int = 0


def good(name, raw, host, authority, target, *, secure=False, port=None, ip=None,
         url_cap=16384, target_cap=8192):
    address = None if ip is None else ipaddress.ip_address(ip)
    kind = 0 if address is None else address.version
    port = (443 if secure else 80) if port is None else port
    answer = W(MAGIC, 0, int(secure), kind, port) + B(host) + B(authority) + B(target)
    answer += W(address is not None)
    if address is not None:
        answer += B(address.packed)
    return Case(name, raw, answer, url_cap, target_cap)


def bad(name, raw, kind, offset=-1, *, syntax=None, url_cap=16384,
        target_cap=8192, malformed=0):
    answer = W(MAGIC, 1, kind, offset, syntax is not None)
    if syntax is not None:
        answer += W(*syntax)
    return Case(name, raw, answer, url_cap, target_cap, malformed)


# Every expected component is independent literal data. This small catalog
# targets distinctions introduced by the URL policy, not generic URI coverage.
CASES = [
    good("default-path", b"http://Example.com", b"Example.com", b"Example.com", b"/"),
    good("mixed-scheme-query-fragment", b"HTTPS://a?q=x#not-sent", b"a", b"a", b"/?q=x", secure=True),
    good("explicit-default-spelling", b"http://a:00080/", b"a", b"a:00080", b"/", port=80),
    good("explicit-secure-default", b"https://A:443", b"A", b"A:443", b"/", secure=True),
    good("port-one", b"http://a:1/", b"a", b"a:1", b"/", port=1),
    good("port-maximum", b"https://a:065535/", b"a", b"a:065535", b"/", secure=True, port=65535),
    good("single-label", b"http://LOCALHOST", b"LOCALHOST", b"LOCALHOST", b"/"),
    good("ascii-alabel", b"http://xn--p1ai.example", b"xn--p1ai.example", b"xn--p1ai.example", b"/"),
    good("numeric-prefix-dns", b"http://0xface.example", b"0xface.example", b"0xface.example", b"/"),
    good("digits-in-dns", b"http://123a.456", b"123a.456", b"123a.456", b"/"),
    good("ipv4", b"http://127.0.0.1", b"127.0.0.1", b"127.0.0.1", b"/", ip="127.0.0.1"),
    good("ipv4-zero", b"https://0.0.0.0?", b"0.0.0.0", b"0.0.0.0", b"/?", secure=True, ip="0.0.0.0"),
    good("ipv4-largest", b"http://255.255.255.255:80/x", b"255.255.255.255", b"255.255.255.255:80", b"/x", ip="255.255.255.255"),
    good("ipv6", b"https://[::1]:00443", b"::1", b"[::1]:00443", b"/", secure=True, ip="::1"),
    good("ipv6-spelling", b"http://[2001:0DB8:0:0:0:0:0:1]/x", b"2001:0DB8:0:0:0:0:0:1", b"[2001:0DB8:0:0:0:0:0:1]", b"/x", ip="2001:db8::1"),
    good("ipv6-mapped", b"http://[::ffff:192.0.2.1]/", b"::ffff:192.0.2.1", b"[::ffff:192.0.2.1]", b"/", ip="::ffff:192.0.2.1"),
    good("literal-path", b"http://a/a%2Fb/../c//?q=%25#fragment", b"a", b"a", b"/a%2Fb/../c//?q=%25"),
    good("empty-query", b"http://a/path?", b"a", b"a", b"/path?"),
    good("query-delimiters", b"http://a?x=/a?b:@&v=+;#x", b"a", b"a", b"/?x=/a?b:@&v=+;"),
    good("empty-fragment", b"http://a/#", b"a", b"a", b"/"),
    good("target-cap-exact", b"http://a/ab?c#long-fragment", b"a", b"a", b"/ab?c", target_cap=5),
    good("url-cap-exact", b"http://a", b"a", b"a", b"/", url_cap=8, target_cap=1),
]
LABEL = b"a" * 63
HOST_253 = b".".join((LABEL, LABEL, LABEL, b"b" * 61))
assert len(HOST_253) == 253
CASES += [
    good("label-63", b"http://" + LABEL, LABEL, LABEL, b"/"),
    good("host-253", b"http://" + HOST_253, HOST_253, HOST_253, b"/"),
    bad("bounds-negative-start", b"http://a", 1, malformed=1),
    bad("bounds-negative-length", b"http://a", 1, malformed=2),
    bad("bounds-overflow", b"http://a", 1, malformed=3),
    bad("bounds-before-invalid-limits", b"http://a", 1, malformed=1, url_cap=0),
    bad("zero-url-cap", b"http://a", 2, url_cap=0),
    bad("zero-target-cap", b"http://a", 2, target_cap=0),
    bad("large-url-cap", b"http://a", 2, url_cap=1048577),
    bad("large-target-cap", b"http://a", 2, target_cap=1048577),
    bad("relative", b"//a/x", 4, 0),
    bad("unsupported-scheme", b"ftp://a", 4, 0),
    bad("missing-authority", b"http:/a", 5, 5),
    bad("empty-host", b"http://", 5, 7),
    bad("empty-host-with-query", b"https://?q", 5, 8),
    bad("empty-userinfo", b"http://@a", 6, 7),
    bad("userinfo", b"http://user:pass@a", 6, 16),
    bad("host-underscore", b"http://a_b", 7, 8),
    bad("host-leading-hyphen", b"http://-a", 7, 7),
    bad("host-final-hyphen", b"http://a-", 7, 9),
    bad("host-trailing-dot", b"http://a.", 7, 9),
    bad("host-empty-label", b"http://a..b", 7, 9),
    bad("host-label-64", b"http://" + b"a" * 64, 7, 70),
    bad("host-254", b"http://" + HOST_253 + b"b", 7, 260),
    bad("ipvfuture", b"http://[v1.a]/", 7, 7),
    bad("encoded-host", b"http://ex%61mple", 7, 9),
    bad("legacy-two-part", b"http://127.1", 7, 7),
    bad("legacy-octal", b"http://0177.0.0.1", 7, 7),
    bad("legacy-whole-decimal", b"http://2130706433", 7, 7),
    bad("legacy-whole-hex", b"http://0x7f000001", 7, 7),
    bad("legacy-mixed-part", b"http://127.0x0.0.1", 7, 7),
    bad("invalid-dotted-ip", b"http://256.0.0.1", 7, 7),
    bad("port-empty", b"http://a:", 8, 9),
    bad("port-zero", b"http://a:0", 8, 9),
    bad("port-overflow", b"http://a:65536", 8, 13),
    bad("port-overflow-long", b"http://a:999999999999999999999999", 8, 13),
    bad("target-cap-below", b"http://a/ab?c#ignored", 9, 8, target_cap=4),
    bad("generated-slash-counts", b"http://a?", 9, 8, target_cap=1),
    bad("url-cap-below", b"http://a", 3, -1, syntax=(2, -1), url_cap=7),
    bad("syntax-before-scheme", b"ftp://a/%", 3, 8, syntax=(4, 8)),
    bad("syntax-after-userinfo", b"http://@a/#%", 3, 11, syntax=(4, 11)),
    bad("raw-backslash", b"http://a/\\", 3, 9, syntax=(3, 9)),
    bad("raw-nul", b"http://a/\0", 3, 9, syntax=(3, 9)),
    bad("raw-nonascii", b"http://\xff", 3, 7, syntax=(3, 7)),
    bad("bad-port-syntax", b"http://a:1x", 3, 10, syntax=(8, 10)),
    bad("bad-scheme-syntax", b"1http://a", 3, 0, syntax=(5, 0)),
    bad("zone-id-not-ipv6", b"http://[fe80::1%25lo]/", 3, 7, syntax=(7, 7)),
    bad("two-userinfo-markers", b"http://a@b@c", 3, 10, syntax=(6, 10)),
]


def packet(case, layout):
    assert len(case.raw) <= 512 and layout in (0, 1)
    return W(len(case.raw), case.url_cap, case.target_cap, layout, case.malformed) + case.raw.ljust(512, b"\0")


def check_answer(case, layout, actual):
    assert actual == case.answer, (case.name, layout, actual.hex(), case.answer.hex())


def controls():
    # The native comparison must reject same-length, same-case mutations in
    # the status word and last byte of four differently shaped records.
    samples = [CASES[0], CASES[2], CASES[10], CASES[-1]]
    count = 0
    for sample in samples:
        original = sample.answer
        check_answer(sample, 0, original)
        for at in (8, len(original) - 1):
            mutant = bytearray(original)
            mutant[at] ^= 1
            assert len(mutant) == len(original)
            try:
                check_answer(sample, 0, bytes(mutant))
            except AssertionError:
                pass
            else:
                raise AssertionError("same-case semantic comparison accepted changed bytes")
            count += 1
    assert len({case.name for case in CASES}) == len(CASES)
    assert all(len(packet(case, 0)) == 552 and len(packet(case, 1)) == 552 for case in CASES)
    count += 2
    print(f"http-url CPU controls={count}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "model.py EXECUTABLE | controls"
    executable = Path(sys.argv[1]).resolve()
    records = [(case, layout) for case in CASES for layout in (0, 1)]
    command = [str(executable)]
    result = subprocess.run(command, input=b"".join(packet(case, layout) for case, layout in records),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0 and result.stderr == b"", (command, result.returncode, result.stderr)
    offset = 0
    for case, layout in records:
        expected = case.answer
        actual = result.stdout[offset:offset + len(expected)]
        check_answer(case, layout, actual)
        offset += len(expected)
    assert offset == len(result.stdout), ("extra output", offset, len(result.stdout))
    print(f"http-url model cases={len(CASES)} layouts=2")


if __name__ == "__main__":
    main()
