"""Sorted-list reference for ordered navigation and bounded ranges.

The reference is a Python dict plus sorted() per query; it has no tree. Search
observations are checked as lawful binary-search descents: every visited key
is stored, each step narrows an open key interval in the direction implied by
the comparator answer, the final interval holds no stored key, the visit count
respects the AVL height bound, and every descent of one unchanged tree starts
at the same root. No particular AVL shape is fixed.
"""
from __future__ import annotations

import random
import struct
import subprocess
import sys

SEED = 0x0D0E_2026_1031
STAMP_VALUE = 0xAAAAAAAAAAAAAAAA
CALL, RESULT, PULLS = 192, 208, 224
MASK = (1 << 64) - 1
I32_MIN, I32_MAX = -(1 << 31), (1 << 31) - 1
INCLUDED, EXCLUDED, UNBOUNDED = 0, 1, 2


def fail(message):
    raise SystemExit(f"ordered-navigation-model: {message}")


def word(value):
    return value & MASK


def signed(value):
    return value - (1 << 64) if value >> 63 else value


def avl_height_limit(count):
    # Largest h with N(h) <= count, where N(h) is the minimum AVL node count.
    small, large, height = 0, 1, 0
    while large <= count:
        small, large, height = large, small + large + 1, height + 1
    return height


class Reader:
    def __init__(self, data):
        if len(data) % 8:
            fail("partial output word")
        self.words = struct.unpack(f"<{len(data) // 8}Q", data)
        self.at = 0

    def next(self):
        if self.at >= len(self.words):
            fail("output ended early")
        value = self.words[self.at]
        self.at += 1
        return value

    def peek(self):
        return self.words[self.at] if self.at < len(self.words) else None

    def expect(self, value, what):
        got = self.next()
        if got != word(value):
            fail(f"{what}: expected {word(value)}, got {got}")


def band_order(identity, low, high):
    if identity < low:
        return -1
    if identity > high:
        return 1
    return 0


def accepts(mode, order):
    return (order >= 0, order > 0, order <= 0, order < 0)[mode]


class Checker:
    def __init__(self, reader):
        self.r = reader
        self.contents = {}  # identity -> stamp
        self.root = None    # root identity while the tree is unchanged
        self.stats = dict(cases=0, commands=0, navigations=0, policy_navigations=0, ranges=0,
                          policy_ranges=0, invalid_ranges=0, pulls=0, back_pulls=0, policy_calls=0,
                          descents=0, checks=0, empty_ranges=0, equal_runs=0, snapshot_entries=0)
        self.routes = set()
        self.call_groups = []    # word offsets of each operation's CALL records
        self.pull_items = []     # word offsets of found range-pull records

    def keys(self):
        return sorted(self.contents)

    def changed(self):
        self.root = None

    def entry(self, expected, what):
        found = self.r.next()
        if expected is None:
            if found != 0:
                fail(f"{what}: expected None")
            return
        if found != 1:
            fail(f"{what}: expected Some({expected})")
        self.r.expect(expected, f"{what} identity")
        self.r.expect(self.contents[expected], f"{what} stamp")

    def calls(self):
        calls = []
        offsets = []
        while self.r.peek() == CALL:
            offsets.append(self.r.at)
            self.r.next()
            identity = signed(self.r.next())
            stamp = self.r.next()
            role = self.r.next()
            if identity not in self.contents or self.contents[identity] != stamp:
                fail(f"policy saw a key that is not stored: {identity}/{stamp}")
            calls.append((identity, role))
        self.stats["policy_calls"] += len(calls)
        if offsets:
            self.call_groups.append(offsets)
        return calls

    def descent(self, visited, mode, low, high):
        """Check one lawful descent and return its candidate identity."""
        keys = self.keys()
        if len(visited) > avl_height_limit(len(keys)):
            fail(f"descent of {len(visited)} nodes exceeds the AVL bound for {len(keys)}")
        if not keys:
            if visited:
                fail("empty tree consulted the policy")
            return None
        if not visited:
            fail("nonempty tree skipped its root")
        if self.root is None:
            self.root = visited[0]
        elif self.root != visited[0]:
            fail("descents of one unchanged tree started at different roots")
        lo, hi, candidate = None, None, None
        for identity in visited:
            if (lo is not None and identity <= lo) or (hi is not None and identity >= hi):
                fail(f"visit {identity} outside the narrowed interval ({lo}, {hi})")
            accept = accepts(mode, band_order(identity, low, high))
            first_mode = mode < 2
            if accept:
                candidate = identity
            if accept == first_mode:
                hi = identity   # go left
            else:
                lo = identity   # go right
        if any((lo is None or k > lo) and (hi is None or k < hi) for k in keys):
            fail(f"descent stopped with stored keys inside ({lo}, {hi})")
        self.stats["descents"] += 1
        return candidate


def expected_navigation(keys, mode, low, high):
    hits = [k for k in keys if accepts(mode, band_order(k, low, high))]
    if not hits:
        return None
    return hits[0] if mode < 2 else hits[-1]


def in_bounds(identity, lower, upper):
    lk, llow, lhigh = lower
    uk, ulow, uhigh = upper
    if lk == INCLUDED and band_order(identity, llow, lhigh) < 0:
        return False
    if lk == EXCLUDED and band_order(identity, llow, lhigh) <= 0:
        return False
    if uk == INCLUDED and band_order(identity, ulow, uhigh) > 0:
        return False
    if uk == EXCLUDED and band_order(identity, ulow, uhigh) >= 0:
        return False
    return True


def check_pulls(checker, items, mask):
    r = checker.r
    r.expect(PULLS, "pull marker")
    front, back, pull = 0, len(items) - 1, 0
    while True:
        use_back = pull < 64 and (mask >> pull) & 1 == 1
        r.expect(2 if use_back else 3, "pull end")
        if front > back:
            checker.entry(None, "exhausted pull")
            break
        if use_back:
            expected = items[back]
            back -= 1
            checker.stats["back_pulls"] += 1
        else:
            expected = items[front]
            front += 1
        checker.pull_items.append(r.at)
        checker.entry(expected, "range pull")
        checker.stats["pulls"] += 1
        pull += 1


def clamp(value):
    return max(I32_MIN, min(I32_MAX, value))


def generate(rng):
    cases = []
    for number in range(48):
        family = number % 2
        span = (8, 40, 400, 4000)[number % 4]
        size = (4, 30, 120, 260)[(number // 4) % 4]
        actions = [(0, family)]
        identities = list(range(-span, span + 1))
        rng.shuffle(identities)
        stamp = number << 32
        for identity in identities[:size]:
            stamp += 1
            actions.append((1, identity, stamp))
        if number % 6 == 5:
            for identity in (I32_MIN, I32_MAX, I32_MAX - 1, I32_MIN + 1):
                stamp += 1
                actions.append((1, identity, stamp))
        for step in range(150):
            choice = rng.randrange(100)
            point = rng.randint(-span - 3, span + 3)
            if number % 6 == 5 and rng.randrange(4) == 0:
                point = rng.choice((I32_MIN, I32_MAX, I32_MAX - 1, I32_MIN + 1, 0))
            width = rng.choice((0, 0, 1, 3, span // 4, -2))
            low, high = point, point + width
            if choice < 8:
                stamp += 1
                actions.append((1, point, stamp))
            elif choice < 14:
                actions.append((2, point))
            elif choice < 30:
                actions.append((3, rng.randrange(4), point, rng.getrandbits(64)))
            elif choice < 50:
                actions.append((4, rng.randrange(4), low, clamp(high)))
            elif choice < 68:
                other = rng.randint(-span - 3, span + 3)
                if rng.randrange(5) == 0:
                    other = clamp(point - rng.randint(1, 4))  # deliberately reversed
                actions.append((5, rng.randrange(3), point, rng.randrange(3), other, rng.getrandbits(64), rng.getrandbits(64)))
            elif choice < 96:
                lw, uw = rng.choice((0, 0, 2, span // 3)), rng.choice((0, 0, 2, span // 3))
                ul = rng.randint(-span - 3, span + 3)
                if rng.randrange(6) == 0:
                    ul = clamp(point - rng.randint(1, 5))
                kinds = rng.randrange(3) | (rng.randrange(3) << 2)
                actions.append((6, kinds, point, clamp(point + lw), ul, clamp(ul + uw), rng.getrandbits(64)))
            elif choice < 99:
                actions.append((7,))
            else:
                actions.append((8,))
        actions.append((7,))
        cases.append(actions)
    return cases


def check(cases, data):
    r = Reader(data)
    c = Checker(r)
    commands = 0
    for actions in cases:
        c.stats["cases"] += 1
        for action in actions:
            commands += 1
            op = action[0]
            if op == 0:
                c.contents.clear(); c.changed(); r.expect(0, "reset")
                continue
            if op == 1:
                _, identity, stamp = action
                old = c.contents.get(identity)
                if old is None:
                    r.expect(0, "insert of new key")
                else:
                    r.expect(1, "insert replaced"); r.expect(identity, "replaced identity"); r.expect(old, "replaced stamp")
                c.contents[identity] = stamp; c.changed()
                continue
            if op == 2:
                identity = action[1]
                old = c.contents.pop(identity, None)
                if old is None:
                    r.expect(0, "remove of missing key")
                else:
                    r.expect(1, "removed"); r.expect(identity, "removed identity"); r.expect(old, "removed stamp")
                    c.changed()
                continue
            if op == 3:
                _, mode, point, _ = action
                c.entry(expected_navigation(c.keys(), mode, point, point), f"same-key navigation mode {mode}")
                c.stats["navigations"] += 1
                c.routes.add(("nav", mode, expected_navigation(c.keys(), mode, point, point) is not None))
                continue
            if op == 4:
                _, mode, low, high = action
                visited = c.calls()
                if any(role != 0 for _, role in visited):
                    fail("navigation used a non-lower role")
                candidate = c.descent([i for i, _ in visited], mode, low, high)
                expected = expected_navigation(c.keys(), mode, low, high)
                if candidate != expected:
                    fail(f"descent candidate {candidate} != model {expected}")
                r.expect(RESULT, "navigation result marker")
                c.entry(expected, f"policy navigation mode {mode}")
                c.stats["policy_navigations"] += 1
                if low < high and sum(1 for k in c.contents if low <= k <= high) > 1:
                    c.stats["equal_runs"] += 1
                c.routes.add(("nav_by", mode, expected is not None))
                continue
            if op == 5:
                _, lk, lv, uk, uv, _, mask = action
                r.expect(RESULT, "range result marker")
                if lk != UNBOUNDED and uk != UNBOUNDED and uv < lv:
                    r.expect(1, "reversed same-key range")
                    c.stats["invalid_ranges"] += 1
                    continue
                r.expect(0, "accepted same-key range")
                items = [k for k in c.keys() if in_bounds(k, (lk, lv, lv), (uk, uv, uv))]
                check_pulls(c, items, mask)
                c.stats["ranges"] += 1
                c.stats["empty_ranges"] += not items
                c.routes.add(("range", lk, uk, bool(items)))
                continue
            if op == 6:
                _, kinds, llow, lhigh, ulow, uhigh, mask = action
                lk, uk = kinds & 3, (kinds >> 2) & 3
                calls = c.calls()
                lower_calls = [i for i, role in calls if role == 0]
                upper_calls = [i for i, role in calls if role == 1]
                if calls != [(i, 0) for i in lower_calls] + [(i, 1) for i in upper_calls]:
                    fail("lower-bound calls must precede upper-bound calls")
                keys = c.keys()
                if lk == UNBOUNDED:
                    if lower_calls:
                        fail("unbounded lower consulted the policy")
                    front = keys[0] if keys else None
                else:
                    front = c.descent(lower_calls, 0 if lk == INCLUDED else 1, llow, lhigh)
                    if front != expected_navigation(keys, 0 if lk == INCLUDED else 1, llow, lhigh):
                        fail("range front differs from model")
                items = [k for k in keys if in_bounds(k, (lk, llow, lhigh), (uk, ulow, uhigh))]
                if front is None or uk == UNBOUNDED:
                    if upper_calls:
                        fail("upper bound consulted without a found front or with no bound")
                else:
                    if not upper_calls or upper_calls[0] != front:
                        fail("upper bound must first check the found front entry")
                    c.stats["checks"] += 1
                    inside = accepts(2 if uk == INCLUDED else 3, band_order(front, ulow, uhigh))
                    if not inside:
                        if len(upper_calls) != 1:
                            fail("failed front check continued into an upper descent")
                    else:
                        back = c.descent(upper_calls[1:], 2 if uk == INCLUDED else 3, ulow, uhigh)
                        if back is None or back != items[-1]:
                            fail("range back differs from model")
                r.expect(RESULT, "policy range marker")
                check_pulls(c, items, mask)
                c.stats["policy_ranges"] += 1
                c.stats["empty_ranges"] += not items
                c.routes.add(("range_by", lk, uk, bool(items)))
                continue
            if op == 7:
                r.expect(len(c.contents), "length")
                check_pulls(c, c.keys(), 0)
                c.stats["snapshot_entries"] += len(c.contents)
                continue
            if op == 8:
                c.contents.clear(); c.changed(); r.expect(0, "clear")
                continue
            fail(f"unknown op {op}")
    r.expect(255, "trailer")
    r.expect(commands, "command count")
    r.expect(c.stats["policy_calls"], "policy call total")
    if r.at != len(r.words):
        fail("trailing output")
    c.stats["commands"] = commands
    return c


def encode(cases):
    out = bytearray()
    for actions in cases:
        for action in actions:
            values = [word(v) for v in action] + [0] * (8 - len(action))
            out += struct.pack("<8Q", *values)
    return bytes(out)


def corruptions(clean, data):
    """Host-only controls: each altered transcript must be rejected."""
    words = list(Reader(data).words)
    groups = [g for g in clean.call_groups if len(g) >= 2]
    found = [at for at in clean.pull_items if words[at] == 1]
    adjacent = [(a, b) for a, b in zip(found, found[1:]) if b - a == 4 and words[a + 1] != words[b + 1]]
    absent = max(clean.contents, default=0) + 1000003

    def patched(edits=(), drop=None, insert=None):
        copy = list(words)
        for at, value in edits:
            copy[at] = word(value)
        if drop is not None:
            del copy[drop:drop + 4]
        if insert is not None:
            at, record = insert
            copy[at:at] = record
        return struct.pack(f"<{len(copy)}Q", *copy)

    g = groups[len(groups) // 2]
    yield "unstored visited key", patched([(g[0] + 1, absent)])
    yield "dropped final descent call", patched(drop=g[-1])
    yield "swapped descent calls", patched([(g[0] + 1, words[g[1] + 1]), (g[0] + 2, words[g[1] + 2]),
                                            (g[1] + 1, words[g[0] + 1]), (g[1] + 2, words[g[0] + 2])])
    yield "repeated descent call", patched(insert=(g[-1] + 4, words[g[-1]:g[-1] + 4]))
    yield "wrong call role", patched([(g[0] + 3, 1 - words[g[0] + 3] if words[g[0] + 3] < 2 else 0)])
    a, b = adjacent[len(adjacent) // 2]
    yield "swapped range items", patched([(a + 1, words[b + 1]), (a + 2, words[b + 2]),
                                          (b + 1, words[a + 1]), (b + 2, words[a + 2])])
    yield "missing range item", patched([(found[len(found) // 3], 0)])
    yield "changed representative stamp", patched([(found[len(found) // 5] + 2, words[found[len(found) // 5] + 2] ^ 1)])
    yield "truncated transcript", patched(drop=len(words) - 4)


def main():
    if len(sys.argv) != 2:
        fail("usage: oracle.py EXECUTABLE")
    cases = generate(random.Random(SEED))
    run = subprocess.run([sys.argv[1]], input=encode(cases), capture_output=True, timeout=60)
    if run.returncode != 0 or run.stderr:
        fail(f"native exit {run.returncode}, stderr {run.stderr[:200]!r}")
    c = check(cases, run.stdout)
    s = c.stats
    nav_routes = sum(1 for r in c.routes if r[0] in ("nav", "nav_by"))
    range_routes = sum(1 for r in c.routes if r[0] in ("range", "range_by"))
    if nav_routes != 16:
        fail(f"navigation routes {nav_routes} != 16 (4 modes x hit/miss x 2 forms)")
    if range_routes != 36:
        fail(f"only {range_routes} of 36 bound-kind/empty range routes reached")
    controls = 0
    for name, altered in corruptions(c, run.stdout):
        try:
            check(cases, altered)
        except SystemExit:
            controls += 1
            continue
        fail(f"corruption control accepted: {name}")
    print("ordered-navigation-model " + " ".join(f"{k}={v}" for k, v in s.items())
          + f" nav_routes={nav_routes} range_routes={range_routes} controls={controls} seed={SEED:#x}")


if __name__ == "__main__":
    main()
