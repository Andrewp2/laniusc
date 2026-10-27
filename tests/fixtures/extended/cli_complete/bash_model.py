"""Literal Bash spellings and independent NUL-record reply goldens.

The decoder cases state expected literal bytes; generated cases construct safe
single-quoted spellings from chosen bytes. No shell eval or decoder clone is
used. Python only transports/validates the actual Lanius public API results.
"""
import random
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

U64 = (1 << 64) - 1
SEED = 0xBA520026


def frame(mode, spacing, stem=b"", prefix=b"", values=(), *, quote=0, continuation=0, trim=b""):
    return b"\0".join([b"lanius-completion-1", (b"candidates", b"files", b"none")[mode],
                         b"space" if spacing else b"nospace", (b"unquoted", b"single", b"double")[quote],
                         (b"unquoted", b"single", b"double")[continuation], trim, stem, prefix,
                         str(len(values)).encode("ascii"), *values, b"end"]) + b"\0"


def decoder(raw, decoded=None, *, mode=0, quote=0, pending=False, error=None,
            capacity=None, layout=0, input_case=0, output_case=0):
    return dict(operation=0, mode=mode, space=False, first=raw, prefix=b"", values=(),
                decoded=decoded, quote=quote, pending=pending, error=error,
                capacity=capacity, layout=layout, input_case=input_case, output_case=output_case,
                trim=b"", continuation=0)


def encoder(mode=0, spacing=True, stem=b"", prefix=b"", values=(), *, capacity=None,
            layout=0, input_case=0, output_case=0, quote=0, continuation=0, trim=b""):
    return dict(operation=1, mode=mode, space=spacing, first=stem, prefix=prefix, values=tuple(values),
                capacity=capacity, layout=layout, input_case=input_case, output_case=output_case,
                quote=quote, continuation=continuation, trim=trim)


def expected(case):
    operation = case["operation"]
    code, left, right, size, payload, quote, pending = 0, 0, 0, U64, b"", 0, 0
    if operation == 0:
        if case["input_case"]:
            code = 1
        elif case["error"] is not None:
            code, left = case["error"]
        else:
            payload, quote, pending = case["decoded"], case["quote"], int(case["pending"])
            assert payload is not None
            size = len(payload)
    else:
        mode, stem, prefix, values, trim = case["mode"], case["first"], case["prefix"], case["values"], case["trim"]
        if case["input_case"]:
            code = 1
        elif (mode != 0 and values) or (mode != 1 and (stem or prefix)) or (mode == 2 and trim):
            code = 2
        elif b"\0" in trim:
            code, left = 8, trim.index(0)
        elif b"\0" in stem:
            code, left = 3, stem.index(0)
        elif b"\0" in prefix:
            code, left = 4, prefix.index(0)
        elif any(b"\0" in item for item in values):
            left = next(index for index, item in enumerate(values) if b"\0" in item)
            code, right = 5, values[left].index(0)
        else:
            payload = frame(mode, case["space"], stem, prefix, values,
                            quote=case["quote"], continuation=case["continuation"], trim=trim)
            size = len(payload)
    if code == 0 and case["output_case"]:
        code, quote, pending = 1, 0, 0
    if code == 0 and case["capacity"] is not None and case["capacity"] < size:
        code, left, quote, pending = (8 if operation == 0 else 6), size, 0, 0
    if code:
        payload = b""
    header = (operation, code, left, right, size, len(payload), quote, pending,
              1 if case["layout"] & 1 else 2, 1 if case["layout"] & 2 else 2, 0, 0)
    return header, payload


def request(cases):
    output = bytearray(struct.pack("<Q", len(cases)))
    for case in cases:
        header, payload = expected(case)
        capacity = case["capacity"] if case["capacity"] is not None else (header[4] + 3 if header[4] != U64 else 8192)
        assert 0 <= capacity <= 8192
        assert len(case["values"]) <= 32 and len(case["first"]) + len(case["prefix"]) + len(case["trim"]) + sum(map(len, case["values"])) <= 4096
        output.extend(struct.pack("<16Q", case["operation"], case["mode"], case["space"], len(case["first"]),
                                  len(case["prefix"]), len(case["values"]), capacity, case["layout"],
                                  case["input_case"], case["output_case"], len(case["trim"]),
                                  case["quote"] if case["operation"] else 0, case["continuation"], 0, 0, 0))
        output.extend(case["first"] + case["prefix"] + case["trim"])
        for value in case["values"]:
            output.extend(struct.pack("<Q", len(value)))
            output.extend(value)
    return bytes(output)


def validate(cases, output):
    offset = 0
    for index, case in enumerate(cases):
        header, payload = expected(case)
        assert len(output) - offset >= 96, ("partial response header", index, offset, len(output))
        actual = struct.unpack_from("<12Q", output, offset)
        offset += 96
        assert actual == header, ("response metadata", index, case, actual, header)
        assert output[offset:offset + len(payload)] == payload, ("response bytes", index, case)
        offset += len(payload)
    assert offset == len(output), ("extra native output", offset, len(output))


def cases():
    result = []
    literals = [(b"", b""), (b"abc", b"abc"), (b"a\\ b", b"a b"),
                (b"a'bc'\"d\"", b"abcd"), (b"''", b""), (b'""', b""),
                (b"a\\\nb", b"ab"), (b'"a\\qb"', b"a\\qb"),
                (b'"\\!"', b"\\!"), (b"'\xff\n$`*!'", b"\xff\n$`*!"),
                (b"a#b", b"a#b"), (b"''#x", b"#x"),
                (b"a\r\v\fb", b"a\r\v\fb"), (b"name=path:@x", b"name=path:@x"),
                (b'"\\$\\`\\"\\\\"', b'$`"\\'), (b'"a\\\nb"', b"ab")]
    for index, (raw, value) in enumerate(literals):
        for layout in range(4):
            result.append(decoder(raw, value, layout=layout))
        result.append(decoder(raw, value, capacity=len(value), layout=index % 4))
        if value:
            result.append(decoder(raw, value, capacity=len(value) - 1, layout=(index + 1) % 4))
    for raw, value, quote, pending in ((b"'a", b"a", 1, False), (b'"a', b"a", 2, False),
                                       (b"a\\", b"a", 0, True), (b'"a\\', b"a", 2, True),
                                       (b"'\\", b"\\", 1, False), (b"\\", b"", 0, True)):
        result.append(decoder(raw, value, mode=1, quote=quote, pending=pending, layout=len(result) % 4))
    for raw, tag, at in ((b"'a", 6, 0), (b'"a', 6, 0), (b"a\\", 7, 1),
                         (b'"a\\', 7, 2), (b"'\\", 6, 0), (b"\\", 7, 0),
                         (b"a\0b", 2, 1), (b"\\\0", 2, 1), (b"'\0'", 2, 1),
                         (b'"\\\0"', 2, 2), (b"#x", 4, 0), (b"\\\n#x", 4, 2)):
        result.append(decoder(raw, error=(tag, at), layout=len(result) % 4))
    for value in b" \t\n":
        result.append(decoder(b"a" + bytes([value]) + b"b", error=(5, 1), layout=len(result) % 4))
    for value in b"|&;()<>":
        result.append(decoder(b"a" + bytes([value]) + b"b", error=(4, 1), layout=len(result) % 4))
    for value in b"$`*?[]{}~!":
        result.append(decoder(b"a" + bytes([value]), error=(3, 1), layout=len(result) % 4))
    for value in b"$`!":
        result.append(decoder(b'"' + bytes([value]) + b'"', error=(3, 1), mode=1, layout=len(result) % 4))
    for selector in (1, 2, 3):
        result.append(decoder(b"x", b"x", input_case=selector, layout=selector))
        result.append(decoder(b"x", b"x", output_case=selector, layout=selector))
    result.append(decoder(b"$", error=(3, 0), output_case=1))
    randomizer = random.Random(SEED)
    for index in range(64):
        value = bytes(randomizer.randrange(1, 256) for _ in range(randomizer.randrange(0, 17)))
        # Standard literal concatenation: close single quote, bare-escape the
        # apostrophe, then reopen. This generates inputs with known bytes.
        raw = b"'" + value.replace(b"'", b"'\\''") + b"'"
        result.append(decoder(raw, value, layout=index % 4))
        result.append(decoder(raw, value, mode=1, layout=(index + 1) % 4))
    value = bytes(range(1, 256))
    result.append(decoder(b"'" + value.replace(b"'", b"'\\''") + b"'", value, layout=3))

    for mode in range(3):
        for spacing in (False, True):
            for quote in range(3):
                for continuation in range(3):
                    result.append(encoder(mode, spacing, quote=quote, continuation=continuation,
                                          layout=(quote * 3 + continuation) % 4))
    for count in (1, 9, 10, 32):
        values = tuple((b"", b"init", b"a b", b"x\ny", b"\xff*?[]", b"end")[i % 6] for i in range(count))
        for layout in range(4):
            good = encoder(values=values, spacing=bool(layout & 1), layout=layout)
            size = len(expected(good)[1])
            result += [dict(good, capacity=size), dict(good, capacity=size - 1)]
    for layout in range(4):
        result.append(encoder(1, False, b"--file=", b"raw\xff\n*?[]", layout=layout, trim=b"before=", quote=1, continuation=2))
        result.append(encoder(values=(b"whole value",), trim=b"not interpreted", quote=2, continuation=1, layout=layout))
    result += [encoder(0, stem=b"x"), encoder(0, prefix=b"x"), encoder(1, values=(b"x",)),
               encoder(2, stem=b"x"), encoder(2, prefix=b"x"), encoder(2, values=(b"x",)),
               encoder(1, stem=b"a\0b"), encoder(1, prefix=b"a\0b"),
               encoder(values=(b"ok", b"a\0b")), encoder(2, values=(b"\0",)),
               encoder(2, trim=b"x"), encoder(trim=b"a\0b"), encoder(1, stem=b"\0", trim=b"x\0")]
    for selector in range(1, 9):
        result.append(encoder(values=(b"x",), input_case=selector, layout=selector % 4))
    for selector in (1, 2, 3):
        result.append(encoder(output_case=selector, layout=selector))
    result.append(encoder(values=(b"\0",), output_case=1))
    assert len(result) <= 1024
    return result


def controls():
    count = 0
    assert frame(2, False) == b"lanius-completion-1\0none\0nospace\0unquoted\0unquoted\0\0\0\0" + b"0\0end\0"
    assert frame(1, True, b"--x=", b"a\n\xff", quote=1, continuation=2, trim=b"pre:") == b"lanius-completion-1\0files\0space\0single\0double\0pre:\0--x=\0a\n\xff\0" + b"0\0end\0"
    assert frame(0, True, values=(b"", b"end")) == b"lanius-completion-1\0candidates\0space\0unquoted\0unquoted\0\0\0\0" + b"2\0\0end\0end\0"
    count += 3
    selected = cases()
    assert any(case.get("pending") for case in selected)
    assert {case["layout"] for case in selected} == {0, 1, 2, 3}
    assert any(case["operation"] == 1 and len(case["values"]) == 32 for case in selected)
    assert any(case["operation"] == 0 and case.get("decoded") == bytes(range(1, 256)) for case in selected)
    count += 4
    chosen = [decoder(b"'a'", b"a"), decoder(b"x", b"x", capacity=0),
              decoder(b"$", error=(3, 0), output_case=1), encoder(values=(b"", b"a\n\xff")),
              encoder(2, values=(b"x",), input_case=5)]
    good = b"".join(struct.pack("<12Q", *expected(case)[0]) + expected(case)[1] for case in chosen)
    validate(chosen, good)
    assert struct.unpack_from("<Q", request(chosen))[0] == len(chosen)
    count += 2
    for bad in (good[:-1], good + b"x", good[:95], bytes([good[0] ^ 1]) + good[1:],
                good[:96] + b"x" + good[97:]):
        try:
            validate(chosen, bad)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("Bash oracle accepted a changed/partial response")
    print("cli-bash CPU controls=%d cases=%d seed=%d" % (count, len(selected), SEED))


def run(executable):
    selected = cases()
    directory = Path(tempfile.mkdtemp(prefix="cli-bash-model-"))
    data = request(selected)
    (directory / "request.bin").write_bytes(data)
    command = [str(Path(executable).resolve())]
    (directory / "command.txt").write_text(repr(command) + "\n")
    try:
        result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    except subprocess.TimeoutExpired as error:
        (directory / "stdout.bin").write_bytes(error.stdout or b"")
        (directory / "stderr.bin").write_bytes(error.stderr or b"")
        raise
    (directory / "stdout.bin").write_bytes(result.stdout)
    (directory / "stderr.bin").write_bytes(result.stderr)
    assert result.returncode == 0 and not result.stderr, (directory, result.returncode, result.stderr)
    validate(selected, result.stdout)
    decoder_count = sum(case["operation"] == 0 for case in selected)
    print("cli-bash cases=%d decoder=%d replies=%d seed=%d evidence=%s" %
          (len(selected), decoder_count, len(selected) - decoder_count, SEED, directory))


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    elif len(sys.argv) == 2:
        run(sys.argv[1])
    else:
        raise SystemExit("usage: bash_model.py controls | MODEL_ELF")
