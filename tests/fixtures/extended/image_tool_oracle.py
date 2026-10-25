"""Pillow reference for the offline CLI. Never imported by production Lanius."""
import io
import random
import struct
import subprocess
import sys
import time
import zlib
from PIL import Image

SIGNATURE = b"\x89PNG\r\n\x1a\n"


def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))


def rgba(width, height, seed):
    source = random.Random(seed)
    values = bytearray(source.randbytes(width * height * 4))
    # Include transparent colored pixels and all alpha extrema deliberately.
    for pixel in range(width * height):
        if pixel % 11 < 4:
            values[pixel * 4 + 3] = (0, 1, 254, 255)[pixel % 11]
    return Image.frombytes("RGBA", (width, height), bytes(values))


def png(image, level=6):
    output = io.BytesIO()
    image.save(output, format="PNG", compress_level=level)
    return output.getvalue()


def simple(width, height, raw):
    return (SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def chunks(value):
    at = 8
    result = []
    while at < len(value):
        size = int.from_bytes(value[at:at + 4], "big")
        result.append((value[at + 4:at + 8], value[at + 8:at + 8 + size]))
        at += size + 12
    return result


def assemble(items):
    return SIGNATURE + b"".join(chunk(name, data) for name, data in items)


def reference(image, crop, turns, flip_x, flip_y):
    image = image.convert("RGBA")
    if crop is not None:
        x, y, width, height = crop
        image = image.crop((x, y, x + width, y + height))
    # Pillow transpose constants name counterclockwise turns; 270 is CW 90.
    rotations = {1: Image.Transpose.ROTATE_270, 2: Image.Transpose.ROTATE_180,
                 3: Image.Transpose.ROTATE_90}
    if turns:
        image = image.transpose(rotations[turns])
    if flip_x:
        image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if flip_y:
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return image


class Runner:
    def __init__(self, executable):
        self.executable = executable
        self.count = 0
        self.native = 0.0

    def call(self, args, source, status=0, reason=None):
        before = time.monotonic()
        result = subprocess.run([self.executable, *args], input=source,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        self.native += time.monotonic() - before
        self.count += 1
        assert result.returncode == status, (args, result.returncode, result.stderr)
        if status == 0:
            assert result.stderr == b"", (args, result.stderr)
        else:
            assert result.stdout == b"", (args, result.stdout[:100])
            if reason is not None:
                assert result.stderr == reason, (args, result.stderr, reason)
        return result.stdout

    def summary(self, label):
        print(f"{label} cases={self.count} native_ms={self.native * 1000:.0f}")


def check_pixels(encoded, expected):
    actual = Image.open(io.BytesIO(encoded))
    actual.load()
    assert actual.mode == "RGBA", actual.mode
    assert actual.size == expected.size, (actual.size, expected.size)
    assert actual.tobytes() == expected.tobytes(), (actual.size, "RGBA mismatch")
    # Every emitted output must terminate at IEND, without incidental stdout.
    assert encoded.startswith(SIGNATURE) and encoded[-12:] == chunk(b"IEND", b"")


def matrix(executable):
    run = Runner(executable)
    inputs = []
    for index, (width, height) in enumerate([(1, 1), (2, 7), (7, 2), (13, 11), (63, 17), (127, 129)]):
        inputs.append(rgba(width, height, 0x10203040 + index))
    color = rgba(9, 7, 781)
    inputs.extend(color.convert(mode) for mode in ("RGB", "L", "LA", "1"))
    palette = Image.frombytes("P", (13, 7), bytes((i * 73) % 256 for i in range(91)))
    palette.putpalette(bytes((i * 29 + 19) % 256 for i in range(768)))
    palette.info["transparency"] = bytes(range(256))
    inputs.append(palette)
    for index, image in enumerate(inputs):
        source = png(image, index % 10)
        width, height = image.size
        assert run.call(["info"], source) == f"width,height\n{width},{height}\n".encode()
        for turns in range(4):
            for flip in range(4):
                crop = (0, 0, width, height)
                if width > 2 and height > 2:
                    crop = (1, 1, width - 2, height - 2)
                flip_x, flip_y = bool(flip & 1), bool(flip & 2)
                # Options arrive in several orders; semantic order stays fixed.
                args = ["--rotate", str(turns * 90)]
                if flip_x:
                    args.append("--flip-x")
                args.extend(["transform", "--crop", ",".join(map(str, crop))])
                if flip_y:
                    args.insert(0, "--flip-y")
                encoded = run.call(args, source)
                check_pixels(encoded, reference(image, crop, turns, flip_x, flip_y))
        # Bottom-right one-pixel crop and a pure re-encode are useful edges.
        crop = (width - 1, height - 1, 1, 1)
        check_pixels(run.call(["transform", "--crop", ",".join(map(str, crop)),
                               "--rotate", "270", "--flip-x", "--flip-y"], source),
                     reference(image, crop, 3, True, True))
        check_pixels(run.call(["transform"], source), image.convert("RGBA"))
    run.summary("pillow-matrix")


def arguments(executable):
    run = Runner(executable)
    image = rgba(13, 11, 819)
    source = png(image)
    argument_error = b"image-tool: invalid-arguments stage=arguments\n"
    for args in [[], ["bad"], ["info", "transform"], ["info", "extra"], ["--bad"],
                 ["transform", "--rotate"], ["transform", "--crop"],
                 ["info", "--rotate", "0"], ["info", "--crop", "0,0,1,1"],
                 ["info", "--flip-x"], ["info", "--flip-y"],
                 ["transform", "--flip-x=1"], ["transform", "--", "--flip-x"]]:
        run.call(args, source, 2, argument_error)
    for rectangle in ["", "0,0,1", "0,0,1,1,1", "0,0,0,1", "0,0,1,0",
                      "-1,0,1,1", "0,0,-1,1", "0,0,1,+1", "0,0,1, 1",
                      "0,0,1,1,", "0,,1,1", "2147483648,0,1,1"]:
        run.call(["transform", "--crop", rectangle], source, 2, argument_error)
    for angle in ["-90", "1", "45", "89", "91", "360", "271", "90x", "+90", " 90", "", "18446744073709551616"]:
        run.call(["transform", "--rotate", angle], source, 2, argument_error)
    caps = [("--max-input-bytes", 268435456), ("--max-pixels", 67108864),
            ("--max-inflated-bytes", 1073741824), ("--max-chunks", 1000000),
            ("--max-output-bytes", 268435456)]
    for option, maximum in caps:
        for bad in ["-1", str(maximum + 1), "+1", "1.0", "1e1", " 1", "", "18446744073709551616"]:
            run.call(["info", option, bad], source, 2, argument_error)
        assert run.call(["info", option, str(maximum)], source).startswith(b"width,height\n")
        stage = "output" if option == "--max-output-bytes" else "input" if option == "--max-input-bytes" else "decode"
        run.call(["info", option, "0"], source, 3, f"image-tool: resource-limit stage={stage}\n".encode())
    exact = [("--max-input-bytes", len(source), "input"),
             ("--max-pixels", image.width * image.height, "decode"),
             ("--max-inflated-bytes", (image.width * 4 + 1) * image.height, "decode"),
             ("--max-chunks", len(chunks(source)), "decode")]
    for option, maximum, stage in exact:
        assert run.call(["info", option, str(maximum)], source) == b"width,height\n13,11\n"
        run.call(["info", option, str(maximum - 1)], source, 3,
                 f"image-tool: resource-limit stage={stage}\n".encode())
    info = b"width,height\n13,11\n"
    assert run.call(["info", "--max-output-bytes", str(len(info))], source) == info
    run.call(["info", "--max-output-bytes", str(len(info) - 1)], source, 3,
             b"image-tool: resource-limit stage=output\n")
    encoded = run.call(["transform"], source)
    assert run.call(["transform", "--max-output-bytes", str(len(encoded))], source) == encoded
    run.call(["transform", "--max-output-bytes", str(len(encoded) - 1)], source, 3,
             b"image-tool: resource-limit stage=encode\n")
    for crop in ["13,0,1,1", "0,11,1,1", "1,1,13,11", "2147483647,0,2147483647,1"]:
        run.call(["transform", "--crop", crop], source, 2, b"image-tool: invalid-transform stage=transform\n")
    # Snapshot limits count tokens and bytes, not NUL terminators.
    check_pixels(run.call(["transform"] + ["--flip-x"] * 31, source),
                 reference(image, None, 0, True, False))
    run.call(["transform"] + ["--flip-x"] * 32, source, 2, argument_error)
    check_pixels(run.call(["transform", "--rotate", "0" * 8175], source), image)
    run.call(["transform", "--rotate", "0" * 8176], source, 2, argument_error)
    assert run.call(["--help"], b"") == (b"Usage: image-tool info [OPTIONS] <INPUT.png\n"
                                            b"       image-tool transform [OPTIONS] <INPUT.png >OUTPUT.png\n")
    run.summary("arguments-limits")


def malformed_cases():
    source = png(rgba(7, 5, 82))
    cases = [source[:n] for n in [0, 1, 7, 8, 32, len(source) - 12, len(source) - 1]]
    cases.extend([source + b"late", source[:-1] + bytes([source[-1] ^ 1])])
    items = chunks(source)
    data = next(data for name, data in items if name == b"IDAT")
    bad = data[:-1] + bytes([data[-1] ^ 1])
    cases.append(assemble([(name, bad if name == b"IDAT" else value) for name, value in items]))
    raw = bytearray()
    for y in range(5):
        raw.extend(bytes([0]) + bytes((i * 17 + y) % 256 for i in range(28)))
    late = bytearray(raw)
    late[-29] = 5
    cases.extend([simple(7, 5, late), simple(7, 5, raw[:-1]), simple(7, 5, raw + b"extra")])
    items.insert(-1, (b"teXt", b"opaque late metadata"))
    late_crc = bytearray(assemble(items))
    late_crc[-13] ^= 1
    cases.append(bytes(late_crc))
    return cases


def malformed(executable):
    run = Runner(executable)
    for case in malformed_cases():
        for mode in ["info", "transform"]:
            run.call([mode], case, 2, b"image-tool: invalid-png stage=decode\n")
    run.summary("malformed-staging")


def scale(executable):
    run = Runner(executable)
    largest = 0
    for width, height in [(1, 4097), (4097, 1), (1023, 769)]:
        image = rgba(width, height, width + height * 13)
        source = png(image, 6)
        largest = max(largest, width * height)
        crop = (0, 0, width, height) if width == 1 or height == 1 else (17, 19, width - 35, height - 39)
        encoded = run.call(["transform", "--crop", ",".join(map(str, crop)),
                            "--rotate", "90", "--flip-x", "--flip-y"], source)
        check_pixels(encoded, reference(image, crop, 1, True, True))
    assert run.native < 60, run.native
    run.summary(f"scale max_pixels={largest}")


if __name__ == "__main__":
    action = sys.argv[1]
    if action in {"matrix", "arguments", "malformed", "scale"}:
        globals()[action](sys.argv[2])
    elif action == "generate":
        sys.stdout.buffer.write(png(rgba(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))))
    elif action == "late-filter":
        sys.stdout.buffer.write(malformed_cases()[10])
    elif action == "decode":
        image = Image.open(io.BytesIO(sys.stdin.buffer.read())).convert("RGBA")
        sys.stdout.buffer.write(struct.pack("<II", *image.size) + image.tobytes())
    else:
        raise ValueError(action)
