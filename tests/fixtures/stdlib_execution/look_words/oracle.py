"""Independent reference for look_words: sorted distinct words via Python bytes.

Groups: model (output equality), admission (usage and UTF-8 rejection),
limits (exact caps on both sides), faults (output errors, unreadable input and
address-space-limited allocation failures). No tracer is used; every run sets
RLIMIT_CORE to 0.
"""
from pathlib import Path
import os
import random
import re
import resource
import subprocess
import sys
import tempfile

MAX_ARGUMENTS = 256
MAX_ARGUMENT_BYTES = 65536
MAX_INPUT = 1048576
MAX_WORDS = 65536
MAX_OUTPUT = 8388608


def fail(message):
    raise SystemExit(f"look-words: {message}")


def words(data):
    data.decode('utf-8')
    return sorted(set(re.findall(rb'[^ \t\n\v\f\r]+', data)))


def reference(arguments, data):
    """Return (status, stdout) for the documented contract."""
    if not arguments:
        return 2, b''
    try:
        for argument in arguments:
            argument.decode('utf-8')
    except UnicodeDecodeError:
        return 2, b''
    mode, operands = 'list', arguments
    if arguments[0].startswith(b'-'):
        mode = {b'--count': 'count', b'--near': 'near', b'--between': 'between', b'--': 'list'}.get(arguments[0])
        if mode is None:
            return 2, b''
        operands = arguments[1:]
    if not operands or (mode == 'between' and len(operands) != 2):
        return 2, b''
    if mode == 'between' and operands[1] < operands[0]:
        return 2, b''
    if len(data) > MAX_INPUT:
        return 2, b''
    try:
        stored = words(data)
    except UnicodeDecodeError:
        return 2, b''
    if len(stored) > MAX_WORDS:
        return 2, b''
    out = bytearray()
    if mode == 'between':
        low, high = operands
        out += b''.join(w + b'\n' for w in stored if low <= w <= high)
    for prefix in operands if mode != 'between' else ():
        family = [w for w in stored if w.startswith(prefix)]
        if mode == 'list':
            out += b''.join(w + b'\n' for w in family)
        elif mode == 'count':
            out += b'%d\t' % len(family) + prefix + b'\n'
        else:
            before = [w for w in stored if w < prefix and not w.startswith(prefix)]
            after = [w for w in stored if w > prefix and not w.startswith(prefix)]
            out += (before[-1] if before else b'') + b'\t' + (after[0] if after else b'') + b'\n'
    if len(out) > MAX_OUTPUT:
        return 2, b''
    return 0, bytes(out)


class Runner:
    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:20]
        if header[:6] != b'\x7fELF\x02\x01' or int.from_bytes(header[18:20], 'little') != 62:
            fail("not an x86-64 ELF executable")
        self.directory = Path(tempfile.mkdtemp(prefix=f'look-words-{group}-'))
        self.cases = 0

    def run(self, name, arguments, data=b'', *, address_space=None, stdout=None, stdin=None):
        def limits():
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            if address_space is not None:
                resource.setrlimit(resource.RLIMIT_AS, (address_space, address_space))
        source = self.directory / f'{self.cases}.input'
        source.write_bytes(data)
        descriptor = os.open(stdin if stdin is not None else source, os.O_RDONLY)
        try:
            result = subprocess.run([self.executable, *arguments], stdin=descriptor,
                                    stdout=stdout if stdout is not None else subprocess.PIPE,
                                    stderr=subprocess.PIPE, preexec_fn=limits, timeout=60, check=False)
        finally:
            os.close(descriptor)
        self.cases += 1
        if result.stderr:
            fail(f"{name}: unexpected stderr {result.stderr[:100]!r}")
        if result.returncode < 0:
            fail(f"{name}: terminated by signal {-result.returncode}")
        return result.returncode, result.stdout if stdout is None else b''

    def expect(self, name, arguments, data=b''):
        status, output = self.run(name, arguments, data)
        expected = reference(arguments, data)
        if (status, output) != expected:
            fail(f"{name}: got status {status} and {len(output)} bytes {output[:80]!r}, "
                 f"expected {expected[0]} and {len(expected[1])} bytes {expected[1][:80]!r}")
        return status


SAMPLE = b'apple apply app banana ap apt\tapp\nbanana zebra\r\n\v\f'


def model(runner):
    unicode = 'é é éa éz 🙂 🙂x a b ab \0 a\0b ÿ'.encode()
    fixed = [
        ('list', [b'app'], SAMPLE), ('list-many', [b'a', b'b', b'zz', b'ap'], SAMPLE),
        ('list-empty-prefix', [b''], SAMPLE), ('list-separator', [b'--', b'--x', b'-'], b'--x -- - -y'),
        ('list-empty-input', [b'a'], b''), ('list-whitespace-only', [b''], b' \t\n\v\f\r '),
        ('count', [b'--count', b'app', b'b', b'z', b'q', b''], SAMPLE),
        ('near', [b'--near', b'app', b'pa', b'zz', b'', b'a', b'zebra', b'0'], SAMPLE),
        ('near-empty-input', [b'--near', b'x'], b''),
        ('between', [b'--between', b'apply', b'banana'], SAMPLE),
        ('between-equal', [b'--between', b'app', b'app'], SAMPLE),
        ('between-outside', [b'--between', b'c', b'y'], SAMPLE),
        ('between-full', [b'--between', b'', '\U0010ffff'.encode()], SAMPLE + unicode),
        ('unicode-prefix', ['é'.encode(), '🙂'.encode(), b'e'], unicode),
        ('unicode-near', [b'--near', 'é'.encode(), b'a', 'ÿ'.encode()], unicode),
        ('unicode-count', [b'--count', b'a', 'é'.encode()], unicode),
        ('nul-words', [b'a', b''], unicode),
        ('prefix-chain', [b'--count', b'a', b'aa', b'aaa', b'aaaa', b'aaaaa'], b'a aa aaa aaaa a aa b'),
        ('duplicates', [b''], b'x x x y y x'),
    ]
    for name, arguments, data in fixed:
        runner.expect(name, arguments, data)
    rng = random.Random(0x100C0)
    alphabet = ['a', 'b', 'ab', 'ba', 'é', '🙂', 'z', '\0', 'aa']
    for index in range(24):
        pool = [''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 5))) for _ in range(rng.randint(1, 300))]
        data = ''.join(w + rng.choice([' ', '\t', '\n', '\r\n', '  ']) for w in pool).encode()
        queries = [''.join(rng.choice(alphabet[:7]) for _ in range(rng.randint(0, 3))).encode() for _ in range(rng.randint(1, 12))]
        mode = index % 4
        if mode == 0:
            arguments = [b'--'] + queries
        elif mode == 1:
            arguments = [b'--count'] + queries
        elif mode == 2:
            arguments = [b'--near'] + queries
        else:
            low, high = sorted(queries[:2] if len(queries) > 1 else [b'', b'b'])
            arguments = [b'--between', low, high]
        runner.expect(f'seeded-{index}', arguments, data)
    # Larger sorted traversal: every one of 40,000 distinct words, reversed input.
    big = b' '.join(b'%05d' % i for i in reversed(range(40000)))
    runner.expect('large-all', [b''], big)
    runner.expect('large-count', [b'--count', b'1', b'12', b'123', b'3999', b'4'], big)
    runner.expect('large-between', [b'--between', b'12345', b'12399'], big)


def admission(runner):
    cases = [
        ('no-arguments', []), ('count-without-prefix', [b'--count']), ('near-without-prefix', [b'--near']),
        ('separator-only', [b'--']), ('unknown-option', [b'--bogus', b'a']), ('single-dash', [b'-']),
        ('dash-prefix-first', [b'-a', b'b']), ('between-one', [b'--between', b'a']),
        ('between-three', [b'--between', b'a', b'b', b'c']), ('between-reversed', [b'--between', b'b', b'a']),
        ('invalid-operand', [b'a', b'\xff']), ('invalid-option-bytes', [b'\xc3']),
        ('truncated-operand', [b'--count', b'\xe2\x82']), ('overlong-operand', [b'--near', b'\xc0\xaf']),
    ]
    for name, arguments in cases:
        if runner.expect(name, arguments, SAMPLE) != 2:
            fail(f"{name}: expected rejection")
    for name, data in [('invalid-input', b'ok \xff'), ('truncated-input', b'ok \xf0\x9f\x99'),
                       ('surrogate-input', b'\xed\xa0\x80'), ('overlong-input', b'\xc0\x80')]:
        if runner.expect(name, [b'ok'], data) != 2:
            fail(f"{name}: expected rejection")
    # Argument-count and byte caps come from the snapshot, before stdin.
    status, output = runner.run('too-many-arguments', [b'a'] * (MAX_ARGUMENTS + 1), SAMPLE)
    if (status, output) != (2, b''):
        fail("257 arguments must be rejected")
    if runner.expect('max-arguments', [b'--count'] + [b'a'] * (MAX_ARGUMENTS - 1), SAMPLE) != 0:
        fail("256 arguments must be accepted")
    status, output = runner.run('argument-bytes', [b'a' * 40000, b'b' * 25537], SAMPLE)
    if (status, output) != (2, b''):
        fail("65,537 argument bytes must be rejected")
    if runner.expect('argument-bytes-at-cap', [b'--count', b'a' * 40000, b'b' * 25529], SAMPLE) != 0:
        fail("65,536 argument bytes must be accepted")


def limits(runner):
    checks = []
    exact = b'x' * (MAX_INPUT - 2) + b' y'
    checks.append(('input-at-cap', [b'--count', b'x', b'y'], exact, 0))
    checks.append(('input-over-cap', [b'--count', b'x'], exact + b' ', 2))
    distinct = b' '.join(b'%05x' % i for i in range(MAX_WORDS))
    checks.append(('words-at-cap', [b'--count', b''], distinct, 0))
    checks.append(('words-over-cap', [b'--count', b''], distinct + b' zzzzzz', 2))
    # 2,048 words of 63 bytes plus LF, listed 64 times: exactly 8 MiB.
    block = b' '.join(b'%063d' % i for i in range(2048))
    checks.append(('output-at-cap', [b'--'] + [b''] * 63 + [b'0'], block, 0))
    checks.append(('output-over-cap', [b'--'] + [b''] * 64, block + b' 1' * 1 + b'x' * 62, 2))
    for name, arguments, data, status in checks:
        got = runner.expect(name, arguments, data)
        if got != status:
            fail(f"{name}: status {got}, expected {status}")


def faults(runner):
    reached = 0
    reader, writer = os.pipe()
    os.close(reader)
    try:
        status, _ = runner.run('closed-stdout', [b''], SAMPLE, stdout=writer)
    finally:
        os.close(writer)
    if status != 3:
        fail(f"closed stdout: status {status}")
    with open('/dev/full', 'wb') as full:
        status, _ = runner.run('full-device', [b''], SAMPLE, stdout=full)
    if status != 3:
        fail(f"/dev/full: status {status}")
    status, output = runner.run('directory-stdin', [b'a'], stdin=str(runner.directory))
    if (status, output) != (3, b''):
        fail(f"directory stdin: status {status}")
    status, output = runner.run('admission-before-stdin', [b'--bogus'], stdin=str(runner.directory))
    if (status, output) != (2, b''):
        fail("usage errors must precede reading stdin")
    # Address-space limits make allocations fail at different stages; each run
    # either fails with 4 and no output or succeeds exactly, and success is
    # monotone in the limit.
    data = b' '.join(b'w%06d' % i for i in range(20000))
    arguments = [b'--count', b'w0', b'w01', b'w019999']
    expected = reference(arguments, data)
    succeeded = False
    for step in range(48):
        limit = (1 << 20) + step * (1 << 17)
        status, output = runner.run(f'address-space-{limit}', arguments, data, address_space=limit)
        if status == 4:
            if output or succeeded:
                fail(f"address space {limit}: failure after success or with output")
            reached += 1
        elif (status, output) == expected:
            succeeded = True
        else:
            fail(f"address space {limit}: status {status}")
    if not succeeded or reached < 8:
        fail(f"address-space sweep reached {reached} failures, success={succeeded}")
    return reached


def main():
    if len(sys.argv) != 3:
        fail("usage: oracle.py GROUP EXECUTABLE")
    group, executable = sys.argv[1], sys.argv[2]
    runner = Runner(executable, group)
    extra = ''
    if group == 'model':
        model(runner)
    elif group == 'admission':
        admission(runner)
    elif group == 'limits':
        limits(runner)
    elif group == 'faults':
        extra = f' reached_allocation_failures={faults(runner)}'
    else:
        fail(f"unknown group {group}")
    print(f"look-words-{group} cases={runner.cases}{extra}")


if __name__ == '__main__':
    main()
