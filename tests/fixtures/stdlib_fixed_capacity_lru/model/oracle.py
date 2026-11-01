"""Python reference for core::ring, core::inline_string, the core::vec
additions and alloc::lru.

The references are a Python list (ring and vector), a bytearray with Python's
own UTF-8 codec (inline string) and an OrderedDict (LRU recency, oldest
first). The ring reference also tracks the physical head slot, because the
two-view split of `as_views` is part of the public contract. Every response
word is compared exactly, except LRU equality-call counts for the colliding
key kind, which must lie between the hit count and the number of stored keys
sharing the probe's full hash. Spread keys have injective hashes, so their
equality calls are exact: one per successful lookup, none per miss.
"""
from __future__ import annotations

import random
import struct
import subprocess
import sys
from collections import OrderedDict

SEED = 0x51C0_2026_1031
MASK = (1 << 64) - 1
I32_MIN, I32_MAX = -(1 << 31), (1 << 31) - 1
RING_CAPS = (0, 1, 5, 8)
STRING_CAPS = (0, 5, 12)
VEC_CAP = 6


def fail(message):
    raise SystemExit(f"fixed-capacity-lru-model: {message}")


def w(value):
    return value & MASK


class Between:
    def __init__(self, low, high):
        self.low, self.high = low, high


class Stats(dict):
    def bump(self, key, amount=1):
        self[key] = self.get(key, 0) + amount


# ---------------------------------------------------------------- ring
class Ring:
    def __init__(self, cap):
        self.cap, self.items, self.head = cap, [], 0

    def reset_if_empty(self):
        if not self.items:
            self.head = 0

    def apply(self, op, a, b, stats):
        d, c = self.items, self.cap
        if op == 10 or op == 24:
            if len(d) == c:
                stats.bump("ring_full")
                return [1, 1]
            d.append(a)
            return [0, len(d)] if op == 10 else [0]
        if op == 11:
            if len(d) == c:
                stats.bump("ring_full")
                return [1, 1]
            self.head = (self.head - 1) % c
            d.insert(0, a)
            return [0, len(d)]
        if op == 12:
            if c == 0:
                return [1, a]
            if len(d) < c:
                d.append(a)
                return [0]
            stats.bump("ring_overwrites")
            evicted = d.pop(0)
            d.append(a)
            self.head = (self.head + 1) % c
            return [1, evicted]
        if op == 13:
            if c == 0:
                return [1, a]
            result = [0]
            if len(d) == c:
                stats.bump("ring_overwrites")
                result = [1, d.pop()]
            self.head = (self.head - 1) % c
            d.insert(0, a)
            return result
        if op == 14:
            if not d:
                return [0]
            item = d.pop(0)
            self.head = (self.head + 1) % c
            self.reset_if_empty()
            return [1, item]
        if op == 15:
            if not d:
                return [0]
            item = d.pop()
            self.reset_if_empty()
            return [1, item]
        if op == 16:
            return [1, d[a]] if 0 <= a < len(d) else [0]
        if op == 17:
            if not 0 <= a < len(d):
                return [1, 2]
            old, d[a] = d[a], b
            return [0, old]
        if op == 18:
            if not 0 <= a <= len(d):
                return [1, 2]
            if a == len(d):
                self.head = 0
            else:
                self.head = (self.head + a) % c
            del d[:a]
            self.reset_if_empty()
            return [0, len(d)]
        if op == 19:
            if not 0 <= a <= len(d):
                return [1, 2]
            del d[len(d) - a:]
            self.reset_if_empty()
            return [0, len(d)]
        if op == 20:
            count = len(d)
            d.clear()
            self.head = 0
            return [count]
        if op == 21:
            stats.bump("ring_snapshots")
            out = [len(d), c, c - len(d), int(not d), int(len(d) == c)]
            out += [1, d[0]] if d else [0]
            out += [1, d[-1]] if d else [0]
            out += list(d) + [1]
            first = min(len(d), c - self.head)
            if len(d) > first:
                stats.bump("ring_wrapped_views")
            out += [first] + d[:first] + [len(d) - first] + d[first:]
            return out
        if op == 22:
            self.head = 0
            return [len(d)] + list(d)
        if op == 23:
            return pulls(list(d), a, len(d) + 2, lambda x: [1, x], stats, "ring_pulls")
        fail(f"ring op {op}")


def pulls(items, pattern, limit, show, stats, key):
    out, front, back, bits = [], 0, len(items), pattern
    for _ in range(limit):
        out.append(max(back - front, 0))
        stats.bump(key)
        if front >= back:
            front = back = 0
            out.append(0)
        elif bits & 1 == 0:
            out += show(items[front])
            front += 1
        else:
            back -= 1
            out += show(items[back])
        bits = (bits >> 1) | ((bits & 1) << 63)
    return out


# ---------------------------------------------------------------- string
def is_boundary(data, index):
    return index == len(data) or (data[index] & 0xC0) != 0x80


def scalar_valid(value):
    return value <= 0x10FFFF and not 0xD800 <= value <= 0xDFFF


def compare_bytes(left, right):
    return (left > right) - (left < right)


def string_snapshot(data, cap):
    return [len(data), cap, cap - len(data), int(not data), int(len(data) == cap),
            len(data.decode("utf-8"))] + list(data)


class InlineString:
    def __init__(self, cap):
        self.cap, self.data = cap, bytearray()

    def apply(self, op, a, text, stats):
        d, c = self.data, self.cap
        if op == 30:
            if not scalar_valid(a):
                stats.bump("string_invalid_scalars")
                return [1, 4]
            encoded = chr(a).encode("utf-8")
            if len(encoded) > c - len(d):
                stats.bump("string_full")
                return [1, 1]
            d += encoded
            return [0, len(d)]
        if op == 31:
            if len(text) > c - len(d):
                stats.bump("string_full")
                return [1, 1]
            d += text
            return [0, len(d)]
        if op == 32:
            take = len(text)
            if take > c - len(d):
                take = c - len(d)
                while take > 0 and not is_boundary(text, take):
                    take -= 1
                stats.bump("string_truncated_pushes")
            d += text[:take]
            return [take]
        if op == 33:
            if not d:
                return [0]
            start = len(d) - 1
            while start > 0 and (d[start] & 0xC0) == 0x80:
                start -= 1
            scalar = ord(d[start:].decode("utf-8"))
            del d[start:]
            return [1, scalar]
        if op == 34:
            if not 0 <= a <= len(d):
                return [1, 2]
            if not is_boundary(d, a):
                stats.bump("string_not_boundary")
                return [1, 3]
            removed = len(d) - a
            del d[a:]
            return [0, removed]
        if op == 35:
            count = len(d)
            d.clear()
            return [count]
        if op == 36:
            stats.bump("string_snapshots")
            return string_snapshot(d, c)
        if op == 37:
            return [w(compare_bytes(bytes(d), text)), int(bytes(d) == text)]
        fail(f"string op {op}")


# ---------------------------------------------------------------- vec
class Vec:
    def __init__(self):
        self.items = []

    def apply(self, op, a, values, stats):
        d = self.items
        if op == 40:
            if len(d) == VEC_CAP:
                return [1, 1]
            d.append(a)
            return [0, len(d)]
        if op == 41:
            if not 0 <= a < len(d):
                return [1, 2]
            removed = d[a]
            d[a] = d[-1]
            d.pop()
            return [0, removed]
        if op == 42:
            source = list(d) if a == 100 else values[:a]
            if len(source) > VEC_CAP - len(d):
                stats.bump("vec_extend_full")
                return [1, 1]
            if a == 100:
                stats.bump("vec_self_extends")
            d += source
            return [0, len(d)]
        if op == 43:
            return [len(d)] + list(d)
        if op == 44:
            return [1, d.pop()] if d else [0]
        if op == 45:
            count = len(d)
            d.clear()
            return [count]
        fail(f"vec op {op}")


# ---------------------------------------------------------------- lru
class Lru:
    def __init__(self, cap, kind):
        self.cap, self.kind, self.items = cap, kind, OrderedDict()

    def same_hash(self, key):
        if self.kind == 0:
            return 1 if key in self.items else 0
        return sum(1 for stored in self.items if (stored & 3) == (key & 3))

    def apply(self, op, key, stamp, value, stats):
        items = self.items
        present = key in items
        keyed = op in (50, 51, 52, 53, 54, 55)
        hashes = 1 if keyed else 0
        if keyed:
            eq = int(present) if self.kind == 0 else Between(int(present), self.same_hash(key))
            stats.bump("lru_hits" if present else "lru_misses")
        else:
            eq = 0
        out = []
        if op == 50:
            if present:
                old = items[key]
                items[key] = (stamp, value)
                items.move_to_end(key)
                stats.bump("lru_replacements")
                out = [1, w(key), old[0], old[1]]
            elif len(items) == self.cap:
                evicted, (old_stamp, old_value) = items.popitem(last=False)
                items[key] = (stamp, value)
                stats.bump("lru_evictions")
                out = [2, w(evicted), old_stamp, old_value]
            else:
                items[key] = (stamp, value)
                out = [0]
        elif op == 51:
            if present:
                items.move_to_end(key)
                out = [1, items[key][1]]
            else:
                out = [0]
        elif op == 52:
            out = [1, items[key][1]] if present else [0]
        elif op == 53:
            out = [int(present)]
        elif op == 54:
            if present:
                items.move_to_end(key)
            out = [int(present)]
        elif op == 55:
            if present:
                old = items.pop(key)
                out = [1, w(key), old[0], old[1]]
            else:
                out = [0]
        elif op == 56:
            if items:
                evicted, old = items.popitem(last=False)
                out = [1, w(evicted), old[0], old[1]]
            else:
                out = [0]
        elif op == 57:
            for chosen in (next(iter(items), None), next(reversed(items), None)):
                out += [1, w(chosen), items[chosen][0], items[chosen][1]] if chosen is not None else [0]
        elif op == 58:
            stats.bump("lru_snapshots")
            newest_first = list(reversed(items))
            out = [len(items), self.cap, int(not items), int(len(items) == self.cap)]
            for k in newest_first:
                out += [w(k), items[k][0], items[k][1]]
            stats.bump("lru_snapshot_entries", len(items))
            out += [1] + [w(k) for k in items]
        elif op == 59:
            items.clear()
        elif op == 60:
            entries = list(reversed(items))
            out = pulls(entries, value, len(entries) + 2,
                        lambda k: [1, w(k), items[k][0], items[k][1]], stats, "lru_pulls")
        else:
            fail(f"lru op {op}")
        return out + [hashes, eq]


# ---------------------------------------------------------------- generation
SCALARS = [0x41, 0x7A, 0x24, 0xE9, 0x3B1, 0x20AC, 0x4E2D, 0xFFFD, 0x1F600, 0x10FFFF, 0]
INVALID_SCALARS = [0xD800, 0xDFFF, 0x110000, 0xFFFFFFFF]


def random_text(rng, limit):
    chars, size = [], 0
    target = rng.choice([0, 1, 2, 3, 5, 8, 12, 13, 20, 40])
    while True:
        ch = chr(rng.choice(SCALARS))
        encoded = ch.encode("utf-8")
        if size + len(encoded) > min(target, limit):
            break
        chars.append(ch)
        size += len(encoded)
    return "".join(chars).encode("utf-8")


def command(op, *args):
    words = [op] + [w(x) for x in args]
    return words + [0] * (8 - len(words))


def text_command(op, which, text):
    packed = text + bytes(40 - len(text))
    words = [op, which, len(text)] + list(struct.unpack("<5Q", packed))
    return words


def generate():
    rng = random.Random(SEED)
    cases = []
    for case in range(96):
        family = case % 4
        commands = []
        if family == 0:
            for _ in range(rng.randrange(40, 120)):
                which = rng.randrange(4)
                op = rng.choice([10, 10, 11, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 21, 22, 23, 24])
                if op == 20 and rng.random() < 0.7:
                    op = 21
                cap = RING_CAPS[which]
                if op in (16, 17):
                    a = rng.choice([-1, 0, 1, 2, cap - 1, cap, cap + 3, I32_MIN, I32_MAX])
                elif op in (18, 19):
                    a = rng.choice([-1, 0, 1, 2, cap, cap + 1])
                elif op == 23:
                    a = rng.getrandbits(64)
                else:
                    a = rng.getrandbits(64)
                commands.append(command(op, which, a, rng.getrandbits(64)))
        elif family == 1:
            for _ in range(rng.randrange(40, 120)):
                which = rng.randrange(3)
                op = rng.choice([30, 30, 30, 31, 31, 32, 32, 33, 34, 35, 36, 36, 37, 38])
                if op == 30:
                    value = rng.choice(SCALARS * 3 + INVALID_SCALARS)
                    commands.append(command(op, which, value))
                elif op in (33, 35, 36):
                    commands.append(command(op, which))
                elif op == 34:
                    commands.append(command(op, which, rng.choice([-1, 0, 1, 2, 3, 4, 5, 7, 11, 12, 13])))
                else:
                    commands.append(text_command(op, which, random_text(rng, 40)))
        elif family == 2:
            for _ in range(rng.randrange(30, 80)):
                op = rng.choice([40, 40, 41, 42, 42, 43, 43, 44, 45])
                if op == 41:
                    commands.append(command(op, 0, rng.choice([-1, 0, 1, 2, 5, 6])))
                elif op == 42:
                    count = rng.choice([0, 1, 2, 3, 5, 100])
                    commands.append(command(op, 0, count, *[rng.getrandbits(64) for _ in range(5)]))
                else:
                    commands.append(command(op, 0, rng.getrandbits(64)))
        else:
            cap = rng.choice([1, 2, 3, 5, 8, 16, 64])
            kind = case // 4 % 2
            commands.append(command(1, cap, kind))
            span = max(2, cap * 2 + rng.randrange(3))
            pool = list(range(-span // 2, span - span // 2)) + [I32_MIN, I32_MAX]
            for _ in range(rng.randrange(150, 400)):
                op = rng.choice([50, 50, 50, 50, 51, 51, 51, 52, 53, 54, 55, 56, 57, 58, 58, 59, 60])
                if op == 59 and rng.random() < 0.8:
                    op = 58
                # Most keys come from a hot window just over the capacity, so
                # hits, replacements and evictions all stay frequent.
                key = rng.randrange(-1, cap + cap // 2 + 2) if rng.random() < 0.6 else rng.choice(pool)
                commands.append(command(op, 0, key, rng.getrandbits(64), rng.getrandbits(64)))
            for probe in (0, -1, 1, 7, 1000, 1073741825, 100000000):
                commands.append(command(2, probe))
        cases.append((family, commands))
    return cases


def expected_stream(cases, stats):
    rings = [Ring(c) for c in RING_CAPS]
    strings = [InlineString(c) for c in STRING_CAPS]
    vec = Vec()
    caches = {0: Lru(1, 0), 1: Lru(1, 1)}
    kind = 0
    out = []
    count = 0
    for family, commands in cases:
        stats.bump("cases")
        for words in commands:
            count += 1
            op = words[0]
            out.append(op)
            signed = [x - (1 << 64) if x >> 63 else x for x in words]
            if op == 1:
                kind = words[2]
                caches[kind] = Lru(words[1], kind)
                stats.bump("lru_resets")
            elif op == 2:
                cap = signed[1]
                if cap < 1:
                    out += [1, 1]
                elif cap > 1073741824 or cap >= 100000000:
                    out += [1, 2]
                else:
                    out += [0, cap]
                stats.bump("lru_probes")
            elif 10 <= op < 30:
                a = signed[2] if op in (16, 17, 18, 19) else words[2]
                out += rings[words[1]].apply(op, a, words[3], stats)
                stats.bump("ring_ops")
            elif 30 <= op < 40:
                text = struct.pack("<5Q", *words[3:8])[:words[2]] if op in (31, 32, 37, 38) else b""
                if op == 38:
                    out += [1, 1] if len(text) > 12 else [0] + string_snapshot(bytearray(text), 12)
                else:
                    a = signed[2] if op == 34 else words[2]
                    out += strings[words[1]].apply(op, a, text, stats)
                stats.bump("string_ops")
            elif 40 <= op < 50:
                a = signed[2] if op == 41 else words[2]
                out += vec.apply(op, a, list(words[3:8]), stats)
                stats.bump("vec_ops")
            else:
                out += caches[kind].apply(op, signed[2], words[3], words[4], stats)
                stats.bump("lru_ops")
    out += [255, count]
    stats["commands"] = count
    return out


def check(actual, expected, stats=None):
    if len(actual) != len(expected):
        return f"length {len(actual)} != {len(expected)}"
    for index, (got, want) in enumerate(zip(actual, expected)):
        if isinstance(want, Between):
            if not want.low <= got <= want.high:
                return f"word {index}: {got} outside [{want.low},{want.high}]"
            if stats is not None:
                stats.bump("collide_eq_calls", got)
        elif got != want:
            return f"word {index}: {got} != {want}"
    return None


def main():
    binary = sys.argv[1]
    cases = generate()
    stdin = b"".join(struct.pack("<8Q", *words) for _, commands in cases for words in commands)
    stats = Stats()
    expected = expected_stream(cases, stats)
    run = subprocess.run([binary], input=stdin, capture_output=True, timeout=60)
    if run.returncode != 0 or run.stderr:
        fail(f"exit {run.returncode} stderr {run.stderr[:200]!r}")
    if len(run.stdout) % 8:
        fail("partial output word")
    actual = list(struct.unpack(f"<{len(run.stdout) // 8}Q", run.stdout))
    problem = check(actual, expected, stats)
    if problem:
        fail(problem)
    # Corruption controls: each altered transcript must be rejected.
    controls = 0
    for mutate in (
        lambda a: a[:-1],
        lambda a: a[:5] + [a[5] ^ 1] + a[6:],
        lambda a: a[:len(a) // 2] + [a[len(a) // 2] + 1] + a[len(a) // 2 + 1:],
        lambda a: [a[i + 1] if i == 40 else a[i - 1] if i == 41 else x for i, x in enumerate(a)],
    ):
        mutated = mutate(list(actual))
        if mutated != actual and check(mutated, expected) is None:
            fail("corruption control accepted")
        controls += 1
    keys = ["cases", "commands", "ring_ops", "ring_full", "ring_overwrites", "ring_snapshots",
            "ring_wrapped_views", "ring_pulls", "string_ops", "string_full", "string_invalid_scalars",
            "string_not_boundary", "string_truncated_pushes", "string_snapshots", "vec_ops",
            "vec_extend_full", "vec_self_extends", "lru_resets", "lru_probes", "lru_ops", "lru_hits",
            "lru_misses", "lru_replacements", "lru_evictions", "lru_snapshots", "lru_snapshot_entries",
            "lru_pulls", "collide_eq_calls"]
    summary = " ".join(f"{k}={stats.get(k, 0)}" for k in keys)
    print(f"fixed-capacity-lru-model {summary} words={len(actual)} controls={controls} seed={SEED:#x}")


if __name__ == "__main__":
    main()
