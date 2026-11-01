"""Differential oracle for url-parse (ext::url) against the WHATWG URL
implementation in Node.js (whatwg.js), plus the url-parse command line.
Usage: oracle.py MODE EXECUTABLE. No production code is imported.

Mode "whatwg" builds a fixed corpus (hand-picked spec edge cases plus seeded
random combinations of schemes, credentials, hosts, ports, paths, queries,
fragments, whitespace and relative references against bases), runs every
case through Node and through `url-parse --batch`, and requires the same
href, every component getter and the origin, or failure on both sides. The
hrefs Node produced are then parsed again on both sides. Cases built from
non-ASCII or "xn--" host labels are tagged: there ext::url must either match
Node or report unsupported-idna (it does not implement UTS #46)."""
import json
import os
import random
import shutil
import subprocess
import sys

FIELDS = ["href", "protocol", "username", "password", "host", "hostname", "port", "pathname", "search", "hash", "origin"]
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def node():
    for name in ("node", "nodejs"):
        found = shutil.which(name)
        if found:
            return found
    raise SystemExit("node is required for the WHATWG reference")


def escape(text):
    out = bytearray()
    for byte in text.encode("utf-8"):
        if byte == 0x5C:
            out += b"\\\\"
        elif byte in (9, 10, 13):
            out += {9: b"\\t", 10: b"\\n", 13: b"\\r"}[byte]
        elif byte < 0x20 or byte == 0x7F:
            out += b"\\x%02x" % byte
        else:
            out.append(byte)
    return bytes(out)


def ours(exe, corpus):
    lines = b""
    for text, base, _ in corpus:
        lines += escape(text) + (b"\t" + escape(base) if base is not None else b"") + b"\n"
    run = subprocess.run([exe, "--batch"], input=lines, capture_output=True, timeout=120)
    assert run.returncode == 0 and run.stderr == b"", (run.returncode, run.stderr[:400])
    rows = run.stdout.decode("utf-8").split("\n")
    assert rows[-1] == "", rows[-1:]
    rows = rows[:-1]
    assert len(rows) == len(corpus), (len(rows), len(corpus))
    return [row.split("\t") for row in rows]


def reference(corpus):
    run = subprocess.run([node(), os.path.join(os.path.dirname(os.path.abspath(__file__)), "whatwg.js")],
                         input=json.dumps([[text, base] for text, base, _ in corpus]).encode(), capture_output=True, timeout=120)
    assert run.returncode == 0, run.stderr[:400]
    return json.loads(run.stdout)


SCHEMES = ["http", "HTTP", "https", "ws", "wss", "ftp", "file", "FILE", "sc", "non-spec", "a+b-c.d", "blob", "javascript", "mailto",
           "data", "about", "1x", "", "h ttp", "ht%74p", "git+ssh"]
SEPARATORS = [":", "://", ":/", ":///", ":\\\\", ":\\", "://\\", ":////", ":/\\", ": //"]
USERINFO = ["", "user@", "user:pass@", ":pass@", "u:@", "@", "a@b@", "us%20er:p@ss@", "\u00fc:\u00df@", "a:b:c@", "[x]@", "a b:c d@",
            "%3A:%40@", "u;=:x/@", "^|`{}@"]
HOSTS = ["example.com", "EXAMPLE.COM", "a.b.c.", "127.0.0.1", "0x7f.0.0.1", "0177.1", "4294967295", "4294967296", "1.2.3.4.5", "1.2.3", "0x",
         "foo.0x", "foo.09", "09.foo", "1..2", "1.2.3.4.", "1.2.3.4..", "0X7F.1", "0x100000000", "08", "0.0.0.0.", "[::1]", "[::]",
         "[1:2:3:4:5:6:7:8]", "[1:2:3:4:5:6:7:8:9]", "[::ffff:1.2.3.4]", "[1::2::3]", "[0:0:1:0:0:0:0:1]", "[::1.2.3]", "[::01.2.3.4]",
         "[::1.2.3.256]", "[fe80::1%25eth0]", "[", "[::1", "[1:0:0:2::3:0]", "[1:0::0:0]", "[::FFFF:192.168.0.1]", "[1:2:3:4:5:6:1.2.3.4]",
         "[1:2:3:4:5:6:7:1.2.3.4]", "[:1]", "[1:]", "[1::]", "[12345::]", "a b", "a%20b", "%41%42", "a%2", "a%zz", "a<b", "a^b", "a|b",
         "", "localhost", "LOCALHOST", "%30x7f.1", "a.b%2ec", "a\u007fb", "a%7Fb", "1.2.3.0x100", "a..b", ".", "..", "a.-b-", "x_y.z",
         "a!$&'()*+,;=b", "%25", "a%2Fb", "a%3ab", "\u00e9xample", "xn--nxasmq6b", "XN--a.com", "a.xn--b", "\uff21\uff22.com", "b\u00fccher.de",
         "%C3%A9", "a\u00adb"]
IDNA_MARKERS = ["\u00e9", "\u00fc", "\uff21", "\u00ad", "xn--", "XN--", "%C3"]
PORTS = ["", ":", ":80", ":443", ":21", ":0", ":65535", ":65536", ":0008080", ":8a", ": 80", ":99999999999", ":00", ":-1"]
PATHS = ["", "/", "/a/b/c", "/a/./b/../c", "/../..", "/a/%2e%2E/b", "/a/.%2e/b", "/./", "/..", "/C:/x", "/C|/x/../..", "/a b", "/a\\b\\..\\c",
         "/\u00e9", "/%zz", "/^`{}|", "//", "/a//b", "/a/..", "/.//p", "/a/.", "/a/%2e", "/a?/b", "/%2F", "/x/\u0000/y", "/\"<>", "/a;b=c",
         "/C:", "/C:/../..", "/c|", "/a/..%2f..", "/~u/x", "/%2e./%2E%2e/x", "/a\u2028b"]
QUERIES = ["", "?", "?a=b", "?a b", "?a'b", "?<\">", "?\u00e9", "??", "?a=%zz", "?`{}", "?/x/../y"]
FRAGMENTS = ["", "#", "#f", "#a b", "#`<>", "#\u00e9", "##", "#a\"b", "#%zz", "#{}"]
RELATIVES = ["", "?x", "#y", "/p", "p", "../p", "./", "..", "//h/p", "\\\\h\\p", "/\\h", "C|", "C:/x", "/C:", "file:", "http:", "http:x",
             "http:/x", "http://", "sc:", "#", "?", " foo ", "\t/a\n/b\r", "..\\x", "%2e%2e/a", "../../../../g", "g;x?y#s", ";x", ".", "/./g",
             "g/../h", "file:x", "file:/x", "file://h", "///x", "////x", "C|/../y", "c:", "?\u00e9#\u00e9", "//[::1]:8/x", "\\x", "//user@/x",
             "//@h/", "http:#x", "HTTP://H/", "sc:x#f", "//h:65536", "//h:00080/", "/..//x", "a:b", "x:/y", "#\u0000"]
BASES = ["http://a/b/c/d;p?q", "https://u:p@h:8443/x/y?z#w", "file:///C:/a/b", "file://host/share/x", "file:///", "file:///a/b/c",
         "sc://h/p/q", "sc:opaque", "sc:/p", "sc://h", "about:blank", "data:text/plain,x", "mailto:x@y", "http://[::1]:81/", "blob:https://a/b",
         "http://example.com/a?b#c", "ws://h/a/", "ftp://h/", "non-spec:/.//p", "http://h", "file:///C:", "file://localhost/x/", "not a url"]
EDGES = [
    ("http://a/^x{}`|", None), ("a: b ?x", None), ("a: b #x", None), ("a:b  ", None), ("  \u0001http://a/\u001f ", None),
    ("ht\ttp://a\n.com/\rx", None), ("http://user:pa:ss@h/", None), ("http://@h", None), ("http://a@b@c/", None), ("http://:@h", None),
    ("http://a:b@", None), ("http://@/", None), ("http://user@/", None), ("http:///h", None), ("http:\\\\h\\p", None), ("http:h", None),
    ("http:/h", None), ("sc:\\a", None), ("sc://a b/", None), ("sc://%/", None), ("sc://\u00e9/", None), ("sc://[::1]/", None),
    ("sc://[::1/", None), ("sc://:1/", None), ("sc://h:/", None), ("sc://h:x/", None), ("sc://", None), ("sc:///", None), ("sc://@/", None),
    ("sc:/../x", None), ("sc:/.//x", None), ("sc:/a/..//x", None), ("sc://h/a/..//x", None), ("file:", None), ("file:/", None),
    ("file:x", None), ("file://C:/x", None), ("file:///C|/x/../..", None), ("file://localhost", None), ("file://LocalHost/x", None),
    ("file://h:80/", None), ("file://user@h/", None), ("file://[::1]/x", None), ("file:\\\\h\\x", None), ("file:c:\\x\\..\\..", None),
    ("file:/C|", None), ("file://C|", None), ("file:///C:/../../x", None), ("file://h/C:/..", None), ("file:..", None), ("file:?x", None),
    ("file:#x", None), ("http://0x7f.1/", None), ("http://1.2.3.4.5/", None), ("http://999999999999/", None), ("http://0x/", None),
    ("http://foo.0x/", None), ("http://1.0x2.3/", None), ("http://0x100.1/", None), ("http://256.256.256.256/", None),
    ("http://1.16777215/", None), ("http://1.16777216/", None), ("http://4294967295/", None), ("http://00000000000000000000001/", None),
    ("http://0x00000000000000000000001/", None), ("http://09/", None), ("http://1.2.3.08/", None), ("http://1.2.3.4.08/", None),
    ("http://[::1.2.3.4]/", None), ("http://[::127.0.0.1]/", None), ("http://[0::0:1.2.3.4]/", None), ("http://[1:2:3:4:5:6:7::]/", None),
    ("http://[::2:3:4:5:6:7:8]/", None), ("http://[1:2:3:4:5:6:7:8::]/", None), ("http://[0000:0000::1]/", None), ("http://[A:B::C]/", None),
    ("http://a:80/", None), ("https://a:443/", None), ("ws://a:80", None), ("wss://a:443", None), ("ftp://a:21/", None), ("sc://a:80/", None),
    ("http://a:65535", None), ("http://a:65536", None), ("http://a:000000000000000080/", None), ("non-spec:/.//p", None),
    ("web+demo:/.//not-a-host/", None), ("web+demo:/..//not-a-host/", None), ("http://%41.com", None), ("http://a b/", None),
    ("http://example.com/%2e%2E/a", None), ("http://a/b\\c", None), ("http://1.2.3/", None), ("javascript:alert(1)", None),
    ("mailto:x@y.z?subject=a b", None), ("data:,hello world#x", None), ("blob:https://a:443/x", None), ("blob:http://a:8/x", None),
    ("blob:ftp://a/x", None), ("blob:not a url", None), ("blob:file:///x", None), ("HTTP://EX%41MPLE.com:0080/A/../B?Q#F", None),
    ("http://a/b/c/../../../../..", None), ("http://a/./.", None), ("http://a/%2e/%2E%2e/", None), ("http://a/..%2F", None),
    ("http://a?b#c", None), ("http://a#c?d", None), ("http://a/\u00e9?\u00e9#\u00e9", None), ("sc:\u00e9 x", None), ("sc:a\u007fb", None),
    ("http://[::1]:8080/", None), ("http://[::1]8080/", None), ("http://h:8080:80/", None), ("http://h/?'", None), ("sc://h/?'", None),
    ("a://b/c", None), ("A1+.-://h", None), ("1a://h", None), ("+a:b", None), ("", None), ("  ", None), (":", None), ("http:", None),
    ("https:", None), ("about:", None), ("http://ab\u0000c/", None), ("http://a\u007f/", None), ("http://a%00b/", None),
    ("http://a.b/c%", None), ("http://a.b/c%2", None), ("http://xn--abc.com/", None), ("http://\uff21\uff22.com/", None),
    ("x", "http://a/b"), ("?x", "http://a/b?y#z"), ("//x", "file:///C:/a"), ("C|/x", "file:///D:/y"), ("#z", "sc:opaque"),
    ("x", "sc:opaque"), ("", "sc:opaque#f"), ("", "http://a/b?c#d"), ("..", "file:///C:/"), ("/", "file:///C:/a"), ("/x", "file://h/C:/a"),
    ("C:", "file:///D:/a"), ("//C:/x", "file:///D:/a"), ("file:x", "file:///C:/a/b"), ("http:x", "http://h/a/b"), ("https:x", "http://h/a"),
    ("sc:x", "sc://h/a"), ("\\x", "http://h/a/b"), ("\\x", "sc://h/a/b"), ("//", "http://h/"), ("//", "sc://h/"), ("///", "sc://h/"),
    ("x", "about:blank"), ("#", "about:blank"), ("..", "sc:/a"), ("../..", "non-spec:/.//p"), ("x", "non-spec:/.//p"),
    ("http://h", "not a url"), ("../x", "http://h"), ("?", "file:///a?b"), ("x", "file://localhost/a/b"),
]
IDNA = ("xn--", "XN--", "%C3", "%c3")


def generated():
    rng = random.Random(20261031)
    corpus = []
    for _ in range(2600):
        scheme = rng.choice(SCHEMES)
        text = scheme + rng.choice(SEPARATORS) + rng.choice(USERINFO) + rng.choice(HOSTS) + rng.choice(PORTS) + rng.choice(PATHS) \
            + rng.choice(QUERIES) + rng.choice(FRAGMENTS)
        roll = rng.random()
        if roll < 0.08:
            text = rng.choice([" ", "\u0001", "\u001f ", "\t"]) + text + rng.choice([" ", "\u0000", "\u001f", "\n"])
        elif roll < 0.14:
            spot = rng.randrange(len(text) + 1)
            text = text[:spot] + rng.choice(["\t", "\n", "\r"]) + text[spot:]
        corpus.append((text, None))
    for _ in range(1600):
        relative = rng.choice(RELATIVES)
        if rng.random() < 0.5:
            relative = relative + rng.choice(PATHS) + rng.choice(QUERIES) + rng.choice(FRAGMENTS)
        corpus.append((relative, rng.choice(BASES)))
    for relative in RELATIVES:
        for base in BASES:
            corpus.append((relative, base))
    return corpus


def tagged(text, base):
    items = [text] + ([base] if base is not None else [])
    return any(any(ord(c) > 127 for c in item) or any(marker in item for marker in IDNA) for item in items)


def whatwg(exe):
    corpus = [(text, base, tagged(text, base)) for text, base in EDGES + generated()]
    expected = compare(exe, corpus)
    # Parse every href Node produced again, on both sides.
    compare(exe, [(want[1], None, idna) for (_, _, idna), want in zip(corpus, expected) if want[0] == "ok"])


def compare(exe, corpus):
    expected = reference(corpus)
    actual = ours(exe, corpus)
    idna_skips = 0
    for (text, base, idna), want, got in zip(corpus, expected, actual):
        label = (text, base)
        if want[0] == "base-fail":
            case(got[0] == "base-fail", label, want, got)
            continue
        if idna and got == ["fail", "unsupported-idna"]:
            idna_skips += 1
            case(True)
            continue
        if want[0] == "fail":
            case(got[0] == "fail" and len(got) == 2, label, want, got)
            continue
        case(got[0] == "ok" and len(got) == 12, label, want, got)
        for index, name in enumerate(FIELDS):
            assert got[index + 1] == want[index + 1], (label, name, want[index + 1], got[index + 1])
    # Unsupported IDNA must stay the exception, not a blanket escape hatch.
    tagged_count = sum(1 for _, _, idna in corpus if idna)
    case(idna_skips <= tagged_count, idna_skips, tagged_count)
    return expected


def run(exe, *args, stdin=b""):
    return subprocess.run([exe, *args], input=stdin, capture_output=True, timeout=30)


def cli(exe):
    usage = b"Usage: url-parse URL [BASE] | url-parse --batch\n"
    for args, code in (((), 2), (("--help",), 0), (("a", "b", "c"), 2)):
        out = run(exe, *args)
        case(out.returncode == code and out.stdout == usage and out.stderr == b"", args, out)
    out = run(exe, "HTTP://u:p@EXAMPLE.com:8080/a/./b/../c?q=1 2#f`x")
    want = ("href\thttp://u:p@example.com:8080/a/c?q=1%202#f%60x\nprotocol\thttp:\nusername\tu\npassword\tp\nhost\texample.com:8080\n"
            "hostname\texample.com\nport\t8080\npathname\t/a/c\nsearch\t?q=1%202\nhash\t#f%60x\norigin\thttp://example.com:8080\nkind\tdomain\n")
    case(out.returncode == 0 and out.stdout == want.encode(), out)
    for url, kind in (("http://[::1]/", "ipv6"), ("http://0x7f.1/", "ipv4"), ("sc://h/", "opaque"), ("file:///x", "empty"), ("sc:x", "none"),
                      ("sc://", "empty")):
        out = run(exe, url)
        case(out.returncode == 0 and out.stdout.endswith(("kind\t" + kind + "\n").encode()), url, out)
    out = run(exe, "../x?y", "http://h/a/b/c")
    case(out.returncode == 0 and out.stdout.startswith(b"href\thttp://h/a/x?y\n"), out)
    for args, line in ((("http://a b/",), b"fail\tinvalid-host\n"), (("http://h:70000/",), b"fail\tinvalid-port\n"),
                       (("http://1.2.3.4.5/",), b"fail\tinvalid-ipv4\n"), (("http://[1::2::3]/",), b"fail\tinvalid-ipv6\n"),
                       (("x",), b"fail\tmissing-scheme\n"), (("http:///",), b"fail\tmissing-host\n"),
                       (("http://b\u00fccher.de/",), b"fail\tunsupported-idna\n"), (("http://xn--bcher-kva.de/",), b"fail\tunsupported-idna\n"),
                       (("x", "not a url"), b"base-fail\tmissing-scheme\n"), (("x", "sc:opaque"), b"fail\tmissing-scheme\n")):
        out = run(exe, *args)
        case(out.returncode == 1 and out.stdout == line, args, out)
    # Invalid UTF-8 is rejected (a JavaScript string cannot carry it).
    out = run(exe, "--batch", stdin=b"http://h/\\xff\nhttp://h/\\xc3\\xa9\nhttp://h/\\xed\\xa0\\x80\nhttp://h/\\xf4\\x90\\x80\\x80\nhttp://h/\\xc0\\xaf\n")
    rows = out.stdout.split(b"\n")
    case(out.returncode == 0 and rows[0] == b"fail\tinvalid-utf8" and rows[1].startswith(b"ok\thttp://h/%C3%A9\t")
         and rows[2:] == [b"fail\tinvalid-utf8"] * 3 + [b""], out)
    # Batch escapes, a bad escape stops with status 2, empty input prints nothing.
    out = run(exe, "--batch", stdin=b"\\x20http://h/\\\\x\\t\tsc:z\n")
    case(out.returncode == 0 and out.stdout.startswith(b"ok\thttp://h//x\t"), out)
    out = run(exe, "--batch", stdin=b"http://h/\nbad\\q\nhttp://g/\n")
    case(out.returncode == 2 and out.stdout.startswith(b"ok\thttp://h/\t") and out.stdout.count(b"\n") == 1, out)
    out = run(exe, "--batch")
    case(out.returncode == 0 and out.stdout == b"", out)


MODES = {"cli": cli, "whatwg": whatwg}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"url-{mode} cases={cases}")
