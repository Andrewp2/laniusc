#!/usr/bin/env python3
"""Puts and gets per second for Python's sqlite3 (synchronous=OFF, one
transaction) and dbm.dumb, in the shape of `kv bench`: N puts of 11-byte keys
and SIZE-byte values, one commit/sync, then N gets in the same scattered order.

Usage: bench.py WORK_DIR [N] [SIZE]
"""
import dbm.dumb
import os
import sqlite3
import sys
import time


def keys(n):
    return [b"key%08d" % i for i in range(n)]


def order(n):
    at, out = 0, []
    for _ in range(n):
        out.append(at)
        at = (at + 1000003) % n
    return out


def report(name, kind, n, seconds):
    print("%-8s %s %d in %.1f ms: %d/s" % (name, kind, n, seconds * 1000, n / seconds))


def bench_sqlite(path, n, size):
    if os.path.exists(path):
        os.remove(path)
    ks, value = keys(n), b"x" * size
    db = sqlite3.connect(path)
    db.execute("PRAGMA synchronous=OFF")
    db.execute("CREATE TABLE kv (k BLOB PRIMARY KEY, v BLOB) WITHOUT ROWID")
    start = time.perf_counter()
    db.executemany("INSERT OR REPLACE INTO kv VALUES (?, ?)", ((k, value) for k in ks))
    db.commit()
    report("sqlite3", "puts", n, time.perf_counter() - start)
    seq = order(n)
    start = time.perf_counter()
    cur = db.cursor()
    for i in seq:
        cur.execute("SELECT v FROM kv WHERE k = ?", (ks[i],)).fetchone()
    report("sqlite3", "gets", n, time.perf_counter() - start)
    db.close()


def bench_dumb(path, n, size):
    for suffix in (".dat", ".dir", ".bak"):
        if os.path.exists(path + suffix):
            os.remove(path + suffix)
    ks, value = keys(n), b"x" * size
    db = dbm.dumb.open(path, "n")
    start = time.perf_counter()
    for k in ks:
        db[k] = value
    db.sync()
    report("dbm.dumb", "puts", n, time.perf_counter() - start)
    seq = order(n)
    start = time.perf_counter()
    for i in seq:
        db[ks[i]]
    report("dbm.dumb", "gets", n, time.perf_counter() - start)
    db.close()


def main():
    work = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    os.makedirs(work, exist_ok=True)
    bench_sqlite(os.path.join(work, "bench.sqlite"), n, size)
    bench_dumb(os.path.join(work, "bench.dumb"), n, size)


if __name__ == "__main__":
    main()
