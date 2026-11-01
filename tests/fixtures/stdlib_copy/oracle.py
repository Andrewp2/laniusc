"""Finite, deterministic copy schedules checked against a FIFO/payload ledger.

This is test-only reference code. It never imports the production implementation.
The corpus emphasizes distinct stopping/recovery states rather than random volume.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, replace
from pathlib import Path
import struct
import subprocess
import sys

MAX = (1 << 64) - 1
PACKET_WORDS = 88


@dataclass(frozen=True)
class Action:
    read_limit: int = MAX
    max_calls: int = MAX
    abort: bool = False


@dataclass(frozen=True)
class Case:
    name: str
    length: int = 7
    capacity: int = 3
    reads: tuple[int, ...] = ()
    writes: tuple[int, ...] = ()
    actions: tuple[Action, ...] = (Action(),)
    seed: int = 0
    layout: int = 0


def source_bytes():
    result = [(index * 37 + 11) & 255 for index in range(16)]
    result[2:4] = [0, 255]
    return result


class Model:
    def __init__(self, case):
        self.case = case
        self.original = source_bytes()
        self.scratch = [199] * 16
        self.output = [177] * 16
        self.pending = deque()  # Each byte retains its original scratch slot.
        self.consumed = self.committed = 0
        self.read_attempts = self.write_attempts = 0
        self.active, self.eof, self.fault = True, False, False
        self.events = []
        self.stride = -8 if case.layout == 0 else 1

    @property
    def read(self):
        return self.case.seed + self.consumed

    @property
    def written(self):
        return self.case.seed + self.committed

    def provider(self, writing, requested):
        identity = 2 if writing else 1
        attempts = self.write_attempts if writing else self.read_attempts
        schedule = self.case.writes if writing else self.case.reads
        event = schedule[attempts] if attempts < len(schedule) else 99
        offset = self.pending[0][0] if writing else 3
        position = self.committed if writing else self.consumed
        payload = sum(value << (8 * index) for index, (_, value) in enumerate(self.pending)) if writing else 0
        self.events.append((identity, event, offset, requested, position,
                            self.stride, payload, len(self.events)))
        if writing:
            self.write_attempts += 1
        else:
            self.read_attempts += 1
        if -10 <= event <= -1:
            return 'error', -731 if event == -3 else -event
        malformed = {-101: -1, -102: requested + 1, -103: -(1 << 31), -104: (1 << 31) - 1}
        if event in malformed:
            return 'count', malformed[event]
        assert event >= 0
        amount = min(event, requested)
        if not writing:
            amount = min(amount, self.case.length - self.consumed)
        return 'count', amount

    def step(self, action):
        calls = newly_read = 0
        if action.abort:
            self.active = False
            return self.snapshot(2, 0, 0, 0)
        if not self.active:
            return self.snapshot(1, 6, 3, 0)
        if self.fault:
            return self.snapshot(1, 4, 3, 0)
        if self.eof:
            return self.snapshot(0, 1, 0, 0)
        while True:
            writing = bool(self.pending)
            if not writing and newly_read == action.read_limit:
                return self.snapshot(0, 2, 0, calls)
            if calls == action.max_calls:
                return self.snapshot(0, 3, 0, calls)
            if not writing and self.read == MAX:
                return self.snapshot(1, 7, 3, calls)
            requested = len(self.pending) if writing else min(
                self.case.capacity, action.read_limit - newly_read, MAX - self.read)
            assert requested > 0
            kind, reply = self.provider(writing, requested)
            calls += 1
            if kind == 'error':
                if reply == 1:
                    continue
                if reply == 2:
                    return self.snapshot(0, 5 if writing else 4, 0, calls)
                return self.snapshot(1, reply, 2 if writing else 1, calls)
            if not 0 <= reply <= requested:
                self.fault = True
                return self.snapshot(1, 4, 2 if writing else 1, calls)
            if writing:
                if reply == 0:
                    return self.snapshot(1, 5, 2, calls)
                for _ in range(reply):
                    _, value = self.pending.popleft()
                    self.output[2 + self.committed] = value
                    self.committed += 1
            elif reply == 0:
                self.eof = True
                return self.snapshot(0, 1, 0, calls)
            else:
                chunk = self.original[2 + self.consumed:2 + self.consumed + reply]
                for index, value in enumerate(chunk):
                    self.scratch[3 + index] = value
                    self.pending.append((3 + index, value))
                self.consumed += reply
                newly_read += reply

    def snapshot(self, kind, code, side, calls):
        # Conservation and immutable storage supplement transcript equality.
        assert self.read <= MAX and self.written <= self.read
        assert self.read - self.written == len(self.pending)
        assert [value for _, value in self.pending] == self.original[2 + self.committed:2 + self.consumed]
        assert self.output[2:2 + self.committed] == self.original[2:2 + self.committed]
        assert all(value == 177 for index, value in enumerate(self.output)
                   if not 2 <= index < 2 + self.committed)
        assert all(value == 199 for index, value in enumerate(self.scratch)
                   if not 3 <= index < 3 + self.case.capacity)
        assert not self.eof or not self.pending
        header = [kind, code, side, self.read, self.written, calls,
                  int(self.active), int(self.eof), int(self.fault),
                  self.pending[0][0] if self.pending else 3, len(self.pending),
                  self.consumed, self.committed, self.read_attempts,
                  self.write_attempts, len(self.events), self.stride]
        return tuple(value & MAX for value in header + self.original + self.output + self.scratch
                     + [value for _, value in self.pending] + [256] * (8 - len(self.pending))
                     + [value for event in self.events for value in event])


def cases():
    single_calls = tuple(Action(MAX, 1) for _ in range(14))
    templates = [
        Case('empty-observed-eof', length=0,
             actions=(Action(0, 0), Action(1, 0), Action(1, 1), Action(0, 0), Action(abort=True), Action())),
        Case('exact-quota-is-not-eof', length=4, capacity=2,
             actions=(Action(4), Action(0, 0), Action(1, 0), Action(1, 1), Action(0, 0))),
        Case('one-call-resumption', length=5, reads=(2,), writes=(1,), actions=single_calls),
        Case('alternating-would-block', length=5, reads=(-2, 2, -2, 99), writes=(-2, 1, -2, 99),
             actions=tuple(Action() for _ in range(8))),
        Case('eintr-charged-at-both-ends', length=3, reads=(-1, -1, 2), writes=(-1, -1, 1),
             actions=single_calls),
        Case('new-read-quota-pending-first', capacity=4,
             actions=(Action(1), Action(0), Action(3, 1), Action(0, 1), Action(0), Action(1), Action())),
        Case('abort-partial-output', length=5, capacity=4, writes=(1,),
             actions=(Action(4, 2), Action(abort=True), Action(abort=True), Action(), Action(0, 0))),
        Case('write-zero-recovery', length=3, writes=(0, 1, 0),
             actions=(Action(), Action(), Action(), Action(0, 0))),
        Case('small-positive-quota-never-overreads', length=9, capacity=8,
             actions=(Action(1), Action(2), Action(1), Action(2), Action(3), Action(0), Action(1))),
    ]
    for direction in ('read', 'write'):
        for error in range(3, 11):
            options = {'reads' if direction == 'read' else 'writes': (-error,)}
            templates.append(Case(f'{direction}-ordinary-error-{error}', length=2,
                                  actions=(Action(), Action(), Action(0, 0)), **options))
        for malformed in range(101, 105):
            options = {'reads' if direction == 'read' else 'writes': (1, -malformed)}
            templates.append(Case(f'{direction}-malformed-{malformed}', length=4, capacity=3,
                                  actions=(Action(), Action(0, 0), Action(), Action(abort=True), Action()), **options))
    templates += [
        Case('headroom-two-real-bytes', length=3, capacity=4, seed=MAX - 2,
             actions=(Action(MAX, 1), Action(0, 1), Action(0, 0), Action(1, 0), Action(1), Action())),
        Case('zero-headroom-cannot-probe-eof', length=0, seed=MAX,
             actions=(Action(0, 0), Action(1, 0), Action(1), Action(), Action(abort=True), Action())),
        Case('positive-headroom-observes-empty', length=0, seed=MAX - 1,
             actions=(Action(), Action(0, 0), Action(abort=True), Action())),
    ]
    assert len(templates) == 36
    return [replace(case, layout=layout) for case in templates for layout in range(2)]


def packet(values):
    words = []
    for case in values:
        assert 0 < len(case.actions) <= 16
        part = [case.layout, case.length, case.capacity, case.seed, len(case.actions), 0, 0, 0]
        part += list(case.reads) + [99] * (16 - len(case.reads))
        part += list(case.writes) + [99] * (16 - len(case.writes))
        for action in case.actions:
            part += [int(action.abort), action.read_limit, action.max_calls]
        part += [0] * (PACKET_WORDS - len(part))
        assert len(part) == PACKET_WORDS
        words += part
    return struct.pack('<' + 'Q' * len(words), *(value & MAX for value in words))


def expected(values):
    result = []
    offsets = []
    for case in values:
        model = Model(case)
        for index, action in enumerate(case.actions):
            record = model.step(action)
            offsets.append((len(result), len(record), case.name, case.layout, index))
            result.extend(record)
    return result, offsets


def compare(actual, wanted, offsets):
    assert len(actual) == len(wanted), f'output word count {len(actual)} != {len(wanted)}'
    for start, length, name, layout, step in offsets:
        left, right = actual[start:start + length], wanted[start:start + length]
        if left != right:
            at = next(index for index in range(length) if left[index] != right[index])
            raise AssertionError(f'{name} layout={layout} step={step} record_word={at}: {left[at]} != {right[at]}')


def controls(wanted, offsets):
    # Exercise the observer against altered result, state, bytes, and call logs.
    positions = [0, 3, 5, 6, 9, 17, 33, 49]
    active = next(start for start, length, *_ in offsets if length > 73)
    pending = next(start for start, *_ in offsets if wanted[start + 10] > 0)
    positions += [pending + 65, active + 73 + 2, active + 73 + 3, active + 73 + 6]
    for at in positions:
        changed = wanted.copy()
        changed[at] ^= 1
        try:
            compare(changed, wanted, offsets)
        except AssertionError:
            pass
        else:
            raise AssertionError(f'observer missed mutation at word {at}')
    return len(positions)


def main():
    values = cases()
    wanted, offsets = expected(values)
    mutations = controls(wanted, offsets)
    actions = sum(len(case.actions) for case in values)
    if sys.argv[1:] == ['--self-test']:
        print(f'copy-model CPU cases={len(values)} actions={actions} layouts=2 corruption-controls={mutations}')
        return
    assert len(sys.argv) == 2
    executable = str(Path(sys.argv[1]).resolve())
    result = subprocess.run([executable], input=packet(values), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    assert len(result.stdout) % 8 == 0
    actual = list(struct.unpack('<' + 'Q' * (len(result.stdout) // 8), result.stdout))
    compare(actual, wanted, offsets)
    print(f'copy-model cases={len(values)} actions={actions} layouts=2 corruption-controls={mutations}')


if __name__ == '__main__':
    main()
