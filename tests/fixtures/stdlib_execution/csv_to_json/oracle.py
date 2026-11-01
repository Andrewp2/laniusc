"""Python csv oracle for the csv-to-json program (ext::csv + ext::json_stream).

Valid inputs are produced by Python's csv.writer and parsed by csv.reader
(strict=True); the program's JSON must equal the reference rendering and its
--csv output must equal csv.writer(QUOTE_ALL, lineterminator CRLF).

usage: oracle.py GROUP EXECUTABLE   (GROUP: generated, rfc, invalid)
"""
import csv
import io
import random
import subprocess
import sys


def quoted(value):
    out = ['"']
    for c in value:
        if c in ('"', '\\'):
            out.append('\\' + c)
        elif ord(c) < 32:
            out.append('\\u%04x' % ord(c))
        else:
            out.append(c)
    out.append('"')
    return ''.join(out)


def reference_rows(data):
    text = data.decode('utf-8')
    return list(csv.reader(io.StringIO(text, newline=''), strict=True))


def to_json(rows):
    if not rows:
        return b'[]\n'
    header, body = rows[0], rows[1:]
    objects = ['{' + ','.join(quoted(k) + ':' + quoted(v) for k, v in zip(header, row)) + '}' for row in body]
    return ('[' + ','.join(objects) + ']\n').encode('utf-8')


def to_csv(rows):
    buffer = io.StringIO(newline='')
    csv.writer(buffer, quoting=csv.QUOTE_ALL, lineterminator='\r\n').writerows(rows)
    return buffer.getvalue().encode('utf-8')


def run(exe, data, *args):
    proc = subprocess.run([exe, *args], input=data, capture_output=True, timeout=20)
    return proc.returncode, proc.stdout, proc.stderr


FIELD_PARTS = ['a', 'B', ' ', ',', '"', '""', '\r\n', '\n', '\r', 'x y', '\u00e9', '\u4e2d', '\U0001f600',
               '\ufeff', '\\', '/', '0', '-1.5', "'"]


def rand_field(rng):
    return ''.join(rng.choice(FIELD_PARTS) for _ in range(rng.randrange(0, 5)))


def rand_table(rng):
    width = rng.randrange(1, 6)
    header = ['h%d%s' % (i, rng.choice(['', ' x', ',', '"q"', '\u00e9'])) for i in range(width)]
    if width > 1 and rng.random() < 0.1:
        header[1] = header[0]  # duplicate header names stay ordered pairs
    rows = [header]
    for _ in range(rng.randrange(0, 12)):
        rows.append([rand_field(rng) for _ in range(width)])
    return rows


def serialize(rng, rows):
    buffer = io.StringIO(newline='')
    quoting = rng.choice([csv.QUOTE_MINIMAL, csv.QUOTE_MINIMAL, csv.QUOTE_ALL])
    terminator = rng.choice(['\r\n', '\r\n', '\n'])
    csv.writer(buffer, quoting=quoting, lineterminator=terminator).writerows(rows)
    text = buffer.getvalue()
    if text and rng.random() < 0.3:
        text = text[:-len(terminator)]  # final record without a terminator
    return text.encode('utf-8')


RFC = [
    b'', b'h\r\n', b'h', b'a,b\r\n1,2\r\n', b'a,b\r\n1,2', b'a,b\n1,2\n', b'a,b\r\n"1","2"\r\n',
    b'a,b\r\n"x,y","z"\r\n', b'a\r\n"line1\r\nline2"\r\n', b'a\r\n"lf\nonly"\r\n', b'a\r\n"cr\ronly"\r\n',
    b'a\r\n"say ""hi"""\r\n', b'a\r\n""""\r\n', b'a,b\r\n,\r\n', b'a,b\r\n"",""\r\n', b'a\r\n""\r\n',
    b'"a,1","a,2"\r\nx,y\r\n', b'a,b\r\n x , y \r\n', b'\xef\xbb\xbfa,b\r\n1,2\r\n', b'a\r\n\xf0\x9f\x98\x80\r\n',
    b'a,a\r\n1,2\r\n', b'a,b,c\r\n1,"",3\r\n', b'a\r\n"\\"\r\n', b'"a\r\nb"\r\n"c\nd"\r\n',
]

# (input, Python strict reader also rejects?) Every input here is rejected by
# the documented ext::csv dialect.
INVALID = [
    (b'a\r\n"abc', True), (b'a\r\n"abc"x\r\n', True), (b'a\r\n"a""b\r\n', True), (b'a\r\n\xff\r\n', True),
    (b'a\r\n"\xc3("\r\n', True), (b'a\r\n\xed\xa0\x80\r\n', True), (b'a\r\n"x" ,y\r\n', True),
    (b'a,b\r\n1\r\n', False), (b'a\r\n1,2\r\n', False), (b'a\r\nx"y\r\n', False), (b'a\r\n1\r2\r\n', False),
    (b'a\r\nx\ty\r\n', False), (b'a\r\nx\x00y\r\n', False), (b'a\r\nx\x7fy\r\n', False), (b'a,b\r\n\r\n', False),
]


def main():
    group, exe = sys.argv[1], sys.argv[2]
    rng = random.Random(4180)
    cases = agree = 0
    python_rejects = policy = 0
    failures = []

    def compare(name, data):
        nonlocal cases, agree
        rows = reference_rows(data)
        for args, want in (((), to_json(rows)), (('--csv',), to_csv(rows))):
            cases += 1
            code, out, err = run(exe, data, *args)
            if code == 0 and out == want and err == b'':
                agree += 1
            else:
                failures.append((name, args, data[:120], want[:200], code, out[:200], err[:200]))

    if group == 'generated':
        for index in range(250):
            compare('gen%d' % index, serialize(rng, rand_table(rng)))
        big = [['id', 'text']] + [[str(i), rand_field(rng) * 20] for i in range(600)]
        compare('big', serialize(rng, big))
    elif group == 'rfc':
        for index, data in enumerate(RFC):
            compare('rfc%d' % index, data)
    elif group == 'invalid':
        for data, python_also in INVALID:
            cases += 1
            code, out, err = run(exe, data)
            try:
                reference_rows(data)
                python_ok = True
            except (csv.Error, UnicodeDecodeError):
                python_ok = False
            if python_ok != python_also:
                pass
            else:
                failures.append(('python expectation', data, python_also))
            if not python_ok:
                python_rejects += 1
            else:
                policy += 1
            if code == 2 and out == b'' and err == b'csv-to-json: invalid CSV or limit\n':
                agree += 1
            else:
                failures.append((data, code, out, err))
        print('csv-to-json-invalid cases=%d rejected=%d python_strict_rejects=%d dialect_only=%d' % (
            cases, agree, python_rejects, policy))
        for failure in failures[:20]:
            print('MISMATCH', failure, file=sys.stderr)
        return 0 if not failures else 1
    else:
        raise SystemExit('unknown group ' + group)
    print('csv-to-json-%s cases=%d agree=%d' % (group, cases, agree))
    for failure in failures[:20]:
        print('MISMATCH', failure, file=sys.stderr)
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
