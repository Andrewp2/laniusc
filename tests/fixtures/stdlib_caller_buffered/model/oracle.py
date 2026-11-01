"""Test-only queue/acknowledgement ledgers for caller-backed and owned buffering."""
from __future__ import annotations
from collections import Counter, deque
from dataclasses import dataclass, replace
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xB0FFE0261121
MASK = (1 << 64) - 1
MAX_I32 = (1 << 31) - 1
MAGIC = 0x6275666665727631
END = 0x656E646275666631


@dataclass(frozen=True)
class Action:
    op: int
    offset: int = 2
    count: int = 2
    first: int = 99
    second: int = 99
    flush: int = 0
    seek_first: int = 0
    seek_second: int = 0
    target: int = 0
    aux: int = 0
    def words(self): return tuple(getattr(self, key) for key in self.__dataclass_fields__)


@dataclass(frozen=True)
class Case:
    direction: int  # 0 reader, 1 writer
    capacity: int
    actions: tuple


def valid(start, length): return start >= 0 and length >= 0 and start + length <= MAX_I32

def source(step): return [(i * 29 + step * 41 + 17) & 255 for i in range(32)]

def initial_peer(): return [(i * 37 + 11) & 255 for i in range(128)]

def error(event):
    assert -10 <= event <= -1
    return -event, -2147483648 if event == -10 else 0


def offset(base, relative):
    value = base + relative
    return value if 0 <= value <= MASK else None


class Words:
    def __init__(self): self.values = []; self.marks = {}
    def put(self, value, label='word'):
        self.marks.setdefault(label, len(self.values)); self.values.append(value & MASK)
    def many(self, values, label='word'):
        for value in values: self.put(value, label)


class Model:
    def __init__(self, case, route, alternate=False, mutant=None):
        self.case, self.route, self.mutant = case, route, mutant
        self.base = (3, 5, 0)[route]; self.stride = -8 if route == 0 else 1
        self.arg_stride = -8 if route != 1 else 1
        self.caller = [(197 + i * (7 if alternate else 3)) & 255 for i in range(32)]
        self.owner = [0] * case.capacity if route == 2 else None
        self.peer = initial_peer(); self.position = 0; self.calls = [0, 0, 0, 0]
        self.active, self.fault = True, False
        self.pending = deque(); self.epoch_used = 0
        self.parts = None
        self.argument = source(0)
        self.events = []; self.total = Counter(); self.observations = []
        self.accepted = []; self.acknowledged = []; self.fetched = []; self.consumed = []
        self.changed = False

    def cells(self): return self.owner if self.route == 2 else self.caller
    def put(self, slot, values):
        cells = self.cells(); at = self.base + slot
        cells[at:at + len(values)] = values
    def view(self, queue, active):
        start = self.base + queue[0][0] if queue else self.base if active else 0
        return start, len(queue), self.stride, tuple(value for _, value in queue)
    def reply(self, code=0, host=0, number=0, view=None): return code, host, number, view

    def provider(self, kind, a, ordinal, request=0, start=0):
        # The provider has its own byte store, logical position and event tape.
        event = (a.first if ordinal == 0 else a.second if ordinal == 1 else 99) if kind in (0, 1) else a.flush if kind == 2 else a.seek_first if ordinal == 0 else a.seek_second
        before = self.position; offered = tuple(value for _, value in self.pending) if kind == 1 else ()
        argument = a.target if kind == 3 else 0
        code = host = value = 0; copied = []
        self.calls[kind] += 1
        if -10 <= event <= -1:
            code, host = error(event)
            if kind == 3: self.position = 111  # Err may have physical cursor effects.
        elif kind in (0, 1):
            if event == -101: value = -1
            elif event == -102: value = request + 1
            else:
                assert event >= 0
                limit = 19 if kind == 0 else 128
                value = min(event, request, max(0, limit - self.position))
                if kind == 0: copied = self.peer[self.position:self.position + value]
                else:
                    copied = list(offered[:value]); self.peer[self.position:self.position + value] = copied
                self.position += value
        elif kind == 2:
            assert event >= 0; value = event
        else:
            target = a.target if start == 0 else offset(self.position if start == 1 else (19 if self.case.direction == 0 else 128), a.target)
            if target is None: code = 1
            else:
                value = target
                if event == 1: value = (target + 1) & MASK
                if event == 2: value = 0
                if event == 3: value = MASK
                self.position = value
        stride = self.stride if kind in (0, 1) else 0
        self.events.append((kind, event, start, request, before, argument, code, host, value, self.position, stride, offered))
        return code, host, value, copied

    def fill(self, a):
        if self.pending: return self.reply(view=self.view(self.pending, True))
        code, host, count, data = self.provider(0, a, 0, self.case.capacity, self.base)
        if code: return self.reply(code, host)
        if not 0 <= count <= self.case.capacity:
            self.fault = True; return self.reply(4)
        self.put(0, data); self.pending.extend(enumerate(data)); self.epoch_used = count
        self.fetched += data
        return self.reply(view=self.view(self.pending, True))

    def consume(self, count):
        for _ in range(count): self.consumed.append(self.pending.popleft()[1])
        if not self.pending: self.epoch_used = 0

    def drain(self, a):
        offered = list(self.pending)
        # Acknowledgement tape consumes a prefix of a pre-existing queue.
        for ordinal in range(len(offered)):
            if not self.pending: break
            code, host, count, _ = self.provider(1, a, ordinal, len(self.pending), self.base + self.pending[0][0])
            if code: return self.reply(code, host)
            if not 0 <= count <= len(self.pending): self.fault = True; return self.reply(4)
            if count == 0: return self.reply(3)
            for _ in range(count): self.acknowledged.append(self.pending.popleft()[1])
        assert not self.pending; self.epoch_used = 0
        return self.reply()

    def flush(self, a):
        result = self.drain(a)
        if result[0]: return result
        code, host, number, _ = self.provider(2, a, 0)
        if code: return self.reply(code, host)
        if number != 0: self.fault = True; return self.reply(4)
        return self.reply()

    def deactivate(self, release):
        self.active = self.fault = False; self.pending.clear(); self.epoch_used = 0
        if release and self.route == 2: self.owner = None

    def run(self, a, step):
        self.events = []; self.argument = source(step)
        previous = list(self.pending); before_parts = self.parts
        old_active, old_fault = self.active, self.fault
        old_accepted = len(self.accepted); old_ack = len(self.acknowledged)
        extra = (); result = self.reply()
        if a.op == 6:  # hand off the sole controller
            if not self.active: result = self.reply(1)
            else:
                assert self.parts is None
                self.parts = (deque(self.pending), self.fault)
                self.deactivate(False); self.total['handoffs'] += 1
        elif a.op == 7:
            if self.parts is None: result = self.reply(1); self.total['empty_restores'] += 1
            else:
                assert not self.active
                self.pending, self.fault = self.parts; self.parts = None; self.active = True
                self.epoch_used = self.pending[-1][0] + 1 if self.pending else 0
                self.total['restores'] += 1; self.total['fault_restores'] += self.fault
                if not self.pending: self.total['empty_range_restores'] += 1
                if self.mutant == 'clear fault on restore' and self.fault and not self.changed: self.fault = False; self.changed = True
        elif a.op == 8:
            assert self.parts is not None and not self.active
            q, fault = self.parts
            bad_start, bad_length = ((-1, len(q)), (0, self.case.capacity + 1), (self.case.capacity, 1))[a.aux]
            result = self.reply(1); extra = (bad_start, bad_length, self.case.capacity, int(fault))
            self.total['bad_restores'] += 1
        elif a.op == 9:
            result = self.reply(number=len(self.pending)); self.deactivate(self.parts is None)
        elif a.op == 10:
            result = self.reply(number=len(self.parts[0]) if self.parts is not None else 0)
            self.parts = None
            if not self.active and self.route == 2: self.owner = None
        elif a.op == 12:
            assert not self.active and self.parts is None
            self.active = True; self.fault = False; self.pending.clear(); self.epoch_used = 0
            self.accepted.clear(); self.acknowledged.clear(); self.fetched.clear(); self.consumed.clear()
            if self.route == 2: self.owner = [0] * self.case.capacity
        elif not self.active: result = self.reply(1)
        elif self.fault: result = self.reply(4)
        elif a.op in (0, 3) and not valid(a.offset, a.count): result = self.reply(1)
        elif a.op in (0, 3) and a.count == 0: result = self.reply()
        elif a.op in (0, 1):
            result = self.fill(a)
            if a.op == 0 and not result[0]:
                amount = min(a.count, len(self.pending)); data = [value for _, value in list(self.pending)[:amount]]
                self.argument[a.offset:a.offset + amount] = data; self.consume(amount); result = self.reply(number=amount)
        elif a.op == 2:
            if not 0 <= a.count <= len(self.pending): result = self.reply(1)
            else: self.consume(a.count); result = self.reply(number=a.count)
        elif a.op == 3:
            if self.epoch_used == self.case.capacity: result = self.drain(a)
            if not result[0]:
                amount = min(a.count, self.case.capacity - self.epoch_used)
                data = self.argument[a.offset:a.offset + amount]
                assert len(data) == amount
                self.put(self.epoch_used, data)
                self.pending.extend((self.epoch_used + i, value) for i, value in enumerate(data)); self.epoch_used += amount
                self.accepted += data; result = self.reply(number=amount)
        elif a.op in (4, 11):
            result = self.flush(a)
            if a.op == 11 and not result[0]: self.deactivate(True)
        elif a.op == 5:
            request = a; origin = a.aux
            if self.case.direction == 0 and origin == 1:
                query = replace(a, target=0)
                code, host, position, _ = self.provider(3, query, 0, start=1)
                if code or position < len(self.pending):
                    self.pending.clear(); self.epoch_used = 0; self.fault = True
                    result = self.reply(code or 4, host)
                else:
                    target = offset(position - len(self.pending), a.target)
                    if target is None: result = self.reply(1)
                    else: request = replace(a, target=target); origin = 0
            if self.case.direction == 1: result = self.flush(a)
            if not result[0]:
                ordinal = 1 if self.case.direction == 0 and a.aux == 1 else 0
                code, host, position, _ = self.provider(3, request, ordinal, start=origin)
                malformed = not code and origin == 0 and position != request.target
                if self.case.direction == 0:
                    self.pending.clear(); self.epoch_used = 0
                    if code or malformed: self.fault = True
                elif malformed: self.fault = True
                result = self.reply(code or (4 if malformed else 0), host, position if not code and not malformed else 0)
        else: raise AssertionError(a)
        if self.mutant == 'ordinary invalid count faults' and result[0] == 4 and any(e[6] == 4 for e in self.events) and a.op != 5 and not self.changed:
            self.fault = True; self.changed = True
        if self.mutant == 'lost pending suffix' and a.op == 3 and result[0] and self.pending and len(self.acknowledged) > old_ack and not self.changed:
            self.pending.popleft(); self.changed = True
        if self.mutant == 'discard clears caller bytes' and a.op == 9 and self.route != 2 and not self.changed:
            self.caller[self.base] = 0; self.changed = True
        # Independent sequence assertions, beyond serialized state equality.
        if a.op in (6, 7, 8, 9, 10, 12) or not old_active or old_fault: assert not self.events
        if a.op in (0, 3) and valid(a.offset, a.count) and a.count == 0: assert not self.events
        if a.op == 3 and result[0]: assert len(self.accepted) == old_accepted
        if a.op == 8: assert self.parts == before_parts
        if self.pending:
            slots, values = zip(*self.pending)
            assert tuple(slots) == tuple(range(slots[0], slots[0] + len(slots)))
            assert list(values) == self.cells()[self.base + slots[0]:self.base + slots[-1] + 1]
        if not self.mutant:
            if self.case.direction == 1 and a.op not in (6, 7, 8, 9, 10, 12) and self.active:
                assert self.accepted[len(self.acknowledged):] == [v for _, v in self.pending]
            assert len([e for e in self.events if e[0] == 0]) <= 1
            assert len([e for e in self.events if e[0] == 1]) <= len(previous)
        self.total['actions'] += 1; self.total['errors'] += bool(result[0]); self.total['provider_calls'] += len(self.events)
        self.total['fault_observations'] += self.fault; self.total['read_bytes'] += result[2] if a.op == 0 and not result[0] else 0
        self.total['accepted_bytes'] += result[2] if a.op == 3 and not result[0] else 0
        return result, extra

    def emit_view(self, out, view, label):
        start, length, stride, data = view
        out.many((start, length, stride), label + ' metadata'); out.many(data, label + ' byte')

    def emit(self, out, result, extra):
        out.put(len(self.events), 'event count')
        for event in self.events:
            out.many(event[:-1], 'provider event'); out.put(len(event[-1]), 'offered length'); out.many(event[-1], 'offered byte')
        code, host, number, view = result
        out.many((bool(code), code, host, number, view is not None), 'result')
        if view is not None: self.emit_view(out, view, 'returned view')
        out.put(len(extra), 'extra length'); out.many(extra, 'rejected parts')
        out.many((self.active, self.fault, self.case.capacity if self.active else 0), 'owner state')
        self.emit_view(out, self.view(self.pending, self.active), 'owner view')
        q, fault = self.parts if self.parts is not None else ((), False)
        out.many((self.case.capacity if self.parts is not None else 0, q[0][0] if q else 0, len(q), fault), 'parts state')
        self.emit_view(out, self.view(q, self.parts is not None), 'parts view')
        out.many((self.position, *self.calls), 'peer state'); out.many(self.peer, 'peer byte')
        out.put(self.arg_stride, 'argument stride'); out.many(self.argument, 'argument byte')
        cells = self.cells() or []
        out.put(len(cells), 'backing length'); out.many(cells, 'backing byte')
        # Route-independent public meaning; physical offsets and spare cells differ.
        normalized_events = tuple((e[0], e[1], e[2] - self.base if e[0] in (0, 1) else e[2], *e[3:10], e[-1]) for e in self.events)
        self.observations.append((result[:3], None if view is None else view[-1], extra,
                                  self.active, self.fault, tuple(v for _, v in self.pending),
                                  self.parts is not None, fault, tuple(v for _, v in q),
                                  self.position, tuple(self.calls), tuple(self.peer), tuple(self.argument), normalized_events))


def histories():
    # Mandatory transition witnesses precede short deterministic mixed tails.
    c = 4
    readers = [
        [Action(1),Action(1),Action(2,count=1),Action(0,count=9),Action(0,count=2),Action(6),Action(8,aux=0),Action(8,aux=1),Action(8,aux=2),Action(7),Action(7),Action(0,count=2)],
        [Action(0,first=0),Action(0,first=1),Action(1),Action(2,count=99),Action(2,count=-1),Action(2,count=0),Action(6),Action(7)],
        [Action(0,offset=-1,count=0),Action(0,offset=MAX_I32,count=1),Action(0,count=0),Action(6),Action(7),Action(9),Action(0,count=0),Action(10)],
        [Action(1),Action(2,count=1),Action(5,aux=1,target=-2),Action(0,count=1),Action(5,aux=1,target=0),Action(0,count=3),Action(5,aux=0,target=17),Action(0,count=7),Action(5,aux=2,target=-3),Action(0,count=3)],
    ]
    for code in (-7,-8,-4,-10): readers.append([Action(1,first=code),Action(1),Action(2,count=1),Action(6),Action(7),Action(0,count=7)])
    for bad in (-101,-102): readers.append([Action(0,first=bad),Action(0,count=0),Action(1),Action(2,count=0),Action(6),Action(8),Action(7),Action(0),Action(6),Action(10),Action(12),Action(0)])
    for origin,event1,event2 in [(0,-8,0),(2,-7,0),(1,-4,0),(1,2,0),(1,0,-10),(0,1,0),(1,0,1)]:
        readers.append([Action(1),Action(2,count=1),Action(5,aux=origin,target=3,seek_first=event1,seek_second=event2),Action(1),Action(6),Action(7),Action(0,count=0)])
    readers += [[Action(6),Action(8,aux=2),Action(7),Action(1),Action(2,count=c),Action(6),Action(7),Action(1)],
                [Action(1),Action(5,aux=1,target=-(1<<63)),Action(6),Action(7),Action(0)],
                [Action(5,aux=0,target=MASK),Action(5,aux=1,target=1),Action(5,aux=0,target=0),Action(0)]]
    writers = [
        [Action(3,count=c),Action(3,count=2,first=1,second=-8),Action(3,count=0),Action(3,count=2),Action(3,count=7),Action(4,first=1,second=1),Action(11)],
        [Action(3,count=1),Action(3,count=2),Action(3,count=7),Action(6),Action(8,aux=0),Action(8,aux=1),Action(8,aux=2),Action(7),Action(7),Action(4),Action(6),Action(7),Action(11)],
        [Action(3,offset=-1,count=0),Action(3,offset=MAX_I32,count=1),Action(3,count=0),Action(4),Action(9),Action(4),Action(11),Action(10)],
        [Action(3,count=3),Action(5,aux=1,target=-1,first=1,second=1),Action(3,count=2),Action(5,aux=0,target=1),Action(5,aux=2,target=-2),Action(6),Action(7),Action(11)],
    ]
    for code in (-7,-8,-4,-10): writers.append([Action(3,count=c),Action(3,count=2,first=1,second=code),Action(6),Action(7),Action(3,count=2),Action(4)])
    for bad in (0,-101,-102): writers.append([Action(3,count=c),Action(3,count=2,first=1,second=bad),Action(3,count=0),Action(4),Action(6),Action(8),Action(7),Action(11),Action(6),Action(10),Action(12),Action(3,count=2),Action(4)])
    for code in (-7,-8,-4,-10,1): writers.append([Action(3,count=3),Action(11,flush=code),Action(6),Action(7),Action(4),Action(11)])
    for origin,event in ((0,-8),(1,-7),(2,-4),(0,1)):
        writers.append([Action(3,count=3),Action(5,aux=origin,target=2,seek_first=event),Action(6),Action(7),Action(5,aux=0,target=0),Action(3,count=1),Action(4)])
    assert len(readers)==20 and len(writers)==20
    for direction, groups in enumerate((readers,writers)):
        for index in range(4):
            rng=random.Random(SEED+direction*101+index)
            actions=[]
            for step in range(16):
                op=rng.choice((0,1,2,5) if direction==0 else (3,3,4,5))
                actions.append(Action(op,offset=2,count=rng.choice((0,1,2,3,7)),first=rng.choice((1,2,99,-7,-8,-4)),second=99,
                                      flush=rng.choice((0,0,-8)),aux=rng.randrange(3) if op==5 else 0,target=rng.randrange(8)))
            actions += [Action(6),Action(8,aux=index%3),Action(7),Action(9),Action(6),Action(10)]
            groups.append(actions)
    result=[]
    for direction, groups in enumerate((readers,writers)):
        for index, actions in enumerate(groups):
            capacity=4 if index<20 else (1,3,5,7)[index-20]
            result.append(Case(direction,capacity,tuple(actions)))
    assert len(result)==48
    return result


def reference(cases, alternate=False, mutant=None):
    out=Words(); out.many((MAGIC,len(cases)*3)); counts=Counter(); changed=False
    for number,case in enumerate(cases):
        baseline=None
        for route in range(3):
            out.many((number,route,case.direction,case.capacity,len(case.actions)), 'case header')
            m=Model(case,route,alternate,mutant)
            for step,a in enumerate(case.actions):
                out.many((step,*a.words()),'action header'); reply,extra=m.run(a,step); m.emit(out,reply,extra)
            counts.update(m.total); changed|=m.changed
            if baseline is None: baseline=m.observations
            elif not mutant: assert m.observations==baseline, ('route parity',number,route)
    out.put(END,'end');
    if mutant: assert changed, ('unreached mutant',mutant)
    return out,counts


def packet(cases):
    out=Words(); out.many((MAGIC,len(cases)*3))
    for number,case in enumerate(cases):
        for route in range(3):
            out.many((number,route,case.direction,case.capacity,len(case.actions)))
            for action in case.actions: out.many(action.words())
    return struct.pack('<%dQ'%len(out.values),*out.values)


def verify(data, expected):
    assert len(data)==len(expected.values)*8, ('byte length',len(data),len(expected.values)*8)
    actual=struct.unpack('<%dQ'%len(expected.values),data)
    for i,(a,b) in enumerate(zip(actual,expected.values)):
        assert a==b, ('first mismatch',i,a,b,'seed',hex(SEED))


def encoded(words): return struct.pack('<%dQ'%len(words.values),*words.values)


def summary(counts):
    keys=('actions','provider_calls','errors','handoffs','restores','empty_restores','bad_restores','fault_restores','empty_range_restores','fault_observations','read_bytes','accepted_bytes')
    return 'caller-buffered-model histories=48 routes=3 cases=144 '+ ' '.join('%s=%d'%(key,counts[key]) for key in keys)+' seed=0x%x\n'%SEED


def controls(cases):
    expected,counts=reference(cases); good=encoded(expected); verify(good,expected)
    alternate,other=reference(cases,True); verify(encoded(alternate),alternate); assert counts==other
    rejected=0
    def reject(data,label):
        nonlocal rejected
        try: verify(data,expected)
        except AssertionError: rejected+=1; return
        raise AssertionError('accepted corruption: '+label)
    for label in ('event count','provider event','offered byte','result','returned view metadata','returned view byte','rejected parts','owner state','owner view byte','parts state','parts view byte','peer state','peer byte','argument stride','argument byte','backing byte'):
        bad=bytearray(good); bad[expected.marks[label]*8]^=1; reject(bytes(bad),label)
    for label in ('clear fault on restore','ordinary invalid count faults','lost pending suffix','discard clears caller bytes'):
        bad,_=reference(cases,mutant=label); reject(encoded(bad),label)
    reject(good[:-1],'truncation'); reject(good+b'\0','trailing')
    print(summary(counts),end=''); print('cpu-controls=%d rejected=%d initial-patterns=2 bytes=%d'%(rejected,rejected,len(good)))


def main():
    cases=histories()
    if len(sys.argv)==2 and sys.argv[1]=='controls': controls(cases); return
    assert len(sys.argv)==2
    expected,counts=reference(cases)
    child=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(cases),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75,check=False)
    assert child.returncode==0,('native status',child.returncode,child.stderr[:2048])
    assert not child.stderr,('native stderr',child.stderr[:2048]); verify(child.stdout,expected); print(summary(counts),end='')


if __name__=='__main__': main()
