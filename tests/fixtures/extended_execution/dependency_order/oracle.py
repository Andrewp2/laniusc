"""Permutation-order and dense all-pairs/shortest-path-prefix graph oracles."""
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
HELP = (b"Usage: dependency_order --nodes N [--source S] [--help]\n"
        b"Read CSV before,after and print the lexicographically smallest dependency order.\n"
        b"N is 0..4096; source and edge IDs are in [0,N). Leading zeros are allowed.\n"
        b"Output CSV: position,node,hops,predecessor; positions are zero-based.\n"
        b"--source adds shortest-hop distances and first-discovery predecessors; absent values are empty.\n"
        b"Cycles, including self-loops, fail without data output. Empty graphs print only the header.\n"
        b"Short options: -n N, -s S, -h. Duplicate options and operands are errors.\n"
        b"Limits: 4 MiB input, 65536 raw edges, 128 bytes per field, 1 MiB staged output.\n"
        b"Input permits 16384 read attempts and output 2048 attempts; interruptions spend attempts.\n"
        b"Help accepts otherwise valid options and does not read stdin.\n")
ERROR = b"dependency_order: operation failed\n"
INPUT_HEADER = b"before,after\n"
HEADER = ("position", "node", "hops", "predecessor")
TRACE = "read,write,close,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS = {"model": 83, "rejection": 40, "cli": 41, "io": 19}
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


def controls():
    assert len(HELP)==776 and len(ERROR)==35
    assert expected_output(())==b'"position","node","hops","predecessor"\r\n'
    assert len(expected_output(()))==40
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
