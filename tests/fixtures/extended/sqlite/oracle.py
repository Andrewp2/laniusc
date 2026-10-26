"""Independent SQLite/dictionary oracle for the bounded native test protocol."""

import sqlite3
import struct
import sys
from urllib.parse import quote


def signed(word):
    return word if word < 1 << 63 else word - (1 << 64)


def real(word):
    return struct.unpack("<d", struct.pack("<Q", word))[0]


def bits(value):
    return struct.unpack("<Q", struct.pack("<d", value))[0]


source = sys.stdin.buffer.read()
mode, path_length, count = struct.unpack_from("<3Q", source)
at = 24 + path_length
path = source[24:at].decode("utf-8")
database = sqlite3.connect("file:" + quote(path) + "?mode=ro", uri=True, isolation_level=None) if mode == 1 else sqlite3.connect(":memory:", isolation_level=None)
if mode != 1:
    database.execute("create table records(k integer primary key, i integer, r real, t text, b blob, n)")
model = {row[0]: row for row in database.execute("select * from records")}
saved = None
output = [0]


def row(value):
    key, integer, floating, text, blob, null = value
    assert null is None and isinstance(text, str) and isinstance(blob, bytes)
    text = text.encode("utf-8")
    return [key, integer, 5 if floating is None else 2,
            0 if floating is None else bits(floating), len(text), *text, len(blob), *blob, 5]


for _ in range(count):
    op, key, integer, floating, text_length, blob_length, layout, offset = struct.unpack_from(
        "<8Q", source, at
    )
    at += 64
    text = source[at:at + text_length].decode("utf-8")
    at += text_length
    blob = source[at:at + blob_length]
    at += blob_length
    key, integer, floating = signed(key), signed(integer), real(floating)
    try:
        if op == 0:
            database.execute("insert into records values(?,?,?,?,?,null)",
                             (key, integer, floating, text, blob))
            # REAL affinity may canonicalize signed zero; this is SQLite's
            # persisted representation, independent of the wrapper bit ABI.
            model[key] = (key, integer, 0.0 if floating == 0 else floating, text, blob, None)
        elif op == 1:
            database.execute("delete from records where k=?", (key,))
            model.pop(key, None)
        elif op == 2:
            database.execute("update records set i=?,r=?,t=?,b=? where k=?",
                             (integer, floating, text, blob, key))
            if key in model:
                model[key] = (key, integer, 0.0 if floating == 0 else floating, text, blob, None)
        elif op in (3, 4, 9):
            if op == 3:
                rows = database.execute("select * from records where k=?", (key,)).fetchall()
                assert rows == ([] if key not in model else [model[key]])
            elif op == 4:
                rows = database.execute("select * from records order by k").fetchall()
                assert rows == [model[key] for key in sorted(model)]
            else:
                rows = database.execute("select ?,?,?,?,?,null", (key, integer, floating, text, blob)).fetchall()
            output.append(0)
            for value in rows:
                output.extend([1, *row(value)])
            output.append(0)
            continue
        elif op == 5:
            database.execute("begin immediate")
            saved = model.copy()
        elif op == 6:
            database.commit()
            saved = None
        elif op == 7:
            database.rollback()
            model, saved = saved, None
        elif op == 10:
            assert 0 < key <= 32768 and key & (key - 1) == 0
            database.execute("create table bench(k integer primary key,v integer not null)")
            values = {((i * 4051) & (key - 1)): (i * 17) ^ (i // 7) for i in range(key)}
            database.execute("begin")
            database.executemany("insert into bench values(?,?)", values.items())
            database.commit()
            actual = database.execute("select count(*),sum(v),sum(k*v) from bench").fetchone()
            expected = (key, sum(values.values()), sum(k * v for k, v in values.items()))
            assert actual == expected
            indexed = sum((k + 1) * database.execute("select v from bench where k=?", (k,)).fetchone()[0]
                          for k in range(key))
            assert indexed == expected[1] + expected[2]
            output.extend([0, *actual, indexed])
            continue
        else:
            raise AssertionError(op)
        changes, last = database.execute("select changes(),last_insert_rowid()").fetchone()
        output.extend([0, changes, last])
    except sqlite3.Error as error:
        output.extend([1, error.sqlite_errorcode & 255])
assert at == len(source)
sys.stdout.buffer.write(struct.pack("<" + "Q" * len(output), *(word & ((1 << 64) - 1) for word in output)))
