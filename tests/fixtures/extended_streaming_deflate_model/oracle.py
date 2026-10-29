"""Independent RFC block inspector, zlib decoder, and byte-event progress model.

There is no compressor port here. Native wire bytes supply only publication
events after independently checking their complete content and block policy.
The CPU controls use a deliberately simple literal/stored test stream writer.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import random
import struct
import subprocess
import sys
import zlib

SEED = 0xDEF1A7E0261115
MASK = (1 << 64) - 1
MAGIC = 0x6465666C61746531
BLOCK = 32768
BACKING = 2056
HEADER = (b'', b'', b'\x78\x01', b'\x1f\x8b\x08\0\0\0\0\0\0\xff')


@dataclass(frozen=True)
class Case:
    name: str
    data: bytes
    kind: int
    layout: int

    @property
    def passes(self):
        return 3 if len(self.data) <= 64 else 2


def corpus():
    rng = random.Random(SEED)
    random_full = rng.randbytes(BLOCK)
    random_two = rng.randbytes(2 * BLOCK)
    payloads = [
        ('empty', b''), ('zero', b'\0'), ('high', b'\xff'),
        ('pair', b'\0\xff'), ('short-binary', bytes(range(16))),
        ('fixed-tie', bytes(range(144, 167))),
        ('stored-choice', bytes(range(144, 175))),
        ('phrase', b'one little stream, one little stream; done.'),
        ('repeat64', b'A' * 64),
        ('binary255', bytes(range(255))), ('binary256', bytes(range(256))),
        ('random257', rng.randbytes(257)), ('random1024', rng.randbytes(1024)),
        ('repeat1024', (b'ab\0\xffab' * 171)[:1024]),
        ('repeat32767', b'R' * 32767), ('repeat32768', b'R' * BLOCK),
        ('repeat32769', b'R' * (BLOCK + 1)),
        ('random32767', random_full[:-1]), ('random32768', random_full),
        ('random32769', random_full + b'\x82'),
        ('repeat65536', b'XY' * BLOCK), ('random65536', random_two),
        ('repeat65537', b'XY' * BLOCK + b'X'),
        ('random65537', random_two + b'\x17'),
        ('mixed70000', (bytes(range(256)) * 274)[:70000]),
        ('repeated-block70000', (random_full * 3)[:70000]),
        ('near-match70000', ((b'A' * 257 + b'B') * 272)[:70000]),
        ('random70000', rng.randbytes(70000)),
    ]
    assert len(payloads) == 28 and all(len(data) <= 70000 for _, data in payloads)
    return [Case(name, data, kind, (index * 3 + kind * 2) % 8)
            for index, (name, data) in enumerate(payloads) for kind in range(4)]


def summary(cases):
    passes = sum(c.passes for c in cases)
    inputs = sum(len(c.data) * c.passes for c in cases)
    return (f'streaming-deflate-model cases={len(cases)} passes={passes} '
            f'patterns={len({c.name for c in cases})} whole={len(cases)} '
            f'irregular={len(cases)} bytewise={passes - 2 * len(cases)} '
            f'input_bytes={inputs} formats=4 layouts=8 seed=0x{SEED:x}\n')


class Bits:
    def __init__(self, data):
        self.data, self.position = data, 0

    def take(self, width):
        assert self.position + width <= 8 * len(self.data), 'truncated DEFLATE bits'
        value = sum(((self.data[(self.position + n) // 8] >> ((self.position + n) % 8)) & 1) << n
                    for n in range(width))
        self.position += width
        return value

    def align(self):
        self.position = (self.position + 7) // 8 * 8


# Canonical code intervals and length/distance tables from RFC1951 sections
# 3.2.5 and 3.2.6, independent of Lanius hash/match/code-width routines.
FIXED = {(8, 0x30 + s): s for s in range(144)}
FIXED.update({(9, 0x190 + s - 144): s for s in range(144, 256)})
FIXED.update({(7, s - 256): s for s in range(256, 280)})
FIXED.update({(8, 0xC0 + s - 280): s for s in range(280, 288)})
LENGTH_BASE = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
               35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
LENGTH_EXTRA = (0,) * 8 + (1,) * 4 + (2,) * 4 + (3,) * 4 + (4,) * 4 + (5,) * 4 + (0,)
DISTANCE_BASE = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                 8193, 12289, 16385, 24577)
DISTANCE_EXTRA = (0,) * 4 + tuple(n for n in range(1, 14) for _ in range(2))


def fixed_symbol(reader):
    code = 0
    for width in range(1, 10):
        code = code * 2 + reader.take(1)
        if (width, code) in FIXED:
            return FIXED[width, code]
    raise AssertionError('invalid fixed Huffman symbol')


def inspect_blocks(raw):
    """Parse actual wire blocks; every fixed block has independent history."""
    reader, blocks = Bits(raw), []
    while True:
        start = reader.position
        final, kind = reader.take(1), reader.take(2)
        assert kind in (0, 1), 'stream policy permits stored/fixed blocks only'
        decoded = bytearray()
        if kind == 0:
            reader.align()
            length, inverse = reader.take(16), reader.take(16)
            assert length ^ inverse == 0xFFFF, 'stored complement'
            decoded.extend(reader.take(8) for _ in range(length))
        else:
            while True:
                symbol = fixed_symbol(reader)
                if symbol == 256:
                    break
                if symbol < 256:
                    decoded.append(symbol)
                else:
                    assert 257 <= symbol <= 285, 'reserved length symbol'
                    index = symbol - 257
                    length = LENGTH_BASE[index] + reader.take(LENGTH_EXTRA[index])
                    distance_code = 0
                    for _ in range(5):
                        distance_code = 2 * distance_code + reader.take(1)
                    assert distance_code < 30, 'reserved distance symbol'
                    distance = DISTANCE_BASE[distance_code] + reader.take(DISTANCE_EXTRA[distance_code])
                    assert distance <= len(decoded), 'match history crossed block boundary'
                    for _ in range(length):
                        decoded.append(decoded[-distance])
                assert len(decoded) <= BLOCK, 'block exceeds fixed input workspace'
        blocks.append((start, reader.position, final, kind, bytes(decoded)))
        assert len(blocks) <= 7, 'unexpected block count'
        if final:
            break
    assert (reader.position + 7) // 8 == len(raw), 'raw trailing bytes'
    return tuple(blocks)


@lru_cache(maxsize=128)
def policy(raw, data):
    """Group independently parsed blocks into one wire publication per input unit."""
    blocks = inspect_blocks(raw)
    units, at, block_index = [], 0, 0
    expected = (BLOCK,) * (len(data) // BLOCK) + (len(data) % BLOCK,)
    for index, count in enumerate(expected):
        assert block_index < len(blocks), 'missing final partial/empty block'
        start, end, final, kind, decoded = blocks[block_index]
        block_index += 1
        last = index == len(expected) - 1
        assert start % 8 == 0 and bool(final) == last, 'full block must be nonfinal'
        assert decoded == data[at:at + count], 'block data/order/size'
        at += count
        if not last and kind == 1:
            assert block_index < len(blocks), 'missing fixed-block alignment block'
            alignment = blocks[block_index]
            assert alignment[0] == end and alignment[2:] == (0, 0, b''), 'nonfinal fixed alignment'
            end = alignment[1]
            block_index += 1
        if not last:
            assert end % 8 == 0, 'nonfinal block leaves partial byte'
        wire = raw[start // 8:(end + 7) // 8]
        assert len(wire) <= count + 5, 'selected form exceeds stored candidate'
        units.append((count, wire, last))
    assert block_index == len(blocks) and at == len(data), 'extra block or input'
    return tuple(units), blocks


def trailer(case):
    if case.kind == 2:
        return struct.pack('>I', zlib.adler32(case.data))
    if case.kind == 3:
        return struct.pack('<II', zlib.crc32(case.data), len(case.data) & 0xFFFFFFFF)
    return b''


def inspect_wire(case, wire):
    prefix, suffix = HEADER[case.kind], trailer(case)
    assert wire.startswith(prefix) and (not suffix or wire.endswith(suffix)), 'container bytes/checksum/size'
    raw = wire[len(prefix):len(wire) - len(suffix) if suffix else len(wire)]
    decoder = zlib.decompressobj((-15, -15, 15, 31)[case.kind])
    result = decoder.decompress(wire) + decoder.flush()
    assert decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, 'complete single stream'
    assert result == case.data, 'system zlib output mismatch'
    units, blocks = policy(raw, case.data)
    if case.name == 'fixed-tie':
        assert blocks[0][3] == 1 and len(raw) == len(case.data) + 5, 'fixed must win literal-size tie'
    if case.name == 'stored-choice':
        assert blocks[0][3] == 0, 'stored must beat high literal codes'
    if case.name == 'repeat32768':
        assert blocks[0][3] == 1 and len(raw) < 512, 'fixed match witness'
    return raw, units


class Tape:
    """Generic two-channel byte-event interpreter; no compression or bit state.

    One intake event per policy block, a final-promise barrier, and opaque
    output spans. Operations are declaratively derived from inspected wire.
    """
    def __init__(self, case, units):
        self.events = [('put', HEADER[case.kind])]
        for count, wire, last in units:
            self.events.append(('take', count))
            if last:
                self.events.append(('final', 0))
            self.events.append(('put', wire))
        self.events.append(('put', trailer(case)))
        self.event, self.offset = 0, 0

    def step(self, offered, capacity, final):
        read, output = 0, bytearray()
        while self.event < len(self.events):
            operation, payload = self.events[self.event]
            if operation == 'final':
                if not final:
                    return read, bytes(output), 1
            elif operation == 'take':
                count = min(payload - self.offset, offered - read)
                self.offset += count
                read += count
                if self.offset < payload:
                    assert not final, 'producer final promise before complete input'
                    return read, bytes(output), 1
            else:
                count = min(len(payload) - self.offset, capacity - len(output))
                output += payload[self.offset:self.offset + count]
                self.offset += count
                if self.offset < len(payload):
                    return read, bytes(output), 2
            self.event += 1
            self.offset = 0
        return read, bytes(output), 3


def capacity(pass_index, call):
    return 2048 if pass_index == 0 else ((0, 1, 0, 7, 31, 2048, 509, 0)[call % 8]
                                        if pass_index == 1 else (0, 1, 1, 0, 1)[call % 5])


def paint(call):
    return bytearray((193 + call % 29 + index * 7) & 255 for index in range(BACKING))


def source_state(case):
    result = bytearray((81 + index * 11) & 255 for index in range(len(case.data) + 8))
    result[4:4 + len(case.data)] = bytes((index * 17 + 43) & 255 for index in range(len(case.data)))
    return result


def words(*values):
    return struct.pack('<' + 'Q' * len(values), *(value & MASK for value in values))


class Reader:
    def __init__(self, data):
        self.data, self.at = data, 0

    def take(self, count):
        assert 0 <= count <= len(self.data) - self.at, 'truncated observation protocol'
        data = self.data[self.at:self.at + count]
        self.at += count
        return data

    def words(self, count):
        return struct.unpack('<' + 'Q' * count, self.take(count * 8))


def verify_pass(case, pass_index, records):
    assert records and len(records) < 2000
    wire = b''.join(record[1][4:4 + record[0][7]] for record in records)
    raw, units = inspect_wire(case, wire)
    tape = Tape(case, units)
    position = total_written = turn = 0
    frontier, final = (len(case.data), True) if pass_index == 0 else (0, False)
    for call, (header, backing) in enumerate(records):
        record, observed_pass, observed_call, offered, cap, observed_final, read, written, status, error, done, failed, total_r, total_w = header
        assert (record, observed_pass, observed_call, offered, cap, observed_final) == (
            0, pass_index, call, frontier - position, capacity(pass_index, call), int(final)), 'offered schedule'
        expected_read, emitted, expected_status = tape.step(offered, cap, final)
        assert (read, written, status, error, done, failed) == (
            expected_read, len(emitted), expected_status, 0, int(expected_status == 3), 0), 'exact per-call progress/status'
        expected_backing = paint(call)
        expected_backing[4:4 + len(emitted)] = emitted
        assert backing == expected_backing, 'output prefix/tail/guard mismatch'
        position += read
        total_written += written
        assert (total_r, total_w) == ((position, total_written) if case.kind else (0, 0)), 'cumulative accounting'
        if status == 1:
            assert read == offered, 'NeedInput must consume complete offered span'
            if frontier == len(case.data):
                final = True
            else:
                amount = (0, 1, 13, 4093, 32767, 2, 0, 8191, 257)[turn % 9] if pass_index == 1 else 1
                turn += 1
                frontier = min(len(case.data), frontier + amount)
                if pass_index == 2 and frontier == len(case.data):
                    final = True
        if status == 3:
            assert call == len(records) - 1 and position == len(case.data), 'premature/nonfused completion'
    assert records[-1][0][8] == 3 and total_written == len(wire), 'stream never completed'
    return raw, wire


def expected_guards():
    block = bytes(value for index in range(4) for value in (211 + index, 231 + index))
    pending = bytes(range(171, 175)) + bytes((index + 57) & 255 for index in range(32777, 32784))
    scratch = words(*(value for index in range(4) for value in (-131 - index, -151 - index)))
    return block + pending + scratch


def verify(blob, cases):
    reader, baseline = Reader(blob), {}
    call_count = wire_count = 0
    for case_index, case in enumerate(cases):
        try:
            assert reader.words(5) == (MAGIC, case.kind, case.layout, len(case.data), case.passes), 'case header'
            strides = ((1 if case.layout & 1 else -8), (1 if case.layout & 2 else -8),
                       (1 if case.layout & 4 else -8), (-8 if case.layout & 1 else 1), 4)
            assert reader.words(5) == tuple(stride & MASK for stride in strides), 'actual native/packed stride'
            first_wire = None
            for pass_index in range(case.passes):
                assert reader.words(6) == (10, pass_index, 0, 0, 0, 0), 'new/reset encoder state'
                records = []
                while True:
                    header = reader.words(14)
                    assert header[0] == 0, 'missing ordinary call record'
                    backing = reader.take(BACKING)
                    records.append((header, backing))
                    assert len(records) < 2000
                    if header[8] == 3 or header[9] != 0:
                        break
                raw, wire = verify_pass(case, pass_index, records)
                call_count += len(records)
                wire_count += len(wire)
                if first_wire is None:
                    first_wire = wire
                assert wire == first_wire, 'caller chunks changed compressed wire'
                if case.name in baseline:
                    assert raw == baseline[case.name], 'raw/framed/layout body disagreement'
                else:
                    baseline[case.name] = raw
                for record, status, error in ((1, 3, 0), (2, 0, 1)):
                    call = len(records) + record - 1
                    counters = (len(case.data), len(wire)) if case.kind else (0, 0)
                    assert reader.words(14) == (record, pass_index, call, 0, 0, 1, 0, 0, status, error, 1, 0, *counters), 'fused EOF/metadata precedence'
                    assert reader.take(BACKING) == paint(call), 'terminal writes'
                assert reader.words(4) == (4, pass_index, len(case.data), len(case.data)), 'source extent'
                assert reader.take(len(case.data) + 8) == source_state(case), 'recycled input/guards'
                assert reader.words(1) == (5,) and reader.take(83) == expected_guards(), 'workspace guards'
            assert reader.words(1) == (99,), 'case terminator'
        except (AssertionError, zlib.error, IndexError) as error:
            raise AssertionError(f'case {case_index} {case.name} format={case.kind} layout={case.layout}: {error}') from error
    assert reader.at == len(blob), 'trailing observation bytes'
    return call_count, wire_count


def input_bytes(cases):
    return b''.join(words(case.kind, case.layout, len(case.data), case.passes) + case.data for case in cases)


class TestBits:
    """Controls only: literal-only Huffman or stored streams, no match search."""
    def __init__(self):
        self.bits = []

    def put(self, value, width):
        self.bits.extend((value >> i) & 1 for i in range(width))

    def symbol(self, value):
        (width, code), = (item for item, symbol in FIXED.items() if symbol == value)
        self.bits.extend((code >> i) & 1 for i in range(width - 1, -1, -1))

    def bytes(self):
        return bytes(sum(bit << n for n, bit in enumerate(self.bits[i:i + 8])) for i in range(0, len(self.bits), 8))


def control_raw(data):
    output = bytearray()
    for at in range(0, len(data) // BLOCK * BLOCK, BLOCK):
        part = data[at:at + BLOCK]
        output += b'\0' + struct.pack('<HH', len(part), 0xFFFF ^ len(part)) + part
    part = data[len(data) // BLOCK * BLOCK:]
    writer = TestBits()
    writer.put(3, 3)
    for byte in part:
        writer.symbol(byte)
    writer.symbol(256)
    fixed = writer.bytes()
    stored = b'\1' + struct.pack('<HH', len(part), 0xFFFF ^ len(part)) + part
    output += min((fixed, stored), key=len)
    return bytes(output)


def synthetic(cases):
    output = bytearray()
    for case in cases:
        raw = control_raw(case.data)
        wire = HEADER[case.kind] + raw + trailer(case)
        _, units = inspect_wire(case, wire)
        output += words(MAGIC, case.kind, case.layout, len(case.data), case.passes)
        output += words(1 if case.layout & 1 else -8, 1 if case.layout & 2 else -8,
                        1 if case.layout & 4 else -8, -8 if case.layout & 1 else 1, 4)
        for pass_index in range(case.passes):
            output += words(10, pass_index, 0, 0, 0, 0)
            tape, position, total_w, turn, call = Tape(case, units), 0, 0, 0, 0
            frontier, final = (len(case.data), True) if pass_index == 0 else (0, False)
            while True:
                cap, offered = capacity(pass_index, call), frontier - position
                read, emitted, status = tape.step(offered, cap, final)
                position += read
                total_w += len(emitted)
                output += words(0, pass_index, call, offered, cap, int(final), read, len(emitted), status,
                                0, int(status == 3), 0, position if case.kind else 0, total_w if case.kind else 0)
                backing = paint(call)
                backing[4:4 + len(emitted)] = emitted
                output += backing
                call += 1
                if status == 3:
                    break
                if status == 1:
                    if frontier == len(case.data):
                        final = True
                    else:
                        amount = (0, 1, 13, 4093, 32767, 2, 0, 8191, 257)[turn % 9] if pass_index == 1 else 1
                        turn += 1
                        frontier = min(len(case.data), frontier + amount)
                        if pass_index == 2 and frontier == len(case.data):
                            final = True
            for record, status, error in ((1, 3, 0), (2, 0, 1)):
                output += words(record, pass_index, call, 0, 0, 1, 0, 0, status, error, 1, 0,
                                position if case.kind else 0, total_w if case.kind else 0)
                output += paint(call)
                call += 1
            output += words(4, pass_index, len(case.data), len(case.data)) + source_state(case)
            output += words(5) + expected_guards()
        output += words(99)
    return bytes(output)


def controls():
    # Controls test the verifier, not the Lanius encoder. Large stored blocks
    # provide exact-multiple/final-empty coverage without a compressor clone.
    selected = {'empty', 'fixed-tie', 'stored-choice', 'random32768', 'random65537'}
    cases = [case for case in corpus() if case.name in selected]
    good = synthetic(cases)
    calls, wires = verify(good, cases)
    mutants = []
    # First ordinary record follows ten case words and six reset-state words.
    start = 16 * 8
    for label, offset in [('read', 6), ('written', 7), ('status', 8), ('error', 9),
                          ('done', 10), ('failed', 11), ('total-read', 12), ('total-written', 13),
                          ('offer', 3), ('capacity', 4), ('final', 5)]:
        value = bytearray(good)
        value[start + offset * 8] ^= 1
        mutants.append((label, bytes(value)))
    for label, offset in [('output-byte', start + 14 * 8 + 4),
                          ('output-guard', start + 14 * 8 + 3),
                          ('output-tail', start + 14 * 8 + BACKING - 1),
                          ('stride', 5 * 8), ('workspace-guard', good.find(expected_guards()))]:
        assert offset >= 0
        value = bytearray(good)
        value[offset] ^= 1
        mutants.append((label, bytes(value)))
    mutants += [('truncation', good[:-1]), ('trailing', good + b'\0')]
    for label, corrupted in mutants:
        try:
            verify(corrupted, cases)
        except AssertionError:
            pass
        else:
            raise AssertionError(f'control accepted corruption: {label}')
    # Coherent wire changes must also fail, independent of byte protocol noise.
    raw = control_raw(b'')
    for label, corrupted, data in [('missing-final', b'', b''), ('trailing-raw', raw + b'\0', b''),
                                    ('wrong-plaintext', control_raw(b'X'), b'Y'),
                                    ('final-full-block', b'\1\0\x80\xff\x7f' + bytes(BLOCK), bytes(BLOCK))]:
        try:
            inspect_wire(Case(label, data, 0, 0), corrupted)
        except (AssertionError, zlib.error):
            pass
        else:
            raise AssertionError(f'control accepted wire mutation: {label}')
    # Cross-check the RFC inspector's match/overlap handling against the host C
    # implementation. These streams are not predictions of production bytes.
    reference_data = [b'A' * n for n in (3, 64, 258, 259, 4096, BLOCK)]
    reference_data += [(bytes(range(256)) * 32)[:8191], (b'abc\0def\xff' * 1024)]
    reference_raw = None
    for data in reference_data:
        encoder = zlib.compressobj(level=6, wbits=-15, strategy=zlib.Z_FIXED)
        encoded = encoder.compress(data) + encoder.flush()
        blocks = inspect_blocks(encoded)
        assert b''.join(block[4] for block in blocks) == data
        if len(data) == BLOCK:
            assert len(blocks) == 1 and blocks[0][3] == 1
            reference_raw = encoded, blocks[0][1]
    # Turn that independent full fixed block into the promised nonfinal form,
    # append an empty stored alignment block, then a final empty fixed block.
    encoded, end = reference_raw
    bit_values = [(encoded[index // 8] >> (index % 8)) & 1 for index in range(end)]
    bit_values[0] = 0
    aligned = TestBits()
    aligned.bits = bit_values + [0, 0, 0]
    while len(aligned.bits) % 8:
        aligned.bits.append(0)
    aligned.put(0, 16)
    aligned.put(65535, 16)
    aligned_raw = aligned.bytes() + control_raw(b'')
    inspect_wire(Case('alignment-control', b'A' * BLOCK, 0, 0), aligned_raw)
    print(f'cpu-controls cases={len(cases)} passes={sum(c.passes for c in cases)} calls={calls} '
          f'wire_bytes={wires} rejected={len(mutants) + 4} reference_streams={len(reference_data) + 1} '
          f'transcript_bytes={len(good)}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
        return
    assert len(sys.argv) == 2, 'oracle.py EXECUTABLE | controls'
    cases = corpus()
    result = subprocess.run([sys.argv[1]], input=input_bytes(cases), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=75, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr[:2000])
    verify(result.stdout, cases)
    print(summary(cases), end='')


if __name__ == '__main__':
    main()
