"""CPU assembly/table oracle. --write regenerates only reviewed width thunks."""
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[3]
runtime = root / "shaders/codegen/lir/x86/runtime_abi.slang"
assembly = runtime.with_name("runtime_raw_width.s")
source = runtime.read_text()
pattern = re.compile(r"static const uint (\w+)\[(\d+)\]\s*=\s*\{(.*?)\};", re.S)
records = list(pattern.finditer(source))


def literal_bytes(record):
    body = re.sub(r"//[^\n]*", "", record[3])
    values = [int(token[:-1], 0) for token in re.findall(r"(?:0x[0-9a-fA-F]+|\d+)u", body)]
    assert len(values) == int(record[2]) and all(0 <= value <= 255 for value in values), record[1]
    return bytes(values)


with tempfile.TemporaryDirectory(prefix="lanius_width_assembly_") as folder:
    folder = pathlib.Path(folder)
    obj = folder / "width.o"
    subprocess.run(["as", "--64", "-o", obj, assembly], check=True, timeout=10)
    replacements = {}
    for name in re.findall(r"^\.section \.text\.(\w+)", assembly.read_text(), re.M):
        output = folder / name
        subprocess.run(["objcopy", "-O", "binary", "-j", f".text.{name}", obj, output], check=True, timeout=10)
        replacements[name] = output.read_bytes()
    old_base = new_base = 0
    intervals = []
    for record in records:
        old = literal_bytes(record)
        new = replacements.get(record[1], old)
        intervals.append((old_base, len(old), new_base))
        old_base += len(old)
        new_base += len(new)

    def relocate(offset):
        if offset == old_base:
            return new_base
        for start, length, replacement in intervals:
            if start <= offset < start + length:
                return replacement + offset - start
        raise AssertionError(offset)

    result = source
    for record in reversed(records):
        if record[1] not in replacements:
            continue
        data = replacements[record[1]]
        indent = " " * (8 if record[1] in {"monotonic_read_bytes", "system_read_bytes", "var_key_read_bytes", "var_len_bytes", "var_read_bytes", "current_dir_read_bytes"} else 4)
        body = "\n" + "\n".join(indent + "    " + ", ".join(f"0x{byte:02x}u" for byte in data[index:index + 10]) + "," for index in range(0, len(data), 10)) + "\n" + indent
        result = result[:record.start()] + f"static const uint {record[1]}[{len(data)}] = {{{body}}};" + result[record.end():]
        constant = "X86_RUNTIME_" + record[1].removesuffix("_bytes").upper() + "_OFFSET"
        result = re.sub(rf"({constant} \+ ){len(literal_bytes(record))}u", rf"\g<1>{len(data)}u", result)
    result = re.sub(r"(static const uint X86_RUNTIME_(?:\w+_OFFSET|LENGTH) = )(\d+)u;", lambda found: found[1] + str(relocate(int(found[2]))) + "u;", result)
    # These three early entry offsets were formerly anonymous literals.
    if "X86_RUNTIME_STDOUT_OFFSET" not in result:
        definitions = f"static const uint X86_RUNTIME_STDOUT_OFFSET = {relocate(33)}u;\nstatic const uint X86_RUNTIME_STDERR_OFFSET = {relocate(50)}u;\nstatic const uint X86_RUNTIME_STDIN_OFFSET = {relocate(67)}u;\n"
        result = result.replace("static const uint X86_RUNTIME_ARG_READ_OFFSET", definitions + "static const uint X86_RUNTIME_ARG_READ_OFFSET", 1)
        result = result.replace("return 33u;", "return X86_RUNTIME_STDOUT_OFFSET;").replace("return 50u;", "return X86_RUNTIME_STDERR_OFFSET;").replace("return 67u;", "return X86_RUNTIME_STDIN_OFFSET;")
        result = result.replace("if (pos < 50u) return stdout_bytes[pos - 33u];", "if (pos < X86_RUNTIME_STDERR_OFFSET) return stdout_bytes[pos - X86_RUNTIME_STDOUT_OFFSET];")
        result = result.replace("if (pos < 67u) return stderr_bytes[pos - 50u];", "if (pos < X86_RUNTIME_STDIN_OFFSET) return stderr_bytes[pos - X86_RUNTIME_STDERR_OFFSET];")
        result = result.replace("return stdin_bytes[pos - 67u];", "return stdin_bytes[pos - X86_RUNTIME_STDIN_OFFSET];")
    if "--write" in sys.argv:
        runtime.write_text(result)
    else:
        assert result == source, "runtime width arrays/offsets differ from assembled source; run with --write after review"
    # Check contiguous base offsets, including unchanged neighbors and embedded
    # path helper entry offsets. Assembly comparison validates local branches.
    final = result if "--write" in sys.argv else source
    positions = {}
    end = 0
    for record in pattern.finditer(final):
        positions[record[1]] = end
        end += len(literal_bytes(record))
    for constant, number in re.findall(r"static const uint (X86_RUNTIME_\w+) = (\d+)u;", final):
        name = constant.removeprefix("X86_RUNTIME_").removesuffix("_OFFSET").lower() + "_bytes"
        if constant == "X86_RUNTIME_LENGTH":
            assert int(number) == end
        elif name in positions:
            assert int(number) == positions[name], (constant, number, positions[name])
    constants = {name: int(value) for name, value in re.findall(r"static const uint (X86_RUNTIME_\w+) = (\d+)u;", final)}
    arrays = {record[1]: literal_bytes(record) for record in pattern.finditer(final)}
    if "--elf" in sys.argv:
        executable = pathlib.Path(sys.argv[sys.argv.index("--elf") + 1]).read_bytes()
        expected = b"".join(arrays.values())
        position = found = 0
        while True:
            position = executable.find(expected[:81], position)
            if position < 0:
                break
            actual = executable[position:position + len(expected)]
            wrong = [index for index, value in enumerate(expected) if index >= len(actual) or actual[index] != value]
            assert not wrong, ("emitted runtime differs from literal bytes", position, wrong[:12])
            found += 1
            position += len(expected)
        assert found > 0, "no native runtime in executable"
    for stem, array in [("runtime_path_ops", "path_ops_bytes"), ("runtime_linux_syscall", "linux_syscall6_bytes")]:
        obj = folder / (stem + ".o")
        output = folder / (stem + ".bin")
        subprocess.run(["as", "--64", "-o", obj, runtime.with_name(stem + ".s")], check=True, timeout=10)
        subprocess.run(["objcopy", "-O", "binary", "-j", ".text", obj, output], check=True, timeout=10)
        assert arrays[array] == output.read_bytes(), stem
        if stem == "runtime_path_ops":
            symbols = subprocess.run(["nm", "-an", obj], check=True, capture_output=True, text=True, timeout=10).stdout
            for line in symbols.splitlines():
                fields = line.split()
                if len(fields) == 3 and fields[2].startswith("path_"):
                    constant = "X86_RUNTIME_" + fields[2].upper() + "_OFFSET"
                    assert constants[constant] == positions[array] + int(fields[0], 16), (constant, line)
