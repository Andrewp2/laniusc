"""Digest protocol oracle using CPython's implementations, outside OpenSSL.

The language fixture controls partitions and layout. This oracle sees only the
logical algorithm and bytes, so a staging, ordering or stride error changes the
result independently of how those bytes reached EVP.
"""

import struct
import sys

import _sha3

try:
    import _sha2

    sha256, sha512 = _sha2.sha256, _sha2.sha512
except ImportError:  # CPython before its SHA-2 module consolidation.
    import _sha256
    import _sha512

    sha256, sha512 = _sha256.sha256, _sha512.sha512

constructors = (sha256, sha512, _sha3.sha3_256, _sha3.sha3_512)
source = sys.stdin.buffer.read()
count, = struct.unpack_from("<Q", source)
at = 8
output = bytearray()
for _ in range(count):
    algorithm, layout, mode, parameter, start, destination, length = struct.unpack_from(
        "<7Q", source, at
    )
    at += 56
    data = source[at : at + length]
    assert len(data) == length
    at += length
    digest = constructors[algorithm](data).digest()
    output.extend(struct.pack("<Q", len(digest)))
    output.extend(struct.pack("<" + "Q" * len(digest), *digest))
assert at == len(source)
sys.stdout.buffer.write(output)
