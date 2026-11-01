"""Independent sets/paths/permutations reference for directed simple graphs.

No BFS queue, Kahn heap or storage sort implementation is reproduced.
Python and binary framing are test infrastructure only.
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

SEED = 0x6A4F0261103
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
MAX_NODES, MAX_EDGES = 536870910, 268435455
# This gate's native x86_64 profile stores Edge as two eight-byte i32 slots.
# The portable graph ceiling and the owned staging byte ceiling both apply.
NATIVE_EDGE_BYTES = 16
STAGING_EDGES = MAX_I32 // NATIVE_EDGE_BYTES
SUCCESS = [0, 0, -1, -1]


@dataclass(frozen=True)
class Case:
    operation: int
    layout: int
    nodes: int
    query: int
    max_nodes: int
    max_edges: int
    max_work: int
    edge_start: int
    edge_length: int
    offset_start: int
    offset_length: int
    target_start: int
    target_length: int
    edges: tuple
    offsets: tuple
    targets: tuple


class GraphError(Exception):
    def __init__(self, code, node=-1, edge=-1): self.code, self.node, self.edge = code, node, edge


def failed(code, node=-1, edge=-1): return [1, code, node, edge]


def height(value): return max(value - 1, 0).bit_length()


def work(operation, nodes, edges):
    validation = nodes + 1 + edges
    if operation == 0: return nodes + 1 + 6 * edges + 4 * edges * (1 + height(edges))
    if operation == 1: return 2 * validation
    if operation == 5: return validation + 4 * nodes + 2 * edges + 1
    if operation == 6: return validation + 4 * nodes + 2 * edges + 4 * nodes * (1 + height(nodes))
    return validation


def bounds(start, length): return start >= 0 and length >= 0 and start + length <= MAX_I32


def initial(case):
    edges = [(-700 - index, -900 - index) for index in range(100)]
    offsets, targets = [-777] * 12, [-888] * 100
    edges[2:2 + len(case.edges)] = case.edges
    offsets[2:2 + len(case.offsets)] = case.offsets
    targets[2:2 + len(case.targets)] = case.targets
    return edges, offsets, targets


def admission(case, construction=False):
    if min(case.max_nodes, case.max_edges) < 0: raise GraphError(1)
    descriptors = ((case.edge_start, case.edge_length),) if construction else (
        (case.offset_start, case.offset_length), (case.target_start, case.target_length))
    if case.nodes < 0 or not all(bounds(*descriptor) for descriptor in descriptors): raise GraphError(2)
    if case.nodes > min(MAX_NODES, case.max_nodes): raise GraphError(3)
    count = case.edge_length if construction else case.target_length
    if count > min(MAX_EDGES, case.max_edges): raise GraphError(4)
    if construction and count > STAGING_EDGES: raise GraphError(4)
    if not construction and case.offset_length != case.nodes + 1: raise GraphError(2)
    operation = 0 if construction else (1 if case.operation == 1 else 2)
    required = work(operation, case.nodes, count)
    if case.max_work < required: raise GraphError(5)


def canonical(nodes, edges):
    selected = tuple(sorted(set(edges)))
    offsets = [0]
    targets = []
    for node in range(nodes):
        targets.extend(target for source, target in selected if source == node)
        offsets.append(len(targets))
    return tuple(offsets), tuple(targets)


def construct(case):
    admission(case, True)
    backing, _, _ = initial(case)
    assert case.edge_start + case.edge_length <= len(backing) or case.edge_length == 0
    chosen = backing[case.edge_start:case.edge_start + case.edge_length]
    for ordinal, (source, target) in enumerate(chosen):
        if not 0 <= source < case.nodes: raise GraphError(7, source, ordinal)
        if not 0 <= target < case.nodes: raise GraphError(8, target, ordinal)
    return canonical(case.nodes, chosen)


def validate(case):
    admission(case)
    _, offset_backing, target_backing = initial(case)
    assert case.offset_start + case.offset_length <= len(offset_backing)
    assert case.target_length == 0 or case.target_start + case.target_length <= len(target_backing)
    offsets = tuple(offset_backing[case.offset_start:case.offset_start + case.offset_length])
    targets = tuple(target_backing[case.target_start:case.target_start + case.target_length])
    count = len(targets)
    if offsets[0] != 0: raise GraphError(6, 0 if case.nodes else -1)
    for node in range(case.nodes):
        if not offsets[node] <= offsets[node + 1] <= count: raise GraphError(6, node)
    if offsets[-1] != count: raise GraphError(6, case.nodes - 1)
    for node in range(case.nodes):
        previous = None
        for edge in range(offsets[node], offsets[node + 1]):
            target = targets[edge]
            if not 0 <= target < case.nodes: raise GraphError(8, node, edge)
            if previous is not None and target <= previous: raise GraphError(9, node, edge)
            previous = target
    return offsets, targets


@lru_cache(maxsize=None)
def analysis(nodes, edges):
    """All-pairs distance, exhaustive shortest simple paths and all orders."""
    edges = frozenset(edges)
    infinity = nodes + 1
    distance = [[0 if a == b else infinity for b in range(nodes)] for a in range(nodes)]
    for source, target in edges: distance[source][target] = min(distance[source][target], 1)
    for middle in range(nodes):
        distance = [[min(distance[a][b], distance[a][middle] + distance[middle][b])
                     for b in range(nodes)] for a in range(nodes)]
    parents = [[None] * nodes for _ in range(nodes)]
    for source in range(nodes):
        for target in range(nodes):
            hops = distance[source][target]
            if hops in (0, infinity): continue
            candidates = []
            interior = tuple(vertex for vertex in range(nodes) if vertex not in (source, target))
            for middle in itertools.permutations(interior, hops - 1):
                path = (source,) + middle + (target,)
                if all(edge in edges for edge in zip(path, path[1:])): candidates.append(path)
            assert candidates, (nodes, edges, source, target, hops)
            parents[source][target] = min(candidates)[-2]
    orders = []
    for order in itertools.permutations(range(nodes)):
        positions = {node: index for index, node in enumerate(order)}
        if all(positions[source] < positions[target] for source, target in edges): orders.append(order)
    return (tuple(tuple(None if value == infinity else value for value in row) for row in distance),
            tuple(tuple(row) for row in parents), min(orders) if orders else None, len(orders))


def edge_set(nodes, offsets, targets):
    return tuple((node, targets[edge]) for node in range(nodes)
                 for edge in range(offsets[node], offsets[node + 1]))


def csr(nodes, offsets, targets): return [nodes, len(targets)] + list(offsets) + list(targets)


def option(value): return [0, -1] if value is None else [1, value]


def neighbor_result(case, offsets, targets, query):
    if case.max_work < work(2, case.nodes, len(targets)): return failed(5)
    if not 0 <= query < case.nodes: return failed(2, query)
    chosen = targets[offsets[query]:offsets[query + 1]]
    return SUCCESS + [len(chosen)] + list(chosen)


def bfs_result(case, offsets, targets, source):
    if case.max_work < work(2, case.nodes, len(targets)): return failed(5)
    if not 0 <= source < case.nodes: return failed(2, source)
    if case.max_work < work(5, case.nodes, len(targets)): return failed(5)
    distances, parents, _, _ = analysis(case.nodes, edge_set(case.nodes, offsets, targets))
    result = SUCCESS + [1, case.nodes] + option(source)
    for node in range(case.nodes):
        result += SUCCESS + option(distances[source][node]) + SUCCESS + option(parents[source][node])
    result += failed(2, -1) + failed(2, -1) + failed(2, case.nodes) + failed(2, case.nodes)
    result += [1, 0, 0, 0] + option(None) + failed(12) + failed(12)
    return result


def topology_result(case, offsets, targets):
    if case.max_work < work(2, case.nodes, len(targets)): return failed(5)
    if case.max_work < work(6, case.nodes, len(targets)): return failed(5)
    _, _, order, _ = analysis(case.nodes, edge_set(case.nodes, offsets, targets))
    return failed(11) if order is None else SUCCESS + [len(order)] + list(order)


def owned(case, offsets, targets):
    nodes, count = case.nodes, len(targets)
    result = SUCCESS + [1, nodes, count, 1] + csr(nodes, offsets, targets)
    result += SUCCESS + [count]
    for query in range(-1, nodes + 1): result += neighbor_result(case, offsets, targets, query)
    for source in range(-1, nodes + 1): result += bfs_result(case, offsets, targets, source)
    result += topology_result(case, offsets, targets)
    result += csr(nodes, offsets, targets) + [1, 0, 0, 0, 0, 0]
    return result


def reference(case):
    try:
        if case.operation == 0:
            offsets, targets = construct(case)
            result = owned(case, offsets, targets)
        else:
            offsets, targets = validate(case)
            if case.operation == 1:
                result = owned(case, offsets, targets)
            elif case.operation == 2: result = SUCCESS + [len(targets)]
            elif case.operation == 3: result = SUCCESS + csr(case.nodes, offsets, targets)
            elif case.operation == 4: result = neighbor_result(case, offsets, targets, case.query)
            elif case.operation == 5: result = bfs_result(case, offsets, targets, case.query)
            else:
                assert case.operation == 6
                result = topology_result(case, offsets, targets)
    except GraphError as error:
        result = failed(error.code, error.node, error.edge)
    edges, offsets, targets = initial(case)
    result += [word for edge in edges for word in edge] + offsets + targets
    return [word & MASK for word in result]


def cases():
    result, seen = [], set()
    def append(operation, nodes, edges=(), offsets=None, targets=None, query=0,
               max_nodes=100, max_edges=100, max_work=1_000_000, **metadata):
        edges = tuple(edges)
        if offsets is None or targets is None:
            offsets, targets = canonical(max(0, min(nodes, 6)),
                                         ((a, b) for a, b in edges if 0 <= a < nodes and 0 <= b < nodes))
        for layout in range(2):
            case = Case(operation, layout, nodes, query, max_nodes, max_edges, max_work,
                        metadata.get("edge_start", 2), metadata.get("edge_length", len(edges)),
                        metadata.get("offset_start", 2), metadata.get("offset_length", len(offsets)),
                        metadata.get("target_start", 2), metadata.get("target_length", len(targets)),
                        edges, tuple(offsets), tuple(targets))
            if case not in seen:
                seen.add(case)
                result.append(case)

    # Every directed graph on 0..3 labeled nodes, including every self-loop.
    exhaustive = 0
    for nodes in range(4):
        possible = tuple(itertools.product(range(nodes), repeat=2))
        for bits in range(1 << len(possible)):
            edges = tuple(edge for ordinal, edge in enumerate(possible) if bits & (1 << ordinal))
            append(0, nodes, edges)
            if edges: append(0, nodes, tuple(reversed(edges)) + edges[::2])
            if bits % 16 == 0: append(1, nodes, edges)
            exhaustive += 1
    assert exhaustive == 531

    # Every upper-triangular 4-node DAG, plus reversed labels/order.
    possible = tuple((a, b) for a in range(4) for b in range(a + 1, 4))
    for bits in range(64):
        edges = tuple(edge for ordinal, edge in enumerate(possible) if bits & (1 << ordinal))
        append(0, 4, edges)
        append(0, 4, tuple((3 - a, 3 - b) for a, b in reversed(edges)))

    witness = ((0, 1), (0, 2), (1, 5), (2, 3), (5, 4), (3, 4))
    for operation in (0, 1, 5, 6): append(operation, 6, witness, query=0)
    for nodes, edges in ((0, ()), (5, ()), (6, tuple((i, i + 1) for i in range(5))),
                          (6, tuple((0, i) for i in range(1, 6))),
                          (6, tuple((i, i + 1) for i in range(5)) + ((5, 0),)),
                          (4, ((0, 0),)), (5, ((1, 2), (3, 4)))):
        for operation in (0, 1, 2, 3, 4, 5, 6): append(operation, nodes, edges, query=0)

    rng = random.Random(SEED)
    for _ in range(200):
        nodes = rng.randrange(1, 7)
        probability = rng.choice((0.1, 0.25, 0.5, 0.8))
        edges = [edge for edge in itertools.product(range(nodes), repeat=2) if rng.random() < probability]
        edges += rng.sample(edges, rng.randrange(min(8, len(edges)) + 1))
        rng.shuffle(edges)
        append(0, nodes, edges)
        if rng.randrange(4) == 0: append(1, nodes, edges)

    malformed = ((3, (0, 1, 2, 2), (1, 2)), (3, (-1, 1, 2, 2), (1, 2)),
                 (3, (1, 1, 2, 2), (1, 2)), (3, (0, 2, 1, 2), (1, 2)),
                 (3, (0, 1, 2, 3), (1, 2)), (3, (0, 1, 1, 1), (1, 2)),
                 (3, (0, 1, 2, 2), (-1, 2)), (3, (0, 1, 2, 2), (3, 2)),
                 (3, (0, 2, 2, 2), (1, 1)), (3, (0, 2, 2, 2), (2, 1)),
                 (3, (0, 1, 2, 3), (-1, 2)), (0, (0,), (0,)), (0, (1,), ()))
    for nodes, offsets, targets in malformed:
        for operation in range(1, 7):
            for query in (-1, nodes):
                append(operation, nodes, (), offsets, targets, query=query)
                append(operation, nodes, (), offsets, targets, query=query,
                       max_work=work(2, nodes, len(targets)))

    # Every operation's exact estimate and validation-before-body precedence.
    for nodes, edges in ((0, ()), (3, ()), (3, ((0, 1), (1, 2))),
                          (3, ((0, 1), (0, 1), (1, 2))), (3, ((0, 0),))):
        offsets, targets = canonical(nodes, edges)
        for operation in range(7):
            count = len(edges) if operation == 0 else len(targets)
            required = work(operation, nodes, count)
            for max_work in sorted({0, max(0, required - 1), required, required + 1, MASK}):
                append(operation, nodes, edges, offsets, targets, max_work=max_work)
            for query in (-1, nodes, MIN_I32, MAX_I32):
                if operation in (4, 5): append(operation, nodes, edges, offsets, targets, query=query)
            for max_nodes, max_edges in ((-1, -1), (-1, 0), (0, -1),
                                          (max(0, nodes - 1), 100), (100, max(0, count - 1))):
                append(operation, nodes, edges, offsets, targets, max_nodes=max_nodes, max_edges=max_edges)

    for edges in (((3, -1),), ((-1, 3),), ((0, 1), (3, 0), (-1, 0)),
                   ((0, 1), (2, 3), (-1, -1)), ((0, 0), (0, 0), (1, 3)),
                   ((MIN_I32, MAX_I32),), ((2, MIN_I32),)):
        append(0, 3, edges)

    for operation in range(7):
        for nodes in (-1, MIN_I32, MAX_NODES, MAX_NODES + 1, MAX_I32):
            append(operation, nodes, (), (0,), (), max_nodes=MAX_I32,
                   max_edges=MAX_I32, max_work=0, offset_length=nodes + 1 if 0 <= nodes < MAX_I32 else 1)
        for descriptor in ((-1, 0), (MIN_I32, 1), (2, -1), (2, MIN_I32), (MAX_I32, 1), (MAX_I32 - 1, 2)):
            start, length = descriptor
            if operation == 0:
                append(operation, 3, ((0, 1),), edge_start=start, edge_length=length)
            else:
                append(operation, 3, (), (0, 0, 0, 0), (), offset_start=start, offset_length=length)
                append(operation, 3, (), (0, 0, 0, 0), (), target_start=start, target_length=length)
        for edge_length in (MAX_EDGES, MAX_EDGES + 1, MAX_I32):
            fields = {"edge_length": edge_length} if operation == 0 else {"target_length": edge_length}
            append(operation, 0, (), (0,), (), max_nodes=MAX_I32, max_edges=MAX_I32, max_work=0, **fields)
    assert len(result) == 4570
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.operation in range(7) and case.layout in (0, 1)
        assert len(case.edges) <= 96 and len(case.offsets) <= 10 and len(case.targets) <= 96
        numbers = (case.nodes, case.query, case.max_nodes, case.max_edges, case.edge_start,
                   case.edge_length, case.offset_start, case.offset_length, case.target_start, case.target_length)
        assert all(MIN_I32 <= value <= MAX_I32 for value in numbers)
        assert 0 <= case.max_work <= MASK
        fields = (case.operation, case.layout, case.nodes, case.query, case.max_nodes,
                  case.max_edges, case.max_work, case.edge_start, case.edge_length, case.offset_start,
                  case.offset_length, case.target_start, case.target_length, len(case.edges), len(case.offsets), len(case.targets))
        fields += tuple(word for edge in case.edges for word in edge) + case.offsets + case.targets
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
        assert list(observed) == expected, (f"seed={SEED:#x}", index, case, observed, expected)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::43]), values[::43])
    assert canonical(3, ((2, 2), (0, 1), (0, 1))) == ((0, 1, 1, 2), (1, 2))
    witness = ((0, 1), (0, 2), (1, 5), (2, 3), (5, 4), (3, 4))
    distances, parents, order, valid_orders = analysis(6, tuple(sorted(witness)))
    assert distances[0][4] == 3 and parents[0][4] == 5 and parents[0][4] > 3
    assert order == (0, 1, 2, 3, 5, 4) and valid_orders > 1
    assert analysis(1, ((0, 0),))[2] is None
    assert analysis(0, ())[2] == ()
    def sample(**changes):
        fields = dict(operation=2, layout=0, nodes=3, query=0, max_nodes=100, max_edges=100,
                      max_work=10000, edge_start=2, edge_length=0, offset_start=2, offset_length=4,
                      target_start=2, target_length=2, edges=(), offsets=(0, 1, 2, 2), targets=(1, 2))
        fields.update(changes)
        return Case(**fields)
    valid = sample()
    assert reference(valid)[:5] == [0, 0, MASK, MASK, 2]
    offset = sample(offsets=(0, 1, 2, 3), targets=(-1, 2))
    assert reference(offset)[:4] == [1, 6, 2, MASK]
    copy_admission = sample(operation=1, offsets=(-1, 1, 2, 2), max_work=6)
    assert reference(copy_admission)[:4] == [1, 5, MASK, MASK]
    assert reference(replace(copy_admission, max_work=12))[:4] == [1, 6, 0, MASK]
    staging = sample(operation=0, edge_length=STAGING_EDGES + 1,
                     max_edges=MAX_I32, max_work=0)
    assert reference(staging)[:4] == [1, 4, MASK, MASK]
    assert reference(replace(staging, edge_length=STAGING_EDGES))[:4] == [1, 5, MASK, MASK]
    source = sample(operation=0, edges=((0, 1), (-1, 3)), edge_length=2)
    assert reference(source)[:4] == [1, 7, MASK, 1]
    query = sample(operation=5, query=-1, max_work=work(2, 3, 2))
    assert reference(query)[:4] == [1, 2, MASK, MASK]
    target = sample(targets=(1, 3))
    assert reference(target)[:4] == [1, 8, 1, 1]
    bounds_case = sample(operation=4, query=MAX_I32)
    assert reference(bounds_case)[:4] == [1, 2, MAX_I32, MASK]
    bfs_case = sample(operation=5, nodes=6, offset_length=7, target_length=6,
                      offsets=(0, 2, 3, 4, 5, 5, 6), targets=(1, 2, 5, 3, 4, 4))
    bfs_words = reference(bfs_case)
    # Per-node option results occupy 12 words after the 8-word owner header.
    assert bfs_words[8 + 4 * 12 + 6 + 5] == 5
    topology_case = replace(bfs_case, operation=6)
    assert reference(topology_case)[:11] == [0, 0, MASK, MASK, 6, 0, 1, 2, 3, 5, 4]
    mutations = ((valid, 4, 1), (offset, 1, 8), (source, 3, 0), (target, 2, 0),
                 (bounds_case, 2, 0), (bfs_case, 8 + 4 * 12 + 6 + 5, 3),
                 (topology_case, 5, 5), (valid, 5, 0))
    for case, word, replacement in mutations:
        bad = encode([case])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted verifier corruption", case, word))
    operations, statuses = Counter(), Counter()
    for case in values:
        words = reference(case)
        operations[case.operation] += 1
        statuses[words[1]] += 1
    print(f"directed-graph CPU cases={len(values)} operations=7 layouts=2 seed={SEED:#x} verifier-corruptions=8")
    print(f"directed-graph operations={dict(sorted(operations.items()))} first-status={dict(sorted(statuses.items()))} canonical-analyses={analysis.cache_info().currsize}")


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
    print(f"directed-graph cases={len(values)} operations=7 layouts=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
