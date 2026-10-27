"""CPU-only controls for KV-specific read/open baseline binding."""
from copy import deepcopy
import sys
sys.dont_write_bytecode = True
from oracle import bind


def event(name, args, ordinal=1, ip=0x401002):
    return dict(name=name, args=args, ordinal=ordinal, ip=ip, phase=None)


def run():
    count = 0
    def check(before, after, item, accepted):
        nonlocal count
        try:
            bind(dict(events=before), dict(events=after), item)
        except AssertionError:
            assert not accepted, (before, after, item)
        else:
            assert accepted, (before, after, item)
        count += 1
    first = event("read", '4, "\\x00\\xff", 1024')
    target = event("read", '4, "", 1024', 2)
    failed = event("read", '4, 0x7fff002000, 1024', 2)
    item = dict(syscall="read", when=2)
    check([first, target], [first, failed], item, True)
    for index, field, value in ((0, "args", '5, "\\x00\\xff", 1024'),
                                (1, "args", '5, 0x7fff002000, 1024'),
                                (1, "args", '4, 0x7fff002000, 1023'),
                                (1, "ip", 0x402002)):
        changed = deepcopy([first, failed])
        changed[index][field] = value
        check([first, target], changed, item, False)
    def quoted(raw):
        return '"' + "".join("\\x%02x" % byte for byte in raw) + '"'
    left = event("openat", '3, %s, O_RDWR|O_CREAT|O_EXCL|O_CLOEXEC, 0600' % quoted(b".tmp-" + b"a" * 32))
    right = event("openat", '3, %s, O_RDWR|O_CREAT|O_EXCL|O_CLOEXEC, 0600' % quoted(b".tmp-" + b"b" * 32))
    item = dict(syscall="openat", when=1)
    check([left], [right], item, True)
    for args in (right["args"].replace("3, ", "4, ", 1),
                 right["args"].replace("O_EXCL", "O_TRUNC"),
                 right["args"].replace(quoted(b".tmp-" + b"b" * 32), quoted(b"db.kv"))):
        changed = dict(right, args=args)
        check([left], [changed], item, False)
    same = event("open", '%s, O_RDONLY' % quoted(b"db.kv"))
    check([same], [same], dict(syscall="open", when=1), True)
    check([same], [dict(same, args='%s, O_RDONLY' % quoted(b"other"))], dict(syscall="open", when=1), False)
    return count


if __name__ == "__main__":
    print("kv-application binding CPU-controls=%d native-cases=0" % run())
