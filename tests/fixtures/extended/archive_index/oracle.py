#!/usr/bin/env python3
"""Independent ZIP/SQLite oracles and process/fault orchestration; tests only."""
import io
import os
from pathlib import Path
import resource
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib

MODE, EXE = sys.argv[1], os.fsencode(sys.argv[2])
OBSERVER = sys.argv[3] if len(sys.argv) > 3 else None
CONTRACT = os.fsencode(sys.argv[4]) if len(sys.argv) > 4 else None
FAULTS = os.fsencode(sys.argv[5]) if len(sys.argv) > 5 else None
CASES = 0


def archive(entries, comment=b"", prefix=b""):
    """Small independent fixture encoder; never part of the production app."""
    out = bytearray(prefix)
    directory = bytearray()
    expected = []
    for ordinal, (name, data, method, flags) in enumerate(entries):
        compressed = data
        if method == 8:
            compressor = zlib.compressobj(level=6, wbits=-15)
            compressed = compressor.compress(data) + compressor.flush()
        crc = zlib.crc32(data)
        offset = len(out)
        out += struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, flags, method, 0, 33,
                           crc, len(compressed), len(data), len(name), 0)
        out += name + compressed
        end = len(out)
        directory += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20,
                                 flags, method, 0, 33, crc, len(compressed),
                                 len(data), len(name), 0, 0, 0, 0, 0, offset)
        directory += name
        expected.append((ordinal, name, method, flags, crc, len(compressed), len(data), offset, end))
    start = len(out)
    out += directory
    out += struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries), len(directory), start, len(comment))
    out += comment
    return bytes(out), expected


def child(argv, data=b"", fail=None, check_owners=True, **kwargs):
    env = os.environ.copy()
    if fail:
        env["ARCHIVE_FAIL"] = fail
    if not OBSERVER:
        return subprocess.run(argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=20, env=env, **kwargs)
    with tempfile.TemporaryFile() as trace:
        env["LD_PRELOAD"] = OBSERVER
        env["ARCHIVE_TRACE_FD"] = str(trace.fileno())
        result = subprocess.run(argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=20, env=env, pass_fds=(trace.fileno(),), **kwargs)
        trace.seek(0)
        events = trace.read()
        if check_owners:
            db = statement = 0
            for event in events:
                if event == ord('O'):
                    db += 1
                elif event == ord('C'):
                    db -= 1
                elif event == ord('P'):
                    statement += 1
                elif event == ord('F'):
                    statement -= 1
                else:
                    assert event in b'ER', (events, result)
                assert 0 <= db <= 1 and 0 <= statement <= 1, (events, result)
                assert db or not statement, (events, result)
            assert db == statement == 0, (argv, events, result)
        return result


def invoke(args, data=b"", status=0, word=None, **kwargs):
    global CASES
    argv = [EXE] + [value if isinstance(value, bytes) else os.fsencode(value) for value in args]
    result = child(argv, data, **kwargs)
    CASES += 1
    assert result.returncode == status, (argv, status, result)
    if status == 0:
        assert result.stderr == b"", result
    else:
        assert result.stdout == b"", result
        assert result.stderr.startswith(b"archive-index: ") and result.stderr.endswith(b"\n"), result
        assert b"\0" not in result.stderr, result
        if word:
            assert word in result.stderr, result
    return result.stdout


def persisted(path, key):
    with sqlite3.connect(path) as db:
        row = db.execute("SELECT snapshot,entries,typeof(key),typeof(snapshot) FROM archive_index_archives WHERE key=?", (key,)).fetchone()
        assert row and row[2:] == ("blob", "blob"), row
        rows = db.execute("SELECT ordinal,name,method,flags,crc32,csize,usize,local_offset,local_end FROM archive_index_entries WHERE key=? ORDER BY ordinal", (key,)).fetchall()
        assert row[1] == len(rows)
        assert db.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        # The stored catalog really has a composite index rather than a name map.
        plan = db.execute("EXPLAIN QUERY PLAN SELECT name FROM archive_index_entries WHERE key=? AND ordinal=?", (key, 0)).fetchall()
        assert any("PRIMARY KEY" in item[3] for item in plan), plan
        return row[0], rows


def listing(rows):
    return b"".join((f"{o}\t{m}\t{f}\t{crc}\t{c}\t{u}\t".encode() + name.hex().encode() + b"\n")
                    for o, name, m, f, crc, c, u, _, _ in rows)


def saved(path, key, zip_bytes, rows):
    assert persisted(path, key) == (zip_bytes, rows)


def put(path, key, entries):
    data, rows = archive(entries, comment=b"exact\0comment\xff", prefix=b"ignored-prefix\0")
    assert invoke(["--", path, "import", key], data) == b""
    saved(path, key, data, rows)
    return data, rows


def matrix(directory):
    path = directory / 'index.db'
    entries = [(b"duplicate", b"first", 0, 0), (b"duplicate", b"second", 8, 0),
               (b"\x00\xff/../\\C:\x80", bytes(range(256)) * 5, 8, 0),
               ("世界/é".encode(), b"\0\xff\n", 0, 2048), (b"", b"", 0, 0)]
    keys = [b"key", b"", b"quote'); DROP TABLE archive_index_entries;--", b"\xffraw-key", b"-dash"]
    for key in keys:
        data, rows = put(path, key, entries)
        assert invoke(["--", path, "count", key]) == b"5\n"
        assert invoke(["--", path, "list", key]) == listing(rows)
        for ordinal, item in enumerate(entries):
            assert invoke(["--", path, "get", key, str(ordinal)]) == item[1]
        assert invoke(["--", path, "export", key]) == data
    # Independently decode a conventional snapshot through Python's zipfile.
    ordinary = [(b"one", b"A" * 65537, 8, 0), (b"binary", bytes(range(256)), 0, 0)]
    data, rows = put(path, b"ordinary", ordinary)
    with zipfile.ZipFile(io.BytesIO(data)) as reference:
        assert [reference.read(item) for item in reference.infolist()] == [e[1] for e in ordinary]
    original = directory / 'original.zip'
    original.write_bytes(data)
    original.unlink()
    assert invoke([path, "export", "ordinary"]) == data
    replacement, replacement_rows = put(path, b"key", [(b"new", b"replacement", 8, 0)])
    assert invoke([path, "count", "key"]) == b"1\n"
    assert invoke([path, "list", "key"]) == listing(replacement_rows)
    invoke([path, "get", "key", "1"], status=5)
    empty, empty_rows = put(path, b"key", [])
    assert invoke([path, "count", "key"]) == b"0\n"
    assert invoke([path, "list", "key"]) == b""
    assert invoke([path, "export", "key"]) == empty
    invoke([path, "count", "missing"], status=5)
    # Actual library contract has counted NUL in the binary key and a strided
    # native stack view. It also closes the store before reading its snapshot.
    contract_data, _ = archive([(b"same", b"first", 0, 0), (b"same", b"second", 8, 0), (b"tail", b"", 0, 0)])
    result = child([CONTRACT, os.fsencode(path)], contract_data)
    assert result.returncode == 0 and not result.stdout and not result.stderr, result
    assert persisted(path, b"k\0\xff")[0] == contract_data


def limits(directory):
    path = directory / 'limits.db'
    old, old_rows = put(path, b'key', [(b'old', b'old', 0, 0)])
    new, rows = archive([(b'new', b'xyz' * 100, 8, 0), (b'tail', b'abc', 0, 0)])
    tests = [(['--max-input', str(len(new)-1)], 2), (['--max-entries', '1'], 2),
             (['--max-entry', '299'], 2), (['--max-total', '302'], 2),
             (['--max-work', '0'], 2), (['--max-key', '2'], 2),
             (['--max-io-calls', '0'], 2), (['--max-io-calls', '1'], 2)]
    for options, status in tests:
        invoke([path, 'import', 'key', *options], new, status=status)
        saved(path,b'key',old,old_rows)
    assert invoke([path,'import','key','--max-input',str(len(new)), '--max-entries','2','--max-entry','300','--max-total','303'],new)==b''
    saved(path,b'key',new,rows)
    for cmd, extra, size in [('get',['0'],300), ('export',[],len(new)), ('list',[],len(listing(rows))), ('count',[],2)]:
        invoke([path,cmd,'key',*extra,'--max-output',str(size-1)],status=2,word=b'output limit')
        expected = {'get':b'xyz'*100,'export':new,'list':listing(rows),'count':b'2\n'}[cmd]
        assert invoke([path,cmd,'key',*extra,'--max-output',str(size)]) == expected
    bad = [[],[path], [path,'wrong','key'],[path,'get','key'],[path,'get','key','-1'],
           [path,'get','key','2147483648'],[path,'count','key','1'],[path,'count','key','--bad'],
           [path,'count','key','--max-output','67108865'],[path,'count','key','--max-input','16777217'],
           [path,'count','key','--max-entry','67108865'],[path,'count','key','--max-entries','65535'],
           [path,'count','key','--max-total','18446744073709551616'],[path,'count','key','--max-work','-1'],
           [b'', 'count','key'],[b':memory:','import','key'],[b'file::memory:','import','key'],
           [b'file:test.db?mode=memory','import','key'],[b'\xffdb','count','key']]
    for args in bad:
        invoke(args,new,status=2)
    assert invoke(['--help']).startswith(b'Usage: archive-index ')
    invoke(['--help','--max-io-calls','0'],status=2)
    invoke([path,'count','key','--max-io-calls','0'],status=2)
    saved(path,b'key',new,rows)


def corruption(directory):
    path = directory / 'corrupt.db'
    old, old_rows = put(path,b'key',[(b'old',b'old',0,0)])
    valid, rows = archive([(b'first',b'valid',0,0),(b'last',b'BROKEN',8,0)])
    variants = [b'', b'not zip', valid[:-1], valid+b'trailing']
    broken = bytearray(valid)
    off = rows[-1][-2] + 30 + len(rows[-1][1]); broken[off] ^= 1
    variants.append(bytes(broken))
    stored, stored_rows = archive([(b'ok',b'valid',0,0),(b'last',b'BROKEN',0,0)])
    broken = bytearray(stored); off = stored_rows[-1][-2]+30+len(stored_rows[-1][1]); broken[off] ^= 1
    variants.append(bytes(broken))
    for data in variants:
        invoke([path,'import','key'],data,status=6)
        saved(path,b'key',old,old_rows)
    # Each malformed catalog is a separate copy; reading must not mutate it.
    mutations = ["UPDATE archive_index_archives SET entries=2", "UPDATE archive_index_entries SET name=x'00'",
                 "DELETE FROM archive_index_entries", "UPDATE archive_index_entries SET crc32=0",
                 "UPDATE archive_index_entries SET ordinal=1", "UPDATE archive_index_entries SET method=8",
                 "UPDATE archive_index_entries SET flags=2048", "UPDATE archive_index_entries SET csize=999",
                 "UPDATE archive_index_entries SET usize=999", "UPDATE archive_index_entries SET local_offset=1",
                 "UPDATE archive_index_entries SET local_end=1", "DELETE FROM archive_index_meta",
                 "CREATE TABLE unexpected(x)", "CREATE TABLE sqliteXhidden(x)",
                 "CREATE TRIGGER mutate AFTER INSERT ON archive_index_entries BEGIN DELETE FROM archive_index_archives; END"]
    for index, sql in enumerate(mutations):
        altered = directory / f'altered{index}.db'; shutil.copyfile(path,altered)
        with sqlite3.connect(altered) as db:
            db.execute(sql)
        before = altered.read_bytes()
        invoke([altered,'list','key'],status=6)
        assert altered.read_bytes() == before
    # Wrong SQLite value storage class is rejected through strict column APIs.
    for index, sql in enumerate(["UPDATE archive_index_entries SET name='text'", "UPDATE archive_index_archives SET snapshot='zip'"]):
        altered = directory / f'typed{index}.db'; shutil.copyfile(path,altered)
        with sqlite3.connect(altered) as db: db.execute(sql)
        invoke([altered,'list','key'],status=4)
    # Payload corruption after import is intentionally not inferred from a
    # structurally correct directory: selected extraction/export detect CRC.
    damaged = directory / 'payload.db'; shutil.copyfile(path,damaged)
    damaged_bytes = bytearray(old); damaged_bytes[30+len(b'old')+len(b'ignored-prefix\0')] ^= 1
    with sqlite3.connect(damaged) as db: db.execute('UPDATE archive_index_archives SET snapshot=?',(bytes(damaged_bytes),))
    assert invoke([damaged,'count','key']) == b'1\n'
    invoke([damaged,'get','key','0'],status=6)
    invoke([damaged,'export','key'],status=6)
    # SQLite's own invalid-file detection is distinct from archive errors.
    invalid = directory / 'not-sqlite.db'; invalid.write_bytes(b'bad database'*100)
    invoke([invalid,'count','key'],status=4)
    empty = directory / 'empty.db'; sqlite3.connect(empty).close()
    invoke([empty,'count','key'],status=6)
    unknown = directory / 'unknown.db'
    with sqlite3.connect(unknown) as db: db.execute('CREATE TABLE user_data(x)')
    before = unknown.read_bytes(); invoke([unknown,'import','key'],valid,status=6); assert unknown.read_bytes()==before


def failures(directory):
    path = directory/'faults.db'
    old, old_rows = put(path,b'key',[(b'old',b'old',0,0)])
    replacement, rows = archive([(b'a',b'new',8,0),(b'b',b'second',0,0),(b'c',b'last',8,0)])
    # The native fault occurs after at least one metadata row changed.
    for mode in ['step','commit-before','commit-after','rollback']:
        invoke([path,'import','key'],old)
        result = child([FAULTS,os.fsencode(path)],replacement,fail=mode)
        expected = 7 if mode in ['commit-after','rollback'] else 0
        assert result.returncode==expected and not result.stdout and not result.stderr,(mode,result)
        if mode=='commit-after': saved(path,b'key',replacement,rows)
        else: saved(path,b'key',old,old_rows)
    # The production CLI also preserves uncertainty as its own operational exit.
    invoke([path,'import','key'],replacement,status=7,word=b'uncertain',fail='commit-after')
    saved(path,b'key',replacement,rows)
    invoke([path,'import','key'],old)
    with sqlite3.connect(path) as locked:
        locked.execute('BEGIN IMMEDIATE')
        invoke([path,'import','key'],replacement,status=4)
        locked.rollback()
    saved(path,b'key',old,old_rows)
    # Read commands never create a missing file.
    missing=directory/'missing.db'; invoke([missing,'count','key'],status=4); assert not missing.exists()
    # I/O read failure is prior to opening/touching the store.
    fd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
    try:
        result=subprocess.run([EXE,os.fsencode(path),b'import',b'key'],stdin=fd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        assert result.returncode==3 and not result.stdout,result
    finally: os.close(fd)
    saved(path,b'key',old,old_rows)
    with open('/dev/full','wb') as sink:
        result=subprocess.run([EXE,os.fsencode(path),b'export',b'key'],stdout=sink,stderr=subprocess.PIPE,timeout=10)
        assert result.returncode==3,result
    saved(path,b'key',old,old_rows)



def trace_allocations(path, args, data=b"", fail_at=None):
    trace = path.parent/'allocations.trace'
    command=['strace','-qq','-i','-o',os.fspath(trace),'-e','trace=mmap,munmap']
    if fail_at is not None:
        command += ['-e',f'inject=mmap:error=ENOMEM:when={fail_at}']
    command += [EXE] + [os.fsencode(arg) for arg in args]
    result=subprocess.run(command,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
    live={}; attempts=[]; failures=0; syscall=0
    for line in trace.read_text().splitlines():
        match=re.match(r'\[([0-9a-f]+)\]\s+(mmap|munmap)\((.*)',line)
        if not match:
            continue
        address,call,tail=match.groups()
        if call=='mmap':
            syscall+=1
        if call=='mmap':
            # Lanius allocations use MAP_32BIT. Dynamic loader, libc and the
            # CRT process-vector mapping are distinct, even at low syscall IPs.
            if 'MAP_32BIT' not in tail:
                continue
            assert 'MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT' in tail,line
            size=int(tail.split(',')[1]); returned=tail.rsplit(' = ',1)[1].split()[0]
            attempts.append(syscall)
            if returned.startswith('0x'):
                assert returned not in live,line
                live[returned]=size
            else:
                assert returned=='-1' and 'ENOMEM' in line,line
                failures+=1
        else:
            owner,tail=tail.split(',',1);size=int(tail.split(')',1)[0])
            if owner in live:
                assert live.pop(owner)==size,line
                assert tail.endswith(' = 0'),line
    assert not live,(result,live,trace.read_text())
    return result,attempts,failures


def allocations(directory):
    path=directory/'allocation.db'
    old,old_rows=put(path,b'key',[(b'old',b'old',0,0)])
    new,rows=archive([(b'first',b'abc'*20,8,0),(b'second',b'binary\0\xff',0,0)])
    result,positions,failed=trace_allocations(path,[path,'import','key'],new)
    assert result.returncode==0 and not result.stdout and not result.stderr,result
    assert positions and not failed
    for position in positions:
        invoke([path,'import','key'],old)
        result,_,failed=trace_allocations(path,[path,'import','key'],new,position)
        assert result.returncode==4 and not result.stdout and failed==1,(position,result)
        saved(path,b'key',old,old_rows)
    # Reading/extracting includes storage and independent payload result owners.
    invoke([path,'import','key'],new)
    result,read_positions,failed=trace_allocations(path,[path,'get','key','0'])
    assert result.returncode==0 and result.stdout==b'abc'*20 and not failed,result
    for position in read_positions:
        result,_,failed=trace_allocations(path,[path,'get','key','0'],fail_at=position)
        assert result.returncode==4 and not result.stdout and failed==1,(position,result)
        saved(path,b'key',new,rows)
    print(f'archive-allocation import_positions={len(positions)} read_positions={len(read_positions)} balanced_direct_mappings=true')


def workload(directory):
    path=directory/'workload.db'; entries=[]
    for i in range(1024):
        # Four duplicate-name groups plus distinct raw binary names; priority
        # comes from ordinal, not lexicographic name or local byte content.
        name=b'duplicate' if i%17==0 else b'entry/'+i.to_bytes(2,'little')
        data=bytes(((j*37)^(i*13)^(j//256))&255 for j in range(8192))
        entries.append((name,data,0 if i%2 else 8,0))
    data,rows=archive(entries,b'workload')
    before=resource.getrusage(resource.RUSAGE_CHILDREN)
    start=time.monotonic(); invoke([path,'import','bulk'],data); import_seconds=time.monotonic()-start
    saved(path,b'bulk',data,rows)
    start=time.monotonic()
    assert invoke([path,'count','bulk'])==b'1024\n'
    assert invoke([path,'list','bulk'])==listing(rows)
    for ordinal in [0,1,17,511,512,777,1023]:
        assert invoke([path,'get','bulk',str(ordinal)])==entries[ordinal][1]
    assert invoke([path,'export','bulk'])==data
    query_seconds=time.monotonic()-start
    usage=resource.getrusage(resource.RUSAGE_CHILDREN)
    print(f'archive-workload entries=1024 expanded_bytes={sum(len(e[1]) for e in entries)} zip_bytes={len(data)} import_s={import_seconds:.6f} query_export_s={query_seconds:.6f} child_cpu_s={usage.ru_utime+usage.ru_stime-before.ru_utime-before.ru_stime:.6f} peak_child_rss_kib={usage.ru_maxrss}')


with tempfile.TemporaryDirectory(prefix='lanius_archive_index_') as tmp:
    globals()[MODE](Path(tmp))
print(f'archive-index-{MODE} cases={CASES}')
