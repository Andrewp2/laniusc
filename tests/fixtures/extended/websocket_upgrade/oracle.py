"""Differential WebSocket accept tests; no production implementation lives here.

Every positive case calls actual OpenSSL. CPython's _sha1 supplies a separate
SHA-1 implementation for the oracle, then base64 applies the RFC wire encoding.
The optional fault shim only injects provider errors and unexpected sizes.
"""
from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
import os
from pathlib import Path
import struct
import subprocess
import _sha1

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
SAMPLE = b"dGhlIHNhbXBsZSBub25jZQ=="
RECORD = 208

@dataclass(frozen=True)
class Case:
    key: bytes
    layout: int = 0
    mode: int = 0
    capacity: int = 28
    status: int = 0
    label: str = ""


def accepts(key: bytes) -> bytes:
    return base64.b64encode(_sha1.sha1(key + GUID).digest())


def cases() -> list[Case]:
    output = []
    # Include every byte value across nonces, not merely printable input.
    nonces = [b"the sample nonce", bytes(16), bytes([255]) * 16]
    nonces += [bytes((seed * 37 + i * 73) & 255 for i in range(16)) for seed in range(32)]
    for nonce in nonces:
        key = base64.b64encode(nonce)
        for layout in range(2):
            for mode in range(2):
                for capacity in (28, 40):
                    output.append(Case(key, layout, mode, capacity, label=f"nonce={nonce.hex()}"))
    for layout in range(2):
        for key in (b"", SAMPLE[:-1], SAMPLE + b"=", b"!" + SAMPLE[1:],
                    SAMPLE[:-3] + b"R==", SAMPLE[:-2] + b"A=", SAMPLE + b"\r\n",
                    b"AA==" * 6, b"AAAAAAAAAAAAAAAAAAAAAA== ", bytes([255]) * 24):
            output.append(Case(key, layout, status=3, label="invalid key"))
        for capacity in (0, 1, 27):
            output.append(Case(SAMPLE, layout, capacity=capacity, status=2, label="capacity"))
        output.append(Case(SAMPLE, layout, mode=2, status=1, label="source bounds"))
        output.append(Case(SAMPLE, layout, mode=3, status=1, label="destination bounds"))
    return output


def packet(values: list[Case]) -> bytes:
    return struct.pack("<Q", len(values)) + b"".join(
        struct.pack("<4Q", case.layout, case.mode, case.capacity, len(case.key)) + case.key
        for case in values
    )


def verify(actual: bytes, values: list[Case], fault: str | None = None) -> None:
    assert len(actual) == RECORD * len(values), (len(actual), RECORD * len(values))
    for index, case in enumerate(values):
        record = actual[index * RECORD:(index + 1) * RECORD]
        status, value = struct.unpack_from("<2Q", record)
        expected_status = case.status
        if expected_status == 0 and fault:
            expected_status = {"provider": 4, "size": 5, "wide-size": 5}[fault]
        assert status == expected_status, (index, case, status, expected_status, value)
        source = bytearray([165] * 96)
        source[3:3 + len(case.key)] = case.key
        target = source if case.mode == 1 else bytearray([221] * 96)
        if status == 0:
            assert value == 28, (index, case, value)
            target[5:33] = accepts(case.key)
        elif status == 4:
            assert value != 0, (index, case, "missing OpenSSL diagnostic")
        elif status == 5:
            assert value == (0x100000014 if fault == "wide-size" else 19), (index, case, value)
        else:
            assert value == 0, (index, case, value)
        assert record[16:112] == target, (index, case, "target guards/atomic output")
        assert record[112:208] == source, (index, case, "source/overlap copy")


def run(executable: Path, values: list[Case], shim: Path | None = None, fault: str | None = None) -> None:
    environment = os.environ.copy()
    if shim:
        environment["LD_PRELOAD"] = str(shim.resolve())
        environment["LANIUS_WEBSOCKET_FAULT"] = str(fault)
    else:
        environment.pop("LANIUS_WEBSOCKET_FAULT", None)
    result = subprocess.run([str(executable.resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=environment, timeout=30, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values, fault)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--shim", type=Path)
    arguments = parser.parse_args()
    assert accepts(SAMPLE) == b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    values = cases()
    run(arguments.executable, values)
    print(f"websocket-accept cases={len(values)} layouts=2 overlap=yes")
    if arguments.shim:
        selected = [Case(SAMPLE, layout, mode, status=0) for layout in range(2) for mode in range(2)]
        selected += [Case(b"!" + SAMPLE[1:], layout, status=3) for layout in range(2)]
        selected += [Case(SAMPLE, layout, capacity=27, status=2) for layout in range(2)]
        for fault in ("provider", "size", "wide-size"):
            run(arguments.executable, selected, arguments.shim, fault)
        print(f"websocket-accept injected-cases={len(selected) * 3} atomic=yes")


if __name__ == "__main__":
    main()
