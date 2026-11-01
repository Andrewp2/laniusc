"""Independent permutation-order, shortest-path and mutual-reachability oracles."""
from collections import Counter
import csv
from io import StringIO
import itertools
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 4194304
HELP = (b'Usage: dependency_order --nodes N [--source S | --components] [--help]\n'
        b'Read CSV before,after and print the lexicographically smallest dependency order.\n'
        b'N is 0..4096; source and edge IDs are in [0,N). Leading zeros are allowed.\n'
        b'Default CSV: position,node,hops,predecessor; positions are zero-based.\n'
        b'--source adds shortest-hop distances and first-discovery predecessors; absent values are empty.\n'
        b'Default mode rejects cycles, including self-loops, without data output.\n'
        b'--components accepts cycles and prints node,component,position in node order.\n'
        b'Component IDs follow smallest member IDs; positions follow component dependency order.\n'
        b'--components and --source cannot be combined. Empty graphs print only the header.\n'
        b'Short options: -n N, -s S, -C, -h. Duplicate options and operands are errors.\n'
        b'Limits: 4 MiB input, 65536 raw edges, 128 bytes per field, 1 MiB staged output.\n'
        b'Input permits 16384 read attempts and output 2048 attempts; interruptions spend attempts.\n'
        b'Help accepts otherwise valid options and does not read stdin.\n')
ERROR = b"dependency_order: operation failed\n"
INPUT_HEADER = b"before,after\n"
HEADER = ("position", "node", "hops", "predecessor")
COMPONENT_HEADER = ("node", "component", "position")
TRACE = "read,write,close,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS = {"model": 166, "rejection": 52, "cli": 58, "io": 36}
OUTPUT_CALLS = 2048


def encode(rows, quoted=False):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL, lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode("ascii")


def graph_input(edges):
    return encode([("before", "after"), *edges])


def ordered_nodes(nodes, edges):
    """Enumerate every possible order; no ready-heap/indegree algorithm."""
    assert 0 <= nodes <= 8
    constraints = set(edges)
    for candidate in itertools.permutations(range(nodes)):
        positions = {node: index for index, node in enumerate(candidate)}
        if all(positions[before] < positions[after] for before, after in constraints): return candidate
    return None


def hop_paths(nodes, edges, source):
    """Dense all-pairs distances plus lexicographically first shortest paths.

    Sorted-neighbor FIFO discovery picks the lexicographically first shortest
    vertex sequence. Build those sequences by distance layers, not a queue or
    a smallest-predecessor rule, which would break the tied-parent control.
    """
    assert 0 <= source < nodes <= 8
    unique = set(edges); infinity = nodes + 1
    matrix = [[0 if row == column else infinity for column in range(nodes)] for row in range(nodes)]
    for before, after in unique: matrix[before][after] = min(matrix[before][after], 1)
    for middle in range(nodes):
        for row in range(nodes):
            for column in range(nodes): matrix[row][column] = min(matrix[row][column], matrix[row][middle] + matrix[middle][column])
    distance = [None if value == infinity else value for value in matrix[source]]
    paths = {source: (source,)}
    for depth in range(1, nodes):
        for target in range(nodes):
            if distance[target] == depth:
                paths[target] = min(paths[before] + (target,) for before, after in unique
                                    if after == target and distance[before] == depth - 1)
    return [(distance[node], paths[node][-2] if node in paths and len(paths[node]) > 1 else None) for node in range(nodes)]


def expected_output(order, paths=None):
    rows = [HEADER]
    for position, node in enumerate(order):
        distance, parent = (None, None) if paths is None else paths[node]
        rows.append((position, node, "" if distance is None else distance, "" if parent is None else parent))
    return encode(rows, quoted=True)


def reference(nodes, edges, source=None):
    assert all(0 <= u < nodes and 0 <= v < nodes for u, v in edges)
    assert source is None or 0 <= source < nodes
    order = ordered_nodes(nodes, edges)
    if order is None: return 2, b""
    return 0, expected_output(order, None if source is None else hop_paths(nodes, edges, source))



def component_partition(nodes, edges):
    """Dense transitive closure defines equivalence; no DFS/lowlink traversal."""
    assert 0 <= nodes <= 8
    reach = [[left == right for right in range(nodes)] for left in range(nodes)]
    for left, right in edges:
        assert 0 <= left < nodes and 0 <= right < nodes
        reach[left][right] = True
    for middle in range(nodes):
        for left in range(nodes):
            for right in range(nodes):
                reach[left][right] |= reach[left][middle] and reach[middle][right]
    groups = []
    mapping = [-1] * nodes
    for first in range(nodes):
        if mapping[first] >= 0: continue
        members = [node for node in range(nodes) if reach[first][node] and reach[node][first]]
        assert members[0] == first
        for node in members:
            assert mapping[node] == -1
            mapping[node] = len(groups)
        groups.append(members)
    return mapping, groups


def component_output(mapping, order):
    assert sorted(set(mapping)) == list(range(len(order)))
    assert sorted(order) == list(range(len(order)))
    position = {component: index for index, component in enumerate(order)}
    return encode([COMPONENT_HEADER, *((node, component, position[component])
                   for node, component in enumerate(mapping))], quoted=True)


def component_reference(nodes, edges):
    mapping, groups = component_partition(nodes, edges)
    between = {(mapping[left], mapping[right]) for left, right in edges
               if mapping[left] != mapping[right]}
    order = ordered_nodes(len(groups), between)
    assert order is not None
    return 0, component_output(mapping, order)


def cap_input():
    # 65536 duplicate 0->1 edges. Length = header13 + 65535*64 + 51.
    row = b"0" * 31 + b"," + b"0" * 30 + b"1\n"
    tail = b"0" * 25 + b"," + b"0" * 23 + b"1\n"
    result = INPUT_HEADER + row * 65535 + tail
    assert len(row) == 64 and len(tail) == 51 and len(result) == CAP
    return result


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z0-9_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
        name, args, answer = match.groups(); counts[name] += 1
        result.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]; assert address not in live; live[address] = size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk", "close"):
            raise AssertionError(("unexpected allocation service/borrowed descriptor close", line))
        elif name == "read": assert args.startswith("0,"), line
        elif name == "write":
            assert int(args.split(",")[0]) in (1, 2), line
            if args.startswith("2,"): assert not live, "diagnostic before owned storage retirement"
    assert not live, ("observed unreleased mappings", live)
    return result


class Runner:
    observes = True
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"dependency-order-{mode}-")); self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", trace=False,
            injections=(), read_error=False, closed_stdout=False, diagnostic=True, budget=None, preflight=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            maximum = 16384 if budget == "read" else OUTPUT_CALLS
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget, "-e",
                       f"inject={budget}:error=EINTR:when=1..{maximum}", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none", "-e",
                      "trace=" + TRACE, "-o", str(prefix.with_suffix(".trace"))]
            for call, ordinal, failure in injections:
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n"); prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try: result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
            finally: os.close(descriptor)
        elif closed_stdout:
            reader, writer = os.pipe(); os.close(reader)
            try: result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
            finally: os.close(writer)
            result.stdout = b""
        else: result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]; selected = []
        for call, ordinal, failure in injections:
            reached = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(reached) == 1 and reached[0]["answer"].startswith("-1 " + failure + " ")
            selected += reached
        assert {item["line"] for item in marked} == {item["line"] for item in selected}
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            expected = ["16384", "16384", "read"] if budget == "read" else [str(OUTPUT_CALLS + 1), str(OUTPUT_CALLS), "write"]
            assert len(selected) == 1 and selected[0][-3:] == expected, rows
        if preflight: assert not any(item["name"] == "read" for item in found)
        self.count += 1; return found

    def graph(self, name, nodes, edges, source=None, *, wire=None, known=None, arguments=None, **options):
        status, output = reference(nodes, edges, source) if known is None else known
        status, output = options.pop("status", status), options.pop("output", output)
        args = ["--nodes", str(nodes)] + ([] if source is None else ["--source", str(source)])
        return self.run(name, args if arguments is None else arguments, graph_input(edges) if wire is None else wire,
                        status=status, output=output, **options)


    def components(self, name, nodes, edges, *, wire=None, known=None, arguments=None, **options):
        status, output = component_reference(nodes, edges) if known is None else known
        status, output = options.pop("status", status), options.pop("output", output)
        args = ["--nodes", str(nodes), "--components"]
        return self.run(name, args if arguments is None else arguments, graph_input(edges) if wire is None else wire,
                        status=status, output=output, **options)


def model(r):
    possible = [(u, v) for u in range(3) for v in range(3) if u != v]
    for mask in range(64):
        edges = [edge for bit, edge in enumerate(possible) if mask & (1 << bit)]
        r.graph(f"every-three-node-directed-{mask}", 3, edges, 0 if mask % 2 else None)
    r.graph("empty-graph", 0, [])
    r.graph("source-singleton", 1, [], 0)
    for source in (None, 3): r.graph(f"isolated-five-{source}", 5, [], source)
    for source in (0, 5): r.graph(f"chain-source-{source}", 6, [(i, i+1) for i in range(5)], source)
    tied = [(0,1),(0,2),(1,5),(2,3),(5,6),(3,6)]
    r.graph("fifo-parent-is-not-minimum-parent", 7, tied, 0)
    r.graph("diamond-and-isolated", 6, [(0,1),(0,2),(1,3),(2,3),(3,4)], 0)
    r.graph("new-small-ready-node-beats-old-queue", 6, [(4,1),(3,0),(1,2)], 4)
    rng = random.Random(0xDAD004)
    for index in range(2):
        edges = tied * (index + 2); rng.shuffle(edges); r.graph(f"duplicates-shuffled-{index}", 7, edges, 0)
    r.graph("quoted-crlf", 3, [(0,2),(1,2)], 1, wire=b'"before","after"\r\n"0","2"\r\n"1","2"\r\n')
    r.graph("unterminated-final-record", 3, [(0,2)], wire=b"before,after\n0,2")
    r.graph("maximum-decoded-field-record", 2, [(0,1)], 0,
            wire=b'"before","after"\n"' + b"0"*128 + b'","' + b"0"*127 + b'1"\r\n')
    for shape in ("isolated", "chain", "star", "reverse-chain"):
        n = 4096; source = None
        if shape == "isolated": edges, order, paths = [], list(range(n)), None
        elif shape == "chain":
            edges, order, source = [(i,i+1) for i in range(n-1)], list(range(n)), 0
            paths = [(i, i-1 if i else None) for i in range(n)]
        elif shape == "star":
            edges, order, source = [(0,i) for i in range(1,n)], list(range(n)), 0
            paths = [(0,None)] + [(1,0)]*(n-1)
        else:
            edges, order, source = [(i,i-1) for i in range(1,n)], list(reversed(range(n))), n-1
            paths = [(n-1-i, i+1 if i<n-1 else None) for i in range(n)]
        r.graph(f"maximum-nodes-{shape}", n, edges, source, known=(0,expected_output(order,paths)))
    r.graph("maximum-input-and-raw-edges", 2, [(0,1)], 0, wire=cap_input())
    for mask in range(64):
        edges = [edge for bit, edge in enumerate(possible) if mask & (1 << bit)]
        r.components(f"components-every-three-node-directed-{mask}", 3, edges)
    shapes = [
        ("empty", 0, []), ("singleton", 1, []), ("self-loop", 1, [(0,0)]),
        ("isolated", 7, []), ("all-self-loops", 5, [(i,i) for i in range(5)]),
        ("one-cycle", 5, [(i,(i+1)%5) for i in range(5)]),
        ("reverse-id-order", 4, [(3,2),(2,1),(1,0)]),
        ("nested-cycle", 7, [(0,1),(1,2),(2,0),(1,3),(3,4),(4,1),(4,5)]),
        ("completed-target", 7, [(1,2),(2,1),(3,4),(4,3),(4,1),(5,3),(5,0)]),
        ("active-cross-link", 6, [(0,1),(1,2),(2,0),(0,3),(3,1),(3,4),(4,5),(5,4)]),
        ("component-ready-tie", 8, [(0,1),(1,0),(2,3),(3,2),(6,7),(7,6),(6,2),(4,0),(2,5)]),
    ]
    for name, nodes, edges in shapes: r.components("components-"+name, nodes, edges)
    shuffled = [(0,2),(2,0),(1,3),(3,1),(4,1),(4,0),(3,5)] * 4
    rng.shuffle(shuffled)
    r.components("components-duplicate-shuffled", 7, shuffled)
    r.components("components-quoted-crlf", 3, [(0,1),(1,0)],
                 wire=b'"before","after"\r\n"0","1"\r\n"1","0"\r\n')
    r.components("components-unterminated-final-record", 3, [(2,1)], wire=b"before,after\n2,1")
    for shape in ("isolated", "single-cycle", "paired-reverse-chain", "self-loops"):
        n = 4096
        if shape == "isolated": edges, mapping, order = [], list(range(n)), list(range(n))
        elif shape == "single-cycle":
            edges, mapping, order = [(i,(i+1)%n) for i in range(n)], [0]*n, [0]
        elif shape == "paired-reverse-chain":
            edges = [(i,i^1) for i in range(n)] + [(i,i-2) for i in range(2,n,2)]
            mapping, order = [i//2 for i in range(n)], list(reversed(range(n//2)))
        else: edges, mapping, order = [(i,i) for i in range(n)], list(range(n)), list(range(n))
        r.components("components-maximum-nodes-"+shape, n, edges, known=(0,component_output(mapping,order)))
    r.components("components-maximum-input-and-raw-edges", 2, [(0,1)], wire=cap_input())



def rejection(r):
    invalid = [b"", b"\n", b"before,target\n", b"Before,after\n", b"\xef\xbb\xbfbefore,after\n",
               b"before,after,extra\n", b"before\n", b"before,after\n\n", b"before,after\n0\n",
               b"before,after\n0,1,2\n", b'"before,after\n', b'before,after\n"0,1\n',
               b'before,after\n"0"x,1\n', b'before,after\n"0\n",1\n', b"before,after\n\0,1\n",
               b"before,after\n\t0,1\n", b"before,after\n\xff,1\n", b"before,after\n-1,0\n",
               b"before,after\n+0,1\n", b"before,after\n 0,1\n", b"before,after\n0 ,1\n",
               b"before,after\n0x0,1\n", b"before,after\n0.0,1\n", b"before,after\n0e0,1\n",
               b"before,after\n,1\n", b"before,after\n0,\n", b"before,after\n3,0\n",
               b"before,after\n0,3\n", b"before,after\n18446744073709551616,0\n",
               b"before,after\n0,18446744073709551615\n", b"before,after\n" + b"0"*129 + b",1\n",
               b"before,after\n\xd9\xa0,1\n"]
    for index, wire in enumerate(invalid): r.run(f"invalid-csv-{index}", ["--nodes","3"], wire, status=2)
    for index, (n, edges) in enumerate(((1,[(0,0)]),(4,[(3,3)]),(5,[(0,1),(3,4),(4,3)]),(5,[(0,1),(1,2),(2,3),(3,4),(4,1)]))):
        r.graph(f"loop-disconnected-cycle-{index}", n, edges, 0, trace=True)
    r.run("raw-edge-over-limit-before-dedup", ["--nodes","2"], INPUT_HEADER + b"0,1\n"*65537, status=2)
    r.run("zero-nodes-cannot-have-edge", ["--nodes","0"], INPUT_HEADER + b"0,0\n", status=2)
    for length in (CAP, CAP+1):
        found = r.run(f"raw-byte-limit-{length}", ["--nodes","2"], b"x"*length, status=2, trace=True)
        if r.observes:
            reads = [item for item in found if item["name"] == "read"]
            assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"] == str(int(length > CAP))
            assert sum(int(item["answer"]) for item in reads) == length


    component_invalid = [b"", b"before,target\n", b"before,after\n3,0\n", b"before,after\n0,3\n",
                         b"before,after\n-1,0\n", b' before,after\n', b'before,after\n"0"x,1\n',
                         b"before,after\n" + b"0"*129 + b",1\n"]
    for index, wire in enumerate(component_invalid):
        r.run(f"components-invalid-csv-{index}", ["--nodes","3","--components"], wire, status=2, trace=True)
    r.run("components-raw-edge-over-limit", ["--nodes","2","--components"],
          INPUT_HEADER + b"0,1\n"*65537, status=2)
    r.run("components-zero-nodes-edge", ["--nodes","0","--components"], INPUT_HEADER+b"0,0\n",status=2,trace=True)
    for length in (CAP, CAP+1):
        found = r.run(f"components-raw-byte-limit-{length}", ["--nodes","2","--components"],
                      b"x"*length, status=2, trace=True)
        if r.observes:
            reads = [item for item in found if item["name"] == "read"]
            assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"] == str(int(length > CAP))
            assert sum(int(item["answer"]) for item in reads) == length


def cli(r):
    invalid = [[], ["--nodes"], ["--source","0"], ["--nodes","-1"], ["--nodes","+1"], ["--nodes","4097"],
               ["--nodes","1","--source","1"], ["--nodes","0","--source","0"], ["--nodes","1","--source","4096"],
               ["--nodes","1","--source","-1"], ["--nodes","1","--source","+0"], ["--nodes","1","--source",""],
               ["--nodes","1","--source","0","-s","0"], ["--nodes","1","-n","1"], ["-hh"], ["--help","-h"],
               ["--nodes","1","operand"], ["--"], ["--unknown"], ["--help=yes"], ["--nodes","1 "] ,
               ["--nodes"," 1"], ["--nodes","1.0"], ["--nodes","1e0"], ["--nodes","0x1"], ["--nodes","١"],
               ["--nodes",b"\xff"], ["--nodes",""], ["--nodes","0"*65], ["--nodes","18446744073709551616"],
               ["--help","--nodes","0","--source","0"], ["--help","--source","4096"], ["--help","--nodes","4097"],
               ["--nodes","1","x"*1017], ["x"]*25]
    for index, args in enumerate(invalid): r.run(f"invalid-{index}", args, status=2, trace=True, read_error=True, preflight=True)
    valid = [["--help"],["-h"],["--help","--nodes","0000"],["--help","--source","4095"],
             ["--nodes","4096","--source","4095","--help"]]
    for index, args in enumerate(valid): r.run(f"help-{index}", args, output=HELP, trace=True, read_error=True, preflight=True)
    r.graph("short-options-leading-zero64", 2, [(0,1)], 0,
            arguments=["-n","0"*63+"2","-s","0"*64])


    component_invalid = [["--components"], ["--nodes","1","-CC"], ["--nodes","1","--components","-C"],
                         ["--nodes","1","--components","--components"], ["--nodes","1","--components=yes"],
                         ["--nodes","1","--components","--source","0"],
                         ["--nodes","1","-s","0","-C"], ["--help","--components","--source","0"],
                         ["--nodes","1","--source","0","--components","--help"],
                         ["--help","--components","-C"], ["--nodes","4097","--components"],
                         ["--nodes","1","--components","operand"]]
    for index, args in enumerate(component_invalid):
        r.run(f"components-invalid-{index}", args, status=2, trace=True, read_error=True, preflight=True)
    for index, args in enumerate((["--components","--help"], ["-Ch"], ["--nodes","4096","-C","--help"])):
        r.run(f"components-help-{index}", args, output=HELP, trace=True, read_error=True, preflight=True)
    r.components("components-short-alias", 3, [(0,1),(1,0)], arguments=["-n","0003","-C"])
    r.components("components-short-cluster", 3, [(0,1),(1,0)], arguments=["-Cn3"])


def io(r):
    n = 96; edges = [(i,i+1) for i in range(n-1)] * 10
    wire = graph_input(edges)
    paths = [(i, i-1 if i else None) for i in range(n)]
    wanted = expected_output(range(n), paths); known = 0, wanted
    def exercise(name, **options): return r.graph(name,n,edges,0,known=known,**options)
    baseline = exercise("baseline", trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    first_write = next(index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    for owner in maps[:2]:
        released = next(index for index,item in enumerate(baseline) if index>baseline.index(owner) and item["name"]=="munmap" and item["args"].split(",")[0]==owner["answer"])
        assert released < baseline.index(maps[2]) < first_read
    graph_offsets = next(item for item in maps if baseline.index(item)>baseline.index(eof) and int(item["args"].split(",")[1])==(n+1)*4)
    node_storage = [item for item in maps if baseline.index(item)>baseline.index(graph_offsets) and int(item["args"].split(",")[1])==n*4]
    # Frozen call order: topological result/counts/heap, BFS distances/parents/queue.
    assert len(node_storage)==6
    workspace, bfs_parents = node_storage[0], node_storage[4]
    live = {}
    for item in baseline[:first_write]:
        if item["name"] == "mmap": live[item["answer"]] = int(item["args"].split(",")[1])
        elif item["name"] == "munmap": del live[item["args"].split(",")[0]]
    assert live == {maps[-1]["answer"]: int(maps[-1]["args"].split(",")[1])}
    assert next(iter(live.values())) >= len(wanted), "non-output owner remains at publication"
    selected = [maps[0],maps[1],maps[2],graph_offsets,workspace,bfs_parents,maps[-1]]
    assert len({item["ordinal"] for item in selected})==7
    for old in selected:
        actual = exercise(f"owner-oom-{old['ordinal']}",status=4,output=b"",trace=True,injections=(("mmap",old["ordinal"],"ENOMEM"),))
        fault=next(item for item in actual if item["name"]=="mmap" and item["ordinal"]==old["ordinal"])
        assert fault["args"]==old["args"]
    r.run("stdin-directory",["--nodes","1"],status=3,trace=True,read_error=True)
    exercise("read-eintr-retry",trace=True,injections=(("read",1,"EINTR"),))
    exercise("later-read-eio",status=3,output=b"",trace=True,injections=(("read",2,"EIO"),))
    failed=exercise("required-eof-eio",status=3,output=b"",trace=True,injections=(("read",eof["ordinal"],"EIO"),))
    assert sum(int(item["answer"]) for item in failed if item["name"]=="read" and item["answer"].isdigit())==len(wire)
    exercise("closed-data-stdout",status=5,output=b"",trace=True,closed_stdout=True)
    r.run("closed-help-stdout",["--help"],status=5,trace=True,closed_stdout=True)
    exercise("write-eintr-retry",trace=True,injections=(("write",1,"EINTR"),))
    partial=exercise("actual-output-prefix",status=5,output=wanted[:1024],trace=True,injections=(("write",2,"EIO"),))
    assert next(item["answer"] for item in partial if item["name"]=="write")=="1024"
    r.run("signal-setup-eio",status=5,trace=True,injections=(("rt_sigaction",1,"EIO"),),diagnostic=False)
    exercise("read-attempt-cap",status=2,output=b"",budget="read")
    exercise("output-attempt-cap",status=5,output=b"",budget="write")


    # A separate successful native case binds the new path's actual sites. It
    # is part of the reported count, not an uncounted calibration execution.
    n, count = 96, 48
    edges = ([(i,i^1) for i in range(n)] + [(i,i-2) for i in range(2,n,2)]) * 10
    wire = graph_input(edges)
    wanted = component_output([i//2 for i in range(n)], list(reversed(range(count))))
    assert len(wanted) > 1024
    def component_exercise(name, **options):
        return r.components(name,n,edges,known=(0,wanted),**options)
    baseline = component_exercise("components-baseline", trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    first_read = next(index for index,item in enumerate(baseline) if item["name"] == "read")
    first_write = next(index for index,item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    def size(item): return int(item["args"].split(",")[1])
    def release(item):
        # Choose the first release after this allocation; addresses may be reused.
        return next(index for index,event in enumerate(baseline) if index > baseline.index(item)
                    and event["name"] == "munmap" and event["args"].split(",")[0] == item["answer"])
    for owner in maps[:2]: assert release(owner) < baseline.index(maps[2]) < first_read
    offsets = [item for item in maps if baseline.index(item)>baseline.index(eof) and size(item)==(n+1)*4]
    assert len(offsets) == 1, "ambiguous original graph offset allocation"
    offset_index = maps.index(offsets[0]); targets = maps[offset_index+1]
    original_edges = len(set(edges)); cross_edges = count-1
    assert size(targets)==original_edges*4
    # The source constructor's exact sorted edge staging establishes Edge's
    # byte width for this emitted executable before matching component pairs.
    original_staging = maps[offset_index-1]
    assert size(original_staging) % len(edges) == 0
    edge_width = size(original_staging)//len(edges)
    assert edge_width > 0 and release(original_staging) < baseline.index(maps[offset_index+2])
    phase = maps[offset_index+2:offset_index+16]
    expected_sizes = [n*4]*6 + [original_edges*edge_width,cross_edges*edge_width,(count+1)*4,cross_edges*4] + [count*4]*4
    assert list(map(size,phase)) == expected_sizes, (list(map(size,phase)), expected_sizes)
    labels, *workspaces = phase[:6]
    pairs, sorted_pairs, dag_offsets, dag_targets = phase[6:10]
    order, indegrees, ready, positions = phase[10:14]
    for owner in workspaces: assert release(owner) < baseline.index(pairs)
    for owner in (pairs, sorted_pairs): assert release(owner) < baseline.index(order)
    for owner in (indegrees, ready): assert release(owner) < baseline.index(positions)
    assert release(order) < baseline.index(maps[offset_index+16]), "topological owner remains during rendering"
    for owner in (labels,dag_offsets,dag_targets,positions,offsets[0],targets): assert release(owner) < first_write
    live = {}
    for item in baseline[:first_write]:
        if item["name"] == "mmap": live[item["answer"]] = size(item)
        elif item["name"] == "munmap": del live[item["args"].split(",")[0]]
    assert live == {maps[-1]["answer"]: size(maps[-1])} and size(maps[-1]) >= len(wanted)
    selected = [labels,workspaces[-1],pairs,sorted_pairs,dag_offsets,dag_targets,order,positions,maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 9
    for old in selected:
        actual = component_exercise(f"components-owner-oom-{old['ordinal']}",status=4,output=b"",trace=True,
                                    injections=(("mmap",old["ordinal"],"ENOMEM"),))
        actual_maps = [item for item in actual if item["name"] == "mmap"]
        assert len(actual_maps) == old["ordinal"], "allocation attempted after reached failure"
        assert [item["args"] for item in actual_maps] == [item["args"] for item in maps[:old["ordinal"]]]
    component_exercise("components-read-eintr-retry",trace=True,injections=(("read",1,"EINTR"),))
    component_exercise("components-later-read-eio",status=3,output=b"",trace=True,injections=(("read",2,"EIO"),))
    failed=component_exercise("components-required-eof-eio",status=3,output=b"",trace=True,
                             injections=(("read",eof["ordinal"],"EIO"),))
    assert sum(int(item["answer"]) for item in failed if item["name"]=="read" and item["answer"].isdigit())==len(wire)
    component_exercise("components-closed-data-stdout",status=5,output=b"",trace=True,closed_stdout=True)
    component_exercise("components-write-eintr-retry",trace=True,injections=(("write",1,"EINTR"),))
    partial=component_exercise("components-actual-output-prefix",status=5,output=wanted[:1024],trace=True,
                               injections=(("write",2,"EIO"),))
    assert next(item["answer"] for item in partial if item["name"]=="write")=="1024"
    component_exercise("components-output-attempt-cap",status=5,output=b"",budget="write")


def controls():
    assert len(HELP)==1023 and len(ERROR)==35
    assert expected_output(())==b'"position","node","hops","predecessor"\r\n'
    assert len(expected_output(()))==40

    assert component_reference(0,[]) == (0,b'"node","component","position"\r\n')
    assert component_reference(1,[(0,0)]) == (0,b'"node","component","position"\r\n"0","0","0"\r\n')
    assert component_partition(4,[(0,2),(2,0),(3,1)])[0] == [0,1,0,2]
    assert component_reference(4,[(0,2),(2,0),(3,1)]) == (0,
        b'"node","component","position"\r\n"0","0","0"\r\n"1","1","2"\r\n"2","0","0"\r\n"3","2","1"\r\n')
    component_edges=[(0,1),(1,0),(2,3),(3,2),(4,2),(2,0),(5,5)]
    assert component_reference(7,component_edges)==component_reference(7,list(reversed(component_edges))*3)
    # Exact byte comparisons catch reordered node rows, discovery-order labels,
    # component IDs mistaken for topological positions and missing SCC members.
    literal=component_reference(4,[(0,2),(2,0),(3,1)])[1]
    changed=[literal.replace(b'"1","1","2"',b'"1","1","1"'),
             literal.replace(b'"2","0","0"',b'"2","2","0"'),
             literal.replace(b'"3","2","1"\r\n',b''),
             literal.replace(b'"0","0","0"\r\n"1","1","2"',b'"1","1","2"\r\n"0","0","0"')]
    assert all(wrong != literal for wrong in changed)

    assert reference(0,[])==(0,expected_output(()))
    assert ordered_nodes(3,[(0,1),(1,2),(2,0)]) is None
    assert ordered_nodes(1,[(0,0)]) is None
    assert ordered_nodes(6,[(4,1),(3,0),(1,2)])==(3,0,4,1,2,5)
    tied=[(0,1),(0,2),(1,5),(2,3),(5,6),(3,6)]
    assert hop_paths(7,tied,0)[6]==(3,5) and hop_paths(7,tied,0)[4]==(None,None)
    assert reference(7,tied,0)==reference(7,list(reversed(tied))*3,0)
    possible=[(u,v) for u in range(3) for v in range(3) if u!=v]
    assert sum(ordered_nodes(3,[e for bit,e in enumerate(possible) if mask&(1<<bit)]) is not None for mask in range(64))==25
    rows=csv.reader(StringIO(cap_input().decode("ascii"),newline=""))
    assert next(rows)==["before","after"]
    count=0
    for row in rows:
        assert len(row)==2 and tuple(map(int,row))==(0,1); count+=1
    assert count==65536
    class CounterOnly:
        observes=False
        def __init__(self): self.count=0
        def run(self,*args,**kwargs): self.count+=1; return []
        def graph(self,name,nodes,edges,source=None,known=None,**kwargs):
            if known is None: reference(nodes,edges,source)
            self.count+=1; return []
        def components(self,name,nodes,edges,known=None,**kwargs):
            if known is None: component_reference(nodes,edges)
            self.count+=1; return []
    for function in (model,rejection,cli):
        r=CounterOnly(); function(r)
        assert r.count==COUNTS[function.__name__]
    good="mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(2, X, 1) = 1\n"
    assert len(events(good))==3
    try: events(good.replace("munmap(0x1000, 16) = 0\n",""))
    except AssertionError: pass
    else: raise AssertionError("missing owner release accepted")
    print(f"dependency-order CPU controls passed; native cases={sum(COUNTS.values())}")


if __name__=="__main__":
    if sys.argv[1:]==["controls"]: controls()
    else:
        mode,executable=sys.argv[1:]; runner=Runner(executable,mode)
        {"model":model,"rejection":rejection,"cli":cli,"io":io}[mode](runner)
        assert runner.count==COUNTS[mode],(mode,runner.count)
        print(f"dependency-order-{mode} cases={runner.count} evidence={runner.directory}")
