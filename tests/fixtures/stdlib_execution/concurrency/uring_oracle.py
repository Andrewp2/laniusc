#!/usr/bin/env python3
"""uring_oracle.py CAT COPY DIR SEED: check the std::uring samples against
GNU cat and cp.

CAT and COPY are built sample_programs/library/uring_cat.lani and
uring_copy.lani; DIR is scratch space (emptied first). Cases: block-boundary
sizes (0, 1, 4095..4097, 128 KiB +-1, 8 blocks +-1, ...) and random sizes;
multi-file concatenation; missing files and directories mixed in (same
stdout, exit 1, one diagnostic per bad name, same errno text); stdin and a
FIFO fed in random chunks with pauses (short reads); 300 small files
(batch boundaries); copies over an existing longer file (truncation); a
missing source leaving DST untouched; and write errors on /dev/full.
Prints one summary line; exit 0 when every case matched."""
import os, random, shutil, subprocess, sys, threading, time

CAT, COPY, DIR, SEED = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
BLOCK = 131072
rng = random.Random(SEED)
failures = []
cases = 0


def check(label, ok, detail=''):
    global cases
    cases += 1
    if not ok:
        failures.append(f'{label} {detail}'.strip())


def run(argv, stdin=None, data=None, timeout=60):
    return subprocess.run(argv, stdin=stdin, input=data, capture_output=True, timeout=timeout)


def write(name, size):
    path = os.path.join(DIR, name)
    with open(path, 'wb') as f:
        f.write(rng.randbytes(size))
    return path


def diagnostics(stderr, gnu):
    """(name, error text) per line: GNU 'cat: NAME: TEXT', ours 'tool: NAME: errno N'."""
    out = []
    for line in stderr.decode(errors='replace').splitlines():
        prefix, name, rest = line.split(': ', 2) if gnu else line.rsplit(': ', 2)
        out.append((name, rest if gnu else os.strerror(int(rest.split()[-1]))))
    return out


def feed(pipe_path_or_fd, data, chunky):
    """Write data in random chunks with short pauses, then close."""
    f = open(pipe_path_or_fd, 'wb', buffering=0) if isinstance(pipe_path_or_fd, str) else pipe_path_or_fd
    at = 0
    while at < len(data):
        step = rng.randint(1, 70000) if chunky else len(data)
        f.write(data[at:at + step])
        at += step
        if chunky and rng.random() < 0.3:
            time.sleep(rng.random() * 0.002)
    f.close()


shutil.rmtree(DIR, ignore_errors=True)
os.makedirs(DIR)
sizes = [0, 1, 2, 4095, 4096, 4097, BLOCK - 1, BLOCK, BLOCK + 1, 8 * BLOCK - 1, 8 * BLOCK, 8 * BLOCK + 1,
         9 * BLOCK + 7, 17 * BLOCK + 3] + [rng.randint(0, 3_000_000) for _ in range(6)]
files = [write(f'f{i}', size) for i, size in enumerate(sizes)]

# Single files and random concatenations, byte-exact against GNU cat.
for path in files:
    mine, gnu = run([CAT, path]), run(['cat', path])
    check(f'cat {os.path.getsize(path)}', mine.returncode == 0 and mine.stdout == gnu.stdout and not mine.stderr)
for _ in range(12):
    pick = [rng.choice(files) for _ in range(rng.randint(2, 6))]
    mine, gnu = run([CAT] + pick), run(['cat'] + pick)
    check('cat many', mine.returncode == 0 and mine.stdout == gnu.stdout)

# Bad names mixed in: same bytes, exit 1, same diagnostics in the same order.
missing = os.path.join(DIR, 'missing')
for _ in range(8):
    pick = [rng.choice(files + [missing, DIR]) for _ in range(rng.randint(1, 6))] + [missing]
    rng.shuffle(pick)
    mine, gnu = run([CAT] + pick), run(['cat'] + pick)
    want, got = diagnostics(gnu.stderr, True), diagnostics(mine.stderr, False)
    check('cat errors', mine.returncode == 1 == gnu.returncode and mine.stdout == gnu.stdout and got == want,
          f'{got} != {want}')

# Short reads: stdin is a pipe fed in random chunks, alone and around "-".
for size in [0, 1, 5000, 3 * BLOCK + 11, 2_500_000]:
    data = rng.randbytes(size)
    for argv in ([CAT], [CAT, files[3], '-', files[8]]):
        proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        writer = threading.Thread(target=feed, args=(proc.stdin, data, True))
        writer.start()
        out = proc.stdout.read()
        err = proc.stderr.read()
        proc.wait(timeout=60)
        writer.join()
        expect = data if len(argv) == 1 else open(files[3], 'rb').read() + data + open(files[8], 'rb').read()
        check(f'cat stdin {size} {len(argv)}', proc.returncode == 0 and out == expect and not err)

# 300 small files: crosses the 32-name open/close batches.
small = [write(f's{i}', rng.randint(0, 5000)) for i in range(300)]
small.insert(37, missing)
mine, gnu = run([CAT] + small), run(['cat'] + small)
check('cat 300 files', mine.returncode == 1 == gnu.returncode and mine.stdout == gnu.stdout and mine.stderr.count(b'\n') == 1)

# stdout a regular file (positional writes, position set at the end), an
# O_APPEND file (ordered writes), and one descriptor shared by two runs.
sink = os.path.join(DIR, 'sink')
for _ in range(6):
    pick = [rng.choice(files) for _ in range(rng.randint(1, 4))]
    expect = b''.join(open(p, 'rb').read() for p in pick)
    with open(sink, 'wb') as out:
        mine = subprocess.run([CAT] + pick, stdout=out, timeout=60)
    check('cat >file', mine.returncode == 0 and open(sink, 'rb').read() == expect)
    with open(sink, 'ab') as out:
        mine = subprocess.run([CAT] + pick, stdout=out, timeout=60)
    check('cat >>file', mine.returncode == 0 and open(sink, 'rb').read() == expect + expect)
    with open(sink, 'wb') as out:
        out.write(b'head')
        out.flush()
        first = subprocess.run([CAT] + pick, stdout=out, timeout=60)
        second = subprocess.run([CAT, pick[0]], stdout=out, timeout=60)
    check('cat shared fd', first.returncode == second.returncode == 0
          and open(sink, 'rb').read() == b'head' + expect + open(pick[0], 'rb').read())

# Write errors: stdout is /dev/full.
with open('/dev/full', 'wb') as full:
    mine = subprocess.run([CAT, files[5]], stdout=full, stderr=subprocess.PIPE, timeout=60)
check('cat /dev/full', mine.returncode == 1 and b'write error: errno 28' in mine.stderr)

# Copies: exact bytes, truncation of a longer DST, missing SRC leaves DST alone.
target = os.path.join(DIR, 'copy')
for path in files:
    with open(target, 'wb') as f:
        f.write(b'x' * (os.path.getsize(path) + 1000))
    mine = run([COPY, path, target])
    check(f'copy {os.path.getsize(path)}', mine.returncode == 0 and open(target, 'rb').read() == open(path, 'rb').read())
with open(target, 'wb') as f:
    f.write(b'keep')
mine, gnu = run([COPY, missing, target]), run(['cp', missing, target])
check('copy missing', mine.returncode == 1 == gnu.returncode and open(target, 'rb').read() == b'keep'
      and diagnostics(mine.stderr, False) == [(missing, 'No such file or directory')])
mine = run([COPY, files[9], '/dev/full'])
check('copy /dev/full', mine.returncode == 1 and diagnostics(mine.stderr, False) == [('/dev/full', 'No space left on device')])
mine = run([COPY, files[9], os.path.join(missing, 'x')])
check('copy bad dst', mine.returncode == 1)

# A FIFO source: stream reads, positional writes at the landed offsets.
fifo = os.path.join(DIR, 'fifo')
os.mkfifo(fifo)
for size in [0, 7, 3 * BLOCK + 5, 1_700_000]:
    data = rng.randbytes(size)
    proc = subprocess.Popen([COPY, fifo, target], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    feed(fifo, data, True)
    out, err = proc.communicate(timeout=60)
    check(f'copy fifo {size}', proc.returncode == 0 and open(target, 'rb').read() == data, err.decode())

shutil.rmtree(DIR, ignore_errors=True)
print(f'seed {SEED}: {cases} cases, {len(failures)} mismatches')
for line in failures[:20]:
    print('  ' + line)
sys.exit(1 if failures else 0)
