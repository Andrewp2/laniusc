"""Finite queue/dictionary expectations and binary transport, never library code."""
from collections import Counter, deque
from pathlib import Path
import struct
import subprocess
import sys

MAX = (1 << 64)-1


class State:
    def __init__(self, command):
        self.mode,length,prefix,self.reject,self.deny,self.quota,self.second,pattern = command
        value = lambda representative: 0 if self.mode >= 3 else MAX-representative
        self.source = deque((0 if pattern == 0 else i%3 if pattern == 1 else (2*i+1)%3,
                             100+i,value(100+i)) for i in range(length))
        self.target = {i:(i,10+i,value(10+i)) for i in range(prefix)}
        self.original = Counter(item[1] for item in (*self.target.values(),*self.source))
        self.length = length; self.source_calls = self.delivery_calls = 0
        self.replacement_calls = prefix if self.mode == 0 else 0
        self.history = []; self.trace = []; self.pending = None

    def inventory(self):
        owners = list(self.target.values())+self.history+list(self.source)
        if self.pending is not None:
            owners.append(self.pending[1])
        assert Counter(item[1] for item in owners) == self.original

    @staticmethod
    def result(tag, committed=0, replaced=0, exhausted=False, item=None, code=0, detail=0):
        return [tag,committed,replaced,int(exhausted),int(item is not None),
                *(item if item is not None else (0,0,0)),code,detail]

    def transfer(self, quota):
        # Calculate a finite candidate window and its committed dictionary
        # timeline before accounting for iterator pulls. Keys compare only by
        # identity; complete representative/value tuples remain distinct.
        window = list(self.source)[:min(quota,len(self.source))]
        target = self.target.copy(); timeline = []
        for incoming in window:
            if self.mode == 0 and incoming[1] == self.reject:
                timeline.append((incoming,None,1)); break
            old = target.get(incoming[0]); target[incoming[0]] = incoming
            failure = 2 if old is not None and old[1] == self.deny else 0
            timeline.append((incoming,old,failure))
            if failure:
                break
        self.target = target; self.pending = None
        committed = sum(failure != 1 for _,_,failure in timeline)
        replaced = sum(old is not None for _,old,_ in timeline)
        deliveries = [(old,failure) for _,old,failure in timeline if old is not None]
        self.history.extend(old for old,failure in deliveries if failure != 2)
        prior_deliveries = self.delivery_calls; self.delivery_calls += len(deliveries)
        consumed = len(timeline); self.source_calls += consumed
        if self.mode == 0:
            self.replacement_calls += consumed
        for incoming,old,failure in timeline:
            assert self.source.popleft() == incoming
            self.trace.extend([1,2] if self.mode == 0 else [1])
            if old is not None:
                self.trace.append(3)
        failure = timeline[-1][2] if timeline else 0
        if failure:
            incoming,old,_ = timeline[-1]
            item = incoming if failure == 1 else old
            self.pending = failure,item
            code = 1000+incoming[1] if failure == 1 else 2000+prior_deliveries+len(deliveries)
            answer = self.result(failure,committed,replaced,item=item,code=code,detail=old[1] if failure == 2 else 0)
        else:
            exhausted = quota > consumed
            if exhausted:
                assert not self.source
                self.source_calls += 1; self.trace.append(1)
            answer = self.result(0,committed,replaced,exhausted)
        assert replaced <= committed <= quota
        self.inventory()
        return answer

    def retry(self):
        if self.pending is None:
            return self.result(3)
        kind,item = self.pending; committed = replaced = 0
        if kind == 1:
            assert self.mode == 0
            self.trace.append(2); self.replacement_calls += 1
            if item[1] == self.reject:
                return self.result(4,item=item,code=1000+item[1])
            old = self.target.get(item[0]); self.target[item[0]] = item
            committed = 1; replaced = int(old is not None)
        else:
            old = item
        if old is not None:
            self.trace.append(3); self.delivery_calls += 1
            if old[1] == self.deny:
                self.pending = 2,old
                self.inventory()
                return self.result(5,committed,replaced,item=old,code=2000+self.delivery_calls,detail=old[1])
            self.history.append(old)
        self.pending = None; self.inventory()
        return self.result(6,committed,replaced)

    def snapshot(self):
        self.inventory()
        words = [self.length-len(self.source),self.source_calls,self.replacement_calls,
                 self.delivery_calls,len(self.history)]
        for item in self.history:
            words.extend(item)
        words.append(len(self.target))
        for identity in range(3):
            item = self.target.get(identity)
            words.extend([int(item is not None),*(item if item is not None else (0,0,0))])
        return words


def expected(command):
    state = State(command); words = []
    words.extend(state.transfer(state.quota)); words.extend(state.snapshot())
    words.extend(state.retry()); words.extend(state.snapshot())
    state.reject = state.deny = MAX
    words.extend(state.retry()); words.extend(state.snapshot())
    for quota in (state.second,MAX,0,1):
        words.extend(state.transfer(quota)); assert state.pending is None
        words.extend(state.snapshot())
    assert not state.source
    return words+[len(state.trace)]+state.trace


def cases():
    # n,prefix,reject-representative,deny-old-representative,quota,resume,pattern
    base = (
        (0,0,MAX,MAX,MAX,MAX,1),
        (4,2,MAX,MAX,0,2,1),
        (3,0,MAX,MAX,3,1,1),
        (5,1,MAX,MAX,MAX,MAX,0),
        (6,3,MAX,MAX,2,2,1),
        (4,3,MAX,10,MAX,MAX,1),
        (6,0,MAX,100,MAX,1,1),
        (4,0,MAX,MAX,5,0,2),
        (1,1,MAX,10,1,MAX,0),
        (2,3,MAX,MAX,MAX,0,2),
    )
    for mode in range(5):
        for profile in base:
            command = (mode,*profile)
            yield command,expected(command)
    for profile in ((4,2,100,MAX,MAX,MAX,1),(6,3,102,MAX,MAX,1,1),
                    (5,3,102,10,MAX,MAX,1)):
        command = (0,*profile)
        yield command,expected(command)


def validate(payload, campaign):
    assert len(payload)%8 == 0, "partial result word"
    actual = list(struct.unpack("<"+"Q"*(len(payload)//8),payload)); offset = 0
    for ordinal,(command,answer) in enumerate(campaign):
        assert actual[offset:offset+len(answer)] == answer, (ordinal,command,actual[offset:offset+len(answer)],answer)
        offset += len(answer)
    assert offset == len(actual), "truncated or extra phase/result data"


def controls():
    count = 0
    zero = State((0,2,1,MAX,MAX,0,MAX,1))
    assert zero.transfer(0)[:4] == [0,0,0,0] and not zero.trace and zero.source_calls == 0; count += 1
    exact = State((0,3,0,MAX,MAX,3,MAX,1))
    assert exact.transfer(3)[:4] == [0,3,0,0] and exact.source_calls == 3; count += 1
    assert exact.transfer(1)[:4] == [0,0,0,1] and exact.source_calls == 4; count += 1
    rejected = State((0,4,2,100,MAX,MAX,MAX,1))
    assert rejected.transfer(MAX) == [1,0,0,0,1,0,100,MAX-100,1100,0]; count += 1
    assert rejected.target[0][1] == 10 and rejected.pending[1][1] == 100; count += 1
    before = list(rejected.trace),rejected.source_calls,rejected.target.copy()
    assert rejected.retry()[0] == 4 and rejected.source_calls == before[1] and rejected.target == before[2]; count += 1
    rejected.reject = MAX
    assert rejected.retry()[:4] == [6,1,1,0] and rejected.target[0][1] == 100 and rejected.history[0][1] == 10; count += 1
    delivered = State((1,4,3,MAX,10,MAX,MAX,1))
    assert delivered.transfer(MAX) == [2,1,1,0,1,0,10,MAX-10,2001,10]; count += 1
    assert delivered.target[0][1] == 100 and delivered.pending[1][1] == 10 and not delivered.history; count += 1
    before = delivered.target.copy(),delivered.source_calls,delivered.replacement_calls
    assert delivered.retry()[0] == 5 and before == (delivered.target,delivered.source_calls,delivered.replacement_calls); count += 1
    delivered.deny = MAX
    assert delivered.retry()[:4] == [6,0,0,0] and delivered.history[0][1] == 10; count += 1
    repeated = State((0,5,1,MAX,MAX,MAX,MAX,0))
    assert repeated.transfer(MAX)[:4] == [0,5,5,1] and [item[1] for item in repeated.history] == [10,100,101,102,103]; count += 1
    assert repeated.target[0][1] == 104 and repeated.trace[:6] == [1,2,3,1,2,3]; count += 1
    set_case = State((3,2,1,MAX,MAX,MAX,MAX,0)); set_case.transfer(MAX)
    assert all(item[2] == 0 for item in (*set_case.target.values(),*set_case.history)); count += 1
    campaign = list(cases())
    payload = b"".join(struct.pack("<"+"Q"*len(answer),*answer) for _,answer in campaign)
    validate(payload,campaign); count += 1
    for changed in (payload[:-1],payload+b"\0"*8,struct.pack("<Q",999)+payload[8:]):
        try: validate(changed,campaign)
        except AssertionError: count += 1
        else: raise AssertionError("accepted changed model result or framing")
    print(f"replacement-sinks CPU controls={count} cases={len(campaign)} native-cases=0")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    assert len(sys.argv) == 2
    campaign = list(cases()); request = b"".join(struct.pack("<8Q",*command) for command,_ in campaign)
    result = subprocess.run([str(Path(sys.argv[1]).resolve())],input=request,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    assert result.returncode == 0 and not result.stderr, (result.returncode,result.stderr)
    validate(result.stdout,campaign)
    print(f"replacement-sinks model cases={len(campaign)}")


if __name__ == "__main__": main()
