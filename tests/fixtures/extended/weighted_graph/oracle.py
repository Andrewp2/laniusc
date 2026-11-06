"""Integer shortest paths from exhaustive simple paths and reachable cycles.

No Dijkstra queue or Bellman--Ford relaxation schedule is reproduced here.
Small costs keep this model separate from the direct checked-i64 boundary gate.
Binary framing and Python are test infrastructure only.
"""
from collections import Counter
from dataclasses import dataclass
from functools import lru_cache
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x6A90261107
MAGIC = 0x57474936344D4F44
MASK = (1 << 64) - 1


@dataclass(frozen=True)
class Case:
    nodes: int
    source: int
    edges: tuple


def corpus():
    cases = []
    pairs = tuple(itertools.product(range(2), repeat=2))
    for weights in itertools.product((None, -1, 0, 2), repeat=4):
        edges = tuple((a, b, w) for (a, b), w in zip(pairs, weights) if w is not None)
        cases.extend(Case(2, source, edges) for source in range(2))
    pairs = tuple((a, b) for a in range(3) for b in range(3) if a != b)
    for weights in itertools.product((None, 0, 2), repeat=6):
        edges = tuple((a, b, w) for (a, b), w in zip(pairs, weights) if w is not None)
        cases.extend(Case(3, source, edges) for source in range(3))
    rng = random.Random(SEED)
    extra = []
    for ordinal in range(96):
        nodes = 4 + ordinal % 3
        edges = []
        for a in range(nodes):
            for b in range(nodes):
                if ordinal >= 64 and a >= b:
                    continue  # Signed DAGs guarantee meaningful finite distances.
                if rng.randrange(4) == 0:
                    cost = rng.randrange(-4, 10)
                    edges.append((a, b, cost))
                    if rng.randrange(3) == 0:
                        edges.extend(((a, b, cost), (a, b, cost + 3)))
        extra.append(Case(nodes, rng.randrange(nodes), tuple(edges)))
    cases.extend(extra)
    for original in extra[:12]:
        changed = list(original.edges)
        rng.shuffle(changed)
        cases.extend((Case(original.nodes, original.source, tuple(changed)),
                      Case(original.nodes, original.source, tuple(reversed(changed)))))
    return cases


def canonical(case):
    edges = tuple(sorted(case.edges))
    offsets = [0]
    arcs = []
    for node in range(case.nodes):
        arcs.extend((target, cost) for source, target, cost in edges if source == node)
        offsets.append(len(arcs))
    return tuple(offsets), tuple(arcs), edges


@lru_cache(maxsize=None)
def mathematics(nodes, source, edges):
    # Parallel arcs retain their identities in the native storage check. Only
    # their cheapest cost matters to the independent optimal-cost calculation.
    cheapest = {}
    for a, b, cost in edges:
        cheapest[a, b] = min(cost, cheapest.get((a, b), cost))
    adjacency = [tuple((b, cheapest[a, b]) for b in range(nodes) if (a, b) in cheapest)
                 for a in range(nodes)]
    distances = [None] * nodes

    def paths(node, visited, cost):
        if distances[node] is None or cost < distances[node]:
            distances[node] = cost
        for target, weight in adjacency[node]:
            if target not in visited:
                paths(target, visited | {target}, cost + weight)

    paths(source, {source}, 0)
    reachable = tuple(value is not None for value in distances)

    def negative_cycle(start, node, visited, cost):
        for target, weight in adjacency[node]:
            if target == start and cost + weight < 0:
                return True
            if target not in visited and negative_cycle(start, target, visited | {target}, cost + weight):
                return True
        return False

    negative = any(reachable[start] and negative_cycle(start, start, {start}, 0)
                   for start in range(nodes))
    return tuple(distances), reachable, negative


def analyze(case, algorithm, result):
    offsets, arcs, edges = canonical(case)
    distances, reachable, cycle = mathematics(case.nodes, case.source, edges)
    negative = next((index for index, (_, _, cost) in enumerate(edges) if cost < 0), None)
    kind, node, edge, records = result
    if algorithm == 0 and negative is not None:
        assert (kind, node, edge) == (10, edges[negative][0], negative), result
        assert records is None
        return "negative-edge"
    if algorithm == 1 and cycle:
        assert kind == 12 and 0 <= edge < len(edges), result
        assert node == edges[edge][0] and reachable[node], result
        assert records is None
        return "negative-cycle"
    assert kind == 0 and records is not None and len(records) == case.nodes, result
    assert [record[0] for record in records] == list(distances), (case, algorithm, result, distances)
    edge_set = set(edges)
    for target, (distance, predecessor, path) in enumerate(records):
        if distance is None:
            assert predecessor is None and path is None, (target, records[target])
            continue
        assert path is not None and len(path) < case.nodes, (target, path)
        if target == case.source:
            assert distance == 0 and predecessor is None and path == (), (target, records[target])
            continue
        assert path and predecessor == path[-1], (target, predecessor, path)
        current, total, visited = case.source, 0, {case.source}
        for a, b, cost in path:
            assert a == current and (a, b, cost) in edge_set and b not in visited, (target, path)
            assert records[b][1] == (a, b, cost), (target, path, records[b])
            visited.add(b)
            current, total = b, total + cost
        assert current == target and total == distance, (target, path, distance)
    return "finite"


class Reader:
    def __init__(self, raw):
        assert len(raw) % 8 == 0, "truncated weighted graph output"
        self.words = struct.unpack("<" + "Q" * (len(raw) // 8), raw)
        self.at = 0

    def word(self):
        assert self.at < len(self.words), "missing weighted graph output"
        value = self.words[self.at]
        self.at += 1
        return value

    def signed(self):
        value = self.word()
        return value - (1 << 64) if value >> 63 else value

    def edge(self):
        return self.signed(), self.signed(), self.signed()

    def option(self, read):
        flag = self.word()
        assert flag in (0, 1), flag
        return read() if flag else None

    def path(self):
        count = self.word()
        assert count <= 6, count
        return tuple(self.edge() for _ in range(count))


def decode(raw, cases):
    reader, results = Reader(raw), []
    counts = Counter()
    deterministic = {}
    for index, case in enumerate(cases):
        assert reader.word() == index, (index, reader.at)
        offsets, arcs, edges = canonical(case)
        assert (reader.word(), reader.word()) == (case.nodes, len(arcs))
        assert tuple(reader.signed() for _ in offsets) == offsets
        assert tuple((reader.signed(), reader.signed()) for _ in arcs) == arcs
        outputs = []
        for algorithm in range(2):
            assert reader.word() == algorithm
            kind, node, edge = reader.word(), reader.signed(), reader.signed()
            records = None
            if kind == 0:
                assert (reader.word(), reader.word(), reader.word()) == (1, case.nodes, case.source)
                records = tuple((reader.option(reader.signed), reader.option(reader.edge), reader.option(reader.path))
                                for _ in range(case.nodes))
            result = kind, node, edge, records
            counts[analyze(case, algorithm, result)] += 1
            outputs.append(result)
        assert tuple(reader.edge() for _ in case.edges) == case.edges, "construction mutated original edges"
        assert reader.word() == 1, "input guards or owner lifecycle failed"
        signature = case.nodes, case.source, edges
        if signature in deterministic:
            assert outputs == deterministic[signature], "canonical inputs changed deterministic tie/error results"
        else:
            deterministic[signature] = outputs
        results.append(outputs)
    assert reader.at == len(reader.words), "unexpected output suffix"
    assert all(counts[name] for name in ("finite", "negative-edge", "negative-cycle")), counts
    return counts, results


def encode(cases):
    words = [MAGIC, len(cases)]
    for case in cases:
        assert 1 <= case.nodes <= 6 and len(case.edges) <= 64
        words.extend((case.nodes, case.source, len(case.edges)))
        for edge in case.edges:
            words.extend(value & MASK for value in edge)
    return struct.pack("<" + "Q" * len(words), *words)


def controls():
    case = Case(4, 0, ((0, 1, 2), (0, 2, 4), (1, 2, -1), (1, 2, 7)))
    records = ((0, None, ()), (2, (0, 1, 2), ((0, 1, 2),)),
               (1, (1, 2, -1), ((0, 1, 2), (1, 2, -1))), (None, None, None))
    good = 0, -1, -1, records
    assert analyze(case, 1, good) == "finite"
    changed = []
    wrong = list(records); wrong[2] = (2, records[2][1], records[2][2]); changed.append((0, -1, -1, tuple(wrong)))
    wrong = list(records); wrong[2] = (1, (0, 2, 4), ((0, 2, 4),)); changed.append((0, -1, -1, tuple(wrong)))
    wrong = list(records); wrong[2] = (1, (1, 2, -1), ((0, 1, 3), (1, 2, -1))); changed.append((0, -1, -1, tuple(wrong)))
    wrong = list(records); wrong[3] = (0, None, ()); changed.append((0, -1, -1, tuple(wrong)))
    wrong = list(records); wrong[0] = (0, (0, 0, 0), ((0, 0, 0),)); changed.append((0, -1, -1, tuple(wrong)))
    changed.extend(((12, 0, 0, None), (11, 0, 0, None)))
    for result in changed:
        try:
            analyze(case, 1, result)
        except AssertionError:
            continue
        raise AssertionError(("weighted model admitted a corrupted result", result))
    unreachable_cycle = Case(3, 0, ((0, 1, 2), (2, 2, -1)))
    assert mathematics(3, 0, tuple(sorted(unreachable_cycle.edges))) == ((0, 2, None), (True, True, False), False)
    reachable_cycle = Case(3, 0, ((0, 1, 2), (1, 2, 0), (2, 1, -1)))
    assert mathematics(3, 0, tuple(sorted(reachable_cycle.edges)))[2]
    assert analyze(reachable_cycle, 1, (12, 1, 1, None)) == "negative-cycle"
    assert analyze(unreachable_cycle, 0, (10, 2, 1, None)) == "negative-edge"
    return 1 + len(changed) + 4


def main():
    checked = controls()
    cases = corpus()
    if sys.argv[1:] == ["controls"]:
        print(f"weighted-graph-model controls={checked} cases={len(cases)}")
        return
    assert len(sys.argv) == 2
    result = subprocess.run([str(Path(sys.argv[1]).resolve())], input=encode(cases), capture_output=True, timeout=50)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr[:1000])
    counts, _ = decode(result.stdout, cases)
    print(f"weighted-graph-model cases={len(cases)} algorithms={2*len(cases)} finite={counts['finite']} "
          f"negative_edges={counts['negative-edge']} negative_cycles={counts['negative-cycle']} "
          f"controls={checked} seed=0x{SEED:x}")


if __name__ == "__main__":
    main()
