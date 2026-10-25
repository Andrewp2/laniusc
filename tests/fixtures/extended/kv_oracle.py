"""Independent snapshot oracle for tests; production never invokes Python."""
import binascii
import struct
import sys


def encode(records):
    payload = b"".join(struct.pack("<II", len(k), len(v)) + k + v for k, v in sorted(dict(records).items()))
    head = b"LANIKV\r\n" + struct.pack("<IIII", 1, len(dict(records)), len(payload), 0)
    return head + payload + struct.pack("<I", binascii.crc32(head + payload))


def decode(snapshot):
    assert len(snapshot) >= 28 and snapshot[:8] == b"LANIKV\r\n"
    version, count, size, flags = struct.unpack_from("<IIII", snapshot, 8)
    assert version == 1 and flags == 0 and size == len(snapshot) - 28
    assert binascii.crc32(snapshot[:-4]) == struct.unpack_from("<I", snapshot, len(snapshot) - 4)[0]
    records, pos = [], 24
    for _ in range(count):
        kl, vl = struct.unpack_from("<II", snapshot, pos)
        pos += 8
        assert kl + vl <= len(snapshot) - 4 - pos
        key, value = snapshot[pos:pos + kl], snapshot[pos + kl:pos + kl + vl]
        pos += kl + vl
        assert not records or records[-1][0] < key
        records.append((key, value))
    assert pos == len(snapshot) - 4
    return records


def packed(records):
    return struct.pack("<I", len(records)) + b"".join(struct.pack("<II", len(k), len(v)) + k + v for k, v in records)


def unpacked(data):
    count, = struct.unpack_from("<I", data)
    records, pos = [], 4
    for _ in range(count):
        kl, vl = struct.unpack_from("<II", data, pos)
        pos += 8
        records.append((data[pos:pos + kl], data[pos + kl:pos + kl + vl]))
        pos += kl + vl
    assert pos == len(data)
    return records


if __name__ == "__main__":
    source = sys.stdin.buffer.read()
    pos = 0
    while pos < len(source):
        size, = struct.unpack_from("<I", source, pos)
        pos += 4
        item = source[pos:pos + size]
        pos += size
        output = encode(unpacked(item)) if sys.argv[1] == "encode" else packed(decode(item))
        sys.stdout.buffer.write(struct.pack("<I", len(output)) + output)
