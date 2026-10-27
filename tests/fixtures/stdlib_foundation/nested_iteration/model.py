"""Independent finite sequence/generator expectations; binary test transport only."""
from collections import deque
import itertools
from pathlib import Path
import struct
import subprocess
import sys

WIDE = 4294967297
MAX = (1 << 64)-1


class World:
    def __init__(self, lengths, fail=9, map_fail=9, mapped=False):
        self.rows = [list(range(WIDE+10*i, WIDE+10*i+n)) for i,n in enumerate(lengths)]
        self.position = self.calls = self.maps = self.retires = 0
        self.trace = []
        self.fail, self.map_fail, self.mapped = fail, map_fail, mapped

    def source(self):
        # A shared sequence index, with each generator acquiring only when
        # resumed. Separate nested traversals retain separate row generators.
        while True:
            self.trace.append(100+self.position); self.calls += 1
            if self.position == len(self.rows):
                return
            index = self.position; self.position += 1
            yield index

    def retire(self, inner):
        assert not inner["rest"]
        self.trace.append(200+inner["id"]); self.retires += 1
        inner["steps"] += 1
        return 1000+inner["id"] if inner["id"] == self.fail and inner["steps"] == 1 else None

    def read(self, inner):
        self.trace.append(300+inner["id"])
        if not inner["rest"]:
            return None
        inner["position"] += 1
        return inner["rest"].popleft()


class Nested:
    def __init__(self, world):
        self.world, self.active, self.closed = world, None, False
        self.stream = self.traverse()

    def traverse(self):
        world = self.world
        for index in world.source():
            if world.mapped:
                world.trace.append(400+index); world.maps += 1
                if index == world.map_fail:
                    self.closed = True
                    yield 2, 2000+index
                    return
            self.active = dict(id=index, position=0, steps=0, rest=deque(world.rows[index]))
            # The reference consumes an ordinary finite row sequence. Its
            # generator suspension represents each returned item, independently
            # of the production Option/move-out/reinstall transitions.
            for value in world.rows[index]:
                world.trace.append(300+index)
                assert self.active["rest"].popleft() == value
                self.active["position"] += 1
                yield 1, value
            world.trace.append(300+index)
            error = world.retire(self.active)
            if error is not None:
                self.closed = True
                yield 2, error
                return
            self.active = None
        self.closed = True

    def next(self):
        return (0,0) if self.closed else next(self.stream, (0,0))

    def finish(self):
        if self.active is not None:
            return 4,0
        self.closed = True; self.stream.close()
        return 3,0

    def take(self):
        inner, self.active = self.active, None
        self.closed = True; self.stream.close()
        return inner


def nested_expected(mode, lengths, fail, map_fail, actions):
    world = World(lengths, fail, map_fail, bool(mode))
    adapters = [Nested(world), Nested(world)]
    recovered = None; words = []
    for ordinal, action in enumerate(actions):
        if action in (0,5):
            tag,value = adapters[action//5].next()
        elif action in (1,6):
            tag,value = adapters[(action-1)//5].finish()
        elif action in (2,7):
            taken = adapters[(action-2)//5].take(); tag,value = 5,0
            if taken is not None:
                assert recovered is None, "invalid test schedule: two recovered authorities"
                recovered = taken; tag = 6
        elif action == 3:
            tag,value = 8,0
            if recovered is not None:
                item = world.read(recovered)
                if item is not None:
                    tag,value = 7,item
                else:
                    error = world.retire(recovered)
                    if error is not None:
                        tag,value = 9,error
                    else:
                        recovered = None
        else:
            assert action in (4,8)
            selected = 0 if action == 4 else 1
            assert adapters[selected].active is None, "invalid test schedule: abandons active authority"
            adapters[selected].finish(); adapters[selected] = Nested(world)
            tag,value = 10,0
        words.extend([tag,value,int(adapters[0].active is not None),int(adapters[1].active is not None),
                      world.position,world.calls,world.maps,world.retires,int(recovered is not None),
                      recovered["id"] if recovered is not None else 0,
                      recovered["position"] if recovered is not None else 0,
                      recovered["steps"] if recovered is not None else 0,len(world.trace),ordinal])
    return words+[len(world.trace)]+world.trace


def scan_expected(mode, length, stop, fail, initial, actions):
    # Source and callback effects come from the consumed prefix of one shared
    # finite sequence. Each adapter independently latches its decisive boundary.
    values = deque(range(length)); position = calls = callbacks = 0
    total = initial; closed = [False,False]; trace = []; words = []
    for action in actions:
        tag = value = 0
        if action >= 3:
            closed[action-3] = False; tag = 3
        elif action == 2 or not closed[action]:
            trace.append(100+position); calls += 1
            if not values:
                if action != 2:
                    closed[action] = True
            else:
                item = values.popleft(); position += 1
                if action == 2:
                    tag,value = 1,item
                else:
                    trace.append(200+item); callbacks += 1; total += 1+item
                    if mode and item == fail:
                        tag,value = 2,MAX-item; closed[action] = True
                    elif item == stop:
                        closed[action] = True
                    else:
                        tag,value = 1,total
        words.extend([tag,value,position,calls,callbacks,total,len(trace)])
    return words+[len(trace)]+trace


NESTED_SCHEDULES = (
    (0,)*12+(1,0),
    (1,0,5,5,6,0,5),
    (0,1,2,0,2,3,3,3,3,3,4,0,0,0,0,0),
    (0,5,0,5,1,6,0,5,0,5,0,5,1,6,0,5),
    (0,0,0,0,0,2,3,3,3,3,4,0,0,0,0,0),
    (2,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0),
)
SCAN_SCHEDULES = (
    (0,)*10,
    (0,1,0,1,0,1,0,1,0,1),
    (0,0,2,0,0,1,1,1,1,0),
    (0,0,0,3,0,1,1,4,1,2,0,1),
)


def nested_cases():
    for mode in (0,1):
        for lengths in ((),(0,),(1,),(3,),(0,0,2,0),(2,1),(3,0,2,1)):
            choices = sorted({9,0,max(0,len(lengths)-1)})
            for fail,map_fail in itertools.product(choices, choices if mode else (9,)):
                for actions in NESTED_SCHEDULES:
                    header = (mode,len(lengths),fail,map_fail)+tuple(lengths)+(0,)*(4-len(lengths))+(len(actions),)
                    command = header+actions+(0,)*(16-len(actions))
                    yield command,nested_expected(mode,lengths,fail,map_fail,actions)


def scan_cases():
    for mode,length,initial in itertools.product((0,1),range(7),(0,WIDE)):
        for stop,fail in ((9,9),(0,9),(2,9),(9,0),(9,2),(2,2)):
            for actions in SCAN_SCHEDULES:
                command = (mode,length,stop,fail,initial,len(actions))+actions+(0,)*(12-len(actions))
                yield command,scan_expected(mode,length,stop,fail,initial,actions)


def validate(actual, cases):
    assert len(actual)%8 == 0, "partial binary observation"
    words = list(struct.unpack("<"+"Q"*(len(actual)//8),actual)); offset = 0
    for ordinal,(command,expected) in enumerate(cases):
        assert words[offset:offset+len(expected)] == expected, (ordinal,command,words[offset:offset+len(expected)],expected)
        offset += len(expected)
    assert offset == len(words), "extra observations or incomplete case framing"


def controls():
    count = 0
    world = World([0,2]); nested = Nested(world)
    assert not world.trace and world.calls == world.retires == 0; count += 1
    assert nested.next() == (1,WIDE+10) and world.trace == [100,300,200,101,301]; count += 1
    before = (nested.active,world.position,list(world.trace))
    assert nested.finish() == (4,0) and before == (nested.active,world.position,world.trace); count += 1
    assert nested.next() == (1,WIDE+11); count += 1
    assert nested.next() == (0,0) and world.trace[-3:] == [301,201,102]; count += 1
    before = list(world.trace)
    assert nested.next() == (0,0) and world.trace == before; count += 1
    world = World([0,1],fail=0); nested = Nested(world)
    assert nested.next() == (2,1000) and nested.active["steps"] == 1; count += 1
    before = list(world.trace)
    assert nested.next() == (0,0) and nested.finish() == (4,0) and world.trace == before; count += 1
    recovered = nested.take()
    assert recovered["steps"] == 1 and nested.take() is None and world.trace == before; count += 1
    assert world.retire(recovered) is None and recovered["steps"] == 2; count += 1
    resumed = Nested(world)
    assert resumed.next() == (1,WIDE+10) and world.position == 2; count += 1
    world = World([2,1],map_fail=0,mapped=True); nested = Nested(world)
    assert nested.next() == (2,2000) and nested.active is None and (world.position,world.maps,world.retires) == (1,1,0); count += 1
    scan = scan_expected(1,4,2,2,WIDE,(0,0,0,0,1))
    snapshots = [scan[i*7:(i+1)*7] for i in range(5)]
    assert snapshots[2][:2] == [2,MAX-2] and snapshots[3] == [0,0]+snapshots[2][2:]; count += 1
    assert snapshots[4][0] == 1 and snapshots[4][2:6] == [4,4,4,WIDE+10]; count += 1
    cases = list(nested_cases())+list(scan_cases())
    payload = b"".join(struct.pack("<"+"Q"*len(expected),*expected) for _,expected in cases)
    validate(payload,cases); count += 1
    for changed in (payload[:-1],payload+b"\0"*8,struct.pack("<Q",999)+payload[8:]):
        try: validate(changed,cases)
        except AssertionError: count += 1
        else: raise AssertionError("accepted changed model observation")
    print(f"nested-iteration CPU controls={count} nested-cases={len(list(nested_cases()))} scan-cases={len(list(scan_cases()))} native-cases=0")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    assert len(sys.argv) == 3 and sys.argv[1] in ("nested","scan")
    group,executable = sys.argv[1],Path(sys.argv[2]).resolve()
    cases = list(nested_cases() if group == "nested" else scan_cases())
    request = b"".join(struct.pack("<"+"Q"*len(command),*command) for command,_ in cases)
    result = subprocess.run([str(executable)],input=request,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    assert result.returncode == 0 and not result.stderr, (result.returncode,result.stderr)
    validate(result.stdout,cases)
    print(f"nested-iteration group={group} cases={len(cases)}")


if __name__ == "__main__": main()
