"""Independent mutual-reachability reference for graph components.

Boolean transitive closure determines components; no Tarjan lowlinks, DFS
frames, finishing order, reverse traversal, or storage sort is reproduced.
Python and raw binary framing are test infrastructure only.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, replace
from functools import lru_cache
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x5CC0261105
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
MAX_NODES, MAX_EDGES = 536870910, 268435455
SUCCESS = [0, 0, -1, -1]
PREFIX_WORDS = 3 + 24 + 260


@dataclass(frozen=True)
class Case:
    operation: int
    layout: int
    nodes: int
    max_nodes: int
    max_edges: int
    max_work: int
    offset_start: int
    offset_length: int
    target_start: int
    target_length: int
    offsets: tuple
    targets: tuple


class GraphError(Exception):
    def __init__(self, code, node=-1, edge=-1):
        self.code, self.node, self.edge = code, node, edge


def failed(code, node=-1, edge=-1):
    return [1, code, node, edge]


def height(value):
    return max(value - 1, 0).bit_length()


def required(operation, nodes, edges):
    validation = nodes + 1 + edges
    base = validation + 16 * nodes + 4 * edges + 1
    if operation == 0:
        return base
    edge_construction = nodes + 1 + 6 * edges + 4 * edges * (1 + height(edges))
    return base + 2 * edges + edge_construction


def initial(case):
    offsets = [-777 - index for index in range(24)]
    targets = [-888 - index for index in range(260)]
    offsets[2:2 + len(case.offsets)] = case.offsets
    targets[2:2 + len(case.targets)] = case.targets
    return offsets, targets


def canonical(nodes, edges):
    selected = sorted(set(edges))
    offsets, targets = [0], []
    for node in range(nodes):
        targets.extend(target for source, target in selected if source == node)
        offsets.append(len(targets))
    return tuple(offsets), tuple(targets)


def validate(case):
    if min(case.max_nodes, case.max_edges) < 0:
        raise GraphError(1)
    valid = lambda start, length: start >= 0 and length >= 0 and start + length <= MAX_I32
    if case.nodes < 0 or not valid(case.offset_start, case.offset_length) or not valid(case.target_start, case.target_length):
        raise GraphError(2)
    if case.nodes > min(MAX_NODES, case.max_nodes):
        raise GraphError(3)
    if case.target_length > min(MAX_EDGES, case.max_edges):
        raise GraphError(4)
    if case.offset_length != case.nodes + 1:
        raise GraphError(2)
    if case.max_work < case.nodes + 1 + case.target_length:
        raise GraphError(5)
    offset_backing, target_backing = initial(case)
    assert case.offset_start + case.offset_length <= len(offset_backing), case
    assert case.target_length == 0 or case.target_start + case.target_length <= len(target_backing), case
    offsets = tuple(offset_backing[case.offset_start:case.offset_start + case.offset_length])
    targets = tuple(target_backing[case.target_start:case.target_start + case.target_length])
    count = len(targets)
    if offsets[0] != 0:
        raise GraphError(6, 0 if case.nodes else -1)
    for node in range(case.nodes):
        if not offsets[node] <= offsets[node + 1] <= count:
            raise GraphError(6, node)
    if offsets[-1] != count:
        raise GraphError(6, case.nodes - 1)
    for node in range(case.nodes):
        previous = -1
        for edge in range(offsets[node], offsets[node + 1]):
            target = targets[edge]
            if not 0 <= target < case.nodes:
                raise GraphError(8, node, edge)
            if target <= previous:
                raise GraphError(9, node, edge)
            previous = target
    return tuple((node, targets[edge]) for node in range(case.nodes)
                 for edge in range(offsets[node], offsets[node + 1]))


@lru_cache(maxsize=None)
def components(nodes, edges):
    """All pairs reachability by finite Boolean transitive closure."""
    reachable = [[left == right for right in range(nodes)] for left in range(nodes)]
    for left, right in edges:
        reachable[left][right] = True
    for middle in range(nodes):
        reachable = [[reachable[left][right] or (reachable[left][middle] and reachable[middle][right])
                      for right in range(nodes)] for left in range(nodes)]
    groups = []
    unseen = set(range(nodes))
    while unseen:
        first = min(unseen)
        group = frozenset(node for node in range(nodes)
                          if reachable[first][node] and reachable[node][first])
        assert group and group <= unseen
        groups.append(group)
        unseen -= group
    ids = tuple(next(index for index, group in enumerate(groups) if node in group) for node in range(nodes))
    condensed = tuple(sorted({(ids[left], ids[right]) for left, right in edges if ids[left] != ids[right]}))
    # Independent scan over the predecessor relation; no production indegree
    # array, heap, or adjacency iterator. Every selected prefix is minimal.
    remaining, order = set(range(len(groups))), []
    while remaining:
        ready = [node for node in remaining
                 if not any(right == node and left in remaining for left, right in condensed)]
        assert ready, ("condensation has a cycle", nodes, edges, ids, condensed)
        selected = min(ready)
        order.append(selected)
        remaining.remove(selected)
    position = {node: index for index, node in enumerate(order)}
    assert all(position[left] < position[right] for left, right in condensed)
    offsets, targets = canonical(len(groups), condensed)
    return ids, len(groups), offsets, targets, tuple(order)


def pair_result(nodes, ids, left, right):
    if not 0 <= left < nodes:
        return failed(2, left)
    if not 0 <= right < nodes:
        return failed(2, right)
    return SUCCESS + [int(ids[left] == ids[right])]


def observation(case, edges):
    ids, count, offsets, targets, order = components(case.nodes, edges)
    result = SUCCESS + [1, case.nodes, count]
    for component in ids:
        result += SUCCESS + [component]
    for left in range(case.nodes):
        for right in range(case.nodes):
            result += pair_result(case.nodes, ids, left, right)
    for node in (-1, case.nodes, MIN_I32, MAX_I32):
        result += failed(2, node)
    for left, right in ((-1, case.nodes), (case.nodes, -1), (0, case.nodes), (-1, MIN_I32), (MIN_I32, MAX_I32), (MAX_I32, MIN_I32)):
        result += pair_result(case.nodes, ids, left, right)
    if case.operation == 1:
        result += [1, count, len(targets)] + list(offsets) + list(targets)
        result += SUCCESS + [count] + list(order)
    result += [1, 0, 0, 0] + failed(12) * 4
    if case.operation == 1:
        result += [0]
    return result + [0]


def reference(case):
    offsets, targets = initial(case)
    result = [case.layout, 4, 4] + offsets + targets
    try:
        edges = validate(case)
        # Every accepted physical graph here has <=256 edges. The large Edge
        # staging capacity boundary cannot be reached without huge valid input;
        # it is deliberately not simulated by lying about its backing.
        if case.max_work < required(case.operation, case.nodes, len(edges)):
            raise GraphError(5)
        result += observation(case, edges)
    except GraphError as error:
        result += failed(error.code, error.node, error.edge)
    return [word & MASK for word in result]


def cases():
    result, seen = [], set()

    def append(nodes, edges=(), offsets=None, targets=None, operations=(0, 1),
               max_nodes=100, max_edges=1000, max_work=1_000_000, **metadata):
        if offsets is None or targets is None:
            offsets, targets = canonical(nodes, edges)
        for operation in operations:
            for layout in (0, 1):
                case = Case(operation, layout, nodes, max_nodes, max_edges, max_work,
                            metadata.get("offset_start", 2), metadata.get("offset_length", len(offsets)),
                            metadata.get("target_start", 2), metadata.get("target_length", len(targets)),
                            tuple(offsets), tuple(targets))
                if case not in seen:
                    seen.add(case)
                    result.append(case)

    exhaustive = 0
    for nodes in range(4):
        possible = tuple(itertools.product(range(nodes), repeat=2))
        for mask in range(1 << len(possible)):
            append(nodes, tuple(edge for index, edge in enumerate(possible) if mask & (1 << index)))
            exhaustive += 1
    assert exhaustive == 531

    witnesses = (
        (6, ()),
        (8, tuple((i, i + 1) for i in range(7))),
        (8, tuple((i, (i + 1) % 8) for i in range(8))),
        # Active cross links, nested discovery cycles and completed targets.
        (8, ((0, 1), (0, 4), (1, 2), (2, 0), (2, 3), (3, 1), (4, 5), (5, 4), (5, 2), (6, 7), (7, 6))),
        (8, ((0, 1), (0, 2), (1, 1), (2, 3), (3, 2), (3, 1), (4, 5), (5, 6), (6, 4), (6, 2), (7, 6))),
        # Every cross-component original edge below collapses to one 0->1.
        (6, ((0, 1), (1, 0), (2, 3), (3, 2), (0, 2), (0, 3), (1, 2), (1, 3), (4, 5), (5, 4))),
        # Canonical IDs are opposite their only valid topological order.
        (6, ((0, 1), (1, 0), (2, 3), (3, 2), (4, 5), (5, 4), (4, 2), (3, 0))),
        (16, tuple(itertools.product(range(16), repeat=2))),
        (16, tuple((i, i) for i in range(16))),
    )
    for nodes, edges in witnesses:
        append(nodes, edges)
        append(nodes, ((nodes - 1 - left, nodes - 1 - right) for left, right in edges))

    rng = random.Random(SEED)
    for index in range(128):
        nodes = rng.randrange(4, 17)
        probability = (0.04, 0.12, 0.25, 0.5, 0.9)[index % 5]
        edges = [edge for edge in itertools.product(range(nodes), repeat=2) if rng.random() < probability]
        append(nodes, edges)

    for nodes, edges in ((0, ()), (3, ()), (3, ((0, 1), (1, 2))),
                         (3, ((0, 0),)), witnesses[3], witnesses[5], witnesses[6]):
        _, targets = canonical(nodes, edges)
        for operation in (0, 1):
            need = required(operation, nodes, len(targets))
            validation = nodes + 1 + len(targets)
            for budget in sorted({0, validation - 1, validation, need - 1, need, need + 1, MASK}):
                append(nodes, edges, operations=(operation,), max_work=budget)
        for max_nodes, max_edges in ((-1, -1), (-1, 0), (0, -1),
                                     (max(0, nodes - 1), 1000), (100, max(0, len(targets) - 1))):
            append(nodes, edges, max_nodes=max_nodes, max_edges=max_edges)

    malformed = ((3, (-1, 1, 2, 2), (1, 2)), (3, (1, 1, 2, 2), (1, 2)),
                 (3, (0, 2, 1, 2), (1, 2)), (3, (0, 1, 2, 3), (1, 2)),
                 (3, (0, 1, 1, 1), (1, 2)), (3, (0, 1, 2, 2), (-1, 2)),
                 (3, (0, 1, 2, 2), (3, 2)), (3, (0, 2, 2, 2), (1, 1)),
                 (3, (0, 2, 2, 2), (2, 1)), (3, (0, 1, 2, 3), (-1, 2)),
                 (0, (0,), (0,)), (0, (1,), ()),
                 (3, (0, 1, 2, 2), (1, MAX_I32)), (3, (0, 1, 2, 2), (MIN_I32, 2)))
    for nodes, offsets, targets in malformed:
        for budget in (1_000_000, nodes + 1 + len(targets)):
            append(nodes, offsets=offsets, targets=targets, max_work=budget)

    for nodes in (-1, MIN_I32, MAX_NODES, MAX_NODES + 1, MAX_I32):
        append(nodes, offsets=(0,), targets=(), max_nodes=MAX_I32,
               max_edges=MAX_I32, max_work=0, offset_length=nodes + 1 if 0 <= nodes < MAX_I32 else 1)
    for start, length in ((-1, 0), (MIN_I32, 1), (2, -1), (2, MIN_I32), (MAX_I32, 1), (MAX_I32 - 1, 2)):
        append(3, offset_start=start, offset_length=length)
        append(3, target_start=start, target_length=length)
    for edge_length in (MAX_EDGES, MAX_EDGES + 1, MAX_I32):
        append(0, max_nodes=MAX_I32, max_edges=MAX_I32, max_work=0, target_length=edge_length)
    append(1, target_start=MAX_I32, target_length=0)
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.operation in (0, 1) and case.layout in (0, 1)
        assert len(case.offsets) <= 20 and len(case.targets) <= 256
        numbers = (case.nodes, case.max_nodes, case.max_edges, case.offset_start,
                   case.offset_length, case.target_start, case.target_length)
        assert all(MIN_I32 <= value <= MAX_I32 for value in numbers)
        assert 0 <= case.max_work <= MASK
        fields = (case.operation, case.layout, case.nodes, case.max_nodes, case.max_edges,
                  case.max_work, case.offset_start, case.offset_length, case.target_start,
                  case.target_length, len(case.offsets), len(case.targets)) + case.offsets + case.targets
        data += struct.pack("<" + "Q" * len(fields), *(word & MASK for word in fields))
    return data


def encode(values):
    data = bytearray()
    for case in values:
        words = reference(case)
        data += struct.pack("<" + "Q" * len(words), *words)
    return data


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        expected = reference(case)
        size = len(expected) * 8
        assert offset + size <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        observed = struct.unpack_from("<" + "Q" * len(expected), actual, offset)
        if tuple(expected) != observed:
            word = next(at for at, pair in enumerate(zip(observed, expected)) if pair[0] != pair[1])
            raise AssertionError((f"seed={SEED:#x}", index, case, "word", word,
                                  "observed", observed[word], "expected", expected[word]))
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values), values)
    edges = ((0, 1), (1, 0), (2, 3), (3, 2), (4, 5), (5, 4), (4, 2), (3, 0))
    assert components(6, edges) == ((0, 0, 1, 1, 2, 2), 3, (0, 0, 1, 2), (0, 1), (2, 1, 0))
    assert components(0, ()) == ((), 0, (0,), (), ())
    assert components(3, ((1, 1),)) == ((0, 1, 2), 3, (0, 0, 0, 0), (), (0, 1, 2))
    collapse = ((0, 1), (1, 0), (2, 3), (3, 2), (0, 2), (0, 3), (1, 2), (1, 3))
    assert components(4, collapse) == ((0, 0, 1, 1), 2, (0, 1, 1), (1,), (0, 1))
    offsets, targets = canonical(6, edges)
    sample = Case(1, 0, 6, 100, 1000, 1_000_000, 2, 7, 2, len(targets), offsets, targets)
    words = reference(sample)
    start = PREFIX_WORDS
    mapping_start = start + 7
    pair_start = mapping_start + 6 * 5
    csr_start = pair_start + 36 * 5 + 40
    closed_start = csr_start + 3 + 4 + 2 + 4 + 1 + 3
    assert words[csr_start:csr_start + 9] == [1, 3, 2, 0, 0, 1, 2, 0, 1]
    assert words[closed_start:closed_start + 4] == [1, 0, 0, 0]
    mutations = ((2, 8), (3, 99), (start + 6, 2), (mapping_start + 4, 2),
                 (pair_start + 5 + 4, 0), (csr_start + 8, 2), (csr_start + 9 + 5, 0),
                 (closed_start + 4 + 1, 2))
    for word, replacement in mutations:
        bad = encode([sample])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try:
            verify(bad, [sample])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted verifier corruption", word))
    for bad in (encode([sample])[:-1], encode([sample]) + b"\0"):
        try:
            verify(bad, [sample])
        except AssertionError:
            pass
        else:
            raise AssertionError("accepted framing corruption")
    malformed = replace(sample, nodes=3, offset_length=4, offsets=(0, 1, 2, 3), targets=(-1, 2), target_length=2, max_work=6)
    assert reference(malformed)[start:start + 4] == [1, 6, 2, MASK]
    malformed = replace(malformed, offsets=(0, 1, 2, 2))
    assert reference(malformed)[start:start + 4] == [1, 8, 0, 0]
    assert reference(replace(malformed, max_work=5))[start:start + 4] == [1, 5, MASK, MASK]
    counts = Counter(reference(case)[PREFIX_WORDS + 1] for case in values)
    print(f"graph-components CPU cases={len(values)} operations=2 storage-preparations=2 seed={SEED:#x} verifier-corruptions=10")
    print(f"graph-components first-status={dict(sorted(counts.items()))} closure-analyses={components.cache_info().currsize}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f"graph-components cases={len(values)} operations=2 storage-preparations=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
